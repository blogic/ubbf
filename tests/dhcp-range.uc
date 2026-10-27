// Host test of the DHCPv4 pool split around ReservedAddresses in
// render/templates/dhcp.uc: the segments between the reserved addresses,
// with the work bound by the number of reservations, not the pool size.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { generate } from 'ubbf.render.renderer';

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

describe('DHCPv4 pool split around ReservedAddresses', () => {
	beforeEach(() => mock.global.patch('uci', { data: {} }));

	it('gives one segment without a reservation', () => {
		assert.match([ 100, 150 ], ranges('10.0.0.100', '10.0.0.249', ''));
	});

	it('splits the pool around a reservation inside it', () => {
		assert.match([ 100, 50, 151, 99 ], ranges('10.0.0.100', '10.0.0.249', '10.0.0.150'));
	});

	it('ignores duplicates and skips the first address', () => {
		assert.match([ 101, 49, 151, 99 ],
			ranges('10.0.0.100', '10.0.0.249', '10.0.0.150,10.0.0.150,10.0.0.100'));
	});

	it('skips the last address', () => {
		assert.match([ 100, 149 ], ranges('10.0.0.100', '10.0.0.249', '10.0.0.249'));
	});

	it('ignores reservations outside the pool', () => {
		assert.match([ 100, 150 ], ranges('10.0.0.100', '10.0.0.249', '10.0.0.50,10.0.1.1'));
	});

	it('splits a /8 pool with one reservation in under a second', () => {
		let t0 = clock(true);
		let big = ranges('10.0.0.1', '10.255.255.254', '10.1.2.3');
		let t1 = clock(true);
		assert.match(4, length(big), 'a /8 pool with one reservation gives two segments');
		assert.match(true, (t1[0] - t0[0]) + (t1[1] - t0[1]) / 1e9 < 1, 'a /8 pool renders in under a second');
	});
});
