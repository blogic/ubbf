// Host test of the instance numbers of Device.DHCPv4.Server.Pool.{i}.Client
// and Device.DHCPv6.Server.Pool.{i}.Client in tr181/DHCPv4.uc and
// tr181/DHCPv6.uc: a client keeps its number across renewals while other
// clients come and go. The leases come from /tmp/dhcp.leases and the
// instance map lives in /tmp/ubbf, so run it in a private mount namespace;
// tests/ip/ holds a stand-in for ubus, tests/render/ one for uci,
// tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && \
//     ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/render/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/pool-clients.uc'
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import { model as v4 } from 'ubbf.tr181.DHCPv4';
import { model as v6 } from 'ubbf.tr181.DHCPv6';
import { instance_map_own } from 'ubbf';

// This process numbers rows, as the agent does.
instance_map_own(true);

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const pool = { Enable: 'true', MinAddress: '192.168.1.100', MaxAddress: '192.168.1.200' };
const v4_pool = v4['Device.DHCPv4.Server.Pool.{i}'].get;
const v4_client = v4['Device.DHCPv4.Server.Pool.{i}.Client.{i}'].get;

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

// ubbf.cache_call() keeps the odhcpd leases for 2 s of event loop time.
function cache_expire() {
	uloop.init();
	uloop.timer(2100, () => uloop.end());
	uloop.run();
}

let now = time();
leases_write([ [ now + 100, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 200, '02:00:00:00:00:0B', '192.168.1.111' ] ]);
check('first numbers', chaddrs(v4_pool({ config: pool, instance: 1 }).Client), { '1': '02:00:00:00:00:0B', '2': '02:00:00:00:00:0A' });

// A renewal moves the client to the top of the expiry order.
leases_write([ [ now + 900, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 200, '02:00:00:00:00:0B', '192.168.1.111' ] ]);
check('a renewal keeps the numbers', chaddrs(v4_client({ parent: pool, instances: [ 1 ] })), { '1': '02:00:00:00:00:0B', '2': '02:00:00:00:00:0A' });
check('one client by number', v4_client({ parent: pool, instances: [ 1, 2 ], instance: 2 }).Chaddr, '02:00:00:00:00:0A');

leases_write([ [ now + 900, '02:00:00:00:00:0A', '192.168.1.110' ], [ now + 300, '02:00:00:00:00:0C', '192.168.1.112' ] ]);
let rows = v4_pool({ config: pool, instance: 1 });
check('a leaving client does not shift the other, a new one gets a new number',
	chaddrs(rows.Client), { '2': '02:00:00:00:00:0A', '3': '02:00:00:00:00:0C' });
check('count', rows.ClientNumberOfEntries, '2');
check('another pool has its own numbers', keys(v4_pool({ config: pool, instance: 2 }).Client), [ '1', '2' ]);

function addresses(rows) {
	let out = {};
	for (let n in sort(keys(rows ?? {}), (a, b) => +a - +b))
		out[n] = rows[n].IPv4Address['1'].IPAddress;
	return out;
}

// One client with two leases: a renewal that changes their expiry order
// keeps each address on its number.
leases_write([ [ now + 100, '02:00:00:00:00:0D', '192.168.1.120' ], [ now + 200, '02:00:00:00:00:0D', '192.168.1.121' ] ]);
let two_leases = addresses(v4_pool({ config: pool, instance: 3 }).Client);
leases_write([ [ now + 900, '02:00:00:00:00:0D', '192.168.1.120' ], [ now + 200, '02:00:00:00:00:0D', '192.168.1.121' ] ]);
check('two leases keep their numbers', addresses(v4_pool({ config: pool, instance: 3 }).Client), two_leases);

global.netifd = { lan: { up: true, l3_device: 'br-lan' } };
const v6_pool_cfg = { Enable: 'true', Interface: 'Device.IP.Interface.2' };
const root = { Device: { IP: { Interface: { '2': { Name: 'lan' } } } } };
const v6_pool = v6['Device.DHCPv6.Server.Pool.{i}'].get;
const v6_client = v6['Device.DHCPv6.Server.Pool.{i}.Client.{i}'].get;

function v6_leases(duids) {
	global.ipv6leases = { device: { 'br-lan': { leases: map(duids, (d) => ({
		duid: d, mac: null, 'ipv6-addr': [ { address: '2001:db8::' + d } ], 'ipv6-prefix': []
	})) } } };
}

function v6_addresses(rows) {
	return by_number(rows, 'SourceAddress');
}

v6_leases([ 'a1', 'b2' ]);
check('DHCPv6 first numbers', v6_addresses(v6_pool({ config: v6_pool_cfg, instance: 1, root }).Client),
	{ '1': '2001:db8::a1', '2': '2001:db8::b2' });
v6_leases([ 'b2', 'c3' ]);
cache_expire();
check('DHCPv6 a leaving client does not shift the other',
	v6_addresses(v6_client({ parent: v6_pool_cfg, instances: [ 1 ], root })), { '2': '2001:db8::b2', '3': '2001:db8::c3' });
check('DHCPv6 one client by number', v6_client({ parent: v6_pool_cfg, instances: [ 1, 3 ], instance: 3, root }).SourceAddress, '2001:db8::c3');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
