'use strict';

import * as iwinfo from 'iwinfo';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { cache_call } from 'ubbf';
import { log_exception } from 'ubbf';
import { instance_number, instance_rows } from 'ubbf';

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
