'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.SoftwareModules';
import { du_state_change_emit, oci_status_to_tr181 } from 'ubbf.utils.container';
import { container_read, container_write } from 'ubbf.container.uci';
import { rmdir_recursive } from 'ubbf.container.daemon';
import * as ubbf from 'ubbf';
import {
	config_apply, execenvs_read, execenvs_write,
	execenv_classes_read
} from 'ubbf.tr181.SoftwareModules.common';

let _model = {};
let _operations = {};

if (fs.stat('/sbin/uxc')) {

	/**
	 * Invokes a method on the ubbf-container ubus object.
	 *
	 * @param {string} method - ubus method name
	 * @param {object} [args] - Optional method arguments
	 * @returns {object|null} ubus reply or null when ubus is unavailable
	 */
	function daemon_call(method, args) {
		return ubus?.call('ubbf-container', method, args ?? {});
	}

	/**
	 * Fetches the container list from the ubbf-container daemon.
	 *
	 * @returns {object} Map of container name to container record
	 */
	function daemon_list() {
		let result = daemon_call('list');
		return result?.containers ?? {};
	}

	/**
	 * Fetches detailed info for a single container from the daemon.
	 *
	 * @param {string} name - Container name
	 * @returns {object|null} Daemon info reply
	 */
	function daemon_info(name) {
		return daemon_call('info', { name });
	}

	/**
	 * Resolves a TR-181 ExecutionUnit instance to its container name.
	 *
	 * @param {number} instance - ExecutionUnit instance number
	 * @returns {string|null} Container name or null when not found
	 */
	function name_from_instance(instance) {
		let containers = daemon_list();
		for (let name, ct in containers) {
			if (ct.instance == instance)
				return name;
		}
		return null;
	}

	/**
	 * Filters the daemon container list to entries belonging to an ExecEnv.
	 *
	 * @param {number} ee_instance - ExecEnv instance number
	 * @returns {object} Map of container name to container record for the EE
	 */
	function containers_for_ee(ee_instance) {
		let ee_ref = sprintf('Device.SoftwareModules.ExecEnv.%d', ee_instance);
		let containers = daemon_list();
		let result = {};
		for (let name, ct in containers) {
			if ((ct.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1') == ee_ref)
				result[name] = ct;
		}
		return result;
	}

	/**
	 * Get handler for Device.SoftwareModules.
	 *
	 * @param {object} ctx - Handler context
	 * @returns {object} SoftwareModules properties with instance counts
	 */
	function softwaremodules_get(ctx) {
		let containers = daemon_list();
		return {
			ExecEnvClassNumberOfEntries: sprintf('%d', length(keys(execenv_classes_read()))),
			ExecEnvNumberOfEntries: sprintf('%d', length(execenvs_read())),
			DeploymentUnitNumberOfEntries: sprintf('%d', length(containers)),
			ExecutionUnitNumberOfEntries: sprintf('%d', length(containers))
		};
	}

	/**
	 * Get handler for Device.SoftwareModules.ExecEnvClass.{i}.
	 *
	 * @param {object} ctx - Handler context with optional instance number
	 * @returns {object|null} ExecEnvClass properties or enumerated instances
	 */
	function execenvclass_get(ctx) {
		let classes = execenv_classes_read();

		if (ctx.instance == null) {
			let result = {};
			for (let k, cls in classes) {
				result[k] = {
					Alias: cls.Alias ?? '',
					Name: cls.Name ?? '',
					Vendor: cls.Vendor ?? '',
					Version: cls.Version ?? '',
					DeploymentUnitRef: cls.DeploymentUnitRef ?? '',
					CapabilityNumberOfEntries: sprintf('%d', length(keys(cls.Capability ?? {})))
				};
			}
			return result;
		}

		let cls = classes[sprintf('%d', ctx.instance)];
		if (!cls)
			return null;

		return {
			Alias: cls.Alias ?? '',
			Name: cls.Name ?? '',
			Vendor: cls.Vendor ?? '',
			Version: cls.Version ?? '',
			DeploymentUnitRef: cls.DeploymentUnitRef ?? '',
			CapabilityNumberOfEntries: sprintf('%d', length(keys(cls.Capability ?? {})))
		};
	}

	/**
	 * Get handler for Device.SoftwareModules.ExecEnvClass.{i}.Capability.{i}.
	 *
	 * @param {object} ctx - Handler context with optional instance number
	 * @returns {object|null} Capability entry or full Capability map
	 */
	function execenvclass_capability_get(ctx) {
		let classes = execenv_classes_read();
		let cls = classes[sprintf('%d', ctx.parent?.instance ?? 1)];
		let caps = cls?.Capability ?? {};

		if (ctx.instance == null)
			return caps;

		return caps[sprintf('%d', ctx.instance)] ?? null;
	}

	/** @returns {object} ExecEnv properties with active EUs and system resources */
	function execenv_to_object(ee, idx) {
		let ee_ref = sprintf('Device.SoftwareModules.ExecEnv.%d', idx + 1);
		let containers = daemon_list();
		let active = [];
		let appdata_count = 0;

		for (let name, ct in containers) {
			if ((ct.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1') != ee_ref)
				continue;
			if (ct.status == 'running')
				push(active, sprintf('Device.SoftwareModules.ExecutionUnit.%d', ct.instance));
			appdata_count += ct.appdata_count ?? 0;
		}

		let avail_mem = -1;
		let meminfo = ubbf.readfile_trim('/proc/meminfo');
		if (meminfo) {
			let m = match(meminfo, /MemAvailable:\s+(\d+)\s+kB/);
			if (m)
				avail_mem = +m[1];
		}

		let avail_disk = ubbf.statvfs_info('/opt')?.avail_kib ?? -1;

		let constraints = ee.constraints ?? {};
		let enabled = (ee.enabled != false);

		return {
			Enable: enabled ? 'true' : 'false',
			Status: enabled ? 'Up' : 'Disabled',
			Alias: ee.alias ?? ubbf.alias_from_name(ee.name),
			Name: ee.name,
			Type: ee.type ?? 'OCI Runtime',
			Vendor: ee.vendor ?? 'openwrt.org',
			Version: ee.version ?? '0.3',
			ParentExecEnv: '',
			CurrentRunLevel: sprintf('%d', ee.current_run_level ?? -1),
			InitialRunLevel: '0',
			AllocatedDiskSpace: sprintf('%d', constraints.disk_space_kib ?? -1),
			AllocatedMemory: sprintf('%d', constraints.memory_kib ?? -1),
			AllocatedCPUPercent: sprintf('%d', constraints.cpu_percent ?? -1),
			AvailableDiskSpace: sprintf('%d', avail_disk),
			AvailableMemory: sprintf('%d', avail_mem),
			AvailableCPUPercent: '-1',
			ActiveExecutionUnits: join(',', active),
			ExecEnvClassRef: sprintf('Device.SoftwareModules.ExecEnvClass.%d', idx + 1),
			ApplicationDataNumberOfEntries: sprintf('%d', appdata_count),
			Signers: ee.signers ?? '',
			AvailableRoles: join(',', ee.available_roles ?? []),
			AvailableAccessInterfaces: join(',', ee.access_interfaces ?? [])
		};
	}

	function execenv_get(ctx) {
		let ees = execenvs_read();
		if (ctx.instance == null)
			return ubbf.enumerate_instances(ees, execenv_to_object);

		let ee = ubbf.get_by_instance(ees, ctx.instance);
		return ee ? execenv_to_object(ee, ctx.instance - 1) : null;
	}

	function execenv_set(ctx) {
		let ees = execenvs_read();
		let idx = ctx.instance - 1;
		if (idx < 0 || idx >= length(ees))
			return;
		if (ctx.value?.Signers != null)
			ees[idx].signers = ctx.value.Signers;
		execenvs_write(ees);
	}

	/** @returns {object} DeploymentUnit TR-181 properties */
	function deploymentunit_to_object(ct) {
		return {
			UUID: ct.uuid ?? '',
			DUID: ct.name,
			Alias: ubbf.alias_from_name(ct.name),
			Name: ct.name,
			Status: 'Installed',
			Resolved: 'true',
			URL: ct.url ?? '',
			Description: '',
			Vendor: ct.vendor ?? '',
			Version: ct.version ?? '',
			ExecutionUnitList: sprintf('Device.SoftwareModules.ExecutionUnit.%d', ct.instance),
			ExecutionEnvRef: ct.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1',
			Installed: ct.installed ?? '',
			LastUpdate: ct.last_update ?? ''
		};
	}

	function deploymentunit_get(ctx) {
		let containers = daemon_list();
		let by_inst = {};
		for (let name, ct in containers) {
			if (ct.instance)
				by_inst[sprintf('%d', ct.instance)] = ct;
		}

		if (ctx.instance == null) {
			let result = {};
			for (let k, ct in by_inst)
				result[k] = deploymentunit_to_object(ct);
			return result;
		}

		let ct = by_inst[sprintf('%d', ctx.instance)];
		return ct ? deploymentunit_to_object(ct) : null;
	}

	/** @returns {object} ExecutionUnit TR-181 properties from daemon info response */
	function executionunit_to_object(ct) {
		let status = oci_status_to_tr181(ct.status ?? 'stopped');
		let fault_code = 'NoFault';
		let fault_msg = '';
		if (status == 'Idle' && ct.exit_code > 0) {
			fault_code = 'Other';
			fault_msg = sprintf('exited with code %d', ct.exit_code);
		}

		return {
			EUID: ct.name,
			Alias: ubbf.alias_from_name(ct.name),
			Name: ct.name,
			ExecEnvLabel: ct.name,
			Status: status,
			ExecutionFaultCode: fault_code,
			ExecutionFaultMessage: fault_msg,
			AutoStart: ct.autostart ? 'true' : 'false',
			RunLevel: '0',
			Vendor: ct.vendor ?? '',
			Version: ct.version ?? '',
			Description: '',
			Privileged: ct.privileged ? 'true' : 'false',
			AllocatedDiskSpace: sprintf('%d', ct.disk_allocated ?? -1),
			DiskSpaceInUse: sprintf('%d', ct.disk_in_use ?? -1),
			AllocatedMemory: sprintf('%d', ct.memory_kib ?? -1),
			MemoryInUse: sprintf('%d', ct.memory_in_use ?? -1),
			AllocatedCPUPercent: sprintf('%d', ct.cpu_percent ?? -1),
			CPUPercentInUse: sprintf('%d', ct.cpu_in_use ?? -1),
			AllocatedEUUID: sprintf('%d', ct.uid_mapping?.container_id ?? 0),
			AllocatedEUGID: sprintf('%d', ct.uid_mapping?.container_id ?? 0),
			AllocatedHostUID: sprintf('%d', ct.uid_mapping?.host_id ?? 0),
			AllocatedHostGID: sprintf('%d', ct.uid_mapping?.host_id ?? 0),
			ExecutionEnvRef: ct.exec_env_ref ?? 'Device.SoftwareModules.ExecEnv.1',
			HostObjectNumberOfEntries: sprintf('%d', length(ct.mounts ?? [])),
			EnvVariableNumberOfEntries: sprintf('%d', length(ct.env_variables ?? []))
		};
	}

	function executionunit_get(ctx) {
		let containers = daemon_list();

		if (ctx.instance == null) {
			let result = {};
			for (let name, ct in containers) {
				if (!ct.instance)
					continue;
				let info = daemon_info(name);
				if (info)
					result[sprintf('%d', ct.instance)] = executionunit_to_object(info);
			}
			return result;
		}

		let name = name_from_instance(ctx.instance);
		if (!name)
			return null;
		let info = daemon_info(name);
		return info ? executionunit_to_object(info) : null;
	}

	/** @returns {object} AutoRestart properties from daemon info */
	function executionunit_autorestart_get(ctx) {
		let name = ctx.parent?.['.name'];
		let info = name ? daemon_info(name) : null;
		return {
			Enable: info?.autorestart ? 'true' : 'false',
			RetryMinimumWaitInterval: sprintf('%d', info?.restart_min_wait ?? 5),
			RetryMaximumWaitInterval: sprintf('%d', info?.restart_max_wait ?? 300),
			RetryIntervalMultiplier: sprintf('%d', info?.restart_multiplier ?? 2000),
			MaximumRetryCount: sprintf('%d', info?.restart_max_retries ?? 0),
			ResetPeriod: sprintf('%d', info?.restart_reset_period ?? 0),
			RetryCount: sprintf('%d', info?.retry_count ?? 0)
		};
	}

	function executionunit_autorestart_set(ctx) {
		let name = ctx.parent?.['.name'];
		if (!name)
			return;

		let cfg = container_read(name);
		if (!cfg)
			return;

		if (ctx.value?.Enable != null)
			cfg.autorestart = ubbf.to_bool(ctx.value.Enable);
		if (ctx.value?.RetryMinimumWaitInterval != null)
			cfg.restart_min_wait = +ctx.value.RetryMinimumWaitInterval;
		if (ctx.value?.RetryMaximumWaitInterval != null)
			cfg.restart_max_wait = +ctx.value.RetryMaximumWaitInterval;
		if (ctx.value?.RetryIntervalMultiplier != null)
			cfg.restart_multiplier = +ctx.value.RetryIntervalMultiplier;
		if (ctx.value?.MaximumRetryCount != null)
			cfg.restart_max_retries = +ctx.value.MaximumRetryCount;
		if (ctx.value?.ResetPeriod != null)
			cfg.restart_reset_period = +ctx.value.ResetPeriod;

		container_write(name, cfg);
		daemon_call('reload');
	}

	/** @returns {object} NetworkConfig properties */
	function executionunit_networkconfig_get(ctx) {
		return {
			AccessInterfaceRefList: '',
			PortMappingRefList: ''
		};
	}

	function hostobject_to_object(obj, idx, eu_name) {
		return {
			Source: obj.Source ?? '',
			Destination: obj.Destination ?? '',
			Options: obj.Options ?? '',
			Alias: obj.Alias ?? ubbf.alias_from_name(sprintf('%s-ho-%d', eu_name, idx + 1))
		};
	}

	function executionunit_hostobject_get(ctx) {
		let eu_name = ctx.parent?.['.name'];
		let info = eu_name ? daemon_info(eu_name) : null;
		let items = info?.mounts ?? [];

		if (ctx.instance == null)
			return ubbf.enumerate_instances(items, (obj, i) => hostobject_to_object(obj, i, eu_name));

		let obj = ubbf.get_by_instance(items, ctx.instance);
		return obj ? hostobject_to_object(obj, ctx.instance - 1, eu_name) : null;
	}

	function envvariable_to_object(v, idx, eu_name) {
		return {
			Key: v.Key ?? '',
			Value: v.Value ?? '',
			Alias: v.Alias ?? ubbf.alias_from_name(sprintf('%s-ev-%d', eu_name, idx + 1))
		};
	}

	function executionunit_envvariable_get(ctx) {
		let eu_name = ctx.parent?.['.name'];
		let info = eu_name ? daemon_info(eu_name) : null;
		let items = info?.env_variables ?? [];

		if (ctx.instance == null)
			return ubbf.enumerate_instances(items, (v, i) => envvariable_to_object(v, i, eu_name));

		let v = ubbf.get_by_instance(items, ctx.instance);
		return v ? envvariable_to_object(v, ctx.instance - 1, eu_name) : null;
	}

	/**
	 * Sync operation: ExecutionUnit SetRequestedState.
	 *
	 * @param {object} input - {RequestedState}
	 * @param {string} command_key
	 * @param {array} instances - [eu_instance]
	 * @returns {object|null}
	 */
	function executionunit_set_requested_state(input, command_key, instances) {
		let name = name_from_instance(instances[0]);
		if (!name)
			return null;

		let requested_state = input?.RequestedState;
		if (requested_state != 'Active' && requested_state != 'Idle')
			return null;

		if (requested_state == 'Active') {
			daemon_call('start', { name });
			let cfg = container_read(name);
			if (cfg) {
				cfg.autostart = true;
				container_write(name, cfg);
				config_apply();
			}
			return {};
		}

		daemon_call('stop', { name });
		let cfg = container_read(name);
		if (cfg) {
			cfg.autostart = false;
			container_write(name, cfg);
			config_apply();
		}
		return {};
	}

	/** Sync operation: ExecutionUnit Restart */
	function executionunit_restart(input, command_key, instances) {
		let name = name_from_instance(instances[0]);
		if (!name)
			return null;
		daemon_call('restart', { name });
		return {};
	}

	/**
	 * Async operation: SoftwareModules InstallDU.
	 * Delegates to daemon which handles download, registration, and OCI config.
	 *
	 * @param {object} input - USP InstallDU input
	 * @param {number} instance - Operation instance
	 * @param {function} complete_cb - Completion callback
	 * @param {string} command_key
	 */
	function install_du(input, instance, complete_cb, command_key) {
		let result = daemon_call('install', {
			url: input?.URL ?? '',
			uuid: input?.UUID ?? '',
			vendor: input?.Vendor ?? '',
			version: input?.Version ?? '',
			exec_env_ref: input?.ExecutionEnvRef ?? '',
			username: input?.Username ?? '',
			password: input?.Password ?? '',
			privileged: input?.Privileged != 'false',
			signature: input?.Signature ?? '',
			memory_kib: input?.AllocatedMemory != null ? +input.AllocatedMemory : -1,
			cpu_percent: input?.AllocatedCPUPercent != null ? +input.AllocatedCPUPercent : -1,
			disk_space_kib: input?.AllocatedDiskSpace != null ? +input.AllocatedDiskSpace : -1,
			share_parent_network: ubbf.to_bool(input?.NetworkConfig?.ShareParentNetwork),
			host_objects: input?.HostObject ?? [],
			env_variables: input?.EnvVariable ?? [],
			application_data: input?.ApplicationData ?? [],
			port_forwards: input?.NetworkConfig?.PortForwarding ?? []
		});

		if (!result || result.error) {
			let code = result?.error_code ?? 7012;
			let msg = result?.error ?? 'Install failed';
			du_state_change_emit({
				state: 'Failed', operation: 'Install',
				fault_code: code, fault_string: msg
			});
			complete_cb(instance, code, msg, {});
			return;
		}

		du_state_change_emit({
			uuid: result.uuid, state: 'Installed', operation: 'Install',
			exec_env_ref: input?.ExecutionEnvRef ?? 'Device.SoftwareModules.ExecEnv.1'
		});
		complete_cb(instance, 0, '', {
			UUID: result.uuid,
			DeploymentUnitRef: result.deployment_unit_ref,
			ExecutionUnitRefList: result.execution_unit_ref_list
		});
	}

	/**
	 * Async operation: DeploymentUnit Update.
	 *
	 * @param {object} input - USP Update input
	 * @param {number} instance - Operation instance
	 * @param {function} complete_cb
	 * @param {array} instances - [du_instance]
	 * @param {string} command_key
	 */
	function update_du(input, instance, complete_cb, instances, command_key) {
		let name = name_from_instance(instances[0]);
		if (!name) {
			complete_cb(instances[0], 7012, 'DeploymentUnit not found', {});
			return;
		}

		let info = daemon_info(name);
		let result = daemon_call('update', {
			name,
			url: input?.URL ?? '',
			version: input?.Version ?? '',
			username: input?.Username ?? '',
			password: input?.Password ?? '',
			signature: input?.Signature ?? ''
		});

		if (!result || result.error) {
			let code = result?.error_code ?? 7012;
			let msg = result?.error ?? 'Update failed';
			du_state_change_emit({
				uuid: info?.uuid, state: 'Failed', operation: 'Update',
				fault_code: code, fault_string: msg
			});
			complete_cb(instances[0], code, msg, {});
			return;
		}

		du_state_change_emit({
			uuid: result.uuid, version: result.version,
			state: 'Installed', operation: 'Update',
			exec_env_ref: info?.exec_env_ref
		});
		complete_cb(instances[0], 0, '', {});
	}

	/**
	 * Async operation: DeploymentUnit Uninstall.
	 *
	 * @param {object} input - USP Uninstall input
	 * @param {number} instance - Operation instance
	 * @param {function} complete_cb
	 * @param {array} instances - [du_instance]
	 * @param {string} command_key
	 */
	function uninstall_du(input, instance, complete_cb, instances, command_key) {
		let name = name_from_instance(instances[0]);
		if (!name) {
			complete_cb(instances[0], 7012, 'DeploymentUnit not found', {});
			return;
		}

		let info = daemon_info(name);
		let result = daemon_call('uninstall', {
			name,
			retain_data: ubbf.to_bool(input?.RetainData)
		});

		if (!result || result.error) {
			complete_cb(instances[0], result?.error_code ?? 7012,
				result?.error ?? 'Uninstall failed', {});
			return;
		}

		du_state_change_emit({
			uuid: result.uuid, version: info?.version,
			state: 'Uninstalled', operation: 'Uninstall',
			exec_env_ref: info?.exec_env_ref
		});
		complete_cb(instances[0], 0, '', {});
	}

	/** Sync operation: ExecEnvClass.{i}.AddExecEnv */
	function add_exec_env(input, command_key, instances) {
		let name = input?.Name;
		if (!name)
			return null;

		let ees = execenvs_read();
		for (let ee in ees) {
			if (ee.name == name)
				return null;
		}

		let new_ee = {
			name,
			alias: input?.Alias ?? ubbf.alias_from_name(name),
			vendor: input?.Vendor ?? 'openwrt.org',
			version: input?.Version ?? '0.3',
			type: input?.Type ?? 'OCI Runtime',
			constraints: {
				disk_space_kib: input?.AllocatedDiskSpace != null ? +input.AllocatedDiskSpace : -1,
				memory_kib: input?.AllocatedMemory != null ? +input.AllocatedMemory : -1,
				cpu_percent: input?.AllocatedCPUPercent != null ? +input.AllocatedCPUPercent : -1
			},
			available_roles: input?.AvailableRoles ? split(input.AvailableRoles, ',') : [],
			current_run_level: -1
		};

		if (!ubbf.to_bool(input?.Enable ?? 'true'))
			new_ee.enabled = false;

		push(ees, new_ee);
		execenvs_write(ees);

		return {
			ExecEnvRef: sprintf('Device.SoftwareModules.ExecEnv.%d', length(ees))
		};
	}

	/** @returns {array} Flattened appdata entries from all containers in an EE */
	function appdata_entries_for_ee(ee_instance) {
		let ee_cts = containers_for_ee(ee_instance);
		let all_appdata = [];
		for (let name in ee_cts) {
			let info = daemon_info(name);
			for (let ad in (info?.application_data ?? []))
				push(all_appdata, { name, data: ad });
		}
		return all_appdata;
	}

	function appdata_to_object(entry, idx) {
		let ad = entry.data;
		let vol_path = sprintf('/opt/container-data/%s/%s', entry.name, ad.Name);
		let utilisation = ubbf.du_kib(vol_path);
		if (utilisation < 0)
			utilisation = 0;
		return {
			Name: ad.Name ?? '',
			Capacity: sprintf('%d', ad.Capacity ?? 0),
			Retain: ad.Retain ?? '',
			AccessPath: ad.AccessPath ?? sprintf('/data/%s', ad.Name),
			Alias: ad.Alias ?? ubbf.alias_from_name(sprintf('%s-ad-%d', entry.name, idx + 1)),
			ApplicationUUID: ad.ApplicationUUID ?? '',
			Utilization: sprintf('%d', utilisation)
		};
	}

	function execenv_applicationdata_get(ctx) {
		let items = appdata_entries_for_ee(ctx.parent?.instance ?? 1);
		if (ctx.instance == null)
			return ubbf.enumerate_instances(items, appdata_to_object);

		let entry = ubbf.get_by_instance(items, ctx.instance);
		return entry ? appdata_to_object(entry, ctx.instance - 1) : null;
	}

	/** Sync operation: ExecEnv.{i}.SetRunLevel() */
	function execenv_set_run_level(input, command_key, instances) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees))
			return null;
		if (input?.RequestedRunLevel == null)
			return null;
		ees[idx].current_run_level = +input.RequestedRunLevel;
		execenvs_write(ees);
		return {};
	}

	/** Async operation: ExecEnv.{i}.ModifyConstraints() */
	function execenv_modify_constraints(input, instance, complete_cb, instances, command_key) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees)) {
			complete_cb(instances[0], 7012, 'ExecEnv not found', {});
			return;
		}

		let ee = ees[idx];
		ee.constraints ??= {};
		if (input?.AllocatedDiskSpace != null)
			ee.constraints.disk_space_kib = +input.AllocatedDiskSpace;
		if (input?.AllocatedMemory != null)
			ee.constraints.memory_kib = +input.AllocatedMemory;
		if (input?.AllocatedCPUPercent != null)
			ee.constraints.cpu_percent = +input.AllocatedCPUPercent;

		execenvs_write(ees);
		complete_cb(instances[0], 0, '', {});
	}

	/** Async operation: ExecEnv.{i}.ModifyAvailableRoles() */
	function execenv_modify_available_roles(input, instance, complete_cb, instances, command_key) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees)) {
			complete_cb(instances[0], 7012, 'ExecEnv not found', {});
			return;
		}

		let new_roles = input?.AvailableRoles ? split(input.AvailableRoles, ',') : [];
		let ee_cts = containers_for_ee(instances[0]);
		for (let ct_name in ee_cts) {
			let cfg = container_read(ct_name);
			for (let r in (cfg?.roles?.required ?? [])) {
				if (index(new_roles, r) < 0) {
					complete_cb(instances[0], 7004,
						sprintf('Role %s required by container %s', r, ct_name), {});
					return;
				}
			}
		}

		ees[idx].available_roles = new_roles;
		execenvs_write(ees);
		complete_cb(instances[0], 0, '', {});
	}

	/** Async operation: ExecEnv.{i}.ModifyAvailableAccessInterfaces() */
	function execenv_modify_access_interfaces(input, instance, complete_cb, instances, command_key) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees)) {
			complete_cb(instances[0], 7012, 'ExecEnv not found', {});
			return;
		}
		ees[idx].access_interfaces = input?.AccessInterfaces ? split(input.AccessInterfaces, ',') : [];
		execenvs_write(ees);
		complete_cb(instances[0], 0, '', {});
	}

	/**
	 * Async operation: ExecEnv.{i}.Restart().
	 * Stops all containers, then restarts those with autostart.
	 */
	function execenv_restart(input, instance, complete_cb, instances, command_key) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees)) {
			complete_cb(instances[0], 7012, 'ExecEnv not found', {});
			return;
		}
		if (ees[idx].enabled == false) {
			complete_cb(instances[0], 7004, 'ExecEnv is disabled', {});
			return;
		}

		let ee_cts = containers_for_ee(instances[0]);
		for (let name in ee_cts)
			daemon_call('stop', { name });
		for (let name, ct in ee_cts) {
			if (ct.autostart)
				daemon_call('start', { name });
		}
		complete_cb(instances[0], 0, '', {});
	}

	/**
	 * Async operation: ExecEnv.{i}.Reset().
	 * Reverts EE to factory state using onboarding.json as manifest.
	 */
	function execenv_reset(input, instance, complete_cb, instances, command_key) {
		let manifest_content = fs.readfile('/etc/ubbf/onboarding.json');
		if (!manifest_content) {
			complete_cb(instances[0], 7005, 'No factory manifest found', {});
			return;
		}

		let manifest = json(manifest_content);
		if (!manifest?.containers || !length(manifest.containers)) {
			complete_cb(instances[0], 7005, 'Empty factory manifest', {});
			return;
		}

		let factory_names = {};
		for (let ct in manifest.containers)
			factory_names[ct.name] = ct;

		let ee_cts = containers_for_ee(instances[0]);
		let ee_ref = sprintf('Device.SoftwareModules.ExecEnv.%d', instances[0]);

		for (let name, ct in ee_cts) {
			if (name in factory_names)
				continue;
			daemon_call('uninstall', { name, retain_data: false });
			du_state_change_emit({
				uuid: ct.uuid, version: ct.version,
				state: 'Uninstalled', operation: 'Uninstall',
				exec_env_ref: ee_ref
			});
		}

		complete_cb(instances[0], 0, '', {});
	}

	/**
	 * Async operation: ExecEnv.{i}.Remove().
	 * Removes the EE. Fails if DUs installed unless Force=true.
	 */
	function execenv_remove(input, instance, complete_cb, instances, command_key) {
		let ees = execenvs_read();
		let idx = instances[0] - 1;
		if (idx < 0 || idx >= length(ees)) {
			complete_cb(instances[0], 7012, 'ExecEnv not found', {});
			return;
		}
		if (instances[0] == 1) {
			complete_cb(instances[0], 7004, 'Cannot remove default ExecEnv', {});
			return;
		}

		let ee_cts = containers_for_ee(instances[0]);
		let force = ubbf.to_bool(input?.Force);
		let ee_ref = sprintf('Device.SoftwareModules.ExecEnv.%d', instances[0]);

		if (length(ee_cts) > 0 && !force) {
			complete_cb(instances[0], 7004,
				sprintf('ExecEnv has %d installed DUs, use Force=true to remove', length(ee_cts)), {});
			return;
		}

		for (let name, ct in ee_cts) {
			daemon_call('uninstall', { name, retain_data: false });
			du_state_change_emit({
				uuid: ct.uuid, version: ct.version,
				state: 'Uninstalled', operation: 'Uninstall',
				exec_env_ref: ee_ref
			});
		}

		splice(ees, idx, 1);
		execenvs_write(ees);
		complete_cb(instances[0], 0, '', {});
	}

	/** Sync operation: ExecEnv.{i}.ApplicationData.{i}.Remove() */
	function execenv_appdata_remove(input, command_key, instances) {
		let items = appdata_entries_for_ee(instances[0]);
		let ad_idx = instances[1] - 1;
		if (ad_idx < 0 || ad_idx >= length(items))
			return null;

		let entry = items[ad_idx];
		let vol_path = sprintf('/opt/container-data/%s/%s', entry.name, entry.data.Name);
		rmdir_recursive(vol_path);

		let cfg = container_read(entry.name);
		if (cfg?.application_data) {
			let app_data = cfg.application_data;
			for (let i = 0; i < length(app_data); i++) {
				if (app_data[i].Name == entry.data.Name) {
					splice(app_data, i, 1);
					break;
				}
			}
			cfg.application_data = app_data;
			container_write(entry.name, cfg);
			daemon_call('reload');
		}

		return {};
	}

	_model = {
		'Device.SoftwareModules': { schema: schemas.SoftwareModules, get: softwaremodules_get },
		'Device.SoftwareModules.ExecEnvClass': {},
		'Device.SoftwareModules.ExecEnvClass.{i}': { schema: schemas.ExecEnvClass, get: execenvclass_get },
		'Device.SoftwareModules.ExecEnvClass.{i}.Capability': {},
		'Device.SoftwareModules.ExecEnvClass.{i}.Capability.{i}': { schema: schemas.ExecEnvClass_Capability, get: execenvclass_capability_get },
		'Device.SoftwareModules.ExecEnv': {},
		'Device.SoftwareModules.ExecEnv.{i}': { schema: schemas.ExecEnv, get: execenv_get, set: execenv_set },
		'Device.SoftwareModules.ExecEnv.{i}.ApplicationData': {},
		'Device.SoftwareModules.ExecEnv.{i}.ApplicationData.{i}': { schema: schemas.ExecEnv_ApplicationData, get: execenv_applicationdata_get },
		'Device.SoftwareModules.DeploymentUnit': {},
		'Device.SoftwareModules.DeploymentUnit.{i}': { schema: schemas.DeploymentUnit, get: deploymentunit_get },
		'Device.SoftwareModules.ExecutionUnit': {},
		'Device.SoftwareModules.ExecutionUnit.{i}': { schema: schemas.ExecutionUnit, get: executionunit_get },
		'Device.SoftwareModules.ExecutionUnit.{i}.HostObject': {},
		'Device.SoftwareModules.ExecutionUnit.{i}.HostObject.{i}': { schema: schemas.ExecutionUnit_HostObject, get: executionunit_hostobject_get },
		'Device.SoftwareModules.ExecutionUnit.{i}.EnvVariable': {},
		'Device.SoftwareModules.ExecutionUnit.{i}.EnvVariable.{i}': { schema: schemas.ExecutionUnit_EnvVariable, get: executionunit_envvariable_get },
		'Device.SoftwareModules.ExecutionUnit.{i}.AutoRestart': { schema: schemas.ExecutionUnit_AutoRestart, get: executionunit_autorestart_get, set: executionunit_autorestart_set },
		'Device.SoftwareModules.ExecutionUnit.{i}.NetworkConfig': { schema: schemas.ExecutionUnit_NetworkConfig, get: executionunit_networkconfig_get }
	};

	_operations = {
		'Device.SoftwareModules.InstallDU()': { type: 'async', handler: install_du },
		'Device.SoftwareModules.DeploymentUnit.{i}.Update()': { type: 'async', handler: update_du },
		'Device.SoftwareModules.DeploymentUnit.{i}.Uninstall()': { type: 'async', handler: uninstall_du },
		'Device.SoftwareModules.ExecutionUnit.{i}.SetRequestedState()': { type: 'sync', handler: executionunit_set_requested_state },
		'Device.SoftwareModules.ExecutionUnit.{i}.Restart()': { type: 'sync', handler: executionunit_restart },
		'Device.SoftwareModules.ExecEnvClass.{i}.AddExecEnv()': { type: 'sync', handler: add_exec_env },
		'Device.SoftwareModules.ExecEnv.{i}.SetRunLevel()': { type: 'sync', handler: execenv_set_run_level },
		'Device.SoftwareModules.ExecEnv.{i}.ModifyConstraints()': { type: 'async', handler: execenv_modify_constraints },
		'Device.SoftwareModules.ExecEnv.{i}.ModifyAvailableRoles()': { type: 'async', handler: execenv_modify_available_roles },
		'Device.SoftwareModules.ExecEnv.{i}.ModifyAvailableAccessInterfaces()': { type: 'async', handler: execenv_modify_access_interfaces },
		'Device.SoftwareModules.ExecEnv.{i}.Restart()': { type: 'async', handler: execenv_restart },
		'Device.SoftwareModules.ExecEnv.{i}.Reset()': { type: 'async', handler: execenv_reset },
		'Device.SoftwareModules.ExecEnv.{i}.Remove()': { type: 'async', handler: execenv_remove },
		'Device.SoftwareModules.ExecEnv.{i}.ApplicationData.{i}.Remove()': { type: 'sync', handler: execenv_appdata_remove }
	};
}

export const model = _model;
export const operations = _operations;
