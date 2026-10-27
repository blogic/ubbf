'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import { log_err, log_exception } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { prefix_length_nibble_check } from 'ubbf.utils.dhcp';
import { ifstats_get, ifstats_aggregate, ifstats_reset, ip_interface_members } from 'ubbf.utils.ifstats';
import { link_local_addresses_get, ipv6_prefix_rows } from 'ubbf.utils.ipv6';
import { instance_stack } from 'ubbf.utils.instance-map';

/**
 * Brings an IPv6 address or prefix to one spelling, so that a stored value
 * matches the address netifd reports.
 *
 * @param {string} addr - Address, optionally with /length
 * @returns {string|null} Canonical address, with /length when one was given
 */
function ip_canonical(addr) {
	if (type(addr) != 'string' || addr == '')
		return null;
	let parts = split(addr, '/', 2);
	let bytes = iptoarr(parts[0]);
	if (!bytes)
		return null;
	let ip = arrtoip(bytes);
	return (length(parts) > 1) ? sprintf('%s/%s', ip, parts[1]) : ip;
}

/**
 * Netifd devices of an IP.Interface: the IPv6 status of an upstream
 * interface comes from its `<name>6` companion.
 *
 * @param {object} iface - Stored IP.Interface row
 * @returns {object} { netifd, netifd6, l2_dev, upstream }
 */
function interface_status(iface) {
	let netifd = netifd_status_get(iface?.Name);
	let upstream = ubbf.to_bool(iface?.Upstream);
	return {
		netifd,
		netifd6: upstream ? netifd_status_get(iface.Name + '6') : netifd,
		l2_dev: netifd?.l3_device ?? netifd?.device,
		upstream
	};
}

/**
 * Numbers the IPv4 addresses of an interface: a stored row keeps its
 * number and its address, a DHCP row takes the leased address, and the
 * other addresses follow the stored rows.
 *
 * @param {object} iface - Stored IP.Interface row
 * @param {object} st - interface_status() of the row
 * @returns {object} Instance number to netifd ipv4-address entry
 */
function ipv4_items(iface, st) {
	return instance_stack(iface?.IPv4Address, st.netifd?.['ipv4-address'] ?? [],
		(row, a) => (row?.AddressingType ?? 'Static') == 'Static' && row?.IPAddress == a.address,
		(row, a) => (row?.AddressingType ?? 'Static') != 'Static');
}

/**
 * Lists the IPv6 addresses of an interface: netifd ipv6-address, the local
 * addresses of the prefix assignments (PD), and the kernel link-local
 * addresses, each with the Origin it has without a stored row.
 *
 * @param {object} st - interface_status() of the row
 * @returns {array} Items { data, origin, permanent }
 */
function ipv6_address_list(st) {
	let items = [];

	// On an upstream interface odhcp6c hands netifd its IA_NA leases as /128
	// and its SLAAC addresses with the length of their prefix, in one list;
	// the list of a downstream interface holds no such mix.
	for (let a in st.netifd6?.['ipv6-address'] ?? [])
		push(items, { data: a, origin: 'DHCPv6', permanent: false, lease: !st.upstream || a.mask == 128 });

	for (let pa in st.netifd6?.['ipv6-prefix-assignment'] ?? []) {
		// netifd always emits the local-address table and only fills
		// address/mask when the assignment is enabled
		if (!pa?.['local-address']?.address)
			continue;
		// PA rows with RA/PD-sourced lifetimes are Child (auto-configured from
		// a delegated parent prefix); PA rows without lifetimes come from a
		// locally-configured prefix (e.g. ULA) and are Static per TR-181.
		let has_lifetime = (pa.preferred != null) || (pa.valid != null);
		push(items, {
			data: {
				address: pa['local-address'].address,
				mask: pa['local-address'].mask,
				preferred: pa.preferred,
				valid: pa.valid
			},
			origin: has_lifetime ? 'Child' : 'Static',
			permanent: !has_lifetime
		});
	}

	// Kernel-assigned link-local addresses have no RA/DHCPv6 lifetime;
	// pull them directly via rtnl on the L2 device and mark permanent.
	for (let ll in link_local_addresses_get(st.l2_dev))
		push(items, { data: ll, origin: 'AutoConfigured', permanent: true });

	return items;
}

/**
 * Numbers the IPv6 addresses of an interface: a stored row with an address
 * takes that address, a stored row without one takes the first address of
 * its Origin (a DHCPv6 row only a lease), and the other addresses follow
 * the stored rows.
 *
 * @param {object} iface - Stored IP.Interface row
 * @param {object} st - interface_status() of the row
 * @returns {object} Instance number to ipv6_address_list() item
 */
function ipv6_address_items(iface, st) {
	return instance_stack(iface?.IPv6Address, ipv6_address_list(st),
		(row, item) => ip_canonical(row?.IPAddress) != null &&
			ip_canonical(row.IPAddress) == ip_canonical(item.data.address),
		(row, item) => !row?.IPAddress && (row?.Origin ?? 'DHCPv6') == item.origin &&
			(item.origin != 'DHCPv6' || item.lease));
}

/**
 * Numbers the dynamic IPv6 prefixes of an interface: a stored row with a
 * Prefix takes that prefix, a stored row of the same Origin without one
 * takes the first prefix of that Origin, and the other prefixes follow the
 * stored rows. A Child row (with ParentPrefix) takes the next delegated
 * prefix on an upstream interface, where ipv6_prefix_get() reads it from
 * the same netifd list; on a downstream interface it reads a prefix
 * assignment, which is not in this list.
 *
 * @param {object} iface - Stored IP.Interface row
 * @param {object} st - interface_status() of the row
 * @returns {object} Instance number to ipv6_prefix_rows() item
 */
function ipv6_prefix_items(iface, st) {
	return instance_stack(iface?.IPv6Prefix, ipv6_prefix_rows(iface?.Name, st.upstream, st.l2_dev),
		(row, item) => !row?.ParentPrefix && ip_canonical(row?.Prefix) != null &&
			ip_canonical(row.Prefix) == ip_canonical(sprintf('%s/%d', item.data.address, item.data.mask)),
		(row, item) => row?.ParentPrefix
			? (st.upstream && item.origin == 'PrefixDelegation')
			: (!row?.Prefix && row?.Origin == item.origin));
}


/**
 * Get handler for Device.IP.
 *
 * @param {object} ctx - Context with config
 * @returns {object} IP capabilities and status
 */
function ip_get(ctx) {
	let ipv4_capable = false;
	let ipv6_capable = false;

	try {
		ipv4_capable = fs.access('/proc/sys/net/ipv4', 'r');
	} catch (e) {
		log_exception('Device.IP', e);
	}

	try {
		ipv6_capable = fs.access('/proc/sys/net/ipv6', 'r');
	} catch (e) {
		log_exception('Device.IP', e);
	}

	let cfg = ubbf.ctx_config(ctx);
	let ipv4_enable = ubbf.to_bool(cfg.IPv4Enable ?? 'true');
	let ipv6_enable = ubbf.to_bool(cfg.IPv6Enable ?? 'true');

	return {
		...cfg,
		IPv4Capable: ipv4_capable ? 'true' : 'false',
		IPv4Enable: ipv4_enable ? 'true' : 'false',
		IPv4Status: (ipv4_capable && ipv4_enable) ? 'Enabled' : 'Disabled',
		IPv6Capable: ipv6_capable ? 'true' : 'false',
		IPv6Enable: ipv6_enable ? 'true' : 'false',
		IPv6Status: (ipv6_capable && ipv6_enable) ? 'Enabled' : 'Disabled'
	};
}

/**
 * Get handler for Device.IP.Interface.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Interface properties with addresses and prefixes
 */
function interface_get(ctx) {
	if (!ctx.config)
		return null;

	let st = interface_status(ctx.config);
	let netifd = st.netifd;
	let l2_dev = st.l2_dev;
	let result = {
		...ctx.config,
		Status: netifd?.up ? 'Up' : 'Down',
		LastChange: last_change_get(l2_dev)
	};

	// Without a configured MTU (an older ubbf stored 0) the MTU in use
	// reads back, which TR-181 bounds to 64..65535
	if (!(ubbf.to_int(ctx.config.MaxMTUSize) >= 64)) {
		let mtu = l2_dev ? ubbf.readfile_int(`/sys/class/net/${l2_dev}/mtu`, -1) : -1;
		if (mtu >= 64)
			result.MaxMTUSize = sprintf('%d', min(mtu, 65535));
		else
			delete result.MaxMTUSize;
	}

	let config_ipv4 = ctx.config.IPv4Address ?? {};
	let ipv4 = {};
	for (let n, a in ipv4_items(ctx.config, st))
		ipv4[n] = ubbf.ipv4_addr_to_object(a, config_ipv4[n]?.AddressingType);
	if (length(ipv4) > 0)
		result.IPv4Address = ipv4;
	result.IPv4AddressNumberOfEntries = sprintf('%d', length(ipv4));

	// TR-181 IPv6Address holds both directly-assigned addresses and
	// addresses derived from local prefix assignments (PD), in one
	// instance space.
	let config_ipv6 = ctx.config.IPv6Address ?? {};
	let ipv6 = {};
	for (let n, item in ipv6_address_items(ctx.config, st))
		ipv6[n] = ubbf.ipv6_addr_to_object(item.data, config_ipv6[n]?.Origin ?? item.origin, item.permanent);
	if (length(ipv6) > 0)
		result.IPv6Address = ipv6;
	result.IPv6AddressNumberOfEntries = sprintf('%d', length(ipv6));

	// Upstream interfaces combine two prefix sources: netifd's ipv6-prefix
	// (the DHCPv6-PD grant) and RA-learned PIOs. RA PIOs come from the
	// odhcp6c.user.d hook state file when present (our stack runs
	// accept_ra=0 so the kernel FIB has no RTPROT_RA routes); fall back
	// to the kernel FIB for setups where the kernel does process RAs.
	let prefixes = {};
	for (let n, item in ipv6_prefix_items(ctx.config, st))
		prefixes[n] = ubbf.ipv6_prefix_to_object(item.data, item.origin);
	if (length(prefixes) > 0)
		result.IPv6Prefix = prefixes;
	result.IPv6PrefixNumberOfEntries = sprintf('%d', length(prefixes));

	return result;
}

/**
 * Get handler for Device.IP.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} Interface statistics
 */
function interface_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	// IP.Interface stats sum across the wire-level bridge members so
	// L2 traffic the L3 sub-device never sees (flooded multicast,
	// broadcast, etc) still counts. Single-netdev interfaces (WAN)
	// come back as a one-element list, same effect as before.
	let members = ip_interface_members(ctx.root, parent);
	if (length(members) > 0)
		return ifstats_aggregate(members);

	let netifd = netifd_status_get(parent.Name);
	let device_name = netifd?.l3_device ?? netifd?.device;
	if (!device_name)
		return null;

	return ifstats_get(device_name);
}

/**
 * Sync operation handler for IP.Interface.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function interface_stats_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface = root?.Device?.IP?.Interface?.['' + idx];
	if (!iface?.Name)
		return null;

	let members = ip_interface_members(root, iface);
	if (length(members) == 0) {
		let netifd = netifd_status_get(iface.Name);
		let device_name = netifd?.l3_device ?? netifd?.device;
		if (!device_name)
			return null;
		members = [ device_name ];
	}

	let any_ok = false;
	for (let name in members)
		if (ifstats_reset(name))
			any_ok = true;
	return any_ok ? {} : null;
}

/**
 * Sync operation handler for IP.Interface.{i}.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function interface_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface = root?.Device?.IP?.Interface?.['' + idx];
	if (!iface?.Name)
		return null;

	// netifd splits IPv4/IPv6 leases across paired interfaces named
	// '<iface>' and '<iface>6'; TR-181 requires both to be refreshed.
	for (let name in [ iface.Name, iface.Name + '6' ]) {
		ubus.call('network.interface.' + name, 'down', {});
		ubus.call('network.interface.' + name, 'up', {});
	}

	return {};
}

/**
 * Get handler for Device.IP.Interface.{i}.IPv4Address.{i}.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object|null} IPv4 address properties
 */
function ipv4_address_get(ctx) {
	if (!ctx.config)
		return null;

	let addr_data = ipv4_items(ctx.parent, interface_status(ctx.parent))[sprintf('%d', ctx.instance)];

	if (addr_data) {
		return {
			...ctx.config,
			IPAddress: addr_data.address ?? '',
			SubnetMask: ubbf.cidr_to_netmask(addr_data.mask ?? 0)
		};
	}

	return {
		...ctx.config
	};
}

/**
 * Copies the named fields of an object built by the native IPv6 helpers,
 * which turn lifetimes into TR-181 dateTime values.
 *
 * @param {object} obj - ubbf.ipv6_addr_to_object() or ipv6_prefix_to_object()
 * @param {array} names - Fields to copy
 * @returns {object} The fields
 */
function ipv6_fields(obj, names) {
	let out = {};
	for (let name in names)
		out[name] = obj[name];
	return out;
}

const IPV6_ADDRESS_FIELDS = [ 'IPAddressStatus', 'IPAddress', 'PreferredLifetime', 'ValidLifetime' ];
const IPV6_PREFIX_FIELDS = [ 'PrefixStatus', 'Prefix', 'PreferredLifetime', 'ValidLifetime' ];

/**
 * Get handler for Device.IP.Interface.{i}.IPv6Address.{i}.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object|null} IPv6 address properties
 */
function ipv6_address_get(ctx) {
	if (!ctx.config)
		return null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = enabled ? 'Enabled' : 'Disabled';

	if (ctx.config.Origin == 'Static')
		return { ...ctx.config, Status: status, IPAddressStatus: enabled ? 'Preferred' : 'Invalid' };

	let item = ipv6_address_items(ctx.parent, interface_status(ctx.parent))[sprintf('%d', ctx.instance)];
	if (!item)
		return { ...ctx.config, Status: status, IPAddressStatus: 'Invalid' };

	let obj = ubbf.ipv6_addr_to_object(item.data, null, item.permanent);
	return { ...ctx.config, Status: status, ...ipv6_fields(obj, IPV6_ADDRESS_FIELDS) };
}

/**
 * Get handler for Device.IP.Interface.{i}.IPv6Prefix.{i}.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object|null} IPv6 prefix properties
 */
function ipv6_prefix_get(ctx) {
	let st = interface_status(ctx.parent);

	if (!ctx.config) {
		if (!st.upstream)
			return null;
		let row = ipv6_prefix_items(ctx.parent, st)[sprintf('%d', ctx.instance)];
		if (!row)
			return null;
		return ubbf.ipv6_prefix_to_object(row.data, row.origin);
	}

	// On upstream (WAN) interfaces netifd reports prefixes received via
	// DHCPv6-PD or RA in ipv6-prefix; on downstream (LAN) interfaces it
	// reports the locally-derived sub-prefixes in ipv6-prefix-assignment.
	// The stored Child rows take these in the order of their numbers.
	let prefix_key = st.upstream ? 'ipv6-prefix' : 'ipv6-prefix-assignment';
	let prefixes = st.netifd6?.[prefix_key] ?? [];
	let children = sort(filter(keys(ctx.parent?.IPv6Prefix ?? {}),
		(n) => ubbf.is_instance_key(n) && ctx.parent.IPv6Prefix[n]?.ParentPrefix), (a, b) => +a - +b);
	let pos = index(children, sprintf('%d', ctx.instance));
	let prefix_data = (pos >= 0) ? prefixes[pos] : null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = enabled ? 'Enabled' : 'Disabled';
	// Origin is read-only per TR-181: PrefixDelegation/RouterAdvertisement
	// can only appear on upstream interfaces; on downstream interfaces a
	// row carrying a ParentPrefix reference is a Child prefix derived from
	// the upstream parent, and rows without ParentPrefix default to Static.
	let origin = ctx.config.ParentPrefix ? 'Child' : 'Static';

	if (prefix_data && origin != 'Static') {
		let obj = ubbf.ipv6_prefix_to_object(prefix_data, origin);
		return { ...ctx.config, Origin: origin, Status: status, ...ipv6_fields(obj, IPV6_PREFIX_FIELDS) };
	}

	return {
		...ctx.config,
		Origin: origin,
		Status: status,
		PrefixStatus: enabled ? 'Preferred' : 'Invalid'
	};
}

/**
 * Set handler for Device.IP.Interface.{i}.IPv6Prefix.{i}.
 *
 * Enforces RFC 7084 / TR-181 PD recommendation that prefix lengths
 * land on a nibble boundary (multiple of 4 bits).
 *
 * @param {object} ctx - Context with param, value
 * @returns {number} 0 on success, -1 on failure
 */
function ipv6_prefix_set(ctx) {
	switch (ctx.param) {
	case 'ChildPrefixBits':
		if (ctx.value != null && ctx.value != '' &&
		    !prefix_length_nibble_check(ctx.value)) {
			log_err('IPv6Prefix.ChildPrefixBits must be on nibble boundary, got %s', ctx.value);
			return -1;
		}
		return 0;
	case 'Prefix':
		if (ctx.value && ctx.value != '') {
			let m = match(ctx.value, /\/(\d+)$/);
			if (m && !prefix_length_nibble_check(m[1])) {
				log_err('IPv6Prefix.Prefix length must be on nibble boundary, got %s', ctx.value);
				return -1;
			}
		}
		return 0;
	}
	return 0;
}

/**
 * Name callback for Device.IP.Interface.{i}.
 *
 * @param {object} inst - Instance data
 * @param {object} root - Root config data
 * @returns {string|null} Sanitised lower-layer device name
 */
function interface_name(inst, root) {
	let dev = ubbf.lower_layer_resolve(root, inst.LowerLayers);
	if (!dev)
		return null;
	return replace(dev, /[^a-zA-Z0-9_]/g, '_');
}

/**
 * Set handler for Device.IP.Interface.{i}.
 *
 * Upstream is read-only and names the direction of the link below. The
 * first object down the LowerLayers chain that declares its own Upstream,
 * a cellular modem or an Ethernet interface, decides it for the IP
 * interface stacked on it; a chain that declares nothing leaves the stored
 * value alone.
 *
 * @param {object} ctx - Set context with param, config and root
 */
function interface_set(ctx) {
	if (ctx.param != 'LowerLayers')
		return;

	let lower = ctx.config;
	for (let hop = 0; hop < 8; hop++) {
		let first_ref = ubbf.csv_to_list(lower.LowerLayers ?? '')[0];
		if (!first_ref)
			return;

		lower = ubbf.get(ctx.root, first_ref);
		if (type(lower) != 'object')
			return;

		if (type(lower.Upstream) == 'string') {
			ctx.config.Upstream = lower.Upstream;
			return;
		}
	}
}

/**
 * Firewall hook for Device.IP.Interface.{i}.
 * Declares an InterfaceSetting per enabled interface.
 *
 * @param {object} inst - Instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path (e.g. Device.IP.Interface.1)
 * @returns {array|null} InterfaceSetting descriptors
 */
function interface_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Name)
		return null;

	let upstream = ubbf.to_bool(inst.Upstream);

	return [{
		type: 'InterfaceSetting',
		alias: sprintf('cpe-ifsetting-%s', inst.Name),
		Interface: path,
		StealthMode: upstream ? 'true' : 'false'
	}];
}

/**
 * Get handler for Device.IP.Interface.{i}.X_UBBF_DNSProbe.
 *
 * @param {object} ctx - Context with stored config and parent interface
 * @returns {object} Stored probe config merged with live status from the
 *          dnsprobe daemon. Daemon absence is silently ignored; schema
 *          defaults then fill the read-only fields.
 */
function dnsprobe_get(ctx) {
	let base = ctx.config ?? {};
	let name = ctx.parent?.Name;
	if (!name)
		return base;

	let reply;
	try {
		reply = ubus.call('dnsprobe', 'status', { interface: name });
	} catch (e) {
		/* daemon not running or object absent -> leave defaults */
	}

	let entry = reply?.probes?.[0];
	if (!entry)
		return base;

	return {
		...base,
		Status: entry.status ?? base.Status,
		ConsecutiveFailures: sprintf('%d', entry.consecutive_failures ?? 0),
		LastTriggerTime: entry.last_trigger_time ?? base.LastTriggerTime
	};
}

export const model = {
	'Device.IP': {
		schema: 'IP.IP',
		get: ip_get
	},

	'Device.IP.Interface': {
	},

	'Device.IP.Interface.{i}': {
		schema: 'IP.Interface',
		get: interface_get,
		set: interface_set,
		name: interface_name,
		firewall: interface_firewall
	},

	'Device.IP.Interface.{i}.Stats': {
		schema: 'IP.Interface_Stats',
		get: interface_stats_get
	},

	'Device.IP.Interface.{i}.IPv4Address': {
	},

	'Device.IP.Interface.{i}.IPv4Address.{i}': {
		schema: 'IP.Interface_IPv4Address',
		get: ipv4_address_get,
		enable_status_derive: true
	},

	'Device.IP.Interface.{i}.IPv6Address': {
	},

	'Device.IP.Interface.{i}.IPv6Address.{i}': {
		schema: 'IP.Interface_IPv6Address',
		get: ipv6_address_get
	},

	'Device.IP.Interface.{i}.IPv6Prefix': {
	},

	'Device.IP.Interface.{i}.IPv6Prefix.{i}': {
		schema: 'IP.Interface_IPv6Prefix',
		get: ipv6_prefix_get,
		set: ipv6_prefix_set
	},

	'Device.IP.Interface.{i}.X_UBBF_DNSProbe': {
		schema: 'X_UBBF.Interface_X_UBBF_DNSProbe',
		get: dnsprobe_get
	}
};

export const operations = {
	'Device.IP.Interface.{i}.Reset()': {
		type: 'sync',
		handler: interface_reset
	},

	'Device.IP.Interface.{i}.Stats.Reset()': {
		type: 'sync',
		handler: interface_stats_reset
	}
};
