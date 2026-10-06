'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;

const ubus = require('ubus');

let schemas = {};
include('schema.uc', { schemas });

/**
 * Retrieves qosify status via ubus.
 *
 * @returns {object} QoSify status with interfaces and devices
 */
function qosify_status_get() {
	return ubus.call('qosify', 'status', {}) ?? {};
}

/**
 * Retrieves qosify statistics via ubus.
 *
 * @returns {object} QoSify statistics including DSCP and DNS cache data
 */
function qosify_stats_get() {
	return ubus.call('qosify', 'get_stats', {}) ?? {};
}

/**
 * Get handler for Device.X_UBBF.QoSify.
 *
 * @param {object} ctx - Context with config
 * @returns {object} QoSify status (Disabled, Enabled, or Error)
 */
function x_qosify_get(ctx) {
	let status = qosify_status_get();
	let has_active = false;

	for (let name, iface in status.interfaces ?? {}) {
		if (iface.active) {
			has_active = true;
			break;
		}
	}

	if (!has_active) {
		for (let name, dev in status.devices ?? {}) {
			if (dev.active) {
				has_active = true;
				break;
			}
		}
	}

	let enabled = ctx.config?.Enable == 'true';
	let derived_status = 'Disabled';

	if (enabled && has_active)
		derived_status = 'Enabled';
	else if (enabled && !has_active)
		derived_status = 'Error';

	return {
		Status: derived_status
	};
}

/**
 * Get handler for Device.X_UBBF.QoSify.InterfaceConfig.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object} Interface configuration with active status
 */
function interface_config_get(ctx) {
	let status = qosify_status_get();
	let iface_name = ctx.config?.InterfaceName;

	if (!iface_name && ctx.config?.Interface)
		iface_name = ubbf.interface_to_name(ctx.root, ctx.config.Interface);

	let active = false;

	if (iface_name) {
		let iface_status = status.interfaces?.[iface_name];
		if (iface_status?.active)
			active = true;

		let dev_status = status.devices?.[iface_name];
		if (dev_status?.active)
			active = true;
	}

	return {
		InterfaceName: iface_name ?? '',
		Active: active ? 'true' : 'false'
	};
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.Class.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} DSCP class statistics with packets and bytes
 */
function stats_class_get(ctx) {
	let stats = qosify_stats_get();
	let dscp = stats.dscp ?? {};
	let result = {};
	let idx = 1;

	for (let dscp_name, dscp_stats in dscp) {
		let packets = dscp_stats.packets ?? 0;
		let bytes = dscp_stats.bytes ?? 0;

		if (!packets && !bytes)
			continue;

		result[sprintf('%d', idx)] = {
			Name: dscp_name,
			Packets: sprintf('%d', packets),
			Bytes: sprintf('%d', bytes)
		};
		idx++;
	}

	if (ctx.instance != null)
		return result[ctx.instance] ?? null;

	return result;
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.FQDN.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} FQDN statistics with hit counts, packets and bytes
 */
function stats_fqdn_get(ctx) {
	let stats = qosify_stats_get();
	let dns = stats.dns ?? {};
	let result = {};
	let idx = 1;

	for (let fqdn, fqdn_stats in dns) {
		let hits = fqdn_stats.hits ?? 0;

		if (!hits)
			continue;

		let name = fqdn;
		if (substr(name, 0, 2) == '*.')
			name = substr(name, 2);

		result[sprintf('%d', idx)] = {
			Name: name,
			Class: fqdn_stats.dscp ?? '',
			Hits: sprintf('%d', hits),
			Packets: sprintf('%d', fqdn_stats.packets ?? 0),
			Bytes: sprintf('%d', fqdn_stats.bytes ?? 0)
		};
		idx++;
	}

	if (ctx.instance != null)
		return result[ctx.instance] ?? null;

	return result;
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.
 *
 * @param {object} ctx - Context
 * @returns {object} Aggregated QoSify statistics
 */
function stats_get(ctx) {
	let stats = qosify_stats_get();
	let dscp = stats.dscp ?? {};
	let dns_cache = stats.dns_cache ?? {};
	let dns = stats.dns ?? {};
	let class_count = 0;
	let fqdn_count = 0;

	for (let name, dscp_stats in dscp) {
		if (dscp_stats.packets || dscp_stats.bytes)
			class_count++;
	}

	for (let fqdn, fqdn_stats in dns) {
		if (fqdn_stats.hits)
			fqdn_count++;
	}

	return {
		DNSCacheHits: sprintf('%d', dns_cache.hits ?? 0),
		DNSCacheMisses: sprintf('%d', dns_cache.misses ?? 0),
		DNSCacheSize: sprintf('%d', dns_cache.size ?? 0),
		eBPFMapEntries: sprintf('%d', stats.ebpf_map_entries ?? 0),
		LastReloadTime: ubbf.iso8601_format(stats.last_reload_time ?? 0),
		ClassNumberOfEntries: sprintf('%d', class_count),
		FQDNNumberOfEntries: sprintf('%d', fqdn_count)
	};
}

model['Device.X_UBBF.QoSify'] = {
	schema: schemas.QoSify,
	get: x_qosify_get
};

model['Device.X_UBBF.QoSify.Config'] = {
	schema: schemas.Config
};

model['Device.X_UBBF.QoSify.Classifier'] = {
};

model['Device.X_UBBF.QoSify.Classifier.{i}'] = {
	schema: schemas.Classifier
};

model['Device.X_UBBF.QoSify.DNSClassifier'] = {
};

model['Device.X_UBBF.QoSify.DNSClassifier.{i}'] = {
	schema: schemas.DNSClassifier
};

model['Device.X_UBBF.QoSify.DSCPMap'] = {
};

model['Device.X_UBBF.QoSify.DSCPMap.{i}'] = {
	schema: schemas.DSCPMap
};

model['Device.X_UBBF.QoSify.InterfaceConfig'] = {
};

model['Device.X_UBBF.QoSify.InterfaceConfig.{i}'] = {
	schema: schemas.InterfaceConfig,
	get: interface_config_get
};

model['Device.X_UBBF.QoSify.Stats'] = {
	schema: schemas.Stats,
	get: stats_get
};

model['Device.X_UBBF.QoSify.Stats.Class'] = {
};

model['Device.X_UBBF.QoSify.Stats.Class.{i}'] = {
	schema: schemas.StatsClass,
	get: stats_class_get
};

model['Device.X_UBBF.QoSify.Stats.FQDN'] = {
};

model['Device.X_UBBF.QoSify.Stats.FQDN.{i}'] = {
	schema: schemas.StatsFQDN,
	get: stats_fqdn_get
};
