'use strict';

import * as schemas from 'ubbf.schemas.Syslog';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.Syslog.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Syslog properties with instance counts
 */
function syslog_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		FilterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Filter)),
		SourceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Source)),
		TemplateNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Template)),
		ActionNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Action))
	};
}

/**
 * Get handler for Device.Syslog.Action.{i}.LogRemote.
 *
 * Produces a coarse Status. We mark Enabled when the LogRemote and its parent
 * Action are enabled and the destination is configured; Disabled otherwise.
 * Error_Unreachable would require connection-state polling from syslog-ng-ctl
 * stats, which is not yet wired up.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object} LogRemote properties with derived Status
 */
function logremote_get(ctx) {
	let cfg = ubbf.ctx_config(ctx);
	let action_enabled = ubbf.to_bool(ctx.parent?.Enable ?? 'true');
	let self_enabled = ubbf.to_bool(cfg.Enable);

	let status;
	if (!action_enabled || !self_enabled)
		status = 'Disabled';
	else if (!cfg.Address || cfg.Address == '')
		status = 'Error';
	else
		status = 'Enabled';

	return { ...cfg, Status: status };
}

/**
 * Firewall hook for Device.Syslog.Source.{i}.Network.
 *
 * Opens the configured port on the named interface for each enabled
 * network listener so external syslog senders can reach syslog-ng.
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

	let port = net.Port ?? '1099';
	let proto_map = { TCP: 'tcp', UDP: 'udp', TLS: 'tcp' };
	let proto = proto_map[net.Protocol ?? 'UDP'] ?? 'udp';

	return [{
		type: 'Service',
		alias: sprintf('cpe-syslog-%s-%s', proto, port),
		Interface: net.Interface,
		Protocol: proto,
		DestPort: sprintf('%s', port),
		Action: 'Accept'
	}];
}

export const model = {
	'Device.Syslog': {
		schema: schemas.Syslog,
		get: syslog_get,
		enable_status_derive: true
	},

	'Device.Syslog.Filter': {
	},

	'Device.Syslog.Filter.{i}': {
		schema: schemas.Filter
	},

	'Device.Syslog.Source': {
	},

	'Device.Syslog.Source.{i}': {
		schema: schemas.Source,
		firewall: source_firewall
	},

	'Device.Syslog.Source.{i}.Network': {
		schema: schemas.Source_Network
	},

	'Device.Syslog.Template': {
	},

	'Device.Syslog.Template.{i}': {
		schema: schemas.Template
	},

	'Device.Syslog.Action': {
	},

	'Device.Syslog.Action.{i}': {
		schema: schemas.Action
	},

	'Device.Syslog.Action.{i}.LogFile': {
		schema: schemas.Action_LogFile
	},

	'Device.Syslog.Action.{i}.LogRemote': {
		schema: schemas.Action_LogRemote,
		get: logremote_get
	}
};
