// Host test of the Protocol and DestPort render of Device.Firewall.Service
// and Device.Firewall.Pinhole: -1 means the criterion is not used for
// matching. Run from the repository root with the native module built for
// the host:
//   ucode -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/firewall-service.uc
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const TEMPLATES = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/';

function render(template, table, row) {
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'wan' } } },
		Firewall: { [table]: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.1', ...row } } }
	} };
	let output = [];

	include(TEMPLATES + template, { ...h, output, config, ubbf, ubbf_instances: ubbf.instances,
		ubbf_to_bool: ubbf.to_bool, ubbf_to_int: ubbf.to_int, interface_to_name: ubbf.interface_to_name,
		csv_to_list: ubbf.csv_to_list, schedule_windows: () => null });

	let rule = {};
	for (let line in output) {
		let m = match(line, /^(set|add_list) firewall\.@rule\[-1\]\.([a-z_]+)='?([^']*)'?$/);
		if (!m)
			continue;
		if (m[1] == 'set')
			rule[m[2]] = m[3];
		else
			push(rule[m[2]] ??= [], m[3]);
	}
	return rule;
}

function service(row) {
	let r = render('firewall-services.uc', 'Service', row);
	return [ r.proto, r.dest_port ];
}

check('Service -1 matches any protocol and port', service({ Protocol: '-1', DestPort: '-1' }), [ [ 'all' ], null ]);
check('Service protocol and port lists', service({ Protocol: '6,17', DestPort: '22,80' }),
	[ [ 'tcp', 'udp' ], [ '22', '80' ] ]);
check('Service -1 in a list wins', service({ Protocol: '6,-1', DestPort: '22,-1' }), [ [ 'all' ], null ]);
check('Service without Protocol keeps the fw4 default', service({}), [ null, null ]);

function pinhole(protocol) {
	return render('firewall-pinholes.uc', 'Pinhole', { Protocol: protocol, DestIP: '2001:db8::1', DestPort: '443' }).proto;
}

check('Pinhole -1 matches any protocol', pinhole('-1'), [ 'all' ]);
check('Pinhole protocol list', pinhole('6,17'), [ 'tcp', 'udp' ]);
check('Pinhole single protocol', pinhole('17'), [ 'udp' ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
