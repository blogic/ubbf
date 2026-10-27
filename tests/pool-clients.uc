// Host test of the instance numbers of Device.DHCPv4.Server.Pool.{i}.Client
// and Device.DHCPv6.Server.Pool.{i}.Client in tr181/DHCPv4.uc and
// tr181/DHCPv6.uc: a client keeps its number across renewals while other
// clients come and go. The DHCPv4 leases come from /tmp/dhcp.leases, the
// odhcpd leases and the netifd status from a ubus mock, and the instance
// map lives in /tmp/ubbf.
'use strict';

import { describe, it, assert, beforeEach, setup, mock } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import * as fs from 'fs';
import * as uloop from 'uloop';
import { model as v4 } from 'ubbf.tr181.DHCPv4';
import { model as v6 } from 'ubbf.tr181.DHCPv6';
import { instance_map_own } from 'ubbf';

const pool = { Enable: 'true', MinAddress: '192.168.1.100', MaxAddress: '192.168.1.200' };
const v4_pool = v4['Device.DHCPv4.Server.Pool.{i}'].get;
const v4_client = v4['Device.DHCPv4.Server.Pool.{i}.Client.{i}'].get;

const v6_pool_cfg = { Enable: 'true', Interface: 'Device.IP.Interface.2' };
const root = { Device: { IP: { Interface: { '2': { Name: 'lan' } } } } };
const v6_pool = v6['Device.DHCPv6.Server.Pool.{i}'].get;
const v6_client = v6['Device.DHCPv6.Server.Pool.{i}.Client.{i}'].get;

function leases_write(list) {
	fs.writefile('/tmp/dhcp.leases', join('', map(list, (l) => sprintf('%d %s %s host *\n', l[0], l[1], l[2]))));
}

function by_number(rows, field) {
	let out = {};
	for (let n in sort(keys(rows ?? {}), (a, b) => +a - +b))
		out[n] = rows[n][field];
	return out;
}

function chaddrs(rows) {
	return by_number(rows, 'Chaddr');
}

function addresses(rows) {
	let out = {};
	for (let n in sort(keys(rows ?? {}), (a, b) => +a - +b))
		out[n] = rows[n].IPv4Address['1'].IPAddress;
	return out;
}

function v6_leases(duids) {
	netifd_patch({ lan: { up: true, l3_device: 'br-lan' } }, { 'dhcp:ipv6leases': { device: { 'br-lan': {
		leases: map(duids, (d) => ({
			duid: d, mac: null, 'ipv6-addr': [ { address: '2001:db8::' + d } ], 'ipv6-prefix': []
		}))
	} } } });
}

function v6_addresses(rows) {
	return by_number(rows, 'SourceAddress');
}

// ubbf.cache_call() keeps the odhcpd leases for 2 s of event loop time.
function cache_expire() {
	uloop.init();
	uloop.timer(2100, () => uloop.end());
	uloop.run();
}

// This process numbers rows, as the agent does.
setup(() => instance_map_own(true));

describe('DHCP Server Pool Client numbers', () => {
	beforeEach(() => {
		state_clear();
		fs.unlink('/tmp/dhcp.leases');
		mock.global.patch('uci', { data: {} });
		netifd_patch({});
	});

	it('keeps a DHCPv4 client on its number across renewals while others come and go', () => {
		let now = time();
		leases_write([ [ now + 100, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 200, '02:00:00:00:00:0B', '192.168.1.111' ] ]);
		assert.match({ '1': '02:00:00:00:00:0B', '2': '02:00:00:00:00:0A' }, chaddrs(v4_pool({ config: pool, instance: 1 }).Client),
			'first numbers');

		// A renewal moves the client to the top of the expiry order.
		leases_write([ [ now + 900, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 200, '02:00:00:00:00:0B', '192.168.1.111' ] ]);
		assert.match({ '1': '02:00:00:00:00:0B', '2': '02:00:00:00:00:0A' }, chaddrs(v4_client({ parent: pool, instances: [ 1 ] })),
			'a renewal keeps the numbers');
		assert.match('02:00:00:00:00:0A', v4_client({ parent: pool, instances: [ 1, 2 ], instance: 2 }).Chaddr,
			'one client by number');

		leases_write([ [ now + 900, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 300, '02:00:00:00:00:0C', '192.168.1.112' ] ]);
		let rows = v4_pool({ config: pool, instance: 1 });
		assert.match({ '2': '02:00:00:00:00:0A', '3': '02:00:00:00:00:0C' }, chaddrs(rows.Client),
			'a leaving client does not shift the other, a new one gets a new number');
		assert.match('2', rows.ClientNumberOfEntries, 'count');
		assert.match([ '1', '2' ], keys(v4_pool({ config: pool, instance: 2 }).Client), 'another pool has its own numbers');
	});

	// One client with two leases: a renewal that changes their expiry order
	// keeps each address on its number.
	it('keeps each address of a DHCPv4 client with two leases on its number', () => {
		let now = time();
		leases_write([ [ now + 100, '02:00:00:00:00:0D', '192.168.1.120' ], [ now + 200, '02:00:00:00:00:0D', '192.168.1.121' ] ]);
		let two_leases = addresses(v4_pool({ config: pool, instance: 3 }).Client);
		leases_write([ [ now + 900, '02:00:00:00:00:0D', '192.168.1.120' ], [ now + 200, '02:00:00:00:00:0D', '192.168.1.121' ] ]);
		assert.match(two_leases, addresses(v4_pool({ config: pool, instance: 3 }).Client));
	});

	it('keeps a DHCPv6 client on its number while others come and go', () => {
		v6_leases([ 'a1', 'b2' ]);
		assert.match({ '1': '2001:db8::a1', '2': '2001:db8::b2' }, v6_addresses(v6_pool({ config: v6_pool_cfg, instance: 1, root }).Client),
			'DHCPv6 first numbers');

		v6_leases([ 'b2', 'c3' ]);
		cache_expire();
		assert.match({ '2': '2001:db8::b2', '3': '2001:db8::c3' },
			v6_addresses(v6_client({ parent: v6_pool_cfg, instances: [ 1 ], root })), 'DHCPv6 a leaving client does not shift the other');
		assert.match('2001:db8::c3', v6_client({ parent: v6_pool_cfg, instances: [ 1, 3 ], instance: 3, root }).SourceAddress,
			'DHCPv6 one client by number');
	});
});
