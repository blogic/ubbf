'use strict';

import { ipv6_prefix_rows_build } from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Builds the dynamic IPv6 prefix rows of an interface, see
 * ipv6_prefix_rows_build() in ipv6.c of ubbf.so.
 *
 * @param {string} name - IP.Interface Name
 * @param {boolean} upstream - Upstream flag
 * @param {string} l2_dev - L2/L3 device for the kernel RA fallback
 * @returns {array} Array of { data, origin } rows
 */
export function ipv6_prefix_rows(name, upstream, l2_dev) {
	return ipv6_prefix_rows_build(name, upstream, netifd_status_get(upstream ? name + '6' : name), l2_dev);
};
