'use strict';

import * as fs from 'fs';
import { log_info } from 'ubbf.utils.logging';
import {
	firmware_version_get, faults_state_normalise, fault_entry_should_store,
	json_state_load, json_state_save
} from 'ubbf.device.common';

const STORAGE_PATH = '/etc/ubbf';
const FAULTS_PATH = '/etc/ubbf/kernel-faults.json';
const BOOT_PATH = '/tmp/ubbf/kernel-faults-boot.json';

function faults_load() {
	return faults_state_normalise(json_state_load(FAULTS_PATH, null));
}

function faults_save(state) {
	json_state_save(FAULTS_PATH, state);
}

/**
 * Consumes pstore-captured kernel fault records from the boot staging file,
 * appends them to the persistent store, and updates counters.
 *
 * @param {boolean} is_upgrade - true if this boot followed a firmware upgrade
 */
export function record(is_upgrade) {
	let state = faults_load();

	let boot_faults = json_state_load(BOOT_PATH, []) ?? [];
	let new_count = length(boot_faults);

	state.meta.previous_boot_count = new_count;
	state.meta.current_boot_count = 0;
	// staged pstore faults happened on the pre-upgrade firmware, so an
	// upgrade boot starts LastUpgradeCount at 0 (same as process-faults)
	state.meta.last_upgrade_count = is_upgrade
		? 0
		: (state.meta.last_upgrade_count ?? 0) + new_count;

	if (new_count > 0) {
		let fw = firmware_version_get();
		let ts = time();

		for (let f in boot_faults) {
			if (!fault_entry_should_store(state, STORAGE_PATH))
				continue;
			push(state.faults, {
				timestamp: ts,
				reason: f.reason ?? 'Unknown kernel fault',
				process_name: f.process_name ?? '',
				last_instruction: f.last_instruction ?? '',
				fault_location: f.fault_location ?? '',
				firmware_version: fw
			});
		}
	}

	faults_save(state);

	fs.unlink(BOOT_PATH);

	if (new_count > 0)
		log_info('kernel faults recorded: %d entries', new_count);
};

function status_handler(req) {
	let state = faults_load();
	return { faults: state.faults, meta: state.meta };
}

function remove_handler(req) {
	let idx = req.args?.index;
	if (idx == null)
		return { error: 'missing index' };

	let state = faults_load();
	if (idx < 0 || idx >= length(state.faults))
		return { error: 'index out of range' };

	splice(state.faults, idx, 1);
	faults_save(state);
	return { success: true };
}

function remove_all_handler(req) {
	let state = faults_load();
	state.faults = [];
	faults_save(state);
	return { success: true };
}

/**
 * Returns the ubus method table for kernel-fault queries.
 *
 * @returns {object} Method definitions for kernel_faults_status/remove/remove_all
 */
export function ubus_methods() {
	return {
		kernel_faults_status: {
			call: status_handler,
			args: {}
		},
		kernel_faults_remove: {
			call: remove_handler,
			args: { index: 0 }
		},
		kernel_faults_remove_all: {
			call: remove_all_handler,
			args: {}
		}
	};
};
