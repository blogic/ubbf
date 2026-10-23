'use strict';

// iwinfo asks hostapd for every interface when it loads, so a render must
// not import this module: ubbf.utils.wifi holds what a render needs.
import * as iwinfo from 'iwinfo';
import { cache_call, log_exception } from 'ubbf';

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
