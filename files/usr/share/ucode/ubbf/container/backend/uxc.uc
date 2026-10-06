'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import { log_info, log_err } from 'ubbf.utils.logging';
import {
	config_read as oci_config_read, config_write as oci_config_write,
	resources_apply as oci_resources_apply, mounts_apply as oci_mounts_apply,
	env_apply as oci_env_apply, userns_apply as oci_userns_apply
} from 'ubbf.container.oci';
import {
	memory_read as cgroup_memory_read, cpu_read as cgroup_cpu_read
} from 'ubbf.container.cgroup';

const UXC_CONFIG_DIRS = ['/etc/uxc', '/tmp/run/uvol/.meta/uxc'];

/**
 * Finds the first UXC config directory that already holds <name>.json.
 *
 * @param {string} name - Container name
 * @returns {string|null} Directory containing the config, or null if absent
 */
function config_dir_find(name) {
	for (let dir in UXC_CONFIG_DIRS) {
		if (fs.stat(sprintf('%s/%s.json', dir, name)))
			return dir;
	}
	return null;
}

/**
 * Resolves the on-disk UXC config path for a container, defaulting to /etc/uxc.
 *
 * @param {string} name - Container name
 * @returns {string} Absolute path to <dir>/<name>.json
 */
function config_path(name) {
	let dir = config_dir_find(name) ?? '/etc/uxc';
	return sprintf('%s/%s.json', dir, name);
}

/**
 * Writes JSON data atomically so a crash leaves the old file intact.
 *
 * @param {string} path - Final destination path
 * @param {object} data - Object serialised as pretty-printed JSON
 * @returns {boolean} True on success
 */
function config_write_atomic(path, data) {
	return ubbf.write_file_atomic(path, sprintf('%.J\n', data));
}

/**
 * Reads the existing UXC config for a container from the first directory that
 * contains a valid entry.
 *
 * @param {string} name - Container name
 * @returns {object|null} Parsed config object or null when not found
 */
function config_read(name) {
	for (let dir in UXC_CONFIG_DIRS) {
		let content = fs.readfile(sprintf('%s/%s.json', dir, name));
		if (!content)
			continue;
		let cfg = json(content);
		if (cfg?.name)
			return cfg;
	}
	return null;
}

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
	let cfg = config_read(name);
	let volumes = cfg?.volumes;
	if (!volumes || !length(volumes))
		return { allocated: -1, in_use: -1 };

	let p = fs.popen('uvol list 2>/dev/null', 'r');
	if (!p)
		return { allocated: -1, in_use: -1 };

	let output = p.read('all') ?? '';
	p.close();

	let allocated = 0;
	let ro_size = 0;
	for (let hash in volumes) {
		let m = match(output, regexp(hash + '\\s+\\S+\\s+(\\d+)'));
		if (m) {
			allocated += +m[1];
			ro_size += +m[1];
		}
	}

	let overlay_usage = 0;
	let overlay_path = cfg['write-overlay-path'];
	if (overlay_path) {
		let overlay_name = sprintf('%s-overlay', name);
		let m = match(output, regexp(overlay_name + '\\s+\\S+\\s+(\\d+)'));
		if (m)
			allocated += +m[1];

		let kib = ubbf.du_kib(overlay_path);
		if (kib > 0)
			overlay_usage = kib;
	}

	if (!allocated)
		return { allocated: -1, in_use: -1 };

	return {
		allocated: int(allocated / 1024),
		in_use: int(ro_size / 1024) + overlay_usage
	};
};

/**
 * @param {string} name - Container name
 * @returns {object|null} Container state { status: 'running'|'stopped'|... }
 */
export function state(name) {
	return ubus?.call(sprintf('container.%s', name), 'state', {});
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function start(name) {
	return !!ubus?.call('container', 'state', { name, spawn: true });
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function stop(name) {
	return !!ubus?.call('container', 'state', { name, spawn: false });
};

/**
 * @returns {object} Container list from procd
 */
export function list() {
	return ubus?.call('container', 'list', {}) ?? {};
};

/**
 * Generates /etc/uxc/<name>.json from UCI container config.
 *
 * @param {string} name - Container name
 * @param {object} uci_cfg - Container config from uci.uc
 * @returns {boolean} True on success
 */
export function apply_config(name, uci_cfg) {
	let bundle_path = uci_cfg.bundle;
	if (!bundle_path)
		return false;

	let uxc_cfg = config_read(name) ?? {
		name,
		path: bundle_path,
		autostart: false
	};

	uxc_cfg.autostart = uci_cfg.autostart;

	let oci = oci_config_read(bundle_path);
	if (oci) {
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

		oci_config_write(bundle_path, oci);
	}

	let path = config_path(name);
	fs.mkdir('/etc/uxc', 0755);
	return config_write_atomic(path, uxc_cfg);
};

/**
 * Registers a container with procd.
 *
 * @param {string} name - Container name
 * @param {string} bundle_path - OCI bundle path
 * @returns {boolean} True on success
 */
export function register(name, bundle_path) {
	let uxc_cfg = {
		name,
		path: bundle_path,
		autostart: false
	};

	let path = config_path(name);
	fs.mkdir('/etc/uxc', 0755);
	return config_write_atomic(path, uxc_cfg);
};

/**
 * Removes a container from procd and deletes its UXC config.
 *
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function unregister(name) {
	ubus?.call('container', 'delete', { name });

	for (let dir in UXC_CONFIG_DIRS)
		fs.unlink(sprintf('%s/%s.json', dir, name));

	return true;
};

/**
 * Gets container exit code from procd container list.
 *
 * @param {string} name - Container name
 * @returns {object} { exit_code: number, running: boolean }
 */
export function exit_info(name) {
	let ct_list = ubus?.call('container', 'list', {});
	let ct_info = ct_list?.[name]?.instances?.[name];
	return {
		exit_code: ct_info?.exit_code ?? 0,
		running: ct_info?.running ?? false
	};
};

/**
 * @returns {boolean} True if /sbin/uxc exists
 */
export function available() {
	return !!fs.stat('/sbin/uxc');
};
