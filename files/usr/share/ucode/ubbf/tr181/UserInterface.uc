'use strict';

import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.UserInterface';
import * as ubbf from 'ubbf';

/**
 * Retrieves active web sessions from ubbf-ui via ubus.
 *
 * @returns {array} Array of session objects or empty array
 */
function sessions_get() {
	let result = ubus?.call('ubbf-ui', 'web_sessions', {});
	if (!result || !result.sessions)
		return [];

	return result.sessions;
}

/**
 * Converts a session object to TR-181 HTTPAccess_Session format.
 *
 * @param {object} session - Session data with ip and port
 * @returns {object} TR-181 formatted Session object
 */
function session_to_object(session) {
	return {
		IPAddress: session.ip ?? '',
		Port: sprintf('%d', session.port ?? 0)
	};
}

/**
 * Get handler for Device.UserInterface.HTTPAccess.{i}.Session.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single session or enumerated sessions
 */
function session_get(ctx) {
	let sessions = sessions_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(sessions, session_to_object);

	let session = ubbf.get_by_instance(sessions, ctx.instance);
	if (!session)
		return null;

	return session_to_object(session);
}

/**
 * Get handler for Device.UserInterface.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Computed UserInterface properties
 */
function userinterface_get(ctx) {
	let instances = ctx.config?.HTTPAccess;

	return {
		...ctx.config,
		HTTPAccessNumberOfEntries: sprintf('%d', length(instances))
	};
}

/**
 * Firewall hook for Device.UserInterface.HTTPAccess.{i}.
 *
 * @param {object} inst - HTTPAccess instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for web UI port
 */
function http_access_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	let port = inst.Port ?? '80';

	return [{
		type: 'Service',
		alias: sprintf('cpe-webui-%s-%s', iface.Name, port),
		Interface: inst.Interface,
		Protocol: 'tcp',
		DestPort: sprintf('%s', port),
		Action: 'Accept'
	}];
}

export const model = {
	'Device.UserInterface': {
		schema: schemas.UserInterface,
		get: userinterface_get
	},

	'Device.UserInterface.HTTPAccess': {
	},

	'Device.UserInterface.HTTPAccess.{i}': {
		schema: schemas.HTTPAccess,
		firewall: http_access_firewall
	},

	'Device.UserInterface.HTTPAccess.{i}.Session': {
	},

	'Device.UserInterface.HTTPAccess.{i}.Session.{i}': {
		schema: schemas.HTTPAccess_Session,
		get: session_get
	}
};
