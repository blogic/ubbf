'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { transfer_complete, datetime_format } from 'ubbf.utils.helpers';
import { curl_upload } from 'ubbf.utils.curl';
import { log_info, log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

const FAULTS_PATH = '/etc/ubbf/kernel-faults.json';

/**
 * Loads the persisted kernel fault state.
 *
 * @returns {object} `{ meta, faults }`; legacy bare-array files are migrated in-memory
 */
function faults_load() {
	let data = fs.readfile(FAULTS_PATH);
	if (!data)
		return { meta: {}, faults: [] };

	let parsed = json(data);
	if (type(parsed) == 'array')
		return { meta: {}, faults: parsed };
	if (type(parsed) == 'object')
		return { meta: parsed.meta ?? {}, faults: parsed.faults ?? [] };
	return { meta: {}, faults: [] };
}

/**
 * Maps a stored kernel fault entry to TR-181 KernelFault parameters.
 *
 * @param {object} fault - Fault entry from the persisted store
 * @param {number} idx - Zero-based array index, used to derive a stable Alias
 * @returns {object} TR-181 formatted KernelFault object
 */
function fault_to_object(fault, idx) {
	return {
		Alias: sprintf('cpe-kfault-%d', idx + 1),
		FaultLocation: fault.fault_location ?? '',
		LastInstruction: fault.last_instruction ?? '',
		TimeStamp: datetime_format(fault.timestamp),
		FirmwareVersion: fault.firmware_version ?? '',
		ProcessName: fault.process_name ?? '',
		Reason: fault.reason ?? ''
	};
}

/**
 * @param {object} ctx - Context with config
 * @returns {object} KernelFaults container properties
 */
function faults_container_get(ctx) {
	let state = faults_load();
	let meta = state.meta ?? {};

	return {
		...ubbf.ctx_config(ctx),
		StoragePath: '/etc/ubbf',
		KernelFaultNumberOfEntries: sprintf('%d', length(state.faults)),
		LastUpgradeCount: sprintf('%d', meta.last_upgrade_count ?? 0),
		PreviousBootCount: sprintf('%d', meta.previous_boot_count ?? 0)
	};
}

/**
 * @param {object} ctx - Context with instance
 * @returns {object|null} Single or enumerated fault entries
 */
function fault_get(ctx) {
	let state = faults_load();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(state.faults, fault_to_object);

	let fault = ubbf.get_by_instance(state.faults, ctx.instance);
	if (!fault)
		return null;

	return fault_to_object(fault, ctx.instance - 1);
}

/**
 * @param {object} input - Unused
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers
 */
function remove_handler(input, instance, complete, instances) {
	let fault_idx = instances[0];
	if (fault_idx == null) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'missing instance', {});
		return;
	}

	let result = ubus.call({ object: 'bbf-device', method: 'kernel_faults_remove',
		data: { index: fault_idx - 1 } });

	if (result?.error) {
		complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
		return;
	}

	complete(instance, 0, null, {});
}

/**
 * @param {object} input - Unused
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 */
function remove_all_handler(input, instance, complete) {
	ubus.call({ object: 'bbf-device', method: 'kernel_faults_remove_all', data: {} });
	complete(instance, 0, null, {});
}

/**
 * @param {object} input - URL, Username, Password
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers
 * @param {string} command_key - USP command key
 */
function upload_handler(input, instance, complete, instances, command_key) {
	let fault_idx = instances[0];
	let url = input.URL ?? '';
	let username = input.Username ?? '';
	let password = input.Password ?? '';

	if (url == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'URL is required', {});
		return;
	}

	if (!ubbf.transfer_url_validate(url)) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid URL scheme', {});
		return;
	}

	let state = faults_load();
	let fault = ubbf.get_by_instance(state.faults, fault_idx);
	if (!fault) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid fault instance', {});
		return;
	}

	let ctx = {
		command: 'Upload',
		obj_path: sprintf('Device.DeviceInfo.KernelFaults.KernelFault.%d.', fault_idx),
		url,
		transfer_type: 'Upload',
		start_time: time(),
		command_key,
		instance,
		complete
	};

	let opts = { command_key };
	if (username != '')
		opts = { ...opts, username, password };

	let fault_data = fault_to_object(fault, fault_idx - 1);
	let tmpfile = '/tmp/kernel-fault-upload.json';
	fs.writefile(tmpfile, sprintf('%.J\n', fault_data));

	let task = uloop.task(
		(pipe) => {
			let result = curl_upload(url, tmpfile, opts);
			fs.unlink(tmpfile);
			pipe.send(result);
		},
		(result) => {
			if (!result)
				return;

			let fault_string = null;
			if (!result.success)
				fault_string = sprintf('Upload failed: %s', result.output);

			transfer_complete(ctx, fault_string);
		}
	);

	if (!task) {
		fs.unlink(tmpfile);
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
	}
}

export const model = {
	'Device.DeviceInfo.KernelFaults': {
		schema: schemas.KernelFaults,
		get: faults_container_get
	},

	'Device.DeviceInfo.KernelFaults.KernelFault': {
	},

	'Device.DeviceInfo.KernelFaults.KernelFault.{i}': {
		schema: schemas.KernelFaults_KernelFault,
		get: fault_get
	}
};

export const operations = {
	'Device.DeviceInfo.KernelFaults.RemoveAllKernelFaults()': {
		type: 'async',
		handler: remove_all_handler
	},

	'Device.DeviceInfo.KernelFaults.KernelFault.{i}.Remove()': {
		type: 'async',
		handler: remove_handler
	},

	'Device.DeviceInfo.KernelFaults.KernelFault.{i}.Upload()': {
		type: 'async',
		handler: upload_handler
	}
};
