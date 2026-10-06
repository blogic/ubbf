'use strict';

// Shared by handler.uc and render.uc, which include this file with
// { ubbf, dm_visible, upstream_interface_ref, ddns } as the scope; the
// functions are added to `ddns`. Both sides must agree on the sections of
// a client, because the handler reads the runtime files of ddns-scripts by
// section name. The scope exists only while the include runs, so the names
// are bound here.

const ubbf_lib = ubbf;
const dm_visible_fn = dm_visible;
const upstream_ref = upstream_interface_ref;
const out = ddns;

const SERVER_RE = /^Device\.DynamicDNS\.Server\.[0-9]+\.?$/;
const INTERFACE_RE = /^Device\.IP\.Interface\.[0-9]+\.?$/;

/**
 * Looks up a configuration object by path.
 *
 * @param {object} config - Configuration root
 * @param {string} path - Object path, with or without the trailing dot
 * @returns {object|null} Object, null when absent
 */
function object_get(config, path) {
	if (!path)
		return null;

	return ubbf_lib.navigate_data(config, ubbf_lib.path_to_parts(rtrim(path, '.')));
}

/**
 * Returns the netifd interface that holds the IPv6 address of an
 * IP.Interface, as ddns-scripts reads it (network_get_ipaddr6): <name>6
 * for a DHCPv6 client that asks for addresses (ip.uc), <name> for a static
 * address, else the downstream interface whose prefix comes from this one.
 *
 * @param {object} config - Configuration root
 * @param {string} ref - Device.IP.Interface.{i} path
 * @returns {string|null} netifd interface, null without an IPv6 address
 */
function ipv6_network(config, ref) {
	let ip = config?.Device?.IP;
	let iface = object_get(config, ref);
	let path = rtrim(ref, '.');

	if (!iface?.Name || !ubbf_lib.to_bool(ip?.IPv6Enable ?? 'true') || !ubbf_lib.to_bool(iface.IPv6Enable ?? 'true'))
		return null;

	let dhcp6 = filter(values(config?.Device?.DHCPv6?.Client ?? {}), (c) =>
		type(c) == 'object' && ubbf_lib.to_bool(c.Enable) && rtrim(c.Interface ?? '', '.') == path)[0];

	if (dhcp6 && ubbf_lib.to_bool(dhcp6.RequestAddresses ?? 'true'))
		return iface.Name + '6';

	for (let key, addr in iface.IPv6Address ?? {})
		if (type(addr) == 'object' && ubbf_lib.to_bool(addr.Enable) && addr.Origin == 'Static' && addr.IPAddress)
			return iface.Name;

	if (!dhcp6)
		return null;

	for (let key, other in ip?.Interface ?? {}) {
		if (type(other) != 'object' || !other.Name || !ubbf_lib.to_bool(other.IPv6Enable ?? 'true'))
			continue;

		for (let k, prefix in other.IPv6Prefix ?? {})
			if (type(prefix) == 'object' && index(prefix.ParentPrefix ?? '', path + '.IPv6Prefix.') == 0)
				return other.Name;
	}

	return null;
}

/**
 * Returns the address families a client updates and the netifd interface
 * of each. IPVersion -1 (2.21) updates the families the interface has; an
 * explicit version without an address is left out, and the client then
 * reads Error_Misconfigured. Below 2.21 a client updates the A record only.
 * An empty Interface means the upstream interface.
 *
 * @param {object} config - Configuration root
 * @param {object} client - Client row
 * @returns {array} [ { family, network } ]
 */
out.client_networks = function(config, client) {
	let ref = client.Interface || upstream_ref(config);
	let iface = object_get(config, ref);
	if (!iface?.Name)
		return [];

	let version = dm_visible_fn('2.21', null) ? (ubbf_lib.to_int(client.IPVersion) ?? -1) : 4;
	let result = [];

	if (version != 6 && ubbf_lib.to_bool(config?.Device?.IP?.IPv4Enable ?? 'true') && ubbf_lib.to_bool(iface.IPv4Enable ?? 'true'))
		push(result, { family: 4, network: iface.Name });

	let network6 = (version != 4) ? ipv6_network(config, ref) : null;
	if (network6)
		push(result, { family: 6, network: network6 });

	return result;
};

/**
 * Name of the ddns-scripts section of a hostname for one family. The AAAA
 * section of a client that updates both families has the suffix _ipv6.
 *
 * @param {*} client_instance - Client instance number
 * @param {*} hostname_instance - Hostname instance number
 * @param {number} family - 4 or 6
 * @param {boolean} both - Whether the client updates both families
 * @returns {string} UCI section name
 */
out.section_name = function(client_instance, hostname_instance, family, both) {
	let name = ubbf_lib.name_sanitise(sprintf('ddns_%s_%s', client_instance, hostname_instance));

	return (family == 6 && both) ? name + '_ipv6' : name;
};

/**
 * Tells whether a Client.Server value is a Server row path or empty.
 *
 * @param {string} value - Reference
 * @returns {boolean} true when acceptable
 */
out.server_ref_valid = function(value) {
	return value == '' || match(value, SERVER_RE) != null;
};

/**
 * Tells whether a Client.Interface value is an IP.Interface path or empty.
 *
 * @param {string} value - Reference
 * @returns {boolean} true when acceptable
 */
out.interface_ref_valid = function(value) {
	return value == '' || match(value, INTERFACE_RE) != null;
};

/**
 * Tells whether a value is a host name a DDNS record can carry: labels of
 * letters, digits and hyphens, optionally under a wildcard label.
 *
 * @param {string} value - Host name
 * @returns {boolean} true for a host name of at most 253 characters
 */
out.hostname_valid = function(value) {
	return type(value) == 'string' && length(value) <= 253 &&
		match(value, /^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/) != null;
};

/**
 * Tells whether a value is a server address: a host name or an IP address.
 *
 * @param {string} value - ServerAddress
 * @returns {boolean} true when acceptable, also for empty
 */
out.server_address_valid = function(value) {
	if (value == '')
		return true;

	return value != null && (iptoarr(value) != null || out.hostname_valid(value)) && index(value, '*') < 0;
};
