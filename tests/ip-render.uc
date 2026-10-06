// Host test of the IPv4 address render in render/templates/ip.uc: every
// enabled static IPv4Address row of an interface reaches netifd, which
// reads ipaddr as a list. Run from the repository root with the native
// module built for the host:
//   ucode -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/ip-render.uc
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const TEMPLATE = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/ip.uc';

function render(addresses) {
	let config = { Device: { IP: {
		IPv4Enable: 'true',
		Interface: { '1': { Enable: 'true', Name: 'lan', IPv4Enable: 'true', IPv4Address: addresses } }
	} } };
	let output = [];

	include(TEMPLATE, { ...h, output, config, ubbf, render_state: {},
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		lower_layer_resolve_vlan: () => null, device_state_set: () => null });

	return {
		proto: map(filter(output, (l) => match(l, /^set network\.lan\.proto=/)), (l) => split(l, '=')[1]),
		ipaddr: map(filter(output, (l) => match(l, /network\.lan\.ipaddr=/)), (l) => l)
	};
}

let two = render({
	'1': { Enable: 'true', AddressingType: 'Static', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0' },
	'2': { Enable: 'true', AddressingType: 'Static', IPAddress: '10.0.0.1', SubnetMask: '255.0.0.0' },
	'3': { Enable: 'false', AddressingType: 'Static', IPAddress: '172.16.0.1', SubnetMask: '255.255.0.0' }
});
check('both enabled static addresses are listed', two.ipaddr, [
	"add_list network.lan.ipaddr='192.168.1.1/24'",
	"add_list network.lan.ipaddr='10.0.0.1/8'"
]);
check('the interface is static', two.proto, [ "'static'" ]);

let one = render({ '1': { Enable: 'true', AddressingType: 'Static', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0' } });
check('one address is a list of one', one.ipaddr, [ "add_list network.lan.ipaddr='192.168.1.1/24'" ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
