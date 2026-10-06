'use strict';

import { stat } from 'fs';
import * as schemas from 'ubbf.schemas.Time';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.Time.
 *
 * Status uses the TR-181 Time enum (Disabled / Unsynchronized /
 * Synchronized); the sync marker is maintained by the ntp hotplug hook
 * in /etc/hotplug.d/ntp/50-ubbf-time-status.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Time properties with current local time
 */
function time_get(ctx) {
	let status = 'Disabled';
	if (ubbf.to_bool(ctx.config?.Enable))
		status = stat('/tmp/ubbf/ntp-synced') ? 'Synchronized' : 'Unsynchronized';

	// LocalTimeZone comes from the spread above. Reading it back out of UCI
	// returned the rendered value, which trails a write by the deferred apply,
	// so a change to it was invisible to the value-change diff at commit.
	return {
		...ubbf.ctx_config(ctx),
		Status: status,
		CurrentLocalTime: ubbf.iso8601_format(),
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client)),
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Server))
	};
}

/**
 * Firewall hook for Device.Time.Server.{i}.
 *
 * @param {object} inst - Server instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for NTP port 123
 */
function time_server_firewall(inst, root, path) {
	if (!ubbf.to_bool(inst.Enable))
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	return [{
		type: 'Service',
		alias: sprintf('cpe-ntp-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: '123',
		Action: 'Accept'
	}];
}

export const model = {
	'Device.Time': {
		schema: schemas.Time,
		get: time_get
	},

	'Device.Time.Client': {
	},

	'Device.Time.Client.{i}': {
		schema: schemas.Client,
		maxInstances: 1
	},

	'Device.Time.Server': {
	},

	'Device.Time.Server.{i}': {
		schema: schemas.Server,
		firewall: time_server_firewall
	}
};
