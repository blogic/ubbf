'use strict';

import * as ubus from 'ubus';
import { log_info } from 'ubbf.utils.logging';
import {
	firmware_version_get, faults_state_normalise, fault_entry_should_store,
	json_state_load, json_state_save
} from 'ubbf.device.common';
import { is_shutting_down } from 'ubbf.device.lifecycle';

const STORAGE_PATH = '/etc/ubbf';
const FAULTS_PATH = '/etc/ubbf/process-faults.json';
const SIGNAL_NAMES = {
	'1': 'SIGHUP', '2': 'SIGINT', '3': 'SIGQUIT', '4': 'SIGILL',
	'6': 'SIGABRT', '7': 'SIGBUS', '8': 'SIGFPE', '9': 'SIGKILL',
	'11': 'SIGSEGV', '13': 'SIGPIPE', '14': 'SIGALRM', '15': 'SIGTERM'
};

function faults_load() {
	return faults_state_normalise(json_state_load(FAULTS_PATH, null));
}

function faults_save(state) {
	json_state_save(FAULTS_PATH, state);
}

function fault_reason(exit_code) {
	if (exit_code >= 128) {
		let sig = exit_code - 128;
		let name = SIGNAL_NAMES['' + sig] ?? sprintf('SIG%d', sig);
		return sprintf('Signal %d (%s)', sig, name);
	}

	return sprintf('Exit code %d', exit_code);
}

function fault_record(event_type, data) {
	let command = data?.command ?? [];
	let process_name = replace(command[0] ?? '', /.*\//, '');
	let arguments_str = join(' ', command);

	let entry = {
		pid: sprintf('%d', data?.pid ?? 0),
		process_name,
		arguments: arguments_str,
		timestamp: time(),
		firmware_version: firmware_version_get(),
		exit_code: data?.exit_code ?? 0,
		reason: fault_reason(data?.exit_code ?? 0)
	};

	let state = faults_load();
	state.meta.current_boot_count = (state.meta.current_boot_count ?? 0) + 1;
	state.meta.last_upgrade_count = (state.meta.last_upgrade_count ?? 0) + 1;

	let stored = fault_entry_should_store(state, STORAGE_PATH);
	if (stored)
		push(state.faults, entry);

	faults_save(state);

	log_info('process fault: %s (pid %s) %s%s',
		process_name, entry.pid, entry.reason, stored ? '' : ' (entry dropped)');
}

function procd_notify_cb(req) {
	if (is_shutting_down())
		return;

	let event_type = req.type;
	if (event_type != 'instance.respawn' && event_type != 'instance.fail')
		return;

	fault_record(event_type, req.data);
}

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
 * Rolls over per-boot fault counters. Called once at daemon startup.
 *
 * @param {boolean} is_upgrade - true if this boot followed a firmware upgrade
 */
export function boot_promote(is_upgrade) {
	let state = faults_load();
	state.meta.previous_boot_count = state.meta.current_boot_count ?? 0;
	state.meta.current_boot_count = 0;
	if (is_upgrade)
		state.meta.last_upgrade_count = 0;
	faults_save(state);
};

/**
 * Registers the procd notification subscriber.
 */
export function subscribe() {
	ubus.subscriber(procd_notify_cb, null, ['service']);
};

/**
 * Returns the ubus method table for process-fault queries.
 *
 * @returns {object} Method definitions for process_faults_status/remove/remove_all
 */
export function ubus_methods() {
	return {
		process_faults_status: {
			call: status_handler,
			args: {}
		},
		process_faults_remove: {
			call: remove_handler,
			args: { index: 0 }
		},
		process_faults_remove_all: {
			call: remove_all_handler,
			args: {}
		}
	};
};
