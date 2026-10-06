'use strict';

import * as fs from 'fs';

/**
 * @param {string} bundle_path - Path to OCI bundle
 * @returns {object|null} Parsed OCI config or null
 */
export function config_read(bundle_path) {
	let content = fs.readfile(sprintf('%s/config.json', bundle_path));
	return content ? json(content) : null;
};

/**
 * @param {string} bundle_path - Path to OCI bundle
 * @param {object} config - OCI configuration object
 * @returns {boolean} True on success
 */
export function config_write(bundle_path, config) {
	return !!fs.writefile(sprintf('%s/config.json', bundle_path), sprintf('%.J\n', config));
};

/**
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {object} limits - { memory_kib, cpu_percent }
 */
export function resources_apply(oci, limits) {
	oci.linux ??= {};
	oci.linux.resources ??= {};

	if (limits.memory_kib > 0) {
		oci.linux.resources.memory ??= {};
		oci.linux.resources.memory.limit = limits.memory_kib * 1024;
	}

	if (limits.cpu_percent > 0) {
		oci.linux.resources.cpu ??= {};
		oci.linux.resources.cpu.quota = limits.cpu_percent * 1000;
		oci.linux.resources.cpu.period = 100000;
	}
};

/**
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {array} mounts - Array of { Source, Destination, Options }
 */
export function mounts_apply(oci, mounts) {
	oci.mounts ??= [];

	for (let m in mounts) {
		let options = ['bind'];
		if (m.Options)
			push(options, ...split(m.Options, ','));

		push(oci.mounts, {
			destination: m.Destination,
			source: m.Source,
			type: 'bind',
			options
		});
	}
};

/**
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {array} env_vars - Array of { Key, Value }
 */
export function env_apply(oci, env_vars) {
	oci.process ??= {};
	oci.process.env ??= [];

	for (let v in env_vars)
		push(oci.process.env, sprintf('%s=%s', v.Key, v.Value));
};

/**
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {object} mapping - { host_id, container_id, size }
 */
export function userns_apply(oci, mapping) {
	oci.linux ??= {};
	oci.linux.namespaces ??= [];

	let has_userns;
	for (let ns in oci.linux.namespaces) {
		if (ns.type == 'user') {
			has_userns = true;
			break;
		}
	}

	if (!has_userns)
		push(oci.linux.namespaces, { type: 'user' });

	let id_map = {
		hostID: mapping.host_id,
		containerID: mapping.container_id ?? 0,
		size: mapping.size ?? 1
	};

	oci.linux.uidMappings = [id_map];
	oci.linux.gidMappings = [id_map];
};
