// Host test of the IPv6Address and IPv6Prefix lifetimes in tr181/IP.uc:
// PreferredLifetime and ValidLifetime are TR-181 dateTime values, and a
// read of one row gives what a read of the interface gives. Also the
// MaxMTUSize of an IP.Interface. The netifd status comes from a ubus mock.
'use strict';

import { describe, it, assert, beforeEach, between } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import { model } from 'ubbf.tr181.IP';

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

function near(expected) {
	return map(expected, (v) => (type(v) == 'int') ? between(v - 1, v + 1) : v);
}

const LAN = {
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
};

const WAN = { up: true, device: 'eth0' };
const WAN6 = { 'ipv6-prefix': [ { address: '2001:db8:2::', mask: 56, preferred: 1800, valid: 3600 } ] };

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

const iface_get = model['Device.IP.Interface.{i}'].get;
const row_get = model['Device.IP.Interface.{i}.IPv6Address.{i}'].get;
const prefix_get = model['Device.IP.Interface.{i}.IPv6Prefix.{i}'].get;

describe('IP.Interface lifetimes', () => {
	beforeEach(() => state_clear());

	it('gives IPv6Address lifetimes as dateTime, the same in a row and an interface read', () => {
		netifd_patch({ lan: LAN });

		let subtree = iface_get({ config: iface, instance: 1 });
		for (let i = 0; i < length(CASES); i++) {
			let n = i + 1;
			let row = row_get({ instance: n, config: iface.IPv6Address[n], parent: iface });
			assert.match(near(CASES[i][1]), lifetimes(row), `IPv6Address ${CASES[i][0]}: row read`);
			assert.match(near(CASES[i][1]), lifetimes(subtree.IPv6Address?.[n]), `IPv6Address ${CASES[i][0]}: interface read`);
		}
	});

	it('gives IPv6Prefix lifetimes as dateTime, the same in a row and an interface read', () => {
		netifd_patch({ lan: LAN, wan: WAN, wan6: WAN6 });

		const wan = { Name: 'wan', Enable: 'true', Upstream: 'true',
			IPv6Prefix: { '1': { Enable: 'true', ParentPrefix: 'x' } } };

		let prefix = prefix_get({ instance: 1, config: wan.IPv6Prefix['1'], parent: wan });
		assert.match(near([ 'Preferred', 1800, 3600 ]), lifetimes(prefix), 'IPv6Prefix: row read');
		let wan_tree = iface_get({ config: wan, instance: 2 });
		assert.match(near([ 'Preferred', 1800, 3600 ]), lifetimes(wan_tree.IPv6Prefix?.['1']), 'IPv6Prefix: interface read');
	});
});

// lo has the MTU 65536, above the TR-181 range of MaxMTUSize.
describe('IP.Interface MaxMTUSize', () => {
	beforeEach(() => state_clear());

	it('reads back a configured value, else the MTU in use within the TR-181 range', () => {
		netifd_patch({ lan: LAN, wan: WAN, wan6: WAN6, lo: { up: true, l3_device: 'lo' } });

		assert.match('1492', iface_get({ config: { Name: 'lo', MaxMTUSize: '1492' }, instance: 3 }).MaxMTUSize);
		assert.match('65535', iface_get({ config: { Name: 'lo', MaxMTUSize: '0' }, instance: 3 }).MaxMTUSize);
		assert.match('65535', iface_get({ config: { Name: 'lo' }, instance: 3 }).MaxMTUSize);
	});
});
