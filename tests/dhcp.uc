// Host test of the StaticAddress states in dhcp.c of ubbf.so
// (Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.Status).
'use strict';

import { describe, it, assert } from 'utest';
import { static_address_states } from 'ubbf';

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

describe('DHCPv4 StaticAddress Status', () => {
	it('is Active for an enabled row and Disabled for a disabled one', () => {
		let s = static_address_states(root_make('true', {
			'1': row('true', '02:00:00:00:00:01', '192.168.1.10'),
			'2': row('false', '02:00:00:00:00:02', '192.168.1.11')
		}));
		assert.match('Active', s['1']['1']);
		assert.match('Disabled', s['1']['2']);
	});

	it('is Disabled for a row of a disabled pool', () => {
		let s = static_address_states(root_make('false', { '1': row('true', '02:00:00:00:00:01', '192.168.1.10') }));
		assert.match('Disabled', s['1']['1']);
	});

	it('is Error_Misconfigured for a bad MAC or address', () => {
		let s = static_address_states(root_make('true', {
			'1': row('true', '02:00:00:00:00:1', '192.168.1.10'),
			'2': row('true', '02:00:00:00:00:02', '192.168.1.300'),
			'3': row('true', '02:00:00:00:00:03', '192.168.2.10'),
			'4': row('true', '02:00:00:00:00:04', '192.168.1.0'),
			'5': row('true', '02:00:00:00:00:05', '192.168.1.255'),
			'6': row('true', '', '')
		}));
		assert.match('Error_Misconfigured', s['1']['1'], 'short MAC');
		assert.match('Error_Misconfigured', s['1']['2'], 'bad IPv4');
		assert.match('Error_Misconfigured', s['1']['3'], 'outside the pool subnet');
		assert.match('Error_Misconfigured', s['1']['4'], 'network address');
		assert.match('Error_Misconfigured', s['1']['5'], 'broadcast address');
		assert.match('Error_Misconfigured', s['1']['6'], 'empty row');
	});

	it('is Error_Misconfigured for an address with leading zeros', () => {
		let s = static_address_states(root_make('true', { '1': row('true', '02:00:00:00:00:01', '192.168.001.010') }));
		assert.match('Error_Misconfigured', s['1']['1']);
	});

	it('is Error_DuplicateAddress for enabled rows with the same Yiaddr or Chaddr', () => {
		let s = static_address_states(root_make('true', {
			'1': row('true', '02:00:00:00:00:01', '192.168.1.10'),
			'2': row('true', '02:00:00:00:00:02', '192.168.1.10'),
			'3': row('true', '02:00:00:00:00:0A', '192.168.1.20'),
			'4': row('true', '02:00:00:00:00:0a', '192.168.1.21'),
			'5': row('false', '02:00:00:00:00:05', '192.168.1.20'),
			'6': row('true', '02:00:00:00:00:06', '192.168.1.30')
		}));
		assert.match('Error_DuplicateAddress', s['1']['1'], 'same Yiaddr, first row');
		assert.match('Error_DuplicateAddress', s['1']['2'], 'same Yiaddr, second row');
		assert.match('Error_DuplicateAddress', s['1']['3'], 'same Chaddr in other case, first row');
		assert.match('Error_DuplicateAddress', s['1']['4'], 'same Chaddr in other case, second row');
		assert.match('Disabled', s['1']['5'], 'disabled row is no duplicate');
		assert.match('Active', s['1']['6'], 'unrelated row stays active');
	});

	it('is Error_DuplicateAddress for the same Chaddr in two pools', () => {
		let s = static_address_states(root_make('true',
			{ '1': row('true', '02:00:00:00:00:01', '192.168.1.10') },
			{ '1': row('true', '02:00:00:00:00:01', '10.0.0.5') }));
		assert.match('Error_DuplicateAddress', s['1']['1']);
		assert.match('Error_DuplicateAddress', s['2']['1']);
	});

	it('gives no states without pools', () => {
		assert.match({}, static_address_states({}));
	});
});
