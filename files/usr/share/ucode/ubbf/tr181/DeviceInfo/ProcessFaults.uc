'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import { transfer_complete, datetime_format } from 'ubbf';
import { curl_upload, CURL_TRANSFER_TIMEOUT_S } from 'ubbf';
import { log_info, log_err } from 'ubbf';
import { task_run, TASK_MARGIN_S } from 'ubbf.utils.process';
import * as ubbf from 'ubbf';
import { faults_state_normalise, entries_find, json_state_load } from 'ubbf.device.common';
import { instance_id_rows } from 'ubbf';

const FAULTS_PATH = '/etc/ubbf/process-faults.json';

/**
 * Loads the persisted process fault state as ubbf-device does, with the
 * id of each fault, its instance number.
 *
 * @returns {object} `{ meta, faults }`
 */
function faults_load() {
	return faults_state_normalise(json_state_load(FAULTS_PATH, null));
}

/**
 * Maps a stored process fault entry to TR-181 ProcessFault parameters.
 *
 * @param {object} fault - Fault entry from the persisted store, with its id
 * @returns {object} TR-181 formatted ProcessFault object
 */
function fault_to_object(fault) {
	return {
		Alias: sprintf('cpe-fault-%d', fault.id),
		ProcessID: fault.pid ?? '',
		ProcessName: fault.process_name ?? '',
		FaultLocation: '',
		TimeStamp: datetime_format(fault.timestamp),
		FirmwareVersion: fault.firmware_version ?? '',
		Arguments: fault.arguments ?? '',
		Reason: fault.reason ?? ''
	};
}

/**
 * @param {object} ctx - Context with config
 * @returns {object} ProcessFaults container properties
 */
function faults_container_get(ctx) {
	let state = faults_load();
	let meta = state.meta ?? {};

	return {
		...ubbf.ctx_config(ctx),
		StoragePath: '/etc/ubbf',
		ProcessFaultNumberOfEntries: sprintf('%d', length(state.faults)),
		LastUpgradeCount: sprintf('%d', meta.last_upgrade_count ?? 0),
		PreviousBootCount: sprintf('%d', meta.previous_boot_count ?? 0),
		CurrentBootCount: sprintf('%d', meta.current_boot_count ?? 0)
	};
}

/**
 * @param {object} ctx - Context with instance
 * @returns {object|null} Single or enumerated fault entries
 */
function fault_get(ctx) {
	let state = faults_load();

	if (ctx.instance == null)
		return instance_id_rows(state.faults, fault_to_object);

	let fault = entries_find(state.faults, ctx.instance);
	if (!fault)
		return null;

	return fault_to_object(fault);
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

	let result = ubus.call({ object: 'bbf-device', method: 'process_faults_remove',
		data: { id: fault_idx } });

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
	ubus.call({ object: 'bbf-device', method: 'process_faults_remove_all', data: {} });
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
	let fault = entries_find(state.faults, fault_idx);
	if (!fault) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid fault instance', {});
		return;
	}

	let ctx = {
		command: 'Upload',
		obj_path: sprintf('Device.DeviceInfo.ProcessFaults.ProcessFault.%d.', fault_idx),
		url,
		transfer_type: 'Upload',
		start_time: time(),
		command_key,
		instance,
		complete
	};

	let opts = { command_key, timeout: CURL_TRANSFER_TIMEOUT_S };
	if (username != '')
		opts = { ...opts, username, password };

	let fault_data = fault_to_object(fault);
	let tmpfile = ubbf.tmpfile_name('process-fault-upload', '.json');
	if (!tmpfile || fs.writefile(tmpfile, sprintf('%.J\n', fault_data)) == null) {
		if (tmpfile)
			fs.unlink(tmpfile);
		transfer_complete(ctx, 'Cannot write the fault to a temporary file');
		return;
	}

	task_run(
		() => curl_upload(url, tmpfile, opts),
		(result) => {
			fs.unlink(tmpfile);

			let fault_string = null;
			if (!result.success)
				fault_string = sprintf('Upload failed: %s', result.error ?? result.output);

			transfer_complete(ctx, fault_string);
		},
		{ timeout: CURL_TRANSFER_TIMEOUT_S + TASK_MARGIN_S }
	);
}

export const model = {
	'Device.DeviceInfo.ProcessFaults': {
		schema: 'DeviceInfo.ProcessFaults',
		get: faults_container_get
	},

	'Device.DeviceInfo.ProcessFaults.ProcessFault': {
	},

	'Device.DeviceInfo.ProcessFaults.ProcessFault.{i}': {
		schema: 'DeviceInfo.ProcessFaults_ProcessFault',
		get: fault_get
	}
};

export const operations = {
	'Device.DeviceInfo.ProcessFaults.RemoveAllProcessFaults()': {
		type: 'async',
		handler: remove_all_handler
	},

	'Device.DeviceInfo.ProcessFaults.ProcessFault.{i}.Remove()': {
		type: 'async',
		handler: remove_handler
	},

	'Device.DeviceInfo.ProcessFaults.ProcessFault.{i}.Upload()': {
		type: 'async',
		handler: upload_handler
	}
};
