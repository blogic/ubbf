'use strict';

import * as ubus from 'ubus';

/**
 * Retrieves netifd interface status via ubus.
 *
 * Uncached: netifd status is mutable (DHCP leases, RA-learned SLAAC
 * addresses, PD grants) and we have observed stale snapshots leaking
 * through the prior time-based cache in the long-lived ubbf daemon VM.
 * Every caller needs a fresh view.
 *
 * @param {string} name - Interface name
 * @returns {object|null} Interface status from netifd or null if unavailable
 */
export function netifd_status_get(name) {
	if (!name)
		return null;
	return ubus.call('network.interface.' + name, 'status');
};
