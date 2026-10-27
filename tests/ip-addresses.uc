// Host test of the numbering of Device.IP.Interface.{i}.IPv4Address,
// IPv6Address and IPv6Prefix in tr181/IP.uc: a stored row keeps its number
// and its address whatever order netifd reports, and the other addresses
// follow the stored rows. tests/ip/ holds stand-ins for ubus (netifd
// status) and rtnl, tests/hosts/ one for udebug:
//   ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/ip-addresses.uc
'use strict';

import { model } from 'ubbf.tr181.IP';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const iface_get = model['Device.IP.Interface.{i}'].get;
const ipv4_get = model['Device.IP.Interface.{i}.IPv4Address.{i}'].get;
const ipv6_get = model['Device.IP.Interface.{i}.IPv6Address.{i}'].get;
const prefix_get = model['Device.IP.Interface.{i}.IPv6Prefix.{i}'].get;

function addresses(rows) {
	let out = {};
	for (let n, row in rows ?? {})
		out[n] = row.IPAddress ?? row.Prefix;
	return out;
}

const LEASE = { address: '2001:db8:100::1000', mask: 128, preferred: 1000, valid: 3000 };
const SLAAC = { address: '2001:db8:100:0:74e8:40ff:fe40:be02', mask: 64, preferred: 14000, valid: 86000 };
const PD = { address: '2001:db8:200::', mask: 60, preferred: 1000, valid: 3000 };

const wan = {
	Name: 'wan', Upstream: 'true', Enable: 'true',
	IPv4Address: { '1': { Enable: 'true', Alias: 'WanIPv4', IPAddress: '', AddressingType: 'DHCP' } },
	IPv6Address: { '1': { Enable: 'true', Alias: 'WanIPv6', IPAddress: '', Origin: 'DHCPv6' } }
};

global.netifd = {
	wan: { up: true, device: 'eth1', 'ipv4-address': [ { address: '172.16.100.2', mask: 24 } ] },
	wan6: { up: true, 'ipv6-address': [ LEASE, SLAAC ], 'ipv6-prefix': [ PD ] }
};

let r = iface_get({ config: wan, instance: 1 });
check('WAN DHCP row takes the lease', addresses(r.IPv4Address), { '1': '172.16.100.2' });
check('WAN DHCPv6 row takes the lease, SLAAC follows', addresses(r.IPv6Address), { '1': LEASE.address, '2': SLAAC.address });
check('WAN count', r.IPv6AddressNumberOfEntries, '2');
check('WAN PD prefix', addresses(r.IPv6Prefix), { '1': '2001:db8:200::/60' });
check('per-row DHCP read', ipv4_get({ config: wan.IPv4Address['1'], parent: wan, instance: 1 }).IPAddress, '172.16.100.2');
check('per-row DHCPv6 read', ipv6_get({ config: wan.IPv6Address['1'], parent: wan, instance: 1 }).IPAddress, LEASE.address);
check('per-row PD read', prefix_get({ parent: wan, instance: 1 }).Prefix, '2001:db8:200::/60');

global.netifd.wan6['ipv6-address'] = [ SLAAC, LEASE ];
r = iface_get({ config: wan, instance: 1 });
check('netifd order does not move the lease', addresses(r.IPv6Address), { '1': LEASE.address, '2': SLAAC.address });

// A lease outage: the SLAAC address does not take the DHCPv6 row.
global.netifd.wan6['ipv6-address'] = [ SLAAC ];
r = iface_get({ config: wan, instance: 1 });
check('without a lease the SLAAC address keeps its number', addresses(r.IPv6Address), { '2': SLAAC.address });
check('without a lease the DHCPv6 row is Invalid',
	ipv6_get({ config: wan.IPv6Address['1'], parent: wan, instance: 1 }).IPAddressStatus, 'Invalid');

const lan = {
	Name: 'lan', Upstream: 'false', Enable: 'true',
	IPv4Address: { '1': { Enable: 'true', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0', AddressingType: 'Static' } },
	IPv6Address: { '2': { Enable: 'true', IPAddress: '2001:db8:5::1', Origin: 'Static' } },
	IPv6Prefix: { '1': { Enable: 'true', ParentPrefix: 'Device.IP.Interface.1.IPv6Prefix.1', ChildPrefixBits: '64' } }
};

global.netifd.lan = {
	up: true, device: 'br-lan',
	'ipv4-address': [ { address: '192.168.1.2', mask: 24 }, { address: '192.168.1.1', mask: 24 } ],
	'ipv6-address': [ { address: '2001:db8:5:0::1', mask: 64 } ],
	'ipv6-prefix-assignment': [ {
		address: '2001:db8:200::', mask: 64, preferred: 1000, valid: 3000,
		'local-address': { address: '2001:db8:200::1', mask: 64 }
	} ]
};

r = iface_get({ config: lan, instance: 2 });
check('static row keeps its address listed second', addresses(r.IPv4Address), { '1': '192.168.1.1', '2': '192.168.1.2' });
check('static IPv6 row matches another spelling, found address follows row 2',
	addresses(r.IPv6Address), { '2': '2001:db8:5:0::1', '3': '2001:db8:200::1' });
check('found PD address is Child', r.IPv6Address['3'].Origin, 'Child');
check('per-row static read', ipv4_get({ config: lan.IPv4Address['1'], parent: lan, instance: 1 }).IPAddress, '192.168.1.1');
check('Child prefix row reads its assignment',
	prefix_get({ config: lan.IPv6Prefix['1'], parent: lan, instance: 1 }).Prefix, '2001:db8:200::/64');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
