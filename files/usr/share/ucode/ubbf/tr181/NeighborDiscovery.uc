'use strict';

import * as schemas from 'ubbf.schemas.NeighborDiscovery';
import { netifd_status_get } from 'ubbf.utils.netifd';
import * as ubbf from 'ubbf';

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

	let enabled = ubbf.to_bool(ctx.config.Enable);
	if (!enabled)
		return { NUDEnable: 'true', ...ctx.config, Status: 'Disabled' };

	let device = resolve_interface_device(ctx, ctx.config.Interface);
	if (!device)
		return { NUDEnable: 'true', ...ctx.config, Status: 'Error_Misconfigured' };

	return { ...ndp_kernel_get(device), ...ctx.config, Status: 'Enabled' };
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
		schema: schemas.NeighborDiscovery,
		get: neighbor_discovery_get
	},

	'Device.NeighborDiscovery.InterfaceSetting': {
	},

	'Device.NeighborDiscovery.InterfaceSetting.{i}': {
		schema: schemas.InterfaceSetting,
		get: interface_setting_get
	}
};
