'use strict';

export const DNS_RESOLV_AUTO = '/tmp/resolv.conf.d/resolv.conf.auto';

// dnsmasq jails the directory of its resolv file, so the filtered copy
// lives next to the one netifd writes.
export const DNS_RESOLV_FILTERED = '/tmp/resolv.conf.d/resolv.conf.ubbf';

/**
 * Tells whether a row of Device.DNS.Client.Server or
 * Device.DNS.Relay.Forwarding belongs to a learned server. A controller
 * adds Static rows; the first write into a learned row stores the Type of
 * its source.
 *
 * @param {object|null} row - The row
 * @returns {boolean} True for a learned row
 */
export function dns_learned_row(row) {
	return (row?.Type ?? 'Static') != 'Static';
};
