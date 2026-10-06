'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { datetime_format } from 'ubbf.utils.helpers';
import * as ubbf from 'ubbf';

const REBOOTS_PATH = '/etc/ubbf/reboots.json';

/**
 * Loads the persisted reboot history list.
 *
 * @returns {array} Array of reboot entries, empty when the file is missing or invalid
 */
function reboots_load() {
	let data = fs.readfile(REBOOTS_PATH);
	if (!data)
		return [];

	return json(data) ?? [];
}

/**
 * Maps a stored reboot entry to TR-181 Reboot parameters.
 *
 * @param {object} entry - Reboot entry from the persisted store
 * @param {number} idx - Zero-based array index, used to derive a stable Alias
 * @returns {object} TR-181 formatted Reboot object
 */
function reboot_to_object(entry, idx) {
	return {
		Alias: sprintf('cpe-reboot-%d', idx + 1),
		TimeStamp: datetime_format(entry.timestamp),
		FirmwareUpdated: entry.firmware_updated ? 'true' : 'false',
		Cause: entry.cause ?? '',
		Reason: entry.reason ?? 'Unknown'
	};
}

/**
 * @param {object} ctx - Context with config
 * @returns {object} Reboots container properties
 */
function reboots_container_get(ctx) {
	let reboots = reboots_load();
	let fw = null;
	let board = ubus.call({ object: 'system', method: 'board', data: {} });
	if (board)
		fw = board?.release?.revision;

	let current_version_count = 0;
	let warm_count = 0;

	for (let entry in reboots) {
		if (fw && entry.firmware_version == fw)
			current_version_count++;
		let cause = entry.cause ?? '';
		if (index(cause, 'Reboot') >= 0)
			warm_count++;
	}

	return {
		...ubbf.ctx_config(ctx),
		BootCount: sprintf('%d', length(reboots)),
		CurrentVersionBootCount: sprintf('%d', current_version_count),
		WatchdogBootCount: '0',
		ColdBootCount: '0',
		WarmBootCount: sprintf('%d', warm_count),
		RebootNumberOfEntries: sprintf('%d', length(reboots))
	};
}

/**
 * @param {object} ctx - Context with instance
 * @returns {object|null} Single or enumerated reboot entries
 */
function reboot_get(ctx) {
	let reboots = reboots_load();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(reboots, reboot_to_object);

	let entry = ubbf.get_by_instance(reboots, ctx.instance);
	if (!entry)
		return null;

	return reboot_to_object(entry, ctx.instance - 1);
}

/**
 * @param {object} input - Unused
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers
 */
function remove_handler(input, instance, complete, instances) {
	let idx = instances[0];
	if (idx == null) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'missing instance', {});
		return;
	}

	let result = ubus.call({ object: 'bbf-device', method: 'reboots_remove',
		data: { index: idx - 1 } });

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
	ubus.call({ object: 'bbf-device', method: 'reboots_remove_all', data: {} });
	complete(instance, 0, null, {});
}

export const model = {
	'Device.DeviceInfo.Reboots': {
		schema: schemas.Reboots,
		get: reboots_container_get
	},

	'Device.DeviceInfo.Reboots.Reboot': {
	},

	'Device.DeviceInfo.Reboots.Reboot.{i}': {
		schema: schemas.Reboots_Reboot,
		get: reboot_get
	}
};

export const operations = {
	'Device.DeviceInfo.Reboots.RemoveAllReboots()': {
		type: 'async',
		handler: remove_all_handler
	},

	'Device.DeviceInfo.Reboots.Reboot.{i}.Remove()': {
		type: 'async',
		handler: remove_handler
	}
};
