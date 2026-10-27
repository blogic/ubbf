'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { cache_call } from 'ubbf';
import { interface_resolve } from 'ubbf.utils.path';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { instance_rows } from 'ubbf';

/**
 * Fetches snooped DHCP client data from udhcpsnoop (uncached).
 *
 * @returns {object} Map of lower-case MAC to { ip, options, req_options, server_options }
 */
function dhcpsnoop_dump_fetch() {
	return ubus?.call('dhcpsnoop', 'dump', {}) ?? {};
}

/**
 * Gets the udhcpsnoop dump (cached per request cycle).
 *
 * @returns {object} Map of lower-case MAC to snoop entry
 */
export function dhcpsnoop_dump_get() {
	return cache_call(dhcpsnoop_dump_fetch);
};

/**
 * Fetches raw IPv6 leases from odhcpd via ubus (uncached).
 *
 * @returns {object|null} Raw leases response from ubus
 */
function ipv6_leases_raw_fetch() {
	return ubus?.call('dhcp', 'ipv6leases', {});
}

/**
 * Gets raw IPv6 leases from odhcpd via ubus (cached).
 *
 * @returns {object|null} Raw leases response from ubus
 */
export function ipv6_leases_raw_get() {
	return cache_call(ipv6_leases_raw_fetch);
};

/**
 * Maps the odhcpd IPv6 leases by MAC, from the cached raw response.
 *
 * @returns {object} Map of MAC addresses to arrays of IPv6 addresses
 */
function ipv6_leases_fetch() {
	return ubbf.ipv6_leases_by_mac(ipv6_leases_raw_get());
}

/**
 * Gets the IPv6 leases from odhcpd by MAC (cached).
 *
 * @returns {object} Map of MAC addresses to arrays of IPv6 addresses
 */
export function ipv6_leases_get() {
	return cache_call(ipv6_leases_fetch);
};

/**
 * Returns the clients of a DHCPv6 server pool, one per DUID, in the order
 * of the odhcpd leases (ipv6_pool_clients_build() in dhcp.c of ubbf.so).
 * ipv6_pool_clients_numbered() gives them their instance numbers.
 *
 * @param {object} root - Root data model object
 * @param {object} pool - Pool row with its Interface reference
 * @returns {array} { duid, mac, hostname, addresses, prefixes } per client
 */
export function ipv6_pool_clients(root, pool) {
	let name = ubbf.interface_to_name(root, pool?.Interface);
	if (!name)
		return [];

	return ubbf.ipv6_pool_clients_build(netifd_status_get(name), ipv6_leases_raw_get());
};

/**
 * Numbers the clients of a DHCPv6 server pool by DUID, so that a client
 * keeps its number while other clients come and go.
 *
 * @param {string} pool_path - Path of the pool, e.g. Device.DHCPv6.Server.Pool.1
 * @param {object} root - Root data model object
 * @param {object} pool - Pool row with its Interface reference
 * @returns {object} Instance number to ipv6_pool_clients() client
 */
export function ipv6_pool_clients_numbered(pool_path, root, pool) {
	let by_duid = {};
	for (let c in ipv6_pool_clients(root, pool))
		by_duid[c.duid] = c;
	return instance_rows(pool_path + '.Client', keys(by_duid), (duid) => by_duid[duid]);
};

/**
 * Numbers the leases of a DHCPv4 server pool by client MAC, so that a
 * client keeps its number across renewals while other clients come and
 * go; pool_leases_by_key() in dhcp.c of ubbf.so gives the keys.
 *
 * @param {string} pool_path - Path of the pool, e.g. Device.DHCPv4.Server.Pool.1
 * @param {object} pool_config - Pool object with MinAddress and MaxAddress
 * @returns {object} Instance number to lease
 */
export function pool_leases_numbered(pool_path, pool_config) {
	let by_key = ubbf.pool_leases_by_key(pool_config);
	return instance_rows(pool_path + '.Client', keys(by_key), (key) => by_key[key]);
};

/**
 * Resolves a DHCP client Interface reference to the client's MAC.
 *
 * @param {object} root - Root data model object
 * @param {string} iface_ref - TR-181 interface path reference
 * @returns {string|null} Lowercase MAC or null
 */
export function client_mac_resolve(root, iface_ref) {
	let dev = interface_resolve(root, iface_ref);
	if (!dev)
		return null;
	let mac = ubbf.readfile_trim(`/sys/class/net/${dev}/address`);
	return mac ? lc(mac) : null;
};

/**
 * Looks up the udhcpsnoop dump entry for the given client interface.
 *
 * @param {object} root - Root data model object
 * @param {string} iface_ref - TR-181 interface path reference
 * @returns {object|null} Snoop entry {ip, options, req_options, server_options} or null
 */
export function client_snoop_entry(root, iface_ref) {
	let mac = client_mac_resolve(root, iface_ref);
	if (!mac)
		return null;
	return dhcpsnoop_dump_get()?.[mac];
};
