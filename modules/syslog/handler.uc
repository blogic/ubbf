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

let syslog = {};
include('./shared.uc', { syslog });

// The table that each reference list of an Action points into.
const ACTION_REFS = {
	SourceRef: 'Source',
	FilterRef: 'Filter',
	TemplateRef: 'Template'
};

/**
 * Fetches the state of ubbf-logd (uncached).
 *
 * @returns {object|null} Reply of `ubbf-logd status`, or null while the
 *                        daemon does not run
 */
function logd_status_fetch() {
	return ubus.call('ubbf-logd', 'status', {});
}

/**
 * Returns the state of ubbf-logd for the current request (cached).
 *
 * @returns {object|null} Reply of `ubbf-logd status`
 */
function logd_status_get() {
	return cache_call(logd_status_fetch);
}

/**
 * Tells whether ubbf-logd reports an error for any action.
 *
 * @param {object|null} status - Reply of `ubbf-logd status`
 * @returns {boolean} True when an action or one of its outputs has an error
 */
function logd_has_error(status) {
	for (let id, action in status?.actions ?? {})
		if (action.error || action.file?.state == 'error' || action.remote?.state == 'error')
			return true;

	return false;
}

/**
 * Get handler for Device.Syslog.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Syslog properties with instance counts and Status
 */
function syslog_get(ctx) {
	let cfg = ubbf.ctx_config(ctx);
	let status = 'Disabled';

	if (ubbf.to_bool(cfg.Enable))
		status = logd_has_error(logd_status_get()) ? 'Error' : 'Enabled';

	return {
		...cfg,
		Status: status,
		FilterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Filter)),
		SourceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Source)),
		TemplateNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Template)),
		ActionNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Action))
	};
}

/**
 * Derives LogRemote.Status from the configuration and from ubbf-logd.
 *
 * @param {object} cfg - LogRemote configuration
 * @param {boolean} syslog_enabled - Device.Syslog.Enable
 * @param {object|null} action - The action in `ubbf-logd status`
 * @returns {string} TR-181 LogRemote.Status
 */
function logremote_status(cfg, syslog_enabled, action) {
	if (!syslog_enabled || !ubbf.to_bool(cfg.Enable))
		return 'Disabled';

	if ((cfg.Address ?? '') == '')
		return 'Error';

	// An enabled remote that ubbf-logd does not run, for example without a
	// SourceRef, forwards nothing.
	if (!action?.remote || action.error || action.remote.state == 'error')
		return 'Error';

	if (action.remote.state == 'unreachable')
		return 'Error_Unreachable';

	return 'Enabled';
}

/**
 * Get handler for Device.Syslog.Action.{i}.LogRemote.
 *
 * @param {object} ctx - Context with config, root and the Action instance
 * @returns {object} LogRemote properties with derived Status
 */
function logremote_get(ctx) {
	let cfg = ubbf.ctx_config(ctx);
	let syslog_enabled = ubbf.to_bool(ubbf.get(ctx.root, 'Device.Syslog.Enable'));
	let action = logd_status_get()?.actions?.[`${ctx.instance}`];

	return { ...cfg, Status: logremote_status(cfg, syslog_enabled, action) };
}

/**
 * Set handler for Device.Syslog.Filter.{i}. ubbf-logd compiles PatternMatch
 * with regcomp() of the same libc, so a pattern that ucode refuses fails
 * there as well.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code to refuse the value
 */
function filter_set(ctx) {
	if (ctx.param != 'PatternMatch' || (ctx.value ?? '') == '')
		return 0;

	try {
		regexp(ctx.value);
	} catch (e) {
		log_warn('syslog: Filter.%d.PatternMatch is not a POSIX extended regular expression: %s',
			 ctx.instance, ctx.value);
		return -USP_ERR_INVALID_VALUE;
	}

	return 0;
}

/**
 * Set handler for Device.Syslog.Action.{i}: each reference must name a row
 * of the table that its list belongs to.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code to refuse the value
 */
function action_set(ctx) {
	let table = ACTION_REFS[ctx.param];
	if (!table)
		return 0;

	for (let ref in syslog.split_list(ctx.value)) {
		if (syslog.ref_instance(table, ref) != null)
			continue;

		log_warn('syslog: Action.%d.%s: %s is not a Device.Syslog.%s row', ctx.instance, ctx.param, ref, table);
		return -USP_ERR_INVALID_VALUE;
	}

	return 0;
}

/**
 * Set handler for Device.Syslog.Action.{i}.LogFile.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code to refuse the value
 */
function logfile_set(ctx) {
	if (ctx.param != 'FilePath' || (ctx.value ?? '') == '' || syslog.logfile_path(ctx.value))
		return 0;

	log_warn('syslog: Action.%d.LogFile.FilePath must be a file URI below %s: %s',
		 ctx.instance, syslog.LOG_DIR, ctx.value);
	return -USP_ERR_INVALID_VALUE;
}

/**
 * Set handler for Device.Syslog.Source.{i}.UnixDomainSocket.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code to refuse the value
 */
function unix_socket_set(ctx) {
	if (ctx.param != 'Path' || (ctx.value ?? '') == '' || syslog.socket_path(ctx.value))
		return 0;

	log_warn('syslog: Source.%d.UnixDomainSocket.Path must be a file URI of one name in %s: %s',
		 ctx.instance, syslog.SOCKET_DIR, ctx.value);
	return -USP_ERR_INVALID_VALUE;
}

/**
 * Tells whether ubbf-logd runs and so listens on the Network of a source:
 * Device.Syslog is enabled and some action writes somewhere.
 *
 * @param {object} root - Root config data
 * @returns {boolean} True when ubbf-logd runs
 */
function logd_runs(root) {
	if (!ubbf.to_bool(ubbf.get(root, 'Device.Syslog.Enable')))
		return false;

	for (let id, action in ubbf.get(root, 'Device.Syslog.Action') ?? {})
		if (type(action) == 'object' && syslog.action_has_destination(action))
			return true;

	return false;
}

/**
 * Firewall hook for Device.Syslog.Source.{i}.Network.
 *
 * Opens the configured port on the named interface for each enabled
 * network listener while ubbf-logd runs, so external syslog senders can
 * reach it.
 *
 * @param {object} inst - Source.{i} instance data (parent of Network)
 * @param {object} root - Root config data
 * @param {string} path - Instance path (Device.Syslog.Source.{i})
 * @returns {array|null} Service descriptors for the listener, or null
 */
function source_firewall(inst, root, path) {
	let net = inst.Network;
	if (!net || !ubbf.to_bool(net.Enable))
		return null;
	if (!net.Interface || net.Interface == '')
		return null;
	if (!logd_runs(root))
		return null;

	let port = net.Port ?? '1099';
	let proto_map = { TCP: 'tcp', UDP: 'udp', TLS: 'tcp' };
	let proto = proto_map[net.Protocol ?? 'UDP'] ?? 'udp';

	return [{
		type: 'Service',
		alias: sprintf('cpe-syslog-%s-%s', proto, port),
		Interface: net.Interface,
		Protocol: (proto == 'tcp') ? '6' : '17',
		DestPort: sprintf('%s', port),
		Action: 'Accept'
	}];
}

model['Device.Syslog'] = {
	schema: schema('Syslog'),
	get: syslog_get
};

model['Device.Syslog.Filter'] = {};

model['Device.Syslog.Filter.{i}'] = {
	schema: schema('Filter'),
	set: filter_set
};

model['Device.Syslog.Source'] = {};

model['Device.Syslog.Source.{i}'] = {
	schema: schema('Source'),
	firewall: source_firewall
};

model['Device.Syslog.Source.{i}.Network'] = {
	schema: schema('Source_Network')
};

model['Device.Syslog.Source.{i}.UnixDomainSocket'] = {
	schema: schema('Source_UnixDomainSocket'),
	set: unix_socket_set,
	since: '2.21'
};

model['Device.Syslog.Template'] = {};

model['Device.Syslog.Template.{i}'] = {
	schema: schema('Template')
};

model['Device.Syslog.Action'] = {};

model['Device.Syslog.Action.{i}'] = {
	schema: schema('Action'),
	set: action_set
};

model['Device.Syslog.Action.{i}.LogFile'] = {
	schema: schema('Action_LogFile'),
	set: logfile_set
};

model['Device.Syslog.Action.{i}.LogRemote'] = {
	schema: schema('Action_LogRemote'),
	get: logremote_get
};
