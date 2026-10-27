'use strict';

import * as ubus from 'ubus';
import { ifstats_build } from 'ubbf';

function udevstats_get(ifname) {
	return ifname ? ubus.call('udevstats', 'get', { device: ifname }) : null;
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
	return ifstats_build([ udevstats_get(ifname) ], true);
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
	return ifstats_build([ udevstats_get(ifname) ], false);
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
	return ifstats_build(map(ifnames ?? [], udevstats_get), true);
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
