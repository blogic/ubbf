'use strict';

import * as fs from 'fs';
import { log_info } from 'ubbf.utils.logging';
import {
	firmware_version_get, entries_remove, json_state_load, json_state_save
} from 'ubbf.device.common';
import { instance_ids } from 'ubbf.utils.instance-map';

const REBOOTS_PATH = '/etc/ubbf/reboots.json';
const REBOOTS_MAX_ENTRIES = 100;
const BOOT_CAUSE_PATH = '/tmp/ubbf/boot-cause.json';
const FIRMWARE_UPDATED_PATH = '/tmp/ubbf/firmware-updated';

function reboots_load() {
	let reboots = json_state_load(REBOOTS_PATH, []) ?? [];
	instance_ids(reboots);
	return reboots;
}

function reboots_save(reboots) {
	json_state_save(REBOOTS_PATH, reboots);
}

/**
 * Reads the boot-cause file dropped by early boot into tmpfs.
 *
 * @returns {object|null} Parsed boot cause or null when absent
 */
export function boot_cause_read() {
	return json_state_load(BOOT_CAUSE_PATH, null);
};

/**
 * Removes the boot-cause staging file.
 */
export function boot_cause_clear() {
	fs.unlink(BOOT_CAUSE_PATH);
};

/**
 * Marks a boot that runs new firmware. The clock may not be set this early,
 * so /etc/hotplug.d/ntp/50-ubbf-last-firmware-update stores the boot time
 * as Device.DeviceInfo.LastFirmwareUpdate once NTP has synchronised.
 *
 * @param {boolean} is_upgrade - true when this boot followed a firmware upgrade
 */
export function firmware_update_mark(is_upgrade) {
	if (!is_upgrade)
		return;

	fs.mkdir('/tmp/ubbf');
	fs.writefile(FIRMWARE_UPDATED_PATH, '');
};

/**
 * Returns true when the current boot appears to follow a firmware upgrade.
 * Uses the boot-cause record when available, otherwise compares the stored
 * firmware version against the currently running one.
 *
 * @param {object|null} cause - Result of boot_cause_read()
 * @returns {boolean} true if an upgrade was detected
 */
export function upgrade_detected(cause) {
	if (cause && match(cause.cause ?? '', /Sysupgrade/))
		return true;

	let reboots = reboots_load();
	let last_fw = length(reboots) ? reboots[length(reboots) - 1]?.firmware_version : null;
	return last_fw != null && last_fw != firmware_version_get();
};

/**
 * Records a reboot event in the persistent history.
 *
 * @param {object|null} cause - Boot cause (skipped when null)
 * @param {boolean} is_upgrade - true when the reboot installed a new firmware
 */
export function record(cause, is_upgrade) {
	if (!cause)
		return;

	let reboots = reboots_load();
	let fw = firmware_version_get();
	let cause_str = cause.cause ?? 'LocalReboot';

	push(reboots, {
		id: instance_ids(reboots),
		timestamp: time(),
		cause: cause_str,
		reason: cause.reason ?? 'Unknown',
		command_key: cause.command_key ?? '',
		firmware_version: fw,
		firmware_updated: !!is_upgrade
	});

	while (length(reboots) > REBOOTS_MAX_ENTRIES)
		shift(reboots);

	reboots_save(reboots);
	log_info('reboot recorded: %s', cause_str);
};

function status_handler(req) {
	return { reboots: reboots_load() };
}

function remove_handler(req) {
	let reboots = reboots_load();
	if (!entries_remove(reboots, req.args?.id))
		return { error: 'no reboot with this id' };

	reboots_save(reboots);
	return { success: true };
}

function remove_all_handler(req) {
	reboots_save([]);
	return { success: true };
}

/**
 * Returns the ubus method table for reboot-history queries.
 *
 * @returns {object} Method definitions for reboots_status/remove/remove_all
 */
export function ubus_methods() {
	return {
		reboots_status: {
			call: status_handler,
			args: {}
		},
		reboots_remove: {
			call: remove_handler,
			args: { id: 0 }
		},
		reboots_remove_all: {
			call: remove_all_handler,
			args: {}
		}
	};
};
