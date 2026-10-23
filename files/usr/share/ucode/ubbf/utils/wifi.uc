'use strict';

import * as nl80211 from 'nl80211';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { cache_call } from 'ubbf';
import { instance_number, instance_rows } from 'ubbf';
import { phy_radio_restrict, radio_bands } from 'ubbf.utils.wifi_radio';

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
 * Fetches the wiphy dump from nl80211 (uncached).
 *
 * @returns {array} PHYs indexed by wiphy number, as iwinfo.phys holds them
 */
function phys_fetch() {
	return nl80211.request(nl80211.const.NL80211_CMD_GET_WIPHY, nl80211.const.NLM_F_DUMP,
		{ split_wiphy_dump: true }) ?? [];
}

/**
 * Gets the wiphy dump from nl80211 (cached).
 *
 * @returns {array} PHYs indexed by wiphy number; a phy in another netns is null
 */
export function phys_get() {
	return cache_call(phys_fetch);
};

function stations_table(ap_instance) {
	return sprintf('Device.WiFi.AccessPoint.%s.AssociatedDevice', ap_instance);
}

/**
 * Numbers the stations of an access point by MAC, so that a station keeps
 * its number while other stations come and go.
 *
 * @param {*} ap_instance - AccessPoint instance number
 * @param {object} stations - assoclist_get() result, keyed by MAC
 * @returns {object} Instance number to { mac, sta }
 */
export function stations_numbered(ap_instance, stations) {
	let by_mac = {};
	for (let mac, sta in stations ?? {})
		by_mac[uc(mac)] = { mac, sta };
	return instance_rows(stations_table(ap_instance), keys(by_mac), (mac) => by_mac[mac]);
};

/**
 * Returns the AssociatedDevice instance number of a station.
 *
 * @param {*} ap_instance - AccessPoint instance number
 * @param {string} mac - Station MAC address
 * @returns {number} The instance number
 */
export function station_number(ap_instance, mac) {
	return instance_number(stations_table(ap_instance), uc(mac));
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
	let band_idx = ubbf.band_to_index(band);
	let phys = phys_get();
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
 * Finds the PHY a radio runs on, restricted to the radio's frequencies.
 *
 * The capability radio names its wiphy as board.json does. A wiphy that
 * still has another name, as before netifd renamed it, is found by band.
 *
 * @param {object} radio - Capability radio, or null when unknown
 * @param {string} band - UCI band name
 * @returns {object|null} Object with phy and band_idx, or null
 */
export function radio_phy_get(radio, band) {
	let band_idx = ubbf.band_to_index(band);
	let phy = radio?.phy ? filter(phys_get(), (p) => p?.wiphy_name == radio.phy)[0] : null;

	if (!phy?.wiphy_bands?.[band_idx])
		phy = phy_for_band(band)?.phy;
	if (!phy)
		return null;

	return { phy: phy_radio_restrict(phy, band_idx, radio), band_idx };
};

/**
 * Returns comma-separated TR-181 band names supported by a PHY, or by one
 * radio of it.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {object} radio - Capability radio; one with frequency ranges limits
 *                         the bands to those of its ranges
 * @returns {string} Comma-separated band names (e.g. "2.4GHz,5GHz")
 */
export function radio_supported_bands(phy, radio) {
	let bands = ubbf.phy_supported_bands(phy);
	if (!length(radio?.freq_ranges))
		return bands;

	let names = { '2g': '2.4GHz', '5g': '5GHz', '6g': '6GHz' };
	let radio_names = map(radio_bands(radio), (band) => names[band]);

	return join(',', filter(split(bands, ','), (name) => index(radio_names, name) >= 0));
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
