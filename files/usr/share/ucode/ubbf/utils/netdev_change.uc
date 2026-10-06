'use strict';

import * as ubus from 'ubus';
import { call as cache_call } from 'ubbf.utils.cache';

/**
 * Fetches the per-netdev "seconds since last operstate change" table
 * published by ubbf-device on the 'bbf-device' ubus object. Returns an
 * empty object on failure so callers can index it without a null guard.
 *
 * @returns {object} Map of netdev name to elapsed seconds (integer)
 */
function link_change_status_get() {
	return ubus.call('bbf-device', 'link_change_status') ?? {};
}

/**
 * Returns the seconds elapsed since the named netdev last changed
 * operstate, as tracked by ubbf-device. Result is cached for the
 * duration of the current datamodel get cycle (~2s).
 *
 * @param {string} ifname - Kernel netdev name
 * @returns {string} Decimal seconds, '0' when unknown
 */
export function last_change_get(ifname) {
	if (!ifname)
		return '0';

	let table = cache_call(link_change_status_get);
	let value = table?.[ifname];
	if (value == null)
		return '0';

	return sprintf('%d', value);
};
