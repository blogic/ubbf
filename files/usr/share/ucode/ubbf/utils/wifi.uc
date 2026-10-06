'use strict';

import * as iwinfo from 'iwinfo';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { call as cache_call } from 'ubbf.utils.cache';
import { log_exception } from 'ubbf.utils.logging';

/**
 * Fetches wireless status from network.wireless ubus (uncached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
function wireless_status_fetch() {
	return ubus?.call('network.wireless', 'status');
}

/**
 * Gets wireless status from network.wireless ubus (cached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
export function wireless_status_get() {
	return cache_call(wireless_status_fetch);
};

/**
 * Collects all AP-mode wireless interfaces from runtime status.
 *
 * @returns {array} Array of { ifname, ssid, radio_name } entries
 */
export function ssid_entries_get() {
	let status = wireless_status_get();
	if (!status)
		return [];

	let entries = [];
	for (let radio_name, radio in status) {
		if (!radio.interfaces)
			continue;

		for (let iface in radio.interfaces) {
			if (!iface.ifname || iface.config?.mode != 'ap')
				continue;

			push(entries, {
				ifname: iface.ifname,
				ssid: iface.config?.ssid ?? '',
				radio_name,
			});
		}
	}

	return entries;
};

/**
 * Resolves a TR-181 SSID instance number to its runtime netdev ifname by
 * matching iface.config.ubbf_ssid in network.wireless status, falling back
 * to position-based lookup for runtime-discovered interfaces.
 *
 * @param {number} ssid_instance - TR-181 SSID instance number
 * @returns {string|null} Runtime ifname (e.g. phy0-ap0) or null if not found
 */
export function ssid_ifname_get(ssid_instance) {
	let status = wireless_status_get();
	if (!status)
		return null;

	for (let radio_name, radio in status) {
		if (!radio.interfaces)
			continue;

		for (let iface in radio.interfaces) {
			if (int(iface.config?.ubbf_ssid) == ssid_instance)
				return iface.ifname;
		}
	}

	let entries = ssid_entries_get();
	let entry = entries[ssid_instance - 1];
	return entry?.ifname;
};

/**
 * Refreshes the iwinfo interface cache from kernel (uncached).
 *
 * @returns {boolean} Always returns true as sentinel for caching
 */
function iwinfo_update_fetch() {
	try {
		iwinfo.update();
	} catch (e) {
		log_exception('iwinfo_update', e);
	}
	return true;
}

/**
 * Refreshes the iwinfo interface cache from kernel (cached).
 *
 * @returns {boolean} Always returns true
 */
export function iwinfo_update() {
	return cache_call(iwinfo_update_fetch);
};

/**
 * Fetches WiFi association list for an interface (uncached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Station associations keyed by MAC address
 */
function assoclist_fetch(ifname) {
	iwinfo_update();
	if (!iwinfo.ifaces?.[ifname])
		return {};
	return iwinfo.assoclist(ifname);
}

/**
 * Gets WiFi association list for an interface (cached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Station associations keyed by MAC address
 */
export function assoclist_get(ifname) {
	return cache_call(assoclist_fetch, ifname);
};

const STANDARD_ORDER = ['g', 'n', 'ac', 'ax', 'be'];
const BANDWIDTH_ORDER = ['20MHz', '40MHz', '80MHz', '160MHz', '320MHz'];

/**
 * Converts a band name to TR-181 format.
 *
 * @param {string} band - Band name ('2g', '5g', '6g')
 * @returns {string} TR-181 band format ('2.4GHz', '5GHz', '6GHz')
 */
export function band_to_tr181(band) {
	let map = { '2g': '2.4GHz', '5g': '5GHz', '6g': '6GHz' };
	return map[band] ?? band;
};

/**
 * Converts a TR-181 band name to UCI format.
 *
 * @param {string} band - TR-181 band name
 * @returns {string} UCI band format ('2g', '5g', '6g')
 */
export function band_to_uci(band) {
	let map = { '2.4GHz': '2g', '5GHz': '5g', '6GHz': '6g' };
	return map[band] ?? '2g';
};

/**
 * Converts a band name to the wiphy_bands array index. The array is
 * positioned by the kernel nl80211 band enum (DF_TYPEIDX in the ucode
 * nl80211 module): 0=2.4GHz, 1=5GHz, 2=60GHz, 3=6GHz.
 *
 * @param {string} band - Band name in any format
 * @returns {number} Band index
 */
export function band_to_index(band) {
	if (band == '2g' || band == '2.4GHz')
		return 0;
	if (band == '5g' || band == '5GHz')
		return 1;
	if (band == '6g' || band == '6GHz')
		return 3;
	if (band == '60g' || band == '60GHz')
		return 2;
	return 0;
};

const RADIO_ADDRESS_OFFSET = { '2g': 0, '5g': 1, '6g': 2, '60g': 3 };

/**
 * Derives the unique identifier of a radio from its wiphy's MAC address.
 *
 * The radios of one wiphy share its MAC address, so each band past 2.4 GHz
 * takes a locally administered address with the band's offset in the last
 * byte. The scheme is umapd's (derive_radio_address() in rrmd/opclass.uc),
 * so a radio keeps its identifier with and without EasyMesh.
 *
 * @param {string} phy_mac - MAC address of the wiphy
 * @param {string} band - UCI band name ('2g', '5g', '6g', '60g')
 * @returns {string|null} Radio identifier, or null without a valid MAC
 */
export function radio_address_derive(phy_mac, band) {
	let bytes = phy_mac ? hexdec(phy_mac, ':') : null;
	if (length(bytes) != 6)
		return null;

	let offset = RADIO_ADDRESS_OFFSET[band] ?? 0;
	if (offset == 0)
		return lc(phy_mac);

	let octets = [];
	for (let i = 0; i < 6; i++)
		push(octets, ord(bytes, i));
	octets[0] |= 0x02;
	octets[5] = (octets[5] + offset) & 0xff;
	return sprintf('%02x:%02x:%02x:%02x:%02x:%02x', ...octets);
};

/**
 * Determines the highest WiFi standard from a standards string.
 *
 * @param {string} standards - Standards string (e.g. 'b/g/n/ac')
 * @returns {string} Highest standard ('g', 'n', 'ac', 'ax', 'be')
 */
export function standards_to_highest(standards) {
	if (!standards)
		return 'g';
	let std = lc(standards);
	if (match(std, /be/))
		return 'be';
	if (match(std, /ax/))
		return 'ax';
	if (match(std, /ac/))
		return 'ac';
	if (match(std, /n/))
		return 'n';
	return 'g';
};

const HTMODE_TABLE = {
	be:  { '320MHz': 'EHT320', '160MHz': 'EHT160', '80MHz': 'EHT80', '40MHz': 'EHT40', '20MHz': 'EHT20' },
	ax:  { '160MHz': 'HE160', '80MHz': 'HE80', '40MHz': 'HE40', '20MHz': 'HE20' },
	ac:  { '160MHz': 'VHT160', '80MHz': 'VHT80', '40MHz': 'VHT40', '20MHz': 'VHT20' },
	n:   { '40MHz': 'HT40', '20MHz': 'HT20' }
};

/**
 * Converts WiFi standards and bandwidth to htmode string.
 *
 * @param {string} standards - WiFi standards string
 * @param {string} bandwidth - Bandwidth string
 * @returns {string} htmode string (e.g. 'HE80', 'VHT160')
 */
export function standards_bandwidth_to_htmode(standards, bandwidth) {
	if (!standards)
		return 'NOHT';

	let std = standards_to_highest(standards);
	let bw = bandwidth ?? '20MHz';
	let modes = HTMODE_TABLE[std];

	if (!modes)
		return 'NOHT';

	return modes[bw] ?? modes['20MHz'] ?? 'NOHT';
};

/**
 * Converts a channel width index to bandwidth string.
 *
 * @param {number} width - Channel width index
 * @returns {string} Bandwidth string
 */
export function channel_width_to_bandwidth(width) {
	// indexed by NL80211_CHAN_WIDTH_*: 8-12 are the S1G widths, 320MHz is 13
	let bandwidths = [
		'20MHz', '20MHz', '40MHz', '80MHz',
		'80+80MHz', '160MHz', '5MHz', '10MHz',
		'1MHz', '2MHz', '4MHz', '8MHz', '16MHz', '320MHz'
	];
	return bandwidths[width] ?? '';
};

/**
 * Finds a wireless PHY that supports the specified band.
 *
 * A PHY with a channel the regulatory domain allows comes first. Failing
 * that, the first PHY that has the band at all: its capabilities do not
 * depend on the regulatory domain, and before the country is set at boot
 * the world domain disables every 6 GHz channel.
 *
 * @param {string} band - Band name
 * @returns {object|null} Object with phy and band_idx, or null
 */
export function phy_for_band(band) {
	let band_idx = band_to_index(band);
	let phys = iwinfo.phys ?? [];
	let fallback = null;

	// The wiphy dump is indexed by wiphy number: a phy in another netns
	// leaves a null entry.
	for (let phy in phys) {
		let phy_band = phy?.wiphy_bands?.[band_idx];
		if (!phy_band)
			continue;

		fallback ??= { phy, band_idx };
		for (let freq in phy_band.freqs ?? []) {
			if (!freq.disabled)
				return { phy, band_idx };
		}
	}

	return fallback;
};

/**
 * Picks the links an AP MLD can hold.
 *
 * An AP MLD is an interface of one wiphy, so all its links sit on that
 * wiphy. The wiphy with the most links wins, the first in link order on a
 * tie. A link whose wiphy is unknown joins no AP MLD.
 *
 * @param {array} links - Link descriptions, in preference order
 * @param {function} path_of - Returns the device path of a link's wiphy, or null
 * @returns {object} { links: those on the chosen wiphy, rest: all others }
 */
export function mld_links_select(links, path_of) {
	let by_path = {};
	let order = [];

	for (let link in links) {
		let path = path_of(link);
		if (path == null)
			continue;
		if (!by_path[path]) {
			by_path[path] = [];
			push(order, path);
		}
		push(by_path[path], link);
	}

	let best = [];
	for (let path in order) {
		if (length(by_path[path]) > length(best))
			best = by_path[path];
	}

	return { links: best, rest: filter(links, (link) => index(best, link) < 0) };
};

/**
 * Determines the maximum WiFi standard supported by a PHY on a band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {string} Maximum standard ('g', 'n', 'ac', 'ax', 'be')
 */
export function phy_max_standard(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return 'g';

	for (let ifd in band.iftype_data ?? []) {
		if (!ifd.iftypes?.ap)
			continue;
		if (ifd.eht_cap_phy)
			return 'be';
		if (ifd.he_cap_phy)
			return 'ax';
	}

	if (band.vht_mcs_set)
		return 'ac';
	if (band.ht_capa)
		return 'n';
	return 'g';
};

/**
 * Determines the maximum bandwidth supported by a PHY on a band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {string} Maximum bandwidth ('20MHz' to '320MHz')
 */
export function phy_max_bandwidth(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return '20MHz';

	let has_eht = false;
	for (let ifd in band.iftype_data ?? []) {
		if (ifd.iftypes?.ap && ifd.eht_cap_phy)
			has_eht = true;
	}

	for (let freq in band.freqs ?? []) {
		if (freq.disabled)
			continue;
		if (has_eht && !freq.no_320mhz)
			return '320MHz';
		if (!freq.no_160mhz)
			return '160MHz';
		if (!freq.no_80mhz)
			return '80MHz';
		if (!freq.no_ht40_minus || !freq.no_ht40_plus)
			return '40MHz';
	}

	return '20MHz';
};

/**
 * Returns the maximum number of AP-mode interfaces (SSIDs) a PHY supports.
 *
 * @param {object} phy - PHY object from iwinfo
 * @returns {number} Maximum AP interfaces
 */
export function phy_max_ssids(phy) {
	for (let combo in phy?.interface_combinations ?? []) {
		for (let limit in combo.limits ?? []) {
			if (limit.types?.ap)
				return limit.max ?? 0;
		}
	}

	return 0;
};

const HE_RATE_TABLE = {
	'20MHz':  [ 0, 86,   172,  258,  344,  516,  688,   774,   860 ],
	'40MHz':  [ 0, 172,  344,  516,  688,  1032, 1376,  1549,  1721 ],
	'80MHz':  [ 0, 360,  721,  1081, 1441, 2162, 2882,  3243,  3603 ],
	'160MHz': [ 0, 721,  1441, 2162, 2882, 4324, 5765,  6485,  7206 ],
	// 802.11be 320MHz: ~2x the 160MHz PHY rate per NSS
	'320MHz': [ 0, 1442, 2882, 4324, 5764, 8648, 11530, 12970, 14412 ]
};

const VHT_RATE_TABLE = {
	'20MHz':  [ 0, 87,  173,  260,  347 ],
	'40MHz':  [ 0, 200, 400,  600,  800 ],
	'80MHz':  [ 0, 433, 867,  1300, 1733 ],
	'160MHz': [ 0, 867, 1733, 2600, 3467 ]
};

const HT_RATE_TABLE = {
	'20MHz': [ 0, 72,  144,  217,  289 ],
	'40MHz': [ 0, 150, 300,  450,  600 ]
};

/**
 * Calculates the maximum PHY bitrate from capabilities.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {number} Maximum bitrate in Mbps
 */
export function phy_max_bitrate(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return 0;

	let nss = ubbf.antenna_count(phy.wiphy_antenna_tx ?? 0);
	let max_bw = phy_max_bandwidth(phy, band_idx);
	let max_std = phy_max_standard(phy, band_idx);

	if (max_std == 'be' || max_std == 'ax') {
		let table = HE_RATE_TABLE[max_bw] ?? HE_RATE_TABLE['20MHz'];
		return table[min(nss, length(table) - 1)] ?? 0;
	}

	if (max_std == 'ac') {
		let table = VHT_RATE_TABLE[max_bw] ?? VHT_RATE_TABLE['20MHz'];
		return table[min(nss, length(table) - 1)] ?? 0;
	}

	if (max_std == 'n') {
		let bw = (max_bw != '20MHz') ? '40MHz' : '20MHz';
		let table = HT_RATE_TABLE[bw];
		return table[min(nss, length(table) - 1)] ?? 0;
	}

	return 54;
};

/**
 * Determines the maximum transmit power for a PHY on a band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {number|null} Maximum TX power in dBm, null when the band is unknown
 */
export function phy_max_txpower(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return null;

	let max_power = 0;
	for (let freq in band.freqs ?? []) {
		if (freq.disabled)
			continue;
		if (freq.max_tx_power > max_power)
			max_power = freq.max_tx_power;
	}

	return max_power / 100;
};

/**
 * Clamps requested WiFi standard and bandwidth to supported maximums.
 *
 * @param {string} requested_std - Requested WiFi standard
 * @param {string} requested_bw - Requested bandwidth
 * @param {string} max_std - Maximum supported standard
 * @param {string} max_bw - Maximum supported bandwidth
 * @returns {string} Clamped htmode string
 */
export function clamp_htmode(requested_std, requested_bw, max_std, max_bw) {
	// the wifi stack has no 80+80 htmode; treat the non-contiguous
	// 80+80MHz request as its contiguous 160MHz equivalent instead of
	// letting the table fallback collapse it to 20MHz
	if (requested_bw == '80+80MHz')
		requested_bw = '160MHz';
	if (max_bw == '80+80MHz')
		max_bw = '160MHz';

	let std_idx = index(STANDARD_ORDER, requested_std);
	let max_std_idx = index(STANDARD_ORDER, max_std);
	if (std_idx < 0)
		std_idx = 0;
	if (max_std_idx < 0)
		max_std_idx = 0;

	let actual_std = (std_idx <= max_std_idx) ? requested_std : max_std;

	let bw_idx = index(BANDWIDTH_ORDER, requested_bw);
	let max_bw_idx = index(BANDWIDTH_ORDER, max_bw);
	if (bw_idx < 0)
		bw_idx = 0;
	if (max_bw_idx < 0)
		max_bw_idx = 0;

	let actual_bw = (bw_idx <= max_bw_idx) ? requested_bw : max_bw;

	return standards_bandwidth_to_htmode(actual_std, actual_bw);
};

export const txpower_pct_to_dbm = ubbf.txpower_pct_to_dbm;

/**
 * Returns comma-separated TR-181 band names supported by a PHY.
 *
 * @param {object} phy - PHY object from iwinfo
 * @returns {string} Comma-separated band names (e.g. "2.4GHz,5GHz")
 */
export function phy_supported_bands(phy) {
	let bands = [];
	let band_slots = [
		{ idx: 0, name: '2g' },
		{ idx: 1, name: '5g' },
		{ idx: 3, name: '6g' }
	];

	for (let slot in band_slots) {
		let band = phy?.wiphy_bands?.[slot.idx];
		if (!band)
			continue;

		for (let freq in band.freqs ?? []) {
			if (!freq.disabled) {
				push(bands, band_to_tr181(slot.name));
				break;
			}
		}
	}

	return join(',', bands);
};

/**
 * Returns comma-separated WiFi standards supported by a PHY on a band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index (0=2.4GHz, 1=5GHz, 3=6GHz)
 * @returns {string} Comma-separated standards (e.g. "b,g,n,ax")
 */
export function phy_supported_standards(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return '';

	let standards = [];

	if (band_idx == 0)
		push(standards, 'b', 'g');
	else
		push(standards, 'a');

	if (band.ht_capa)
		push(standards, 'n');

	if (band_idx == 1 && band.vht_mcs_set)
		push(standards, 'ac');

	for (let ifd in band.iftype_data ?? []) {
		if (!ifd.iftypes?.ap)
			continue;
		if (ifd.he_cap_phy)
			push(standards, 'ax');
		if (ifd.eht_cap_phy)
			push(standards, 'be');
		break;
	}

	return join(',', standards);
};

/**
 * Returns comma-separated channel numbers available on a PHY band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {string} Comma-separated channel numbers (e.g. "1,6,11")
 */
export function phy_possible_channels(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return '';

	let channels = [];
	for (let freq in band.freqs ?? []) {
		if (freq.disabled)
			continue;
		let ch = ubbf.freq_to_channel(freq.freq);
		if (ch > 0)
			push(channels, ch);
	}

	return join(',', channels);
};

/**
 * Returns comma-separated bandwidths supported by a PHY on a band.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @returns {string} Comma-separated bandwidths (e.g. "20MHz,40MHz,80MHz")
 */
export function phy_supported_bandwidths(phy, band_idx) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return '20MHz';

	let has_40 = false, has_80 = false, has_160 = false, has_320 = false;
	let has_eht = false;

	for (let ifd in band.iftype_data ?? []) {
		if (ifd.iftypes?.ap && ifd.eht_cap_phy) {
			has_eht = true;
			break;
		}
	}

	for (let freq in band.freqs ?? []) {
		if (freq.disabled)
			continue;
		if (!freq.no_ht40_minus || !freq.no_ht40_plus)
			has_40 = true;
		if (!freq.no_80mhz)
			has_80 = true;
		if (!freq.no_160mhz)
			has_160 = true;
		if (has_eht && !freq.no_320mhz)
			has_320 = true;
	}

	let bw = ['20MHz'];
	if (has_40) push(bw, '40MHz');
	if (has_80) push(bw, '80MHz');
	if (has_160) push(bw, '160MHz');
	if (has_320) push(bw, '320MHz');

	return join(',', bw);
};

/**
 * Checks if a channel supports the requested bandwidth.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index
 * @param {number} channel - Channel number to check
 * @param {string} bandwidth - Requested bandwidth ('20MHz' to '320MHz')
 * @returns {boolean} True if the channel supports the bandwidth
 */
export function channel_valid_for_bandwidth(phy, band_idx, channel, bandwidth) {
	if (bandwidth == '20MHz')
		return true;

	let band = phy?.wiphy_bands?.[band_idx];
	if (!band)
		return false;

	let chan_info;
	for (let freq in band.freqs ?? []) {
		if (freq.disabled)
			continue;
		let ch = ubbf.freq_to_channel(freq.freq);
		if (ch == channel) {
			chan_info = freq;
			break;
		}
	}

	if (!chan_info)
		return false;

	switch (bandwidth) {
	case '40MHz':
		return !chan_info.no_ht40_minus || !chan_info.no_ht40_plus;
	case '80MHz':
		return !chan_info.no_80mhz;
	case '160MHz':
		return !chan_info.no_160mhz;
	case '320MHz':
		return !chan_info.no_320mhz;
	}

	return true;
};

const DSCP_NAMES = {
	MIN:  0, DF:   0, CS0:  0,
	LE:   1,
	CS1:  8,
	AF11: 10, AF12: 12, AF13: 14,
	CS2:  16,
	AF21: 18, AF22: 20, AF23: 22,
	CS3:  24,
	AF31: 26, AF32: 28, AF33: 30,
	CS4:  32,
	AF41: 34, AF42: 36, AF43: 38,
	CS5:  40,
	VA:   44,
	EF:   46,
	CS6:  48,
	CS7:  56
};

/**
 * Parses a single DSCP token (name or 0-63 number) into its numeric codepoint.
 *
 * @param {string} token - DSCP name (case-insensitive) or numeric string
 * @returns {number|null} 0..63 on success, null on parse failure
 */
export function dscp_parse(token) {
	if (token == null)
		return null;
	let t = trim('' + token);
	if (t == '')
		return null;

	let upper = uc(t);
	if (upper in DSCP_NAMES)
		return DSCP_NAMES[upper];

	let n = int(t);
	if (type(n) != 'int' || n < 0 || n > 63)
		return null;
	return n;
};

/**
 * Parses a comma-separated list of DSCP tokens into a sorted unique int array.
 *
 * @param {string} csv - Comma-separated DSCP names or numbers
 * @returns {array} Sorted unique DSCP codepoints (0..63)
 */
export function dscp_list_parse(csv) {
	if (!csv)
		return [];
	let seen = {};
	let out = [];
	for (let token in split('' + csv, ',')) {
		let v = dscp_parse(token);
		if (v == null)
			continue;
		let key = '' + v;
		if (seen[key])
			continue;
		seen[key] = true;
		push(out, v);
	}
	return sort(out, (a, b) => a - b);
};

/**
 * Renders an array of WiFi.X_UBBF_QoSMap.{i}. instances into the
 * 16-byte hostapd qos_map_set CSV. Each enabled entry maps its UserPriority
 * (0..7) to a DSCP range derived from min/max of DSCPList; unconfigured or
 * disabled UPs stay at 255,255 (no claim). The 802.11u exception-pair tail
 * is not emitted; multi-DSCP claims are bounded by the min/max range.
 *
 * @param {array} entries - Instance objects with UserPriority and DSCPList
 * @returns {string} 16-byte comma-separated decimal string, or empty on
 *                   no enabled entries
 */
export function qos_map_set_render(entries) {
	let up_low = [255, 255, 255, 255, 255, 255, 255, 255];
	let up_high = [255, 255, 255, 255, 255, 255, 255, 255];
	let any = false;

	for (let e in entries ?? []) {
		if (!e || !ubbf.to_bool(e.Enable))
			continue;

		let up = int(e.UserPriority);
		if (type(up) != 'int' || up < 0 || up > 7)
			continue;

		let dscps = dscp_list_parse(e.DSCPList);
		if (length(dscps) == 0)
			continue;

		up_low[up] = dscps[0];
		up_high[up] = dscps[length(dscps) - 1];
		any = true;
	}

	if (!any)
		return '';

	let bytes = [];
	for (let i = 0; i < 8; i++) {
		push(bytes, sprintf('%d', up_low[i]));
		push(bytes, sprintf('%d', up_high[i]));
	}
	return join(',', bytes);
};

