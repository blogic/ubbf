'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_info, log_err } from 'ubbf.utils.logging';
import {
	config_read as oci_config_read, config_write as oci_config_write,
	resources_apply as oci_resources_apply, mounts_apply as oci_mounts_apply,
	env_apply as oci_env_apply, userns_apply as oci_userns_apply
} from 'ubbf.container.oci';
import { memory_read as cgroup_memory_read, cpu_read as cgroup_cpu_read } from 'ubbf.container.cgroup';

const BUNDLE_BASES = [
	'/usr/share/containers',
	'/tmp/run/uvol/.meta/oci'
];

/**
 * Resolves the OCI bundle directory for a container, returning the first base
 * that already holds a config.json or falling back to the primary base for
 * fresh bundles.
 *
 * @param {string} name - Container name
 * @returns {string} Absolute bundle directory path
 */
function bundle_path_for(name) {
	for (let base in BUNDLE_BASES) {
		let path = sprintf('%s/%s', base, name);
		if (fs.stat(sprintf('%s/config.json', path)))
			return path;
	}
	return sprintf('%s/%s', BUNDLE_BASES[0], name);
}

/**
 * @returns {boolean} True if crun binary exists
 */
export function available() {
	return !!fs.stat('/usr/bin/crun');
};

/**
 * @param {string} name - Container name
 * @returns {object} { status: 'running'|'stopped'|... }
 */
export function state(name) {
	let p = fs.popen(sprintf('crun state %s 2>/dev/null', name), 'r');
	if (!p)
		return { status: 'stopped' };

	let output = p.read('all') ?? '';
	p.close();

	let st = json(output);
	if (!st)
		return { status: 'stopped' };

	return { status: st.status ?? 'stopped' };
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function start(name) {
	let bundle = bundle_path_for(name);
	let rc = system(sprintf('crun run -d --bundle "%s" %s 2>/dev/null', bundle, name));
	return rc == 0;
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function stop(name) {
	system(sprintf('crun kill %s SIGTERM 2>/dev/null', name));
	system(sprintf('crun delete %s 2>/dev/null', name));
	return true;
};

/**
 * @returns {object} Container list keyed by name
 */
export function list() {
	let p = fs.popen('crun list -q 2>/dev/null', 'r');
	if (!p)
		return {};

	let output = trim(p.read('all') ?? '');
	p.close();

	let result = {};
	for (let line in split(output, '\n')) {
		line = trim(line);
		if (line == '')
			continue;
		let parts = split(line, /\s+/);
		let name = parts[0];
		if (!name)
			continue;
		let status = lc(parts[2] ?? 'stopped');
		result[name] = { status };
	}

	return result;
};

/**
 * Applies OCI config modifications from UCI container config.
 *
 * @param {string} name - Container name
 * @param {object} uci_cfg - Container config from uci.uc
 * @returns {boolean} True on success
 */
export function apply_config(name, uci_cfg) {
	let bundle = uci_cfg.bundle;
	if (!bundle)
		bundle = bundle_path_for(name);

	let oci = oci_config_read(bundle);
	if (!oci)
		return false;

	let limits = {
		memory_kib: uci_cfg.memory_kib,
		cpu_percent: uci_cfg.cpu_percent
	};
	if (limits.memory_kib > 0 || limits.cpu_percent > 0)
		oci_resources_apply(oci, limits);

	if (length(uci_cfg.mounts))
		oci_mounts_apply(oci, uci_cfg.mounts);

	if (length(uci_cfg.env_variables))
		oci_env_apply(oci, uci_cfg.env_variables);

	if (uci_cfg.uid_mapping && !uci_cfg.privileged)
		oci_userns_apply(oci, uci_cfg.uid_mapping);

	return oci_config_write(bundle, oci);
};

/**
 * @param {string} name - Container name
 * @param {string} bundle_path - OCI bundle path
 * @returns {boolean} True on success
 */
export function register(name, bundle_path) {
	return !!fs.stat(sprintf('%s/config.json', bundle_path));
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function unregister(name) {
	system(sprintf('crun delete -f %s 2>/dev/null', name));
	return true;
};

/**
 * @param {string} name - Container name
 * @returns {number} Memory usage in KiB, or -1
 */
export function memory_usage(name) {
	return cgroup_memory_read(name);
};

/**
 * @param {string} name - Container name
 * @returns {number} CPU usage percentage, or -1
 */
export function cpu_usage(name) {
	return cgroup_cpu_read(name);
};

/**
 * @param {string} name - Container name
 * @returns {object} { allocated: KiB, in_use: KiB }
 */
export function disk_usage(name) {
	let bundle = bundle_path_for(name);
	if (!fs.stat(bundle))
		return { allocated: -1, in_use: -1 };

	return {
		allocated: -1,
		in_use: ubbf.du_kib(bundle)
	};
};

/**
 * @param {string} name - Container name
 * @returns {object} { exit_code, running }
 */
export function exit_info(name) {
	let st = state(name);
	return {
		exit_code: 0,
		running: st.status == 'running'
	};
};
