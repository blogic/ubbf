'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_info, log_err } from 'ubbf.utils.logging';
import { memory_read as cgroup_memory_read, cpu_read as cgroup_cpu_read } from 'ubbf.container.cgroup';

const LXC_PATH = '/srv/lxc';

/**
 * @param {string} name - Container name
 * @returns {string} Absolute path to the LXC config file
 */
function config_path(name) {
	return sprintf('%s/%s/config', LXC_PATH, name);
}

/**
 * @param {string} name - Container name
 * @returns {string} Default rootfs directory used when UCI does not override it
 */
function rootfs_path(name) {
	return sprintf('%s/%s/rootfs', LXC_PATH, name);
}

/**
 * Translates lxc-info -sH output to the runtime-neutral status vocabulary used
 * by the rest of the daemon (running, paused, creating, stopping, stopped).
 *
 * @param {string} lxc_state - Raw state string from lxc-info
 * @returns {string} Normalised status
 */
function lxc_state_map(lxc_state) {
	lxc_state = trim(lxc_state ?? '');
	if (lxc_state == 'RUNNING')
		return 'running';
	if (lxc_state == 'FROZEN')
		return 'paused';
	if (lxc_state == 'STARTING')
		return 'creating';
	if (lxc_state == 'STOPPING')
		return 'stopping';
	return 'stopped';
}

/**
 * @returns {boolean} True if lxc-start binary exists
 */
export function available() {
	return !!fs.stat('/usr/bin/lxc-start');
};

/**
 * @param {string} name - Container name
 * @returns {object} { status: 'running'|'stopped'|... }
 */
export function state(name) {
	let p = fs.popen(sprintf('lxc-info -n %s -sH 2>/dev/null', name), 'r');
	if (!p)
		return { status: 'stopped' };

	let output = trim(p.read('all') ?? '');
	p.close();

	return { status: lxc_state_map(output) };
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function start(name) {
	let rc = system(sprintf('lxc-start -n %s -d 2>/dev/null', name));
	return rc == 0;
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function stop(name) {
	let rc = system(sprintf('lxc-stop -n %s -t 10 2>/dev/null', name));
	return rc == 0;
};

/**
 * @returns {object} Container list keyed by name
 */
export function list() {
	let p = fs.popen('lxc-ls -1 2>/dev/null', 'r');
	if (!p)
		return {};

	let output = trim(p.read('all') ?? '');
	p.close();

	let result = {};
	for (let name in split(output, '\n')) {
		name = trim(name);
		if (name == '')
			continue;
		result[name] = state(name);
	}

	return result;
};

/**
 * Generates LXC config file from UCI container config.
 *
 * @param {string} name - Container name
 * @param {object} uci_cfg - Container config from uci.uc
 * @returns {boolean} True on success
 */
export function apply_config(name, uci_cfg) {
	let container_dir = sprintf('%s/%s', LXC_PATH, name);
	fs.mkdir(container_dir, 0755);

	let rootfs = uci_cfg.rootfs;
	if (!rootfs)
		rootfs = rootfs_path(name);

	let lines = [
		sprintf('lxc.uts.name = %s', name),
		sprintf('lxc.rootfs.path = dir:%s', rootfs),
	];

	if (!uci_cfg.share_parent_network) {
		push(lines, 'lxc.net.0.type = veth');
		push(lines, 'lxc.net.0.link = br-virt');
		push(lines, 'lxc.net.0.name = eth0');
		push(lines, 'lxc.net.0.flags = up');
	}

	if (uci_cfg.memory_kib > 0)
		push(lines, sprintf('lxc.cgroup2.memory.max = %d', uci_cfg.memory_kib * 1024));

	if (uci_cfg.cpu_percent > 0)
		push(lines, sprintf('lxc.cgroup2.cpu.max = %d 100000', uci_cfg.cpu_percent * 1000));

	for (let m in (uci_cfg.mounts ?? [])) {
		let opts = m.Options ?? 'bind';
		push(lines, sprintf('lxc.mount.entry = %s %s none %s 0 0',
			m.Source, replace(m.Destination, /^\//, ''), opts));
	}

	for (let ev in (uci_cfg.env_variables ?? []))
		push(lines, sprintf('lxc.environment = %s=%s', ev.Key, ev.Value));

	if (uci_cfg.uid_mapping && !uci_cfg.privileged) {
		let uid = uci_cfg.uid_mapping;
		push(lines, sprintf('lxc.idmap = u 0 %d %d', uid.host_id, uid.size));
		push(lines, sprintf('lxc.idmap = g 0 %d %d', uid.host_id, uid.size));
	}

	push(lines, '');
	return !!fs.writefile(config_path(name), join('\n', lines));
};

/**
 * @param {string} name - Container name
 * @param {string} rootfs - Path to rootfs directory
 * @returns {boolean} True on success
 */
export function register(name, rootfs) {
	let container_dir = sprintf('%s/%s', LXC_PATH, name);
	fs.mkdir(container_dir, 0755);
	fs.mkdir(sprintf('%s/rootfs', container_dir), 0755);

	let lines = [
		sprintf('lxc.uts.name = %s', name),
		sprintf('lxc.rootfs.path = dir:%s', rootfs ?? rootfs_path(name)),
		''
	];

	return !!fs.writefile(config_path(name), join('\n', lines));
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function unregister(name) {
	system(sprintf('lxc-destroy -n %s -f 2>/dev/null', name));
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
	let rootfs = rootfs_path(name);
	if (!fs.stat(rootfs))
		return { allocated: -1, in_use: -1 };

	return {
		allocated: -1,
		in_use: ubbf.du_kib(rootfs)
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
