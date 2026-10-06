// Host test of acl_can_add() in acl.uc: only a write rule that grants the
// whole instance of a table lets a web UI role create rows in it. Run from
// the repository root with the native module built for the host;
// tests/hosts/ holds a stand-in for udebug:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/acl-add.uc
'use strict';

import { acl_can_add } from 'ubbf.acl';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const CASES = [
	[ 'full grant on the rows', { 'Device.A.T.*': true }, 'Device.A.T', true ],
	[ 'property list', { 'Device.A.T.*': [ 'Name' ] }, 'Device.A.T', false ],
	[ 'empty property list', { 'Device.A.T.*': [] }, 'Device.A.T', false ],
	[ 'filtered rule', { 'Device.A.T.*': { filter: { X: 'y' }, properties: [ 'Name' ] } }, 'Device.A.T', false ],
	[ 'denied', { 'Device.A.T.*': false }, 'Device.A.T', false ],
	[ 'one instance only', { 'Device.A.T.1': true }, 'Device.A.T', false ],
	[ 'grant on an ancestor', { 'Device.A': true }, 'Device.A.T', true ],
	[ 'a narrower rule wins over an ancestor grant', { 'Device.A': true, 'Device.A.T.*': [ 'Name' ] }, 'Device.A.T', false ],
	[ 'wildcard parent', { 'Device.P.*.S.*': true }, 'Device.P.3.S', true ],
	[ 'a rule below the rows grants nothing', { 'Device.A.T.*.Sub': true }, 'Device.A.T', false ],
	[ 'no write section', null, 'Device.A.T', false ],
];

for (let c in CASES)
	check(c[0], acl_can_add(c[1] ? { write: c[1] } : {}, c[2]), c[3]);

// The write rules of the shipped admin-user role (ubbf-feed ubbf-ui/acl):
// its web UI adds DHCP static addresses and edits the rest.
const ADMIN_USER = { write: {
	'Device.WiFi.SSID.*': [ 'Enable', 'SSID' ],
	'Device.IP.Interface.*': { filter: { Upstream: 'false' }, properties: [ 'Enable', 'Name' ] },
	'Device.IP.Interface.*.IPv4Address.*': [ 'Enable', 'IPAddress', 'SubnetMask' ],
	'Device.DHCPv4.Server.Pool.*': [ 'Enable', 'MinAddress', 'MaxAddress', 'LeaseTime', 'DNSServers' ],
	'Device.DHCPv4.Server.Pool.*.StaticAddress.*': true
} };

check('admin-user adds static addresses', acl_can_add(ADMIN_USER, 'Device.DHCPv4.Server.Pool.1.StaticAddress'), true);
check('admin-user adds no SSID, interface, address or pool',
	map([ 'Device.WiFi.SSID', 'Device.IP.Interface', 'Device.IP.Interface.1.IPv4Address', 'Device.DHCPv4.Server.Pool' ],
		(p) => acl_can_add(ADMIN_USER, p)), [ false, false, false, false ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
