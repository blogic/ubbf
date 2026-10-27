'use strict';

export const DNS_RESOLV_AUTO = '/tmp/resolv.conf.d/resolv.conf.auto';

// dnsmasq jails the directory of its resolv file, so the filtered copy
// lives next to the one netifd writes.
export const DNS_RESOLV_FILTERED = '/tmp/resolv.conf.d/resolv.conf.ubbf';
