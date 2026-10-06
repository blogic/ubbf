'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import { log_err } from 'ubbf.utils.logging';

const UXC_CONFIG_DIRS = [
	'/etc/uxc',
	'/tmp/run/uvol/.meta/uxc'
];

/**
 * Finds the UXC config directory that contains a given container.
 *
 * @param {string} name - Container name
 * @returns {string|null} Directory path or null
 */
function uxc_config_dir_find(name) {
	for (let dir in UXC_CONFIG_DIRS) {
		if (fs.stat(sprintf('%s/%s.json', dir, name)))
			return dir;
	}
	return null;
}

/**
 * Finds a writable UXC config directory, preferring /etc/uxc.
 *
 * @returns {string} Directory path
 */
function uxc_config_dir_writable() {
	return '/etc/uxc';
}

/**
 * Reads all UXC container configurations from disk.
 * Searches both /etc/uxc and uvol .meta paths.
 *
 * @returns {array} Array of container configuration objects
 */
export function uxc_configs_read() {
	let configs = [];
	let seen = {};

	for (let dir in UXC_CONFIG_DIRS) {
		let files = fs.lsdir(dir);
		if (!files)
			continue;

		for (let file in files) {
			if (!match(file, /\.json$/))
				continue;

			let path = sprintf('%s/%s', dir, file);
			let content = fs.readfile(path);
			if (!content)
				continue;

			let cfg = json(content);
			if (!cfg || !cfg.name)
				continue;

			if (seen[cfg.name])
				continue;

			seen[cfg.name] = true;
			push(configs, cfg);
		}
	}

	return configs;
};

/**
 * Reads a single UXC container configuration from disk.
 *
 * @param {string} name - Container name
 * @returns {object|null} Container configuration or null
 */
export function uxc_config_read(name) {
	for (let dir in UXC_CONFIG_DIRS) {
		let path = sprintf('%s/%s.json', dir, name);
		let content = fs.readfile(path);
		if (!content)
			continue;

		let cfg = json(content);
		if (!cfg || !cfg.name)
			continue;

		return cfg;
	}

	return null;
};

/**
 * Writes a UXC container configuration to disk atomically.
 * Writes to the directory where the config already exists,
 * or /etc/uxc for new containers.
 *
 * @param {string} name - Container name
 * @param {object} config - Configuration object to write
 * @returns {boolean} True on success
 */
export function uxc_config_write(name, config) {
	let dir = uxc_config_dir_find(name) ?? uxc_config_dir_writable();
	let path = sprintf('%s/%s.json', dir, name);

	fs.mkdir(dir, 0755);

	if (!ubbf.write_file_atomic(path, sprintf('%.J\n', config))) {
		log_err('container: failed to atomically write %s', path);
		return false;
	}

	return true;
};

/**
 * Gets the UBBF metadata block from a container's UXC config.
 *
 * @param {string} name - Container name
 * @returns {object|null} UBBF metadata or null
 */
export function uxc_meta_get(name) {
	return uxc_config_read(name)?.ubbf;
};

/**
 * Merges updates into a container's UBBF metadata block.
 *
 * @param {string} name - Container name
 * @param {object} updates - Key/value pairs to merge into .ubbf
 * @returns {boolean} True on success
 */
export function uxc_meta_update(name, updates) {
	let config = uxc_config_read(name);
	if (!config)
		return false;

	config.ubbf ??= {};
	for (let k in updates)
		config.ubbf[k] = updates[k];

	return uxc_config_write(name, config);
};

/**
 * Gets container runtime state via ubus.
 *
 * @param {string} name - Container name
 * @returns {object|null} Container state or null
 */
export function container_state_get(name) {
	return ubus?.call(sprintf('container.%s', name), 'state', {});
};

/**
 * Lists all containers via ubus.
 *
 * @returns {object} Container list keyed by name
 */
export function containers_list() {
	let result = ubus?.call('container', 'list', {});
	return result ?? {};
};

/**
 * Maps OCI container status to TR-181 ExecutionUnit status.
 *
 * @param {string} oci_status - OCI status (running, stopped, etc.)
 * @returns {string} TR-181 status (Active, Idle, Starting, Stopping)
 */
export function oci_status_to_tr181(oci_status) {
	if (oci_status == 'running')
		return 'Active';
	if (oci_status == 'stopped')
		return 'Idle';
	if (oci_status == 'creating')
		return 'Starting';
	if (oci_status == 'stopping')
		return 'Stopping';
	return 'Idle';
};

/**
 * Generates a deterministic UUID for a deployment unit.
 *
 * @param {string} name - Container name
 * @param {string} vendor - Vendor name
 * @returns {string} UUID string
 */
export function uuid_generate(name, vendor) {
	let namespace = 'openwrt.org:uxc';
	let input = sprintf('%s:%s:%s', namespace, vendor ?? 'unknown', name);
	let hash = '';

	for (let i = 0; i < length(input); i++)
		hash = sprintf('%s%02x', hash, ord(input, i));

	return sprintf('%s-%s-%s-%s-%s',
		substr(hash, 0, 8),
		substr(hash, 8, 4),
		'5' + substr(hash, 13, 3),
		substr(hash, 16, 4),
		substr(hash, 20, 12)
	);
};

/**
 * Gets container name from TR-181 instance number.
 *
 * @param {number} instance - TR-181 instance number
 * @returns {string|null} Container name or null
 */
export function container_name_from_instance(instance) {
	let configs = uxc_configs_read();

	for (let cfg in configs) {
		if (cfg.ubbf?.instance == instance)
			return cfg.name;
	}

	return null;
};

/**
 * Gets deployment unit name from TR-181 instance number.
 *
 * @param {number} instance - TR-181 instance number
 * @returns {string|null} Deployment unit name or null
 */
export function du_name_from_instance(instance) {
	return container_name_from_instance(instance);
};

/**
 * Allocates the lowest free instance number across all containers.
 *
 * @returns {number} Lowest free instance number (1-based)
 */
export function instance_allocate() {
	let configs = uxc_configs_read();
	let used = {};

	for (let cfg in configs) {
		let inst = cfg.ubbf?.instance;
		if (inst)
			used[inst] = true;
	}

	for (let i = 1; ; i++) {
		if (!used[i])
			return i;
	}
};

/**
 * Reads the OCI runtime config.json from a bundle directory.
 *
 * @param {string} bundle_path - Path to OCI bundle
 * @returns {object|null} Parsed OCI config or null
 */
export function oci_config_read(bundle_path) {
	let path = sprintf('%s/config.json', bundle_path);
	let content = fs.readfile(path);
	if (!content)
		return null;

	return json(content);
};

/**
 * Writes the OCI runtime config.json to a bundle directory.
 *
 * @param {string} bundle_path - Path to OCI bundle
 * @param {object} config - OCI configuration object
 * @returns {boolean} True on success
 */
export function oci_config_write(bundle_path, config) {
	let path = sprintf('%s/config.json', bundle_path);
	let written = fs.writefile(path, sprintf('%.J\n', config));
	if (!written) {
		log_err('container: failed to write OCI config %s', path);
		return false;
	}
	return true;
};

/**
 * Sets resource limits in an OCI config.
 *
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {object} limits - Resource limits (memory_kib, cpu_percent, disk_space_kib)
 */
export function oci_resources_set(oci, limits) {
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
 * Appends bind mount entries to an OCI config.
 *
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {array} host_objects - Array of {Source, Destination, Options}
 */
export function oci_mounts_set(oci, host_objects) {
	oci.mounts ??= [];

	for (let obj in host_objects) {
		let options = ['bind'];
		if (obj.Options)
			push(options, ...split(obj.Options, ','));

		push(oci.mounts, {
			destination: obj.Destination,
			source: obj.Source,
			type: 'bind',
			options
		});
	}
};

/**
 * Appends environment variables to an OCI config.
 *
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {array} env_vars - Array of {Key, Value}
 */
export function oci_env_set(oci, env_vars) {
	oci.process ??= {};
	oci.process.env ??= [];

	for (let v in env_vars)
		push(oci.process.env, sprintf('%s=%s', v.Key, v.Value));
};

/**
 * Configures user namespace mappings in an OCI config.
 *
 * @param {object} oci - OCI configuration object (modified in place)
 * @param {object} mapping - UID/GID mapping with host_id, container_id, size
 */
export function oci_userns_set(oci, mapping) {
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

	oci.linux.uidMappings = [{
		hostID: mapping.host_id,
		containerID: mapping.container_id ?? 0,
		size: mapping.size ?? 1
	}];

	oci.linux.gidMappings = [{
		hostID: mapping.host_id,
		containerID: mapping.container_id ?? 0,
		size: mapping.size ?? 1
	}];
};

/**
 * Detects the cgroup base path for a container.
 *
 * @param {string} name - Container name
 * @returns {object|null} Object with version (1 or 2) and path, or null
 */
export function cgroup_path_detect(name) {
	if (fs.stat('/sys/fs/cgroup/cgroup.controllers')) {
		let paths = [
			sprintf('/sys/fs/cgroup/containers/%s/%s', name, name),
			sprintf('/sys/fs/cgroup/services/%s/%s', name, name),
			sprintf('/sys/fs/cgroup/system.slice/uxc-%s.scope', name),
			sprintf('/sys/fs/cgroup/uxc/%s', name)
		];
		for (let p in paths) {
			if (fs.stat(p))
				return { version: 2, path: p };
		}
		return null;
	}

	let path = sprintf('/sys/fs/cgroup/memory/uxc/%s', name);
	if (fs.stat(path))
		return { version: 1, path };

	return null;
};

/**
 * Reads current memory usage for a container from cgroup.
 *
 * @param {string} name - Container name
 * @returns {number} Memory usage in KiB, or -1 on failure
 */
export function cgroup_memory_read(name) {
	let cg = cgroup_path_detect(name);
	if (!cg)
		return -1;

	let file = (cg.version == 2)
		? sprintf('%s/memory.current', cg.path)
		: sprintf('%s/memory.usage_in_bytes', cg.path);

	let content = ubbf.readfile_trim(file, '');
	let bytes = +content;
	if (bytes == null || bytes != bytes)
		return -1;

	return int(bytes / 1024);
};

/**
 * Reads current CPU usage for a container from cgroup.
 *
 * @param {string} name - Container name
 * @returns {number} CPU usage percentage, or -1 on failure
 */
export function cgroup_cpu_read(name) {
	let cg = cgroup_path_detect(name);
	if (!cg)
		return -1;

	if (cg.version == 2) {
		let content = fs.readfile(sprintf('%s/cpu.stat', cg.path));
		if (!content)
			return -1;

		let m = match(content, /usage_usec\s+(\d+)/);
		if (!m)
			return -1;

		return int(+m[1] / 10000);
	}

	let content = ubbf.readfile_trim(sprintf('%s/cpuacct.usage', cg.path), '');
	let ns = +content;
	if (ns == null || ns != ns)
		return -1;

	return int(ns / 10000000);
};

/**
 * Checks whether a container was installed via APK package.
 *
 * @param {string} name - Container name
 * @returns {boolean} True if container-<name> APK is installed
 */
export function is_apk_installed(name) {
	return ubbf.apk_installed(`container-${name}`);
};

/**
 * Emits a DUStateChange! event via USP.
 *
 * @param {object} params - Event parameters
 * @param {string} params.uuid - Deployment unit UUID
 * @param {string} params.version - Version string
 * @param {string} params.state - CurrentState (Installed, Uninstalled, Failed)
 * @param {string} params.operation - OperationPerformed (Install, Update, Uninstall)
 * @param {string} params.exec_env_ref - ExecutionEnvironment reference
 * @param {number} params.fault_code - Fault code (0 for success)
 * @param {string} params.fault_string - Fault description
 */
export function du_state_change_emit(params) {
	usp_datamodel_event('Device.SoftwareModules.DUStateChange!', {
		UUID: params.uuid ?? '',
		Version: params.version ?? '',
		CurrentState: params.state,
		OperationPerformed: params.operation,
		ExecutionEnvRef: params.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1',
		FaultCode: sprintf('%d', params.fault_code ?? 0),
		FaultString: params.fault_string ?? ''
	});
};
