'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { call as cache_call } from 'ubbf.utils.cache';
import { interface_resolve } from 'ubbf.utils.path';

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
 * Fetches IPv6 leases from odhcpd via ubus (uncached).
 *
 * @returns {object} Map of MAC addresses to arrays of IPv6 addresses
 */
function ipv6_leases_fetch() {
	let leases = ubus?.call('dhcp', 'ipv6leases', {});
	if (!leases || !leases.device)
		return {};

	let result = {};

	for (let dev_name, dev_data in leases.device) {
		if (!dev_data.leases)
			continue;

		for (let lease in dev_data.leases) {
			let mac = lease.mac ? uc(lease.mac) : ubbf.mac_from_duid(lease.duid);
			if (!mac)
				continue;

			if (!result[mac])
				result[mac] = [];

			for (let addr in lease['ipv6-addr'])
				if (addr.address)
					push(result[mac], addr.address);
		}
	}

	return result;
}

/**
 * Gets IPv6 leases from odhcpd via ubus (cached).
 *
 * @returns {object} Map of MAC addresses to arrays of IPv6 addresses
 */
export function ipv6_leases_get() {
	return cache_call(ipv6_leases_fetch);
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
 * Validates that an IPv6 prefix length lands on a nibble boundary
 * (multiple of 4 bits, in [0, 128]). RFC 7084 / TR-181 PD recommends
 * delegating only on nibble boundaries (typically /48, /52, /56, /60, /64).
 *
 * @param {string|number} len - Prefix length value
 * @returns {boolean} true if the value is an integer in [0,128] and (len % 4) == 0
 */
export function prefix_length_nibble_check(len) {
	if (len == null || len == '')
		return false;

	let n = +len;
	if (type(n) != 'int')
		return false;
	if (n < 0 || n > 128)
		return false;
	if ((n % 4) != 0)
		return false;
	return true;
};

export const leases_parse = ubbf.leases_parse;

/**
 * Returns leases whose IP falls inside a DHCPv4 pool address range,
 * sorted by lease expiry descending so the most recently granted lease
 * appears first. dnsmasq's lease file is not stored in any reliable
 * order, and TR-181 callers expect Pool.{i}.Client.1 to track the most
 * recent grant rather than whichever entry happens to sit at the top
 * of the file.
 *
 * @param {object} pool_config - Pool object with MinAddress and MaxAddress
 * @returns {array} Leases inside the pool range, newest expiry first
 */
export function leases_for_pool(pool_config) {
	let min_addr = pool_config?.MinAddress;
	let max_addr = pool_config?.MaxAddress;

	if (!min_addr || !max_addr)
		return [];

	let min_int = ubbf.ip_to_int(min_addr);
	let max_int = ubbf.ip_to_int(max_addr);

	if (min_int == 0 || max_int == 0)
		return [];

	let all_leases = leases_parse();
	let pool_leases = [];

	for (let lease in all_leases)
		if (lease.ip_int >= min_int && lease.ip_int <= max_int)
			push(pool_leases, lease);

	sort(pool_leases, (a, b) => (b?.expiry ?? 0) - (a?.expiry ?? 0));

	return pool_leases;
};

/**
 * Looks up the hex value of a DHCP option by numeric tag.
 *
 * @param {array} options - Snooped options array [{tag, value}, ...]
 * @param {number} tag - DHCP option tag
 * @returns {string} Hex value or empty string when the option is missing
 */
export function dhcp_option_value(options, tag) {
	if (type(options) != 'array')
		return '';

	for (let opt in options) {
		if (opt?.tag == tag)
			return opt.value ?? '';
	}

	return '';
};

/**
 * Decodes a hex string to a printable ASCII string. Returns an empty string
 * when the input is not valid hex or contains any non-printable byte, so that
 * callers for parameters like VendorClassID never emit garbled output.
 *
 * @param {string} hex_str - Even-length hex string
 * @returns {string} Decoded printable string, or "" when any byte is non-printable
 */
export function hex_to_printable(hex_str) {
	if (!hex_str || type(hex_str) != 'string')
		return '';

	let len = length(hex_str);
	if (len == 0 || (len % 2) != 0)
		return '';

	let out = '';
	for (let i = 0; i < len; i += 2) {
		let byte = hex(substr(hex_str, i, 2));
		// hex() yields NaN for invalid input, which passes every
		// comparison below; NaN != NaN catches it
		if (byte == null || byte != byte || byte < 32 || byte > 126)
			return '';
		out += chr(byte);
	}

	return out;
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
