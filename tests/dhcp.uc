// Host test of the StaticAddress states in utils/dhcp.uc
// (Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.Status). Run from the
// repository root with the native module built for the host; tests/hosts/
// holds a stand-in for udebug:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode/*.uc" \
//     -L "<host build>/*.so" tests/dhcp.uc
'use strict';

import { static_address_states } from 'ubbf.utils.dhcp';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function row(enable, chaddr, yiaddr) {
	return { Enable: enable, Chaddr: chaddr, Yiaddr: yiaddr };
}

function root_make(pool_enable, rows, other_rows) {
	let pools = {
		'1': {
			Enable: pool_enable,
			MinAddress: '192.168.1.100',
			MaxAddress: '192.168.1.249',
			SubnetMask: '255.255.255.0',
			StaticAddress: rows
		}
	};
	if (other_rows)
		pools['2'] = {
			Enable: 'true',
			MinAddress: '10.0.0.10',
			MaxAddress: '10.0.0.99',
			SubnetMask: '255.255.255.0',
			StaticAddress: other_rows
		};
	return { Device: { DHCPv4: { Server: { Pool: pools } } } };
}

let s = static_address_states(root_make('true', {
	'1': row('true', '02:00:00:00:00:01', '192.168.1.10'),
	'2': row('false', '02:00:00:00:00:02', '192.168.1.11')
}));
check('active row', s['1']['1'], 'Active');
check('disabled row', s['1']['2'], 'Disabled');

s = static_address_states(root_make('false', { '1': row('true', '02:00:00:00:00:01', '192.168.1.10') }));
check('row of a disabled pool', s['1']['1'], 'Disabled');

s = static_address_states(root_make('true', {
	'1': row('true', '02:00:00:00:00:1', '192.168.1.10'),
	'2': row('true', '02:00:00:00:00:02', '192.168.1.300'),
	'3': row('true', '02:00:00:00:00:03', '192.168.2.10'),
	'4': row('true', '02:00:00:00:00:04', '192.168.1.0'),
	'5': row('true', '02:00:00:00:00:05', '192.168.1.255'),
	'6': row('true', '', '')
}));
check('short MAC', s['1']['1'], 'Error_Misconfigured');
check('bad IPv4', s['1']['2'], 'Error_Misconfigured');
check('outside the pool subnet', s['1']['3'], 'Error_Misconfigured');
check('network address', s['1']['4'], 'Error_Misconfigured');
check('broadcast address', s['1']['5'], 'Error_Misconfigured');
check('empty row', s['1']['6'], 'Error_Misconfigured');

s = static_address_states(root_make('true', {
	'1': row('true', '02:00:00:00:00:01', '192.168.1.10'),
	'2': row('true', '02:00:00:00:00:02', '192.168.1.10'),
	'3': row('true', '02:00:00:00:00:0A', '192.168.1.20'),
	'4': row('true', '02:00:00:00:00:0a', '192.168.1.21'),
	'5': row('false', '02:00:00:00:00:05', '192.168.1.20'),
	'6': row('true', '02:00:00:00:00:06', '192.168.1.30')
}));
check('same Yiaddr, first row', s['1']['1'], 'Error_DuplicateAddress');
check('same Yiaddr, second row', s['1']['2'], 'Error_DuplicateAddress');
check('same Chaddr in other case, first row', s['1']['3'], 'Error_DuplicateAddress');
check('same Chaddr in other case, second row', s['1']['4'], 'Error_DuplicateAddress');
check('disabled row is no duplicate', s['1']['5'], 'Disabled');
check('unrelated row stays active', s['1']['6'], 'Active');

s = static_address_states(root_make('true',
	{ '1': row('true', '02:00:00:00:00:01', '192.168.1.10') },
	{ '1': row('true', '02:00:00:00:00:01', '10.0.0.5') }));
check('same Chaddr in two pools, pool 1', s['1']['1'], 'Error_DuplicateAddress');
check('same Chaddr in two pools, pool 2', s['2']['1'], 'Error_DuplicateAddress');

s = static_address_states(root_make('true', { '1': row('true', '02:00:00:00:00:01', '192.168.001.010') }));
check('leading zeros are an error', s['1']['1'], 'Error_Misconfigured');

check('no pools', static_address_states({}), {});

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
