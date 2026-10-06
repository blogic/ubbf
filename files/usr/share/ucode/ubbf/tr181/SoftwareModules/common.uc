'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import { config_load, config_save } from 'ubbf.utils.config';

const CONFIG_PATH = '/etc/ubbf/config.json';
const UID_ALLOC_PATH = '/etc/ubbf/uid_counter';
const UID_RANGE_BASE = 100000;
const UID_RANGE_SIZE = 65536;

/**
 * Triggers a config re-render and reload via the apply pipeline.
 */
export function config_apply() {
	ubus?.call('bbf-device', 'apply', { apply: true });
};

/**
 * Reads the list of execution environments from config.json.
 *
 * @returns {array} Array of ExecEnv definitions
 */
export function execenvs_read() {
	let cfg = config_load(CONFIG_PATH);
	let ee_section = cfg?.data?.Device?.SoftwareModules?.ExecEnv;
	if (!ee_section)
		return [];

	let result = [];
	let sorted_keys = sort(keys(ee_section), (a, b) => +a - +b);
	for (let k in sorted_keys) {
		let entry = ee_section[k];
		push(result, {
			instance: +k,
			name: entry.Name,
			alias: entry.Alias ?? '',
			vendor: entry.Vendor ?? '',
			version: entry.Version ?? '',
			type: entry.Type ?? 'OCI Runtime',
			enabled: entry.Enable != 'false',
			signers: entry.Signers ?? '',
			constraints: entry._constraints ?? {},
			current_run_level: entry._current_run_level != null ? +entry._current_run_level : -1,
			available_roles: entry._available_roles ? split(entry._available_roles, ',') : [],
			access_interfaces: entry._access_interfaces ? split(entry._access_interfaces, ',') : []
		});
	}

	return result;
};

/**
 * Reads the ExecEnvClass entries from config.json.
 *
 * @returns {object} ExecEnvClass section keyed by instance number
 */
export function execenv_classes_read() {
	let cfg = config_load(CONFIG_PATH);
	return cfg?.data?.Device?.SoftwareModules?.ExecEnvClass ?? {};
};

/**
 * Writes the list of execution environments to config.json.
 *
 * @param {array} list - Array of ExecEnv definitions
 * @returns {boolean} True on success
 */
export function execenvs_write(list) {
	let cfg = config_load(CONFIG_PATH);
	if (!cfg)
		return false;

	let data = cfg.data;
	data.Device ??= {};
	data.Device.SoftwareModules ??= {};

	let ee_section = {};
	for (let i = 0; i < length(list); i++) {
		let ee = list[i];
		let inst = sprintf('%d', ee.instance ?? (i + 1));
		ee_section[inst] = {
			Enable: ee.enabled != false ? 'true' : 'false',
			Alias: ee.alias,
			Name: ee.name,
			Vendor: ee.vendor,
			Version: ee.version,
			Type: ee.type ?? 'OCI Runtime'
		};

		if (ee.signers)
			ee_section[inst].Signers = ee.signers;
		if (length(keys(ee.constraints)))
			ee_section[inst]._constraints = ee.constraints;
		if (ee.current_run_level != null && ee.current_run_level != -1)
			ee_section[inst]._current_run_level = sprintf('%d', ee.current_run_level);
		if (length(ee.available_roles))
			ee_section[inst]._available_roles = join(',', ee.available_roles);
		if (length(ee.access_interfaces))
			ee_section[inst]._access_interfaces = join(',', ee.access_interfaces);
	}

	data.Device.SoftwareModules.ExecEnv = ee_section;
	return !!config_save(CONFIG_PATH, data);
};

/**
 * Allocates the next host UID range for an unprivileged container.
 *
 * @param {number} size - Number of UIDs to allocate
 * @returns {object} Mapping with host_id, container_id, size
 */
export function uid_range_allocate(size) {
	size ??= UID_RANGE_SIZE;
	fs.mkdir('/etc/ubbf', 0755);
	let counter = ubbf.counter_bump(UID_ALLOC_PATH) ?? 0;

	return {
		host_id: UID_RANGE_BASE + (counter * UID_RANGE_SIZE),
		container_id: 0,
		size
	};
};

/**
 * Returns the keyring path for signature verification from ExecEnv Signers.
 *
 * @param {string} exec_env_ref - ExecEnv reference path
 * @returns {string|null} Keyring path or null if no signing required
 */
export function signers_keyring_get(exec_env_ref) {
	let ees = execenvs_read();
	let idx = 0;

	let m = match(exec_env_ref ?? '', /\.(\d+)$/);
	if (m)
		idx = (+m[1]) - 1;

	if (idx < 0 || idx >= length(ees))
		return null;

	let ee = ees[idx];
	if (!ee?.signers || ee.signers == '')
		return null;

	return ee.signers;
};

/**
 * Calculates the restart delay with exponential backoff.
 *
 * @param {object} ar - AutoRestart config from metadata
 * @returns {number} Delay in milliseconds
 */
export function restart_delay_calculate(ar) {
	let base = (ar.retry_min_wait ?? 5) * 1000;
	let multiplier = (ar.retry_multiplier ?? 2000) / 1000;
	let max_wait = (ar.retry_max_wait ?? 300) * 1000;
	let count = ar.retry_count ?? 0;

	let delay = base * (multiplier ** count);
	if (delay > max_wait)
		delay = max_wait;

	return int(delay);
};

/**
 * Validates an ExecutionEnvRef path against config entries.
 *
 * @param {string} exec_env_ref - ExecEnv reference path or null
 * @returns {object} Result with valid, ref, index, ee, and error fields
 */
export function execenv_validate(exec_env_ref) {
	if (!exec_env_ref || exec_env_ref == '')
		return { valid: true, ref: 'Device.SoftwareModules.ExecEnv.1', index: 0 };

	let inst = ubbf.tr181_ref_parse(exec_env_ref, 'Device.SoftwareModules.ExecEnv');
	if (inst == null)
		return { valid: false, error: sprintf('Invalid ExecEnvRef format: %s', exec_env_ref) };

	let idx = inst - 1;
	let ees = execenvs_read();
	if (idx < 0 || idx >= length(ees))
		return { valid: false, error: sprintf('ExecEnv.%d does not exist', inst) };

	let ee = ees[idx];
	if (ee.enabled == false)
		return { valid: false, error: sprintf('ExecEnv.%d is disabled', inst) };

	return { valid: true, ref: exec_env_ref, index: idx, ee };
};
