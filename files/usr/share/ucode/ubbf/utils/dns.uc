'use strict';

import * as ubbf from 'ubbf';

// The rows of learned DNS servers and forwarders are numbered from
// DNS_LEARNED_BASE + 1 upwards, a range the rows a controller adds never
// reach.
export const DNS_LEARNED_BASE = 10000;

export const DNS_RESOLV_AUTO = '/tmp/resolv.conf.d/resolv.conf.auto';

// dnsmasq jails the directory of its resolv file, so the filtered copy
// lives next to the one netifd writes.
export const DNS_RESOLV_FILTERED = '/tmp/resolv.conf.d/resolv.conf.ubbf';

/**
 * Tells whether an instance of Device.DNS.Client.Server or
 * Device.DNS.Relay.Forwarding belongs to a learned server.
 *
 * @param {*} instance - Instance number
 * @returns {boolean} True for a learned row
 */
export function dns_learned_row(instance) {
	return ubbf.to_int(instance) > DNS_LEARNED_BASE;
};
