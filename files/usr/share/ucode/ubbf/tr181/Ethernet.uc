'use strict';

import * as schemas from 'ubbf.schemas.Ethernet';
import * as ubbf from 'ubbf';
import { vlan_termination_bridge_resolve, lower_layer_resolve_vlan } from 'ubbf.render.ubbf_helpers';
import { ethtool_properties_get } from 'ubbf.utils.ethtool';
import { ifop_status_derive } from 'ubbf.utils.status';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';

/**
 * Get handler for Device.Ethernet.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Ethernet container properties with instance counts
 */
function ethernet_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Interface)),
		LinkNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Link)),
		VLANTerminationNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.VLANTermination)),
		RMONStatsNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.RMONStats))
	};
}

/**
 * Get handler for Device.Ethernet.Interface.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Ethernet interface properties
 */
function interface_get(ctx) {
	if (!ctx.config || !ctx.config.Name)
		return null;

	let props = ubbf.ethernet_properties_get(ctx.config.Name);
	let ethtool = ethtool_properties_get(ctx.config.Name);

	return {
		...ctx.config,
		...props,
		...ethtool,
		Enable: ctx.config.Enable,
		Status: ifop_status_derive(ctx.config.Enable, ctx.config.Name, null, null),
		LastChange: last_change_get(ctx.config.Name)
	};
}

/**
 * Get handler for Device.Ethernet.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} Interface statistics
 */
function interface_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	return ifstats_get(parent.Name);
}

/**
 * Get handler for Device.Ethernet.Link.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Ethernet link properties
 */
function link_get(ctx) {
	if (!ctx.config || !ctx.config.Name)
		return null;

	let ifname = ctx.config.Name;
	let props = ubbf.link_properties_get(ifname);

	return {
		...ctx.config,
		...props,
		Status: ifop_status_derive(ctx.config.Enable, ifname,
		                           ctx.config.LowerLayers, ctx.root),
		LastChange: last_change_get(ifname)
	};
}

/**
 * Get handler for Device.Ethernet.Link.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} Link statistics with pause counters
 */
function link_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	return {
		...ifstats_get(parent.Name),
		PausePacketsSent: '0',
		PausePacketsReceived: '0'
	};
}

/**
 * Get handler for Device.Ethernet.VLANTermination.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} VLAN termination properties with status
 */
function vlan_termination_get(ctx) {
	if (!ctx.config || !ctx.config.Name)
		return null;

	return {
		...ctx.config,
		Status: ifop_status_derive(ctx.config.Enable, ctx.config.Name,
		                           ctx.config.LowerLayers, ctx.root),
		LastChange: last_change_get(ctx.config.Name)
	};
}

/**
 * Get handler for Device.Ethernet.VLANTermination.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} VLAN termination statistics
 */
function vlan_termination_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	return ifstats_get(parent.Name);
}

/**
 * Get handler for Device.Ethernet.RMONStats.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} RMON statistics (stub implementation)
 */
function rmon_stats_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...ctx.config,
		DropEvents: '0',
		Bytes: '0',
		Packets: '0',
		BroadcastPackets: '0',
		MulticastPackets: '0',
		CRCErroredPackets: '0',
		UndersizePackets: '0',
		OversizePackets: '0',
		Packets64Bytes: '0',
		Packets65to127Bytes: '0',
		Packets128to255Bytes: '0',
		Packets256to511Bytes: '0',
		Packets512to1023Bytes: '0',
		Packets1024to1518Bytes: '0'
	};
}

/**
 * Name callback for Device.Ethernet.VLANTermination.{i}.
 *
 * When the lower layer is in a VLAN-filtered bridge, the name
 * uses bridge-vlan convention (<bridge>v<vid>); otherwise it
 * uses the standard Linux VLAN naming (<ifname>.<vid>).
 *
 * @param {object} inst - Instance data
 * @param {object} root - Root config data
 * @returns {string|null} Computed device name
 */
function vlan_termination_name(inst, root) {
	let vid = int(inst.VLANID);
	if (!vid)
		return null;

	let bridge_info = vlan_termination_bridge_resolve(root, inst.LowerLayers);
	if (bridge_info)
		return `${bridge_info.bridge_name}v${vid}`;

	let ifname = ubbf.lower_layer_resolve(root, inst.LowerLayers);
	if (!ifname)
		return null;
	return `${ifname}.${vid}`;
}

/**
 * Sync operation handler for Ethernet.Interface.{i}.Stats.Reset().
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

	let iface = root?.Device?.Ethernet?.Interface?.['' + idx];
	if (!iface?.Name)
		return null;

	if (!ifstats_reset(iface.Name))
		return null;
	return {};
}

/**
 * Sync operation handler for Ethernet.Link.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function link_stats_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let link = root?.Device?.Ethernet?.Link?.['' + idx];
	if (!link?.Name)
		return null;

	if (!ifstats_reset(link.Name))
		return null;
	return {};
}

/**
 * Sync operation handler for Ethernet.VLANTermination.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function vlan_stats_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let vlan = root?.Device?.Ethernet?.VLANTermination?.['' + idx];
	if (!vlan?.Name)
		return null;

	if (!ifstats_reset(vlan.Name))
		return null;
	return {};
}

/**
 * Picks a LAN interface device for issuing a Wake-on-LAN packet.
 *
 * Iterates IP interfaces and returns the first non-Upstream device,
 * falling back to br-lan when none match.
 *
 * @param {object} root - Root configuration object
 * @returns {string} LAN device name for the WoL magic-packet send
 */
function wol_resolve_lan_device(root) {
	let ip_ifaces = root?.Device?.IP?.Interface;
	if (!ip_ifaces)
		return 'br-lan';

	for (let inst, iface in ip_ifaces) {
		if (ubbf.to_bool(iface.Upstream))
			continue;

		let dev = lower_layer_resolve_vlan(root, iface.LowerLayers);
		if (dev)
			return dev;
	}

	return 'br-lan';
}

/**
 * Handles Device.Ethernet.WoL.SendMagicPacket() operation.
 *
 * The container-scope SendMagicPacket dispatcher passes the root
 * configuration as the third argument (no instance list) because
 * WoL has no per-instance context.
 *
 * @param {object} input - Operation input with MACAddress and optional Password
 * @param {string} command_key - Command key (unused)
 * @param {object} root - Root configuration object
 * @returns {object|null} Empty result on success, null on failure
 */
function wol_send_magic_packet(input, command_key, root) {
	let mac = input.MACAddress;
	if (!ubbf.mac_is_valid(mac))
		return null;

	let iface = wol_resolve_lan_device(root);

	return ubbf.wol_send(iface, mac, input.Password) ? {} : null;
}

export const model = {
	'Device.Ethernet': {
		schema: schemas.Ethernet,
		get: ethernet_get
	},

	'Device.Ethernet.WoL': {
		schema: schemas.WoL
	},

	'Device.Ethernet.Interface': {
	},

	'Device.Ethernet.Interface.{i}': {
		schema: schemas.Interface,
		get: interface_get
	},

	'Device.Ethernet.Interface.{i}.Stats': {
		schema: schemas.Interface_Stats,
		get: interface_stats_get
	},

	'Device.Ethernet.Link': {
	},

	'Device.Ethernet.Link.{i}': {
		schema: schemas.Link,
		get: link_get
	},

	'Device.Ethernet.Link.{i}.Stats': {
		schema: schemas.Link_Stats,
		get: link_stats_get
	},

	'Device.Ethernet.VLANTermination': {
	},

	'Device.Ethernet.VLANTermination.{i}': {
		schema: schemas.VLANTermination,
		get: vlan_termination_get,
		name: vlan_termination_name
	},

	'Device.Ethernet.VLANTermination.{i}.Stats': {
		schema: schemas.VLANTermination_Stats,
		get: vlan_termination_stats_get
	},

	'Device.Ethernet.RMONStats': {
	},

	'Device.Ethernet.RMONStats.{i}': {
		schema: schemas.RMONStats,
		get: rmon_stats_get,
		enable_status_derive: true
	}
};

export const operations = {
	'Device.Ethernet.Interface.{i}.Stats.Reset()': {
		type: 'sync',
		handler: interface_stats_reset
	},

	'Device.Ethernet.Link.{i}.Stats.Reset()': {
		type: 'sync',
		handler: link_stats_reset
	},

	'Device.Ethernet.VLANTermination.{i}.Stats.Reset()': {
		type: 'sync',
		handler: vlan_stats_reset
	},

	'Device.Ethernet.WoL.SendMagicPacket()': {
		type: 'sync',
		handler: wol_send_magic_packet
	}
};
