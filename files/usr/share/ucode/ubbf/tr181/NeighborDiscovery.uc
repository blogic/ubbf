'use strict';

import * as fs from 'fs';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

// The parameters of NeighborDiscovery.InterfaceSetting.{i} that TR-181 2.21
// deprecates for the same ones in InterfaceSetting.{i}.NDP; both name one
// setting, so a write to either name stores the value under both.
const NDP_SHARED = [
	'DADTransmits', 'RetransTimer', 'RtrSolicitationInterval',
	'MaxRtrSolicitations', 'NUDEnable', 'RSEnable'
];

/**
 * Resolves an interface reference to its underlying network device name.
 *
 * @param {object} ctx - Handler context with root config
 * @param {string} iface_ref - Interface path reference
 * @returns {string|null} Device name or null if not found
 */
function resolve_interface_device(ctx, iface_ref) {
	if (!iface_ref)
		return null;

	let iface = ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref));
	if (!iface?.Name)
		return null;

	let netifd = netifd_status_get(iface.Name);
	let device = netifd?.l3_device ?? netifd?.device;

	return device ?? iface.Name;
}

/**
 * Reads the NDP tunables of a netdev from the kernel sysctls; netifd device
 * status does not expose them.
 *
 * @param {string} device - Netdev name
 * @returns {object} TR-181 parameters for the values that could be read
 */
function ndp_kernel_get(device) {
	let out = {};

	let dad = ubbf.readfile_int(`/proc/sys/net/ipv6/conf/${device}/dad_transmits`, -1);
	if (dad >= 0)
		out.DADTransmits = sprintf('%d', dad);

	// retrans_time_ms is already in the milliseconds TR-181 wants
	let retrans = ubbf.readfile_int(`/proc/sys/net/ipv6/neigh/${device}/retrans_time_ms`, -1);
	if (retrans >= 0)
		out.RetransTimer = sprintf('%d', retrans);

	let rs_interval = ubbf.readfile_int(`/proc/sys/net/ipv6/conf/${device}/router_solicitation_interval`, -1);
	if (rs_interval >= 0)
		out.RtrSolicitationInterval = sprintf('%d', rs_interval * 1000);

	// router_solicitations: -1 means unlimited; -2 marks a failed read
	let rs_count = ubbf.readfile_int(`/proc/sys/net/ipv6/conf/${device}/router_solicitations`, -2);
	if (rs_count != -2) {
		out.MaxRtrSolicitations = sprintf('%d', rs_count < 0 ? 0 : rs_count);
		out.RSEnable = rs_count != 0 ? 'true' : 'false';
	}

	let mcast_sol = ubbf.readfile_int(`/proc/sys/net/ipv6/neigh/${device}/mcast_solicit`, 3);
	out.NUDEnable = mcast_sol > 0 ? 'true' : 'false';

	return out;
}

/**
 * Returns the shared NDP values of a row: an NDP value wins over the
 * deprecated one of the row.
 *
 * @param {object} row - InterfaceSetting row
 * @returns {object} Stored shared values
 */
function ndp_shared_get(row) {
	let out = {};

	for (let name in NDP_SHARED) {
		let v = row?.NDP?.[name] ?? row?.[name];
		if (v != null)
			out[name] = v;
	}

	return out;
}

/**
 * Reads the ARP settings of a netdev from the kernel.
 *
 * @param {string} device - Netdev name
 * @returns {object} TR-181 ARP parameters for the values that could be read
 */
function arp_kernel_get(device) {
	let out = {};
	let neigh = `/proc/sys/net/ipv4/neigh/${device}`;

	let reach = ubbf.readfile_int(`${neigh}/base_reachable_time_ms`, -1);
	if (reach >= 0)
		out.BaseReachableTime = sprintf('%d', reach);

	let retries = ubbf.readfile_int(`${neigh}/mcast_solicit`, -1);
	if (retries >= 0)
		out.MaxRetries = sprintf('%d', retries);

	let retrans = ubbf.readfile_int(`${neigh}/retrans_time_ms`, -1);
	if (retrans >= 0)
		out.RetryInterval = sprintf('%d', retrans);

	let proxy = ubbf.readfile_int(`/proc/sys/net/ipv4/conf/${device}/proxy_arp`, -1);
	if (proxy >= 0)
		out.ProxyARPEnable = proxy ? 'true' : 'false';

	// IFF_NOARP is 0x80 in the flags of the netdev
	let flags = hex(trim(fs.readfile(`/sys/class/net/${device}/flags`) ?? ''));
	if (type(flags) == 'int')
		out.Enable = (flags & 0x80) ? 'false' : 'true';

	return out;
}

/**
 * Get handler for Device.NeighborDiscovery.InterfaceSetting.{i}.ARP.
 *
 * @param {object} ctx - Context with the ARP config and the row as parent
 * @returns {object} ARP parameters with Status
 */
function arp_get(ctx) {
	let row = ctx.parent ?? {};
	let stored = { ...ubbf.schema_defaults('NeighborDiscovery.InterfaceSetting_ARP'), ...(ctx.config ?? {}) };

	if (!ubbf.to_bool(row.Enable) || stored.Enable == 'false')
		return { ...stored, Status: 'Disabled' };

	let iface = row.Interface ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(row.Interface)) : null;
	let device = resolve_interface_device(ctx, row.Interface);
	if (!device || iface?.IPv4Enable == 'false')
		return { ...stored, Status: 'Error_Misconfigured' };

	return { ...stored, ...arp_kernel_get(device), ...(ctx.config ?? {}), Status: 'Enabled' };
}

/**
 * Get handler for Device.NeighborDiscovery.InterfaceSetting.{i}.NDP.
 *
 * DADTransmits, RetransTimer and BaseReachableTime fall back to the kernel
 * values. The Router Solicitation values have none to read: odhcp6c sends
 * the solicitations of a DHCPv6 client interface.
 *
 * @param {object} ctx - Context with the NDP config and the row as parent
 * @returns {object} NDP parameters with Status
 */
function ndp_get(ctx) {
	let row = ctx.parent ?? {};
	let defaults = ubbf.schema_defaults('NeighborDiscovery.InterfaceSetting_NDP');
	let stored = { ...(ctx.config ?? {}), ...ndp_shared_get(row) };

	if (!ubbf.to_bool(row.Enable))
		return { ...defaults, ...stored, Status: 'Disabled' };

	let device = resolve_interface_device(ctx, row.Interface);
	if (!device || ubbf.readfile_int(`/proc/sys/net/ipv6/conf/${device}/disable_ipv6`, 1) != 0)
		return { ...defaults, ...stored, Status: 'Error_Misconfigured' };

	let kernel = {};
	let k = ndp_kernel_get(device);
	for (let name in [ 'DADTransmits', 'RetransTimer' ])
		if (k[name] != null)
			kernel[name] = k[name];

	let reach = ubbf.readfile_int(`/proc/sys/net/ipv6/neigh/${device}/base_reachable_time_ms`, -1);
	if (reach >= 0)
		kernel.BaseReachableTime = sprintf('%d', reach);

	return { ...defaults, ...kernel, ...stored, Status: 'Enabled' };
}

/**
 * Set handler for Device.NeighborDiscovery.InterfaceSetting.{i}.NDP.
 *
 * Linux has no switch for neighbour discovery alone or for Neighbor
 * Unreachability Detection, so both stay on. A shared parameter is stored
 * under its deprecated name in the row too.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or -1 to refuse the value
 */
function ndp_set(ctx) {
	if ((ctx.param == 'Enable' || ctx.param == 'NUDEnable') && !ubbf.to_bool(ctx.value)) {
		log_err('NeighborDiscovery NDP.%s false is not supported by Linux', ctx.param);
		return -1;
	}

	if (index(NDP_SHARED, ctx.param) < 0)
		return 0;

	let row = ctx.root?.Device?.NeighborDiscovery?.InterfaceSetting?.[sprintf('%d', ctx.instance)];
	if (type(row) == 'object')
		row[ctx.param] = ctx.value;

	return 0;
}

/**
 * Set handler for Device.NeighborDiscovery.InterfaceSetting.{i}: a shared
 * parameter is stored under its InterfaceSetting.{i}.NDP name too.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0
 */
function interface_setting_set(ctx) {
	if (index(NDP_SHARED, ctx.param) >= 0 && type(ctx.config?.NDP) == 'object')
		ctx.config.NDP[ctx.param] = ctx.value;

	return 0;
}

/**
 * Gets NeighborDiscovery interface setting with computed status and NDP parameters.
 *
 * The NDP parameters are writable, so a configured value reads back as
 * written; netifd applies it to the kernel some seconds after the commit.
 * The kernel value fills only parameters the configuration does not hold.
 *
 * @param {object} ctx - Handler context with config and root
 * @returns {object} Interface setting with status and NDP configuration
 */
function interface_setting_get(ctx) {
	if (!ctx.config)
		return null;

	let row = { ...ctx.config, ...ndp_shared_get(ctx.config) };

	let enabled = ubbf.to_bool(ctx.config.Enable);
	if (!enabled)
		return { NUDEnable: 'true', ...row, Status: 'Disabled' };

	let device = resolve_interface_device(ctx, ctx.config.Interface);
	if (!device)
		return { NUDEnable: 'true', ...row, Status: 'Error_Misconfigured' };

	return { ...ndp_kernel_get(device), ...row, Status: 'Enabled' };
}

/**
 * Get handler for Device.NeighborDiscovery.
 *
 * @param {object} ctx - Context with config
 * @returns {object} NeighborDiscovery properties with instance counts
 */
function neighbor_discovery_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
	};
}

export const model = {
	'Device.NeighborDiscovery': {
		schema: 'NeighborDiscovery.NeighborDiscovery',
		get: neighbor_discovery_get
	},

	'Device.NeighborDiscovery.InterfaceSetting': {
	},

	'Device.NeighborDiscovery.InterfaceSetting.{i}': {
		schema: 'NeighborDiscovery.InterfaceSetting',
		get: interface_setting_get,
		set: interface_setting_set
	},

	'Device.NeighborDiscovery.InterfaceSetting.{i}.ARP': {
		schema: 'NeighborDiscovery.InterfaceSetting_ARP',
		get: arp_get,
		since: '2.21'
	},

	'Device.NeighborDiscovery.InterfaceSetting.{i}.NDP': {
		schema: 'NeighborDiscovery.InterfaceSetting_NDP',
		get: ndp_get,
		set: ndp_set,
		since: '2.21'
	}
};
