'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const cache_call = ubbf_module.utils.cache.call;
const log_warn = ubbf_module.utils.logging.log_warn;

const ubus = require('ubus');

const schema = ubbf_module.schema;

const qosify_check = {};
include('./check.uc', { qosify_check });

const UNKNOWN_TIME = '0001-01-01T00:00:00Z';

/**
 * Retrieves qosify status via ubus (uncached).
 *
 * @returns {object|null} QoSify status, or null while the daemon is absent
 */
function qosify_status_fetch() {
	return ubus.call('qosify', 'status', {});
}

/**
 * Retrieves qosify statistics via ubus (uncached).
 *
 * @returns {object} QoSify statistics including DSCP and DNS cache data
 */
function qosify_stats_fetch() {
	return ubus.call('qosify', 'get_stats', {}) ?? {};
}

/**
 * Gets qosify status (cached), once for the root and every InterfaceConfig
 * row of one walk.
 *
 * @returns {object|null} QoSify status, or null while the daemon is absent
 */
function qosify_status_get() {
	return cache_call(qosify_status_fetch);
}

/**
 * Gets qosify statistics (cached); get_stats walks every DSCP map entry
 * and DNS pattern, and Stats, Class and FQDN all read it.
 *
 * @returns {object} QoSify statistics
 */
function qosify_stats_get() {
	return cache_call(qosify_stats_fetch);
}

/**
 * Lists the Name of every DSCPMap row, the classes a DSCP mark can name.
 *
 * @param {object} root - Configuration tree
 * @param {string|null} skip - Instance of a row to leave out
 * @returns {array} Class names
 */
function class_names(root, skip) {
	let names = [];

	for (let inst, row in root?.Device?.X_UBBF?.QoSify?.DSCPMap ?? {}) {
		if (`${inst}` != `${skip}` && row?.Name)
			push(names, row.Name);
	}

	return names;
}

/**
 * Refuses a write and logs the reason.
 *
 * @param {object} ctx - Set handler context
 * @param {string} why - Reason
 * @returns {number} Negative USP error code
 */
function write_refuse(ctx, why) {
	log_warn('qosify: %s = %s refused: %s', ctx.path, ctx.value, why);
	return -USP_ERR_INVALID_VALUE;
}

/**
 * Set handler for Device.X_UBBF.QoSify.Config.
 *
 * @param {object} ctx - Set handler context
 * @returns {number} 0, or a negative USP error code
 */
function config_set(ctx) {
	if (!match(ctx.param, /DSCP$/))
		return 0;

	if (!qosify_check.dscp_mark_valid(ctx.value, class_names(ctx.root)))
		return write_refuse(ctx, 'not a DSCP codepoint, 0 to 63, or a DSCPMap Name');

	return 0;
}

/**
 * Set handler for Device.X_UBBF.QoSify.Classifier.{i}.
 *
 * @param {object} ctx - Set handler context
 * @returns {number} 0, or a negative USP error code
 */
function classifier_set(ctx) {
	switch (ctx.param) {
	case 'DSCPMark':
		if (!qosify_check.dscp_mark_valid(ctx.value, class_names(ctx.root)))
			return write_refuse(ctx, 'not a DSCP codepoint, 0 to 63, or a DSCPMap Name');
		break;

	case 'Protocol':
		if (!qosify_check.protocol_valid(ctx.value))
			return write_refuse(ctx, 'not -1, 6 or 17');
		break;

	case 'DestPort':
	case 'DestPortRangeEnd':
		if (!qosify_check.port_valid(ctx.value))
			return write_refuse(ctx, 'not -1 or a port from 1 to 65534');
		break;

	case 'SourceIP':
		if (!qosify_check.address_valid(ctx.value))
			return write_refuse(ctx, 'not one IPv4 or IPv6 address');
		break;
	}

	return 0;
}

/**
 * Set handler for Device.X_UBBF.QoSify.DNSClassifier.{i}.
 *
 * Domain and MatchType are checked together, because a Regex row needs
 * a Domain that compiles.
 *
 * @param {object} ctx - Set handler context
 * @returns {number} 0, or a negative USP error code
 */
function dns_classifier_set(ctx) {
	switch (ctx.param) {
	case 'DSCPMark':
		if (!qosify_check.dscp_mark_valid(ctx.value, class_names(ctx.root)))
			return write_refuse(ctx, 'not a DSCP codepoint, 0 to 63, or a DSCPMap Name');
		break;

	case 'MatchType':
	case 'Domain':
		let match_type = ctx.config?.MatchType ?? 'Suffix';
		if (!qosify_check.match_type_valid(match_type))
			return write_refuse(ctx, 'MatchType is not Exact, Suffix or Regex');
		if (match_type == 'Regex' && ctx.config?.Domain &&
		    !qosify_check.regex_valid(ctx.config.Domain))
			return write_refuse(ctx, 'Domain is not a POSIX extended regular expression');
		break;
	}

	return 0;
}

/**
 * Set handler for Device.X_UBBF.QoSify.DSCPMap.{i}.
 *
 * @param {object} ctx - Set handler context
 * @returns {number} 0, or a negative USP error code
 */
function dscp_map_set(ctx) {
	switch (ctx.param) {
	case 'Name':
		if (!qosify_check.class_name_valid(ctx.value))
			return write_refuse(ctx, 'not a letter followed by letters, digits and _');
		if (index(class_names(ctx.root, ctx.instance), ctx.value) >= 0)
			return write_refuse(ctx, 'another DSCPMap row has this Name');
		break;

	case 'IngressDSCP':
	case 'EgressDSCP':
		if (!qosify_check.dscp_codepoint_valid(ctx.value))
			return write_refuse(ctx, 'not a DSCP codepoint or 0 to 63');
		break;
	}

	return 0;
}

/**
 * Set handler for Device.X_UBBF.QoSify.InterfaceConfig.{i}.
 *
 * @param {object} ctx - Set handler context
 * @returns {number} 0, or a negative USP error code
 */
function interface_config_set(ctx) {
	switch (ctx.param) {
	case 'BandwidthUp':
	case 'BandwidthDown':
		if (!qosify_check.rate_valid(ctx.value))
			return write_refuse(ctx, 'not a tc rate such as 100mbit');
		break;

	case 'Mode':
		if (!qosify_check.mode_valid(ctx.value))
			return write_refuse(ctx, 'not a cake diffserv mode');
		break;
	}

	return 0;
}

/**
 * Get handler for Device.X_UBBF.QoSify.
 *
 * `Enabled` while the daemon answers, `Error` when QoSify is enabled and
 * the daemon does not answer. Whether an interface is shaped is the
 * `Active` of its InterfaceConfig row.
 *
 * @param {object} ctx - Context with config
 * @returns {object} QoSify status (Disabled, Enabled, or Error)
 */
function x_qosify_get(ctx) {
	if (ctx.config?.Enable != 'true')
		return { Status: 'Disabled' };

	return { Status: qosify_status_get() ? 'Enabled' : 'Error' };
}

/**
 * Get handler for Device.X_UBBF.QoSify.InterfaceConfig.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object} Interface configuration with active status
 */
function interface_config_get(ctx) {
	let status = qosify_status_get() ?? {};
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
 * Lists the DSCP classes with traffic.
 *
 * @returns {array} `{ name, packets, bytes }` per class
 */
function classes_list() {
	let rows = [];

	for (let name, s in qosify_stats_get().dscp ?? {}) {
		if (s.packets || s.bytes)
			push(rows, { name, packets: s.packets ?? 0, bytes: s.bytes ?? 0 });
	}

	return rows;
}

/**
 * Converts a DSCP class entry to a TR-181 Stats.Class object.
 *
 * @param {object} entry - `{ name, packets, bytes }`
 * @returns {object} Stats.Class row
 */
function class_to_object(entry) {
	return {
		Name: entry.name,
		Packets: sprintf('%d', entry.packets),
		Bytes: sprintf('%d', entry.bytes)
	};
}

/**
 * Returns the host name a DNS pattern of the rules file stands for.
 *
 * render.uc writes a Suffix rule as `<domain>` and `*.<domain>` and a Regex
 * rule as `/<expression>`; both forms map back to the stored Domain.
 *
 * @param {string} pattern - Pattern as get_stats reports it
 * @returns {string} Domain
 */
function fqdn_name(pattern) {
	if (substr(pattern, 0, 2) == '*.')
		return substr(pattern, 2);
	if (substr(pattern, 0, 1) == '/')
		return substr(pattern, 1);
	return pattern;
}

/**
 * Lists the DNS patterns with hits, one entry per Domain.
 *
 * @returns {array} `{ name, dscp, hits, packets, bytes }` per Domain
 */
function fqdns_list() {
	let by_name = {};
	let rows = [];

	for (let pattern, s in qosify_stats_get().dns ?? {}) {
		if (!s.hits)
			continue;

		let name = fqdn_name(pattern);
		let row = by_name[name];
		if (!row) {
			row = by_name[name] = { name, dscp: s.dscp ?? '', hits: 0, packets: 0, bytes: 0 };
			push(rows, row);
		}

		row.hits += s.hits;
		row.packets += s.packets ?? 0;
		row.bytes += s.bytes ?? 0;
	}

	return rows;
}

/**
 * Converts a DNS pattern entry to a TR-181 Stats.FQDN object.
 *
 * @param {object} entry - `{ name, dscp, hits, packets, bytes }`
 * @returns {object} Stats.FQDN row
 */
function fqdn_to_object(entry) {
	return {
		Name: entry.name,
		Class: entry.dscp,
		Hits: sprintf('%d', entry.hits),
		Packets: sprintf('%d', entry.packets),
		Bytes: sprintf('%d', entry.bytes)
	};
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.Class.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} DSCP class statistics with packets and bytes
 */
function stats_class_get(ctx) {
	let rows = classes_list();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(rows, class_to_object);

	let row = ubbf.get_by_instance(rows, ctx.instance);
	return row ? class_to_object(row) : null;
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.FQDN.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} FQDN statistics with hit counts, packets and bytes
 */
function stats_fqdn_get(ctx) {
	let rows = fqdns_list();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(rows, fqdn_to_object);

	let row = ubbf.get_by_instance(rows, ctx.instance);
	return row ? fqdn_to_object(row) : null;
}

/**
 * Get handler for Device.X_UBBF.QoSify.Stats.
 *
 * @param {object} ctx - Context
 * @returns {object} Aggregated QoSify statistics
 */
function stats_get(ctx) {
	let stats = qosify_stats_get();
	let dns_cache = stats.dns_cache ?? {};
	let reload = stats.last_reload_time;

	return {
		DNSCacheHits: sprintf('%d', dns_cache.hits ?? 0),
		DNSCacheMisses: sprintf('%d', dns_cache.misses ?? 0),
		DNSCacheSize: sprintf('%d', dns_cache.size ?? 0),
		eBPFMapEntries: sprintf('%d', stats.ebpf_map_entries ?? 0),
		LastReloadTime: reload ? ubbf.iso8601_format(reload) : UNKNOWN_TIME,
		ClassNumberOfEntries: sprintf('%d', length(classes_list())),
		FQDNNumberOfEntries: sprintf('%d', length(fqdns_list()))
	};
}

model['Device.X_UBBF.QoSify'] = {
	schema: schema('QoSify'),
	get: x_qosify_get
};

model['Device.X_UBBF.QoSify.Config'] = {
	schema: schema('Config'),
	set: config_set
};

model['Device.X_UBBF.QoSify.Classifier'] = {
};

model['Device.X_UBBF.QoSify.Classifier.{i}'] = {
	schema: schema('Classifier'),
	set: classifier_set
};

model['Device.X_UBBF.QoSify.DNSClassifier'] = {
};

model['Device.X_UBBF.QoSify.DNSClassifier.{i}'] = {
	schema: schema('DNSClassifier'),
	set: dns_classifier_set
};

model['Device.X_UBBF.QoSify.DSCPMap'] = {
};

model['Device.X_UBBF.QoSify.DSCPMap.{i}'] = {
	schema: schema('DSCPMap'),
	set: dscp_map_set
};

model['Device.X_UBBF.QoSify.InterfaceConfig'] = {
};

model['Device.X_UBBF.QoSify.InterfaceConfig.{i}'] = {
	schema: schema('InterfaceConfig'),
	get: interface_config_get,
	set: interface_config_set
};

model['Device.X_UBBF.QoSify.Stats'] = {
	schema: schema('Stats'),
	get: stats_get
};

model['Device.X_UBBF.QoSify.Stats.Class'] = {
};

// The rows come from the daemon; a stored row would hide them.
model['Device.X_UBBF.QoSify.Stats.Class.{i}'] = {
	schema: schema('StatsClass'),
	get: stats_class_get,
	maxInstances: 0
};

model['Device.X_UBBF.QoSify.Stats.FQDN'] = {
};

model['Device.X_UBBF.QoSify.Stats.FQDN.{i}'] = {
	schema: schema('StatsFQDN'),
	get: stats_fqdn_get,
	maxInstances: 0
};
