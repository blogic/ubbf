'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.IP';
import * as schemas_x_ubbf from 'ubbf.schemas.X_UBBF';
import { log_err, log_exception } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { prefix_length_nibble_check } from 'ubbf.utils.dhcp';
import { ifstats_get, ifstats_aggregate, ifstats_reset, ip_interface_members } from 'ubbf.utils.ifstats';
import { link_local_addresses_get, ra_prefixes_get, ra_prefixes_hook_read } from 'ubbf.utils.ipv6';


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
 * Builds the dynamic IPv6 prefix rows for an interface in the exact
 * order the tree read enumerates them: nibble-filtered netifd PD
 * prefixes first, then RA-learned prefixes on upstream interfaces.
 * Both the whole-tree read and per-instance reads index this list so
 * the two views cannot diverge.
 *
 * @param {string} name - IP.Interface Name
 * @param {boolean} upstream - Upstream flag
 * @param {string} l2_dev - L2/L3 device for the kernel RA fallback
 * @returns {array} Array of { data, origin } rows
 */
function ipv6_prefix_rows(name, upstream, l2_dev) {
	let netifd6 = netifd_status_get(upstream ? name + '6' : name);
	let rows = [];

	for (let p in (netifd6?.['ipv6-prefix'] ?? [])) {
		// prpl MVP-2320: only accept delegated prefixes on a nibble
		// boundary. odhcp6c also drops these on the wire; this is the
		// data-model-side check so a stale or non-conforming kernel
		// build does not surface a non-nibble PD via TR-181 either.
		if (!prefix_length_nibble_check(p?.mask)) {
			log_err('IP.Interface %s: dropping non-nibble PD prefix %s/%s',
				name, p?.address ?? '?', p?.mask ?? '?');
			continue;
		}
		push(rows, { data: p, origin: 'PrefixDelegation' });
	}

	if (upstream) {
		let ra_prefixes = ra_prefixes_hook_read(name + '6');
		if (length(ra_prefixes) == 0)
			ra_prefixes = ra_prefixes_get(l2_dev);
		for (let rp in ra_prefixes)
			push(rows, { data: rp, origin: 'RouterAdvertisement' });
	}

	return rows;
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

	let name = ctx.config.Name;
	let netifd = netifd_status_get(name);
	let upstream = ubbf.to_bool(ctx.config.Upstream);
	let netifd6 = upstream ? netifd_status_get(name + '6') : netifd;

	let ipv4_addrs = netifd?.['ipv4-address'] ?? [];
	let ipv6_addrs = netifd6?.['ipv6-address'] ?? [];

	let l2_dev = netifd?.l3_device ?? netifd?.device;
	let result = {
		...ctx.config,
		Status: netifd?.up ? 'Up' : 'Down',
		LastChange: last_change_get(l2_dev)
	};

	let config_ipv4 = ctx.config.IPv4Address ?? {};
	let ipv4_objects = [];
	for (let i = 0; i < length(ipv4_addrs); i++)
		push(ipv4_objects, ubbf.ipv4_addr_to_object(ipv4_addrs[i], config_ipv4?.['' + (i + 1)]?.AddressingType));
	if (length(ipv4_objects) > 0)
		result.IPv4Address = ubbf.enumerate_instances(ipv4_objects, (obj) => obj);
	result.IPv4AddressNumberOfEntries = sprintf('%d',
		result.IPv4Address ? length(keys(result.IPv4Address)) : 0);

	// TR-181 IPv6Address holds both directly-assigned addresses and
	// addresses derived from local prefix assignments (PD). Merge both
	// netifd lists into one TR-181 instance space; ipv6_idx is the
	// running TR-181 instance counter across both sources.
	let config_ipv6 = ctx.config.IPv6Address ?? {};
	let all_ipv6 = [];
	let ipv6_idx = 0;
	for (let a in ipv6_addrs) {
		ipv6_idx++;
		push(all_ipv6, ubbf.ipv6_addr_to_object(a, config_ipv6?.['' + ipv6_idx]?.Origin ?? 'DHCPv6'));
	}

	let prefix_assignments = netifd6?.['ipv6-prefix-assignment'] ?? [];
	for (let pa in prefix_assignments) {
		// netifd always emits the local-address table and only fills
		// address/mask when the assignment is enabled
		if (!pa?.['local-address']?.address)
			continue;
		ipv6_idx++;
		let has_lifetime = (pa.preferred != null) || (pa.valid != null);
		let addr_obj = {
			address: pa['local-address'].address,
			mask: pa['local-address'].mask,
			preferred: pa.preferred ?? 0,
			valid: pa.valid ?? 0
		};
		// PA rows with RA/PD-sourced lifetimes are Child (auto-configured from
		// a delegated parent prefix); PA rows without lifetimes come from a
		// locally-configured prefix (e.g. ULA) and are Static per TR-181.
		let default_origin = has_lifetime ? 'Child' : 'Static';
		let origin = config_ipv6?.['' + ipv6_idx]?.Origin ?? default_origin;
		push(all_ipv6, ubbf.ipv6_addr_to_object(addr_obj, origin, !has_lifetime));
	}

	// Kernel-assigned link-local addresses have no RA/DHCPv6 lifetime;
	// pull them directly via rtnl on the L2 device and mark permanent.
	for (let ll in link_local_addresses_get(l2_dev)) {
		ipv6_idx++;
		push(all_ipv6, ubbf.ipv6_addr_to_object(ll, config_ipv6?.['' + ipv6_idx]?.Origin ?? 'AutoConfigured', true));
	}

	if (length(all_ipv6) > 0)
		result.IPv6Address = ubbf.enumerate_instances(all_ipv6, (obj) => obj);
	result.IPv6AddressNumberOfEntries = sprintf('%d',
		result.IPv6Address ? length(keys(result.IPv6Address)) : 0);

	// Upstream interfaces combine two prefix sources: netifd's ipv6-prefix
	// (the DHCPv6-PD grant) and RA-learned PIOs. RA PIOs come from the
	// odhcp6c.user.d hook state file when present (our stack runs
	// accept_ra=0 so the kernel FIB has no RTPROT_RA routes); fall back
	// to the kernel FIB for setups where the kernel does process RAs.
	let all_prefixes = ipv6_prefix_rows(name, upstream, l2_dev);

	if (length(all_prefixes) > 0)
		result.IPv6Prefix = ubbf.enumerate_instances(all_prefixes,
			(item) => ubbf.ipv6_prefix_to_object(item.data, item.origin));
	result.IPv6PrefixNumberOfEntries = sprintf('%d',
		result.IPv6Prefix ? length(keys(result.IPv6Prefix)) : 0);

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

	let name = ctx.parent?.Name;
	let netifd = netifd_status_get(name);
	let addrs = netifd?.['ipv4-address'] ?? [];
	let addr_data = addrs[ctx.instance - 1];

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

	let name = ctx.parent?.Name;
	let upstream = ubbf.to_bool(ctx.parent?.Upstream);
	let netifd = netifd_status_get(upstream ? name + '6' : name);
	let base_netifd = upstream ? netifd_status_get(name) : netifd;
	let l2_dev = base_netifd?.l3_device ?? base_netifd?.device;

	let addrs = netifd?.['ipv6-address'] ?? [];
	// same filter as interface_get(): netifd always emits the
	// local-address table, address is only present when enabled
	let prefixes = filter(netifd?.['ipv6-prefix-assignment'] ?? [],
		(pa) => pa?.['local-address']?.address);
	let addr_data = addrs[ctx.instance - 1];

	// interface_get() merges netifd ipv6-address, ipv6-prefix-assignment
	// local-addresses, and rtnl-derived link-local into one TR-181
	// IPv6Address instance space. Mirror that ordering for per-instance reads.
	// For prefix-assignment rows the lifetimes live on the parent object, not
	// the local-address sub-object: lift them before emitting.
	if (!addr_data) {
		let prefix_data = prefixes[ctx.instance - 1 - length(addrs)];
		if (prefix_data?.['local-address']) {
			let has_lifetime = (prefix_data.preferred != null) ||
					   (prefix_data.valid != null);
			if (has_lifetime) {
				return {
					...ctx.config,
					Status: status,
					IPAddressStatus: ubbf.ipv6_lifetime_status({
						preferred: prefix_data.preferred ?? 0,
						valid: prefix_data.valid ?? 0
					}),
					IPAddress: prefix_data['local-address'].address ?? '',
					PreferredLifetime: sprintf('%d', prefix_data.preferred ?? 0),
					ValidLifetime: sprintf('%d', prefix_data.valid ?? 0)
				};
			}
			return {
				...ctx.config,
				Status: status,
				IPAddressStatus: 'Preferred',
				IPAddress: prefix_data['local-address'].address ?? '',
				PreferredLifetime: '9999-12-31T23:59:59Z',
				ValidLifetime: '9999-12-31T23:59:59Z'
			};
		}
	}

	if (!addr_data) {
		let link_locals = link_local_addresses_get(l2_dev);
		let ll = link_locals[ctx.instance - 1 - length(addrs) - length(prefixes)];
		if (ll) {
			return {
				...ctx.config,
				Status: status,
				IPAddressStatus: 'Preferred',
				IPAddress: ll.address ?? '',
				PreferredLifetime: '9999-12-31T23:59:59Z',
				ValidLifetime: '9999-12-31T23:59:59Z'
			};
		}
	}

	if (addr_data) {
		return {
			...ctx.config,
			Status: status,
			IPAddressStatus: ubbf.ipv6_lifetime_status(addr_data),
			IPAddress: addr_data.address ?? '',
			PreferredLifetime: sprintf('%d', addr_data.preferred ?? 0),
			ValidLifetime: sprintf('%d', addr_data.valid ?? 0)
		};
	}

	return { ...ctx.config, Status: status, IPAddressStatus: 'Invalid' };
}

/**
 * Get handler for Device.IP.Interface.{i}.IPv6Prefix.{i}.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object|null} IPv6 prefix properties
 */
function ipv6_prefix_get(ctx) {
	let name = ctx.parent?.Name;
	let upstream = ubbf.to_bool(ctx.parent?.Upstream);

	if (!ctx.config) {
		if (!upstream)
			return null;
		let base = netifd_status_get(name);
		let l2_dev = base?.l3_device ?? base?.device;
		let row = ipv6_prefix_rows(name, upstream, l2_dev)[ctx.instance - 1];
		if (!row)
			return null;
		return ubbf.ipv6_prefix_to_object(row.data, row.origin);
	}

	let netifd = netifd_status_get(upstream ? name + '6' : name);
	// On upstream (WAN) interfaces netifd reports prefixes received via
	// DHCPv6-PD or RA in ipv6-prefix; on downstream (LAN) interfaces it
	// reports the locally-derived sub-prefixes in ipv6-prefix-assignment.
	let prefix_key = upstream ? 'ipv6-prefix' : 'ipv6-prefix-assignment';
	let prefixes = netifd?.[prefix_key] ?? [];
	let prefix_data = prefixes[ctx.instance - 1];

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = enabled ? 'Enabled' : 'Disabled';
	// Origin is read-only per TR-181: PrefixDelegation/RouterAdvertisement
	// can only appear on upstream interfaces; on downstream interfaces a
	// row carrying a ParentPrefix reference is a Child prefix derived from
	// the upstream parent, and rows without ParentPrefix default to Static.
	let origin = ctx.config.ParentPrefix ? 'Child' : 'Static';

	if (prefix_data && origin != 'Static') {
		let prefix_str = sprintf('%s/%d', prefix_data.address ?? '', prefix_data.mask ?? 0);
		return {
			...ctx.config,
			Origin: origin,
			Status: status,
			PrefixStatus: ubbf.ipv6_lifetime_status(prefix_data),
			Prefix: prefix_str,
			PreferredLifetime: sprintf('%d', prefix_data.preferred ?? 0),
			ValidLifetime: sprintf('%d', prefix_data.valid ?? 0)
		};
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
		schema: schemas.IP,
		get: ip_get
	},

	'Device.IP.Interface': {
	},

	'Device.IP.Interface.{i}': {
		schema: schemas.Interface,
		get: interface_get,
		set: interface_set,
		name: interface_name,
		firewall: interface_firewall
	},

	'Device.IP.Interface.{i}.Stats': {
		schema: schemas.Interface_Stats,
		get: interface_stats_get
	},

	'Device.IP.Interface.{i}.IPv4Address': {
	},

	'Device.IP.Interface.{i}.IPv4Address.{i}': {
		schema: schemas.Interface_IPv4Address,
		get: ipv4_address_get,
		enable_status_derive: true
	},

	'Device.IP.Interface.{i}.IPv6Address': {
	},

	'Device.IP.Interface.{i}.IPv6Address.{i}': {
		schema: schemas.Interface_IPv6Address,
		get: ipv6_address_get
	},

	'Device.IP.Interface.{i}.IPv6Prefix': {
	},

	'Device.IP.Interface.{i}.IPv6Prefix.{i}': {
		schema: schemas.Interface_IPv6Prefix,
		get: ipv6_prefix_get,
		set: ipv6_prefix_set
	},

	'Device.IP.Interface.{i}.X_UBBF_DNSProbe': {
		schema: schemas_x_ubbf.Interface_X_UBBF_DNSProbe,
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
