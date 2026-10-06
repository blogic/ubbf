'use strict';

import * as schemas from 'ubbf.schemas.UnixDomainSockets';
import * as ubbf from 'ubbf';

const sockets = [
	{ Alias: 'broker-agent', Mode: 'Listen', Path: '/var/run/usp/broker_agent_path' },
	{ Alias: 'broker-controller', Mode: 'Listen', Path: '/var/run/usp/broker_controller_path' },
];

/**
 * Converts a socket entry to a TR-181 instance object.
 *
 * @param {object} sock - Socket entry from the sockets array
 * @returns {object} TR-181 UnixDomainSocket properties
 */
function socket_to_object(sock) {
	return {
		...schemas.UnixDomainSocket.defaults,
		Alias: sock.Alias,
		Mode: sock.Mode,
		Path: sock.Path
	};
}

/**
 * Get handler for Device.UnixDomainSockets.
 *
 * @param {object} ctx - Handler context
 * @returns {object} Root object with socket count
 */
function unix_domain_sockets_get(ctx) {
	return {
		UnixDomainSocketNumberOfEntries: sprintf('%d', length(sockets))
	};
}

/**
 * Get handler for Device.UnixDomainSockets.UnixDomainSocket.{i}.
 *
 * @param {object} ctx - Handler context with optional instance number
 * @returns {object|null} Socket properties, enumerated instances, or null
 */
function unix_domain_socket_get(ctx) {
	if (ctx.instance == null)
		return ubbf.enumerate_instances(sockets, socket_to_object);

	let sock = ubbf.get_by_instance(sockets, ctx.instance);
	if (!sock)
		return null;

	return socket_to_object(sock);
}

export const model = {
	'Device.UnixDomainSockets': {
		schema: schemas.UnixDomainSockets,
		get: unix_domain_sockets_get
	},

	'Device.UnixDomainSockets.UnixDomainSocket': {
	},

	'Device.UnixDomainSockets.UnixDomainSocket.{i}': {
		schema: schemas.UnixDomainSocket,
		get: unix_domain_socket_get
	}
};

export const operations = {};
