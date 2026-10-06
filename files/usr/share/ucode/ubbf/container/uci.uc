'use strict';

import { cursor } from 'uci';
import { log_err } from 'ubbf.utils.logging';

const CONFIG_NAME = 'containers';

/**
 * @returns {object} Daemon globals section
 */
export function globals_read() {
	let uci = cursor();
	if (!uci.load(CONFIG_NAME))
		return { default_runtime: 'uxc', monitor_interval: 10 };

	return {
		default_runtime: uci.get(CONFIG_NAME, 'main', 'default_runtime') ?? 'uxc',
		monitor_interval: +(uci.get(CONFIG_NAME, 'main', 'monitor_interval') ?? '10')
	};
};

/**
 * Collects all anonymous child sections of a given type for a container.
 *
 * @param {object} uci - UCI cursor
 * @param {string} section_type - UCI section type
 * @param {string} container_name - Parent container name
 * @param {function} map_fn - Maps section data to output object
 * @returns {array} Array of mapped child objects
 */
function children_collect(uci, section_type, container_name, map_fn) {
	let result = [];
	let all = uci.get_all(CONFIG_NAME);
	if (!all)
		return result;

	for (let name, section in all) {
		if (section['.type'] != section_type)
			continue;
		if (section.container != container_name)
			continue;
		push(result, map_fn(section));
	}

	return result;
}

/**
 * Maps a container_port_forward UCI section to its in-memory representation.
 *
 * @param {object} s - Raw UCI section
 * @returns {object} { external_port, internal_port, protocol }
 */
function port_forward_map(s) {
	return {
		external_port: s.external_port ?? '',
		internal_port: s.internal_port ?? s.external_port ?? '',
		protocol: s.protocol ?? 'tcp'
	};
}

/**
 * Maps a container_mount UCI section to its TR-181-style representation.
 *
 * @param {object} s - Raw UCI section
 * @returns {object} { Source, Destination, Options }
 */
function mount_map(s) {
	return {
		Source: s.source ?? '',
		Destination: s.destination ?? '',
		Options: s.options ?? 'bind'
	};
}

/**
 * Maps a container_env UCI section to its TR-181-style representation.
 *
 * @param {object} s - Raw UCI section
 * @returns {object} { Key, Value }
 */
function env_map(s) {
	return {
		Key: s.key ?? '',
		Value: s.value ?? ''
	};
}

/**
 * Maps a container_appdata UCI section to its TR-181-style representation.
 *
 * @param {object} s - Raw UCI section
 * @returns {object} { Name, Capacity, Retain, AccessPath }
 */
function appdata_map(s) {
	return {
		Name: s.name ?? '',
		Capacity: +(s.capacity ?? '-1'),
		Retain: s.retain ?? 'none',
		AccessPath: s.access_path ?? ''
	};
}

/**
 * Reads the optional UID/GID mapping section associated with a container.
 *
 * @param {object} uci - UCI cursor
 * @param {string} container_name - Parent container name
 * @returns {object|null} { host_id, container_id, size } or null when absent
 */
function uid_map_read(uci, container_name) {
	let all = uci.get_all(CONFIG_NAME);
	if (!all)
		return null;

	for (let name, section in all) {
		if (section['.type'] != 'container_uid_map')
			continue;
		if (section.container != container_name)
			continue;
		return {
			host_id: +(section.host_id ?? '0'),
			container_id: +(section.container_id ?? '0'),
			size: +(section.size ?? '65536')
		};
	}

	return null;
}

/**
 * Reads a single container section with all child objects.
 *
 * @param {object} uci - UCI cursor
 * @param {string} name - Container section name
 * @param {object} section - Raw UCI section data
 * @returns {object} Complete container config
 */
function container_parse(uci, name, section) {
	return {
		name,
		runtime: section.runtime ?? 'uxc',
		uuid: section.uuid ?? '',
		vendor: section.vendor ?? '',
		version: section.version ?? '',
		url: section.url ?? '',
		exec_env_ref: section.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1',
		instance: +(section.instance ?? '0'),
		bundle: section.bundle ?? '',
		rootfs: section.rootfs ?? '',
		autostart: section.autostart == '1',
		privileged: section.privileged != '0',
		installed: section.installed ?? '',
		last_update: section.last_update ?? '',
		memory_kib: +(section.memory_kib ?? '-1'),
		cpu_percent: +(section.cpu_percent ?? '-1'),
		disk_space_kib: +(section.disk_space_kib ?? '-1'),
		autorestart: section.autorestart == '1',
		restart_min_wait: +(section.restart_min_wait ?? '5'),
		restart_max_wait: +(section.restart_max_wait ?? '300'),
		restart_multiplier: +(section.restart_multiplier ?? '2000'),
		restart_max_retries: +(section.restart_max_retries ?? '0'),
		restart_reset_period: +(section.restart_reset_period ?? '0'),
		share_parent_network: section.share_parent_network == '1',
		port_forwards: children_collect(uci, 'container_port_forward', name, port_forward_map),
		mounts: children_collect(uci, 'container_mount', name, mount_map),
		env_variables: children_collect(uci, 'container_env', name, env_map),
		application_data: children_collect(uci, 'container_appdata', name, appdata_map),
		uid_mapping: uid_map_read(uci, name)
	};
}

/**
 * Reads all container configs from UCI.
 *
 * @returns {object} Map of container name -> config
 */
export function containers_read() {
	let uci = cursor();
	if (!uci.load(CONFIG_NAME))
		return {};

	let all = uci.get_all(CONFIG_NAME);
	if (!all)
		return {};

	let result = {};
	for (let name, section in all) {
		if (section['.type'] != 'container')
			continue;
		result[name] = container_parse(uci, name, section);
	}

	return result;
};

/**
 * Reads a single container config from UCI.
 *
 * @param {string} name - Container name
 * @returns {object|null} Container config or null
 */
export function container_read(name) {
	let uci = cursor();
	if (!uci.load(CONFIG_NAME))
		return null;

	let section = uci.get_all(CONFIG_NAME, name);
	if (!section || section['.type'] != 'container')
		return null;

	return container_parse(uci, name, section);
};

/**
 * Removes all child sections for a container.
 *
 * @param {object} uci - UCI cursor
 * @param {string} container_name - Parent container name
 */
function children_remove(uci, container_name) {
	let child_types = [
		'container_port_forward', 'container_mount', 'container_env',
		'container_appdata', 'container_uid_map'
	];

	let all = uci.get_all(CONFIG_NAME);
	if (!all)
		return;

	let to_delete = [];
	for (let sid, section in all) {
		if (index(child_types, section['.type']) < 0)
			continue;
		if (section.container != container_name)
			continue;
		push(to_delete, sid);
	}

	for (let sid in to_delete)
		uci.delete(CONFIG_NAME, sid);
}

/**
 * Writes a container section and its child objects to UCI.
 *
 * @param {string} name - Container name
 * @param {object} cfg - Container config (same format as container_parse output)
 * @returns {boolean} True on success
 */
export function container_write(name, cfg) {
	let uci = cursor();
	if (!uci.load(CONFIG_NAME))
		return false;

	let existing = uci.get_all(CONFIG_NAME, name);
	if (!existing)
		uci.set(CONFIG_NAME, name, 'container');

	uci.set(CONFIG_NAME, name, 'runtime', cfg.runtime ?? 'uxc');
	uci.set(CONFIG_NAME, name, 'uuid', cfg.uuid ?? '');
	uci.set(CONFIG_NAME, name, 'vendor', cfg.vendor ?? '');
	uci.set(CONFIG_NAME, name, 'version', cfg.version ?? '');
	uci.set(CONFIG_NAME, name, 'url', cfg.url ?? '');
	uci.set(CONFIG_NAME, name, 'exec_env_ref', cfg.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1');
	uci.set(CONFIG_NAME, name, 'instance', sprintf('%d', cfg.instance ?? 0));
	uci.set(CONFIG_NAME, name, 'bundle', cfg.bundle ?? '');
	uci.set(CONFIG_NAME, name, 'autostart', cfg.autostart ? '1' : '0');
	uci.set(CONFIG_NAME, name, 'privileged', cfg.privileged ? '1' : '0');
	uci.set(CONFIG_NAME, name, 'installed', cfg.installed ?? '');
	uci.set(CONFIG_NAME, name, 'last_update', cfg.last_update ?? '');
	uci.set(CONFIG_NAME, name, 'memory_kib', sprintf('%d', cfg.memory_kib ?? -1));
	uci.set(CONFIG_NAME, name, 'cpu_percent', sprintf('%d', cfg.cpu_percent ?? -1));
	uci.set(CONFIG_NAME, name, 'disk_space_kib', sprintf('%d', cfg.disk_space_kib ?? -1));
	uci.set(CONFIG_NAME, name, 'autorestart', cfg.autorestart ? '1' : '0');
	uci.set(CONFIG_NAME, name, 'restart_min_wait', sprintf('%d', cfg.restart_min_wait ?? 5));
	uci.set(CONFIG_NAME, name, 'restart_max_wait', sprintf('%d', cfg.restart_max_wait ?? 300));
	uci.set(CONFIG_NAME, name, 'restart_multiplier', sprintf('%d', cfg.restart_multiplier ?? 2000));
	uci.set(CONFIG_NAME, name, 'restart_max_retries', sprintf('%d', cfg.restart_max_retries ?? 0));
	uci.set(CONFIG_NAME, name, 'restart_reset_period', sprintf('%d', cfg.restart_reset_period ?? 0));
	uci.set(CONFIG_NAME, name, 'share_parent_network', cfg.share_parent_network ? '1' : '0');

	if (cfg.rootfs)
		uci.set(CONFIG_NAME, name, 'rootfs', cfg.rootfs);

	children_remove(uci, name);

	for (let pf in (cfg.port_forwards ?? [])) {
		let sid = uci.add(CONFIG_NAME, 'container_port_forward');
		uci.set(CONFIG_NAME, sid, 'container', name);
		uci.set(CONFIG_NAME, sid, 'external_port', pf.external_port ?? '');
		uci.set(CONFIG_NAME, sid, 'internal_port', pf.internal_port ?? pf.external_port ?? '');
		uci.set(CONFIG_NAME, sid, 'protocol', pf.protocol ?? 'tcp');
	}

	for (let mt in (cfg.mounts ?? [])) {
		let sid = uci.add(CONFIG_NAME, 'container_mount');
		uci.set(CONFIG_NAME, sid, 'container', name);
		uci.set(CONFIG_NAME, sid, 'source', mt.Source ?? '');
		uci.set(CONFIG_NAME, sid, 'destination', mt.Destination ?? '');
		uci.set(CONFIG_NAME, sid, 'options', mt.Options ?? 'bind');
	}

	for (let ev in (cfg.env_variables ?? [])) {
		let sid = uci.add(CONFIG_NAME, 'container_env');
		uci.set(CONFIG_NAME, sid, 'container', name);
		uci.set(CONFIG_NAME, sid, 'key', ev.Key ?? '');
		uci.set(CONFIG_NAME, sid, 'value', ev.Value ?? '');
	}

	for (let ad in (cfg.application_data ?? [])) {
		let sid = uci.add(CONFIG_NAME, 'container_appdata');
		uci.set(CONFIG_NAME, sid, 'container', name);
		uci.set(CONFIG_NAME, sid, 'name', ad.Name ?? '');
		uci.set(CONFIG_NAME, sid, 'capacity', sprintf('%d', ad.Capacity ?? -1));
		uci.set(CONFIG_NAME, sid, 'retain', ad.Retain ?? 'none');
		uci.set(CONFIG_NAME, sid, 'access_path', ad.AccessPath ?? '');
	}

	if (cfg.uid_mapping) {
		let sid = uci.add(CONFIG_NAME, 'container_uid_map');
		uci.set(CONFIG_NAME, sid, 'container', name);
		uci.set(CONFIG_NAME, sid, 'host_id', sprintf('%d', cfg.uid_mapping.host_id ?? 0));
		uci.set(CONFIG_NAME, sid, 'container_id', sprintf('%d', cfg.uid_mapping.container_id ?? 0));
		uci.set(CONFIG_NAME, sid, 'size', sprintf('%d', cfg.uid_mapping.size ?? 65536));
	}

	uci.commit(CONFIG_NAME);
	return true;
};

/**
 * Removes a container and all its child sections from UCI.
 *
 * @param {string} name - Container name
 * @returns {boolean} True on success
 */
export function container_remove(name) {
	let uci = cursor();
	if (!uci.load(CONFIG_NAME))
		return false;

	children_remove(uci, name);
	uci.delete(CONFIG_NAME, name);
	uci.commit(CONFIG_NAME);
	return true;
};

/**
 * Allocates the lowest free instance number across all containers.
 *
 * @returns {number} Lowest free instance number (1-based)
 */
export function instance_allocate() {
	let containers = containers_read();
	let used = {};

	for (let name, cfg in containers) {
		if (cfg.instance > 0)
			used[cfg.instance] = true;
	}

	for (let i = 1; ; i++) {
		if (!used[i])
			return i;
	}
};
