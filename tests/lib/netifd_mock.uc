// Patches the ubus mock so that network.interface.<name> status answers
// from an interface name to status map; extra holds more object:method
// entries of the utest ubus data format.
'use strict';

import { mock } from 'utest';

export function netifd_patch(netifd, extra) {
	let data = { ...(extra ?? {}) };
	for (let name, status in netifd)
		data[`network.interface.${name}:status`] = status;
	return mock.global.patch('ubus', { data });
};
