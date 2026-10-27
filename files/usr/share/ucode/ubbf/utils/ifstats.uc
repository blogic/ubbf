'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

const ZERO_DIR = {
	packets: 0, bytes: 0, unicast: 0, multicast: 0, broadcast: 0
};

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

// The counters that every TR-181 Stats object declares. Errors and discards
// are not in udevstats and stay at '0'.
function totals_to_basic_stats(totals) {
	return {
		BytesSent: sprintf('%d', totals.tx_bytes),
		BytesReceived: sprintf('%d', totals.rx_bytes),
		PacketsSent: sprintf('%d', totals.tx_packets),
		PacketsReceived: sprintf('%d', totals.rx_packets),
		ErrorsSent: '0',
		ErrorsReceived: '0',
		DiscardPacketsSent: '0',
		DiscardPacketsReceived: '0'
	};
}

// The basic counters plus the packet types that the Stats objects of the
// interface tables declare. Only Ethernet.Interface.Stats adds Collisions.
function totals_to_stats(totals) {
	return {
		...totals_to_basic_stats(totals),
		UnicastPacketsSent: sprintf('%d', totals.tx_unicast),
		UnicastPacketsReceived: sprintf('%d', totals.rx_unicast),
		MulticastPacketsSent: sprintf('%d', totals.tx_multicast),
		MulticastPacketsReceived: sprintf('%d', totals.rx_multicast),
		BroadcastPacketsSent: sprintf('%d', totals.tx_broadcast),
		BroadcastPacketsReceived: sprintf('%d', totals.rx_broadcast),
		UnknownProtoPacketsReceived: '0'
	};
}

/**
 * Returns a TR-181-shaped Stats object for a kernel netdev, with the
 * counters of an interface table such as Ethernet.Link or IP.Interface.
 * Every call issues a fresh ubus request so consecutive reads across
 * bbf-cli invocations see live counter values.
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
 * Returns the basic counters (bytes, packets, errors, discards) of a kernel
 * netdev, for a Stats object without packet types, such as WiFi.Radio or
 * Optical.Interface.
 *
 * @param {string} ifname - kernel netdev name
 * @returns {object}
 */
export function ifstats_basic_get(ifname) {
	let totals = totals_zero();
	totals_accumulate(totals, ifname);
	return totals_to_basic_stats(totals);
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
