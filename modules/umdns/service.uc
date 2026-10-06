'use strict';

// DNS-SD naming shared by handler.uc and render.uc. Both include this file
// with { dnssd } as the scope; an included file exports nothing, so each
// function is added to that object.

/**
 * Builds the DNS-SD service type label of an Advertise instance.
 *
 * TR-181 states ApplicationProtocol without the leading underscore and
 * TransportProtocol as TCP or UDP; DNS-SD labels carry both with one. A
 * value that already has the underscore still works.
 *
 * @param {object} advertise - Advertise instance configuration
 * @returns {string} Service type, for example _http._tcp.local
 */
dnssd.service_name = function(advertise) {
	let app = '_' + ltrim(advertise.ApplicationProtocol || 'http', '_');
	let trans = (uc(advertise.TransportProtocol ?? '') == 'UDP') ? '_udp' : '_tcp';
	let domain = advertise.Domain || 'local';
	return `${app}.${trans}.${domain}`;
};

/**
 * Sanitises an instance name into the identifier umdns keys a service by.
 *
 * @param {string} name - Instance name
 * @returns {string} Lowercase alphanumeric name with underscores
 */
dnssd.service_id = function(name) {
	return replace(lc(name), /[^a-z0-9_]/g, '_');
};
