// Stands in for iwinfo on a device whose hostapd answers no ubus call:
// iwinfo.uc calls hostapd bss_info when it loads, on a connection with the
// 30 s default timeout. The load writes the mark file, then waits those 30 s.
'use strict';

import { writefile } from 'fs';

writefile(getenv('WEDGED_MARKS') + '/iwinfo', 'loaded\n');
sleep(30000);

export const phys = [];
export const ifaces = {};
export function update() {};
export function assoclist() { return {}; };
