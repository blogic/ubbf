// Host test of the IPv6Address and IPv6Prefix lifetimes in tr181/IP.uc:
// PreferredLifetime and ValidLifetime are TR-181 dateTime values, and a
// read of one row gives what a read of the interface gives. tests/ip/
// holds stand-ins for ubus (netifd status) and rtnl, tests/hosts/ one for
// udebug. Run from the repository root with the native module built for
// the host:
//   ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/ipv6-lifetime.uc
'use strict';

import { model } from 'ubbf.tr181.IP';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const FOREVER = '9999-12-31T23:59:59Z';

function epoch(datetime) {
	let m = match(datetime ?? '', /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$/);
	if (!m)
		return null;
	return timegm({ year: +m[1], mon: +m[2], mday: +m[3], hour: +m[4], min: +m[5], sec: +m[6] });
}

// The seconds from now to a dateTime, within the second the test runs in.
function left(datetime) {
	return (datetime == FOREVER) ? 'infinite' : epoch(datetime) - time();
}

function lifetimes(row) {
	return [ row?.IPAddressStatus ?? row?.PrefixStatus, left(row?.PreferredLifetime), left(row?.ValidLifetime) ];
}

function abs(n) {
	return (n < 0) ? -n : n;
}

function near(name, got, expected) {
	let ok = (got[0] == expected[0]);
	for (let i in [ 1, 2 ])
		ok = ok && ((type(expected[i]) == 'string') ? got[i] == expected[i] : abs(got[i] - expected[i]) <= 1);
	check(name, ok ? expected : got, expected);
}

global.netifd = {
	lan: {
		up: true, l3_device: 'br-lan',
		'ipv6-address': [
			{ address: '2001:db8::10', mask: 64, preferred: 300, valid: 600 },
			{ address: '2001:db8::11', mask: 64 },
			{ address: '2001:db8::12', mask: 64, preferred: 0, valid: 4294967290 }
		],
		'ipv6-prefix-assignment': [
			{ address: '2001:db8:1::', mask: 64, preferred: 0, valid: 120,
			  'local-address': { address: '2001:db8:1::1', mask: 64 } }
		]
	}
};

const iface = { Name: 'lan', Enable: 'true', Upstream: 'false', IPv6Address: {
	'1': { Enable: 'true', Origin: 'DHCPv6' }, '2': { Enable: 'true', Origin: 'DHCPv6' },
	'3': { Enable: 'true', Origin: 'DHCPv6' }, '4': { Enable: 'true', Origin: 'Child' }
} };

const CASES = [
	[ 'finite', [ 'Preferred', 300, 600 ] ],
	[ 'no lifetimes', [ 'Preferred', 'infinite', 'infinite' ] ],
	[ 'valid run out', [ 'Invalid', 0, 0 ] ],
	[ 'prefix assignment, preferred run out', [ 'Deprecated', 0, 120 ] ],
];

let row_get = model['Device.IP.Interface.{i}.IPv6Address.{i}'].get;
let subtree = model['Device.IP.Interface.{i}'].get({ config: iface, instance: 1 });

for (let i = 0; i < length(CASES); i++) {
	let n = i + 1;
	let row = row_get({ instance: n, config: iface.IPv6Address[n], parent: iface });
	near(`IPv6Address ${CASES[i][0]}: row read`, lifetimes(row), CASES[i][1]);
	near(`IPv6Address ${CASES[i][0]}: interface read`, lifetimes(subtree.IPv6Address?.[n]), CASES[i][1]);
}

global.netifd.wan = { up: true, device: 'eth0' };
global.netifd.wan6 = { 'ipv6-prefix': [ { address: '2001:db8:2::', mask: 56, preferred: 1800, valid: 3600 } ] };
const wan = { Name: 'wan', Enable: 'true', Upstream: 'true',
	IPv6Prefix: { '1': { Enable: 'true', ParentPrefix: 'x' } } };

let prefix = model['Device.IP.Interface.{i}.IPv6Prefix.{i}'].get({ instance: 1, config: wan.IPv6Prefix['1'], parent: wan });
near('IPv6Prefix: row read', lifetimes(prefix), [ 'Preferred', 1800, 3600 ]);
let wan_tree = model['Device.IP.Interface.{i}'].get({ config: wan, instance: 2 });
near('IPv6Prefix: interface read', lifetimes(wan_tree.IPv6Prefix?.['1']), [ 'Preferred', 1800, 3600 ]);

// MaxMTUSize: a configured value reads back, else the MTU in use, within
// the TR-181 range (lo has 65536)
global.netifd.lo = { up: true, l3_device: 'lo' };
let iface_get = model['Device.IP.Interface.{i}'].get;
check('MaxMTUSize configured', iface_get({ config: { Name: 'lo', MaxMTUSize: '1492' }, instance: 3 }).MaxMTUSize, '1492');
check('MaxMTUSize 0 reads the MTU in use', iface_get({ config: { Name: 'lo', MaxMTUSize: '0' }, instance: 3 }).MaxMTUSize, '65535');
check('MaxMTUSize unset reads the MTU in use', iface_get({ config: { Name: 'lo' }, instance: 3 }).MaxMTUSize, '65535');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
