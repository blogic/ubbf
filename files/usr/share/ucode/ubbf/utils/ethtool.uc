'use strict';

import { connect } from 'gnl';
import { call as cache_call } from 'ubbf.utils.cache';

let ethtool = connect("ethtool");

// Numeric keys are the kernel ETH_TP_MDI_* values reported by ethtool's
// linkinfo-get response (include/uapi/linux/ethtool.h):
//   0 = ETH_TP_MDI_INVALID, 1 = ETH_TP_MDI, 2 = ETH_TP_MDI_X.
// The current crossover state has no AUTO value, so 0 reports as Unknown.
const MDIX_MAP = {
	[0]: 'Unknown',
	[1]: 'MDI',
	[2]: 'MDIX'
};

// Same encoding for the configured (control) value, plus 3 = ETH_TP_MDI_AUTO.
// Both 0 (INVALID/unset) and 3 (AUTO) map to 'Auto' since TR-181 has no
// "unset" value and an unset control field means the driver autoselects.
const MDIX_CTRL_MAP = {
	[0]: 'Auto',
	[1]: 'MDI',
	[2]: 'MDIX',
	[3]: 'Auto'
};

/**
 * Flattens an ethtool bitset (as returned by ethtool gnl) to the array
 * of named bits it contains. Empty/missing bitsets yield an empty array.
 * With active_only set, only bits carrying the per-bit value flag are
 * returned (for masked bitsets the full list is the mask and the value
 * flag marks the set bits).
 *
 * @param {object} bs - ethtool bitset structure with bits.bit[] entries
 * @param {boolean} active_only - Return only bits with the value flag
 * @returns {array} Array of bit name strings
 */
function bitset_names(bs, active_only) {
	if (!bs)
		return [];

	let bits = bs.bits?.bit ?? [];
	if (active_only)
		bits = filter(bits, b => b.value);
	return map(bits, b => b.name);
}

/**
 * Filters link mode names to exclude non-speed entries.
 *
 * @param {array} modes - Array of mode name strings from bitset_names
 * @returns {string} Comma-separated list of speed modes only
 */
function link_modes_filter(modes) {
	let result = [];

	for (let mode in modes)
		if (match(mode, /base/))
			push(result, mode);

	return join(',', result);
}

/**
 * Issues an ethtool gnl linkmodes-get for the given interface. Returns
 * null when the gnl connection is unavailable so callers can degrade
 * gracefully on systems without ethtool generic-netlink support.
 *
 * @param {string} ifname - Network interface name
 * @returns {object|null} ethtool linkmodes-get response, or null
 */
function ethtool_linkmodes_fetch(ifname) {
	if (!ethtool)
		return null;

	return ethtool.request("linkmodes-get", 0, {
		header: { "dev-name": ifname }
	});
}

/**
 * Issues an ethtool gnl linkinfo-get for the given interface. Returns
 * null when the gnl connection is unavailable so callers can degrade
 * gracefully on systems without ethtool generic-netlink support.
 *
 * @param {string} ifname - Network interface name
 * @returns {object|null} ethtool linkinfo-get response, or null
 */
function ethtool_linkinfo_fetch(ifname) {
	if (!ethtool)
		return null;

	return ethtool.request("linkinfo-get", 0, {
		header: { "dev-name": ifname }
	});
}

/**
 * Gets ethtool link mode properties for an interface.
 *
 * @param {string} ifname - Network interface name
 * @returns {object} Object with SupportedLinkModes, AdvertisedLinkModes,
 *                   LinkPartnerAdvertisedLinkModes, CurrentDuplexMode
 */
export function ethtool_properties_get(ifname) {
	let result = {};

	let modes = ethtool_linkmodes_fetch(ifname);
	if (modes) {
		// the ours bitset carries mask=supported with the value flag
		// marking advertised bits; peer is a no-mask bitset where
		// every listed bit is set (net/ethtool/linkmodes.c)
		let supported = bitset_names(modes.ours);
		let advertised = bitset_names(modes.ours, true);
		let peer = bitset_names(modes.peer);

		result.SupportedLinkModes = link_modes_filter(supported);
		result.AdvertisedLinkModes = link_modes_filter(advertised);
		result.LinkPartnerAdvertisedLinkModes = link_modes_filter(peer);

		// DUPLEX_HALF=0, DUPLEX_FULL=1, DUPLEX_UNKNOWN=255
		if (modes.duplex == 1)
			result.CurrentDuplexMode = 'Full';
		else if (modes.duplex == 0)
			result.CurrentDuplexMode = 'Half';
		else if (modes.duplex != null)
			result.CurrentDuplexMode = 'Unknown';
	}

	let info = ethtool_linkinfo_fetch(ifname);
	if (info) {
		if (info["tp-mdix"] != null)
			result.CurrentMDIX = MDIX_MAP[info["tp-mdix"]] ?? 'Unknown';

		if (info["tp-mdix-ctrl"] != null)
			result.MDIX = MDIX_CTRL_MAP[info["tp-mdix-ctrl"]] ?? 'Auto';
	}

	return result;
};
