'use strict';

import * as fs from 'fs';
import * as rtnl from 'rtnl';

/* Linux routing protocol identifier for kernel-installed RA on-link prefixes. */
const RTPROT_RA = 9;

/**
 * Enumerates kernel-assigned IPv6 link-local addresses on a device via rtnl.
 *
 * Addresses returned in {address, mask} shape compatible with
 * `ubbf.ipv6_addr_to_object` when combined with the "forever" flag.
 *
 * @param {string} dev - Network device name (e.g. eth0, br-lan)
 * @returns {array} Array of {address, mask} objects; empty array on failure
 */
export function link_local_addresses_get(dev) {
	if (!dev)
		return [];

	let addrs = rtnl.request(rtnl.const.RTM_GETADDR, rtnl.const.NLM_F_DUMP, {
		family: rtnl.const.AF_INET6,
		dev
	});

	if (type(addrs) != 'array')
		return [];

	let result = [];
	for (let a in addrs) {
		if (a.scope != rtnl.const.RT_SCOPE_LINK)
			continue;
		if (a.dev != dev)
			continue;
		let parts = split(a.address ?? '', '/');
		push(result, {
			address: parts[0],
			mask: int(parts[1]) ?? 64
		});
	}

	return result;
};

/**
 * Enumerates IPv6 on-link prefixes learned from Router Advertisements on a
 * device. These surface in the kernel FIB as prefix routes with protocol
 * RTPROT_RA (9), which is exactly how the IPv6 stack records a received
 * Prefix Information option with L=1.
 *
 * Returns rows in the netifd-prefix shape (address, mask, preferred, valid)
 * so they can be passed straight to `ubbf.ipv6_prefix_to_object` with the
 * "RouterAdvertisement" origin.
 *
 * @param {string} dev - Network device name (e.g. eth0)
 * @returns {array} Array of prefix objects; empty array on failure
 */
export function ra_prefixes_get(dev) {
	if (!dev)
		return [];

	let routes = rtnl.request(rtnl.const.RTM_GETROUTE, rtnl.const.NLM_F_DUMP, {
		family: rtnl.const.AF_INET6
	});

	if (type(routes) != 'array')
		return [];

	let result = [];
	for (let r in routes) {
		if (r.protocol != RTPROT_RA)
			continue;
		if (r.oif != dev)
			continue;
		if (!r.dst)
			continue;

		let parts = split(r.dst, '/');
		let mask = length(parts) > 1 ? (int(parts[1]) ?? 0) : (r.dst_len ?? 0);
		let expires = r.cacheinfo?.expires ?? 0;

		push(result, {
			address: parts[0],
			mask,
			preferred: expires,
			valid: expires
		});
	}

	return result;
};

/**
 * Masks the host bits of an IPv6 address, yielding the prefix.
 *
 * @param {string} address - IPv6 address
 * @param {number} mask - Prefix length in bits
 * @returns {string|null} Masked prefix, or null on parse failure
 */
function prefix_from_address(address, mask) {
	let bytes = iptoarr(address);
	if (!bytes || length(bytes) != 16)
		return null;

	for (let i = 0; i < 16; i++) {
		let bit_off = i * 8;
		if (bit_off + 8 <= mask)
			continue;
		if (bit_off >= mask)
			bytes[i] = 0;
		else
			bytes[i] &= 0xff << (8 - (mask - bit_off));
	}

	return arrtoip(bytes);
}

/**
 * Reads the RA-learned prefix set for a netifd interface from the
 * state file maintained by /etc/odhcp6c.user.d/10-ubbf-ra-prefix.
 *
 * Used when the kernel FIB cannot be consulted for on-link PIO routes
 * (accept_ra=0 on the l3 device, because odhcp6c is the userspace RA
 * consumer). Each line in the file is the raw odhcp6c RA_ADDRESSES
 * token (addr/len,preferred,valid[,t1,t2]); only the first three
 * comma-separated fields are used. odhcp6c stores the formed SLAAC
 * address (PIO prefix plus interface identifier) in this state, so
 * the host bits are masked off here and duplicate prefixes from
 * multiple routers collapse into one row.
 *
 * @param {string} iface_name - netifd logical interface (e.g. 'wan6')
 * @returns {array} Array of {address, mask, preferred, valid}; empty on failure
 */
export function ra_prefixes_hook_read(iface_name) {
	if (!iface_name)
		return [];

	let data = fs.readfile(sprintf('/tmp/ubbf/ra-prefix.%s', iface_name));
	if (!data)
		return [];

	let result = [];
	let seen = {};
	for (let line in split(data, '\n')) {
		let entry = trim(line);
		if (entry == '')
			continue;

		let fields = split(entry, ',');
		if (length(fields) < 3)
			continue;

		let addr_parts = split(fields[0], '/');
		if (length(addr_parts) != 2)
			continue;

		let mask = int(addr_parts[1]) ?? 64;
		let prefix = prefix_from_address(addr_parts[0], mask);
		if (!prefix)
			continue;

		let key = sprintf('%s/%d', prefix, mask);
		if (seen[key])
			continue;
		seen[key] = true;

		push(result, {
			address: prefix,
			mask,
			preferred: int(fields[1]) ?? 0,
			valid: int(fields[2]) ?? 0
		});
	}

	return result;
};
