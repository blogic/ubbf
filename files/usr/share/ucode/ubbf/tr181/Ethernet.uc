'use strict';

import * as ubbf from 'ubbf';
import { vlan_termination_bridge_resolve } from 'ubbf.render.ubbf_helpers';
import { ethtool_properties_get, ethtool_stats_get } from 'ubbf.utils.ethtool';
import { ifop_status_derive } from 'ubbf.utils.status';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';
import { modules_registered } from 'ubbf.utils.modules';

/**
 * Get handler for Device.Ethernet.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Ethernet container properties with instance counts
 */
function ethernet_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		WoLSupported: modules_registered.wol ? 'true' : 'false',
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

	return {
		...ifstats_get(parent.Name),
		Collisions: '0'
	};
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

// ETHTOOL_A_STATS_ETH_MAC_* and ETHTOOL_A_STATS_RMON_* indexes
// (include/uapi/linux/ethtool_netlink.h)
const MAC_RX_PKT = '3';
const MAC_FCS_ERR = '4';
const MAC_ALIGN_ERR = '5';
const MAC_RX_BYTES = '12';
const MAC_RX_MCAST = '17';
const MAC_RX_BCAST = '18';
const RMON_UNDERSIZE = '0';
const RMON_OVERSIZE = '1';
const RMON_FRAG = '2';
const RMON_JABBER = '3';

function counter_sum(...values) {
	let sum = null;

	for (let v in values)
		if (v != null)
			sum = (sum ?? 0) + v;

	return sum;
}

function counter_less(value, ...known) {
	if (value == null)
		return null;

	let rest = value - (counter_sum(...known) ?? 0);

	return (rest > 0) ? rest : 0;
}

/**
 * The packets of an RFC 2819 length bucket from the receive histogram of
 * the driver. A driver bucket may be wider: 0..64 also counts the frames
 * below 64 bytes, which RFC 2819 counts as undersize packets or fragments,
 * and a bucket from 1024 up to the MTU also counts the oversize packets
 * and the jabbers above 1518 bytes.
 */
function rmon_bucket(stats, low, high) {
	for (let b in stats.hist_rx) {
		if (b.high == high && b.low == low)
			return b.value;

		if (low == 64 && high == 64 && b.high == 64 && b.low < 64)
			return counter_less(b.value, stats.rmon[RMON_UNDERSIZE], stats.rmon[RMON_FRAG]);

		if (high == 1518 && b.low == low && b.high > high)
			return counter_less(b.value, stats.rmon[RMON_OVERSIZE], stats.rmon[RMON_JABBER]);
	}

	return null;
}

function counter_string(value, uint32) {
	if (value == null)
		return '0';

	return uint32 ? sprintf('%d', value & 0xffffffff) : `${value}`;
}

/**
 * Get handler for Device.Ethernet.RMONStats.{i}. The counters are the
 * receive counters of RFC 2819 etherStats, read from the IEEE 802.3 MAC
 * and the RMON statistics of the driver (ethtool stats-get). The driver
 * counts the whole port, so a row that filters on a VLAN or a queue
 * reports Error. A counter that the driver does not provide reads 0;
 * DropEvents has no counter in the driver statistics.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} RMON statistics
 */
function rmon_stats_get(ctx) {
	let cfg = ctx.config;
	if (!cfg)
		return null;

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	let iface = cfg.Interface ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(cfg.Interface)) : null;
	if (!iface?.Name)
		return { ...cfg, Status: 'Error_Misconfigured' };

	if (ubbf.to_int(cfg.VLANID) || (cfg.Queue && !ubbf.to_bool(cfg.AllQueues)))
		return { ...cfg, Name: iface.Name, Status: 'Error' };

	let stats = ethtool_stats_get(iface.Name);
	if (!stats || (!length(stats.mac) && !length(stats.rmon)))
		return { ...cfg, Name: iface.Name, Status: 'Error' };

	let mac = stats.mac, rmon = stats.rmon;
	let hist_total = length(stats.hist_rx) ? counter_sum(...map(stats.hist_rx, (b) => b.value)) : null;

	return {
		...cfg,
		Name: iface.Name,
		Status: 'Enabled',
		Bytes: counter_string(mac[MAC_RX_BYTES]),
		Packets: counter_string(hist_total ?? counter_sum(mac[MAC_RX_PKT], mac[MAC_FCS_ERR], mac[MAC_ALIGN_ERR])),
		BroadcastPackets: counter_string(mac[MAC_RX_BCAST]),
		MulticastPackets: counter_string(mac[MAC_RX_MCAST]),
		CRCErroredPackets: counter_string(counter_sum(mac[MAC_FCS_ERR], mac[MAC_ALIGN_ERR]), true),
		UndersizePackets: counter_string(rmon[RMON_UNDERSIZE], true),
		OversizePackets: counter_string(rmon[RMON_OVERSIZE], true),
		Packets64Bytes: counter_string(rmon_bucket(stats, 64, 64)),
		Packets65to127Bytes: counter_string(rmon_bucket(stats, 65, 127)),
		Packets128to255Bytes: counter_string(rmon_bucket(stats, 128, 255)),
		Packets256to511Bytes: counter_string(rmon_bucket(stats, 256, 511)),
		Packets512to1023Bytes: counter_string(rmon_bucket(stats, 512, 1023)),
		Packets1024to1518Bytes: counter_string(rmon_bucket(stats, 1024, 1518))
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

export const model = {
	'Device.Ethernet': {
		schema: 'Ethernet.Ethernet',
		get: ethernet_get
	},

	'Device.Ethernet.Interface': {
	},

	'Device.Ethernet.Interface.{i}': {
		schema: 'Ethernet.Interface',
		get: interface_get
	},

	'Device.Ethernet.Interface.{i}.Stats': {
		schema: 'Ethernet.Interface_Stats',
		get: interface_stats_get
	},

	'Device.Ethernet.Link': {
	},

	'Device.Ethernet.Link.{i}': {
		schema: 'Ethernet.Link',
		get: link_get
	},

	'Device.Ethernet.Link.{i}.Stats': {
		schema: 'Ethernet.Link_Stats',
		get: link_stats_get
	},

	'Device.Ethernet.VLANTermination': {
	},

	'Device.Ethernet.VLANTermination.{i}': {
		schema: 'Ethernet.VLANTermination',
		get: vlan_termination_get,
		name: vlan_termination_name
	},

	'Device.Ethernet.VLANTermination.{i}.Stats': {
		schema: 'Ethernet.VLANTermination_Stats',
		get: vlan_termination_stats_get
	},

	'Device.Ethernet.RMONStats': {
	},

	'Device.Ethernet.RMONStats.{i}': {
		schema: 'Ethernet.RMONStats',
		get: rmon_stats_get
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
	}
};
