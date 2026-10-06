// Host test of the DHCPv4 pool split around ReservedAddresses in
// render/templates/dhcp.uc: the segments between the reserved addresses,
// with the work bound by the number of reservations, not the pool size.
// Run from the repository root with the native module built for the host:
//   tests/render/run.sh <host build> tests/dhcp-range.uc
'use strict';

import { generate } from 'ubbf.render.renderer';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function ranges(min, max, reserved) {
	let config = { Device: {
		IP: { Interface: { '1': { Enable: 'true', Name: 'lan', IPv4Enable: 'true',
			IPv4Address: { '1': { Enable: 'true', IPAddress: '10.0.0.1', SubnetMask: '255.0.0.0' } } } } },
		DHCPv4: { Server: { Enable: 'true', Pool: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.1',
			MinAddress: min, MaxAddress: max, SubnetMask: '255.0.0.0', ReservedAddresses: reserved } } } }
	} };
	let out = [];
	for (let line in split(generate(config, [], true).uci, '\n')) {
		let m = match(line, /^set dhcp\.lan[a-z_0-9]*\.(start|limit)=([0-9]+)$/);
		if (m)
			push(out, +m[2]);
	}
	return out;
}

check('no reservation', ranges('10.0.0.100', '10.0.0.249', ''), [ 100, 150 ]);
check('one reservation inside', ranges('10.0.0.100', '10.0.0.249', '10.0.0.150'), [ 100, 50, 151, 99 ]);
check('duplicates and the first address', ranges('10.0.0.100', '10.0.0.249', '10.0.0.150,10.0.0.150,10.0.0.100'),
	[ 101, 49, 151, 99 ]);
check('the last address', ranges('10.0.0.100', '10.0.0.249', '10.0.0.249'), [ 100, 149 ]);
check('outside the pool', ranges('10.0.0.100', '10.0.0.249', '10.0.0.50,10.0.1.1'), [ 100, 150 ]);

let t0 = clock(true);
let big = ranges('10.0.0.1', '10.255.255.254', '10.1.2.3');
let t1 = clock(true);
check('a /8 pool with one reservation gives two segments', length(big), 4);
check('a /8 pool renders in under a second', (t1[0] - t0[0]) + (t1[1] - t0[1]) / 1e9 < 1, true);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
