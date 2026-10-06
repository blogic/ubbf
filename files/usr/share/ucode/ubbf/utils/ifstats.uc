'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

const ZERO_DIR = {
	packets: 0, bytes: 0, unicast: 0, multicast: 0, broadcast: 0
};

/**
 * Returns a fresh TR-181 Stats object with every field set to '0'.
 *
 * @returns {object}
 */
function stats_zero() {
	return {
		BytesSent: '0',
		BytesReceived: '0',
		PacketsSent: '0',
		PacketsReceived: '0',
		ErrorsSent: '0',
		ErrorsReceived: '0',
		UnicastPacketsSent: '0',
		UnicastPacketsReceived: '0',
		DiscardPacketsSent: '0',
		DiscardPacketsReceived: '0',
		MulticastPacketsSent: '0',
		MulticastPacketsReceived: '0',
		BroadcastPacketsSent: '0',
		BroadcastPacketsReceived: '0',
		Collisions: '0',
		UnknownProtoPacketsReceived: '0'
	};
}

function totals_zero() {
	return {
		rx_bytes: 0, rx_packets: 0, rx_unicast: 0, rx_multicast: 0, rx_broadcast: 0,
		tx_bytes: 0, tx_packets: 0, tx_unicast: 0, tx_multicast: 0, tx_broadcast: 0
	};
}

function totals_accumulate(totals, ifname) {
	if (!ifname)
		return;
	let stats = ubus.call('udevstats', 'get', { device: ifname });
	if (!stats)
		return;
	let rx = stats.rx ?? ZERO_DIR;
	let tx = stats.tx ?? ZERO_DIR;
	totals.rx_bytes     += rx.bytes     ?? 0;
	totals.rx_packets   += rx.packets   ?? 0;
	totals.rx_unicast   += rx.unicast   ?? 0;
	totals.rx_multicast += rx.multicast ?? 0;
	totals.rx_broadcast += rx.broadcast ?? 0;
	totals.tx_bytes     += tx.bytes     ?? 0;
	totals.tx_packets   += tx.packets   ?? 0;
	totals.tx_unicast   += tx.unicast   ?? 0;
	totals.tx_multicast += tx.multicast ?? 0;
	totals.tx_broadcast += tx.broadcast ?? 0;
}

function totals_to_stats(totals) {
	let result = stats_zero();
	result.BytesSent                = sprintf('%d', totals.tx_bytes);
	result.BytesReceived            = sprintf('%d', totals.rx_bytes);
	result.PacketsSent              = sprintf('%d', totals.tx_packets);
	result.PacketsReceived          = sprintf('%d', totals.rx_packets);
	result.UnicastPacketsSent       = sprintf('%d', totals.tx_unicast);
	result.UnicastPacketsReceived   = sprintf('%d', totals.rx_unicast);
	result.MulticastPacketsSent     = sprintf('%d', totals.tx_multicast);
	result.MulticastPacketsReceived = sprintf('%d', totals.rx_multicast);
	result.BroadcastPacketsSent     = sprintf('%d', totals.tx_broadcast);
	result.BroadcastPacketsReceived = sprintf('%d', totals.rx_broadcast);
	return result;
}

/**
 * Returns a TR-181-shaped Stats object for a kernel netdev. Counters not
 * exposed by udevstats (errors, discards, collisions, UnknownProto) stay
 * at '0'. Every call issues a fresh ubus request so consecutive reads
 * across bbf-cli invocations see live counter values.
 *
 * @param {string} ifname - kernel netdev name
 * @returns {object}
 */
export function ifstats_get(ifname) {
	let totals = totals_zero();
	totals_accumulate(totals, ifname);
	return totals_to_stats(totals);
};

/**
 * Returns a TR-181-shaped Stats object summing udevstats across several
 * kernel netdevs, for IP interfaces that front a bridge: the wire-level
 * member ports see packets the L3 sub-device never does (bridged multicast
 * flood, broadcast to clients, etc).
 *
 * @param {array} ifnames - kernel netdev names
 * @returns {object}
 */
export function ifstats_aggregate(ifnames) {
	let totals = totals_zero();
	for (let name in (ifnames ?? []))
		totals_accumulate(totals, name);
	return totals_to_stats(totals);
};

/**
 * Zeros the udevstats counters for a given netdev. Affects every TR-181
 * path that reads stats for this netdev.
 *
 * @param {string} ifname - kernel netdev name
 * @returns {boolean} true when udevstats accepted the request
 */
export function ifstats_reset(ifname) {
	if (!ifname)
		return false;
	let result = ubus.call('udevstats', 'clear', { device: ifname });
	return result != null;
};

/**
 * Resolves the wire-level kernel netdev names backing an
 * IP.Interface.{i}. When the Interface's LowerLayers points at a
 * Bridging.Bridge.{n}.Port.{m}, expand the bridge into all of its
 * non-management enabled ports; otherwise return the single netdev
 * resolved from LowerLayers directly.
 *
 * @param {object} root - Full data model root (ctx.root)
 * @param {object} iface - IP.Interface.{i} instance
 * @returns {array} kernel netdev names
 */
export function ip_interface_members(root, iface) {
	if (!root || !iface?.LowerLayers)
		return [];

	let match_bridge = match(iface.LowerLayers, /^Device\.Bridging\.Bridge\.(\d+)\.Port\.\d+$/);
	if (!match_bridge) {
		let dev = ubbf.lower_layer_resolve(root, iface.LowerLayers);
		return dev ? [dev] : [];
	}

	let members = [];
	let ports = ubbf.instances(root, sprintf('Device.Bridging.Bridge.%s.Port', match_bridge[1]));
	for (let port in ports) {
		if (!port || !ubbf.to_bool(port.Enable))
			continue;
		if (ubbf.to_bool(port.ManagementPort))
			continue;
		// a port's LowerLayers may reference several links (e.g. multiple
		// WiFi SSIDs); lower_layer_resolve only returns the first, so
		// resolve each CSV entry individually
		for (let ref in ubbf.csv_to_list(port.LowerLayers ?? '')) {
			let dev = ubbf.lower_layer_resolve(root, ref);
			if (dev && index(members, dev) < 0)
				push(members, dev);
		}
	}
	return members;
};
