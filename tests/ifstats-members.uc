// Host test of ip_interface_members() in ifstats.c of ubbf.so: the
// netdevs behind the LowerLayers of an IP.Interface.
//   ucode -L "<host build>/*.so" tests/ifstats-members.uc
'use strict';

import { ip_interface_members } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const root = { Device: {
	Ethernet: { Interface: {
		'1': { Name: 'lan1' },
		'2': { Name: 'lan2' },
		'3': { Name: 'wan' },
		'4': { Name: 'lan3' }
	} },
	Bridging: { Bridge: { '1': { Port: {
		'1': { Enable: 'true', ManagementPort: 'true', Name: 'br-lan' },
		'2': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.1' },
		'3': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.2,Device.Ethernet.Interface.1' },
		'4': { Enable: 'false', LowerLayers: 'Device.Ethernet.Interface.4' }
	} } } }
} };

function members(lower_layers) {
	return ip_interface_members(root, { LowerLayers: lower_layers });
}

check('bridge', members('Device.Bridging.Bridge.1.Port.1'), [ 'lan1', 'lan2' ]);
check('bridge, trailing dot', members('Device.Bridging.Bridge.1.Port.1.'), [ 'lan1', 'lan2' ]);
check('one link', members('Device.Ethernet.Interface.3'), [ 'wan' ]);
check('bridge and a link', members('Device.Bridging.Bridge.1.Port.1,Device.Ethernet.Interface.3'),
	[ 'lan1', 'lan2', 'wan' ]);
check('two links', members('Device.Ethernet.Interface.3, Device.Ethernet.Interface.4'), [ 'wan', 'lan3' ]);
check('no lower layer', members(''), []);
check('no root', ip_interface_members(null, { LowerLayers: 'Device.Ethernet.Interface.3' }), []);

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
