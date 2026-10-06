// Host test of the bridge port helpers in utils/helpers.uc
// (Device.Bridging.Bridge.{i}.Port.{i}.IGMP and MLD). Run from the
// repository root with the native module built for the host:
//   ucode -L "$PWD/files/usr/share/ucode/*.uc" -L "<host build>/*.so" tests/bridging.uc
'use strict';

import { port_snooped, lower_layers_wifi } from 'ubbf.utils.helpers';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

check('row without the 2.21 values is snooped', port_snooped({ Enable: 'true' }), true);
check('IGMP and MLD true', port_snooped({ IGMP: 'true', MLD: 'true' }), true);
check('IGMP and MLD as 1', port_snooped({ IGMP: '1', MLD: '1' }), true);
check('IGMP false', port_snooped({ IGMP: 'false', MLD: 'true' }), false);
check('MLD false', port_snooped({ IGMP: 'true', MLD: 'false' }), false);
check('both false', port_snooped({ IGMP: 'false', MLD: 'false' }), false);
check('only MLD stored, false', port_snooped({ MLD: '0' }), false);
check('no row', port_snooped(null), true);

check('one SSID', lower_layers_wifi('Device.WiFi.SSID.1'), true);
check('two SSIDs', lower_layers_wifi('Device.WiFi.SSID.1,Device.WiFi.SSID.2'), true);
check('Ethernet link', lower_layers_wifi('Device.Ethernet.Link.2'), false);
check('SSID and link', lower_layers_wifi('Device.WiFi.SSID.1,Device.Ethernet.Link.2'), false);
check('empty', lower_layers_wifi(''), false);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
