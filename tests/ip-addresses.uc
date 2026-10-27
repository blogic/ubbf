// Host test of the numbering of Device.IP.Interface.{i}.IPv4Address,
// IPv6Address and IPv6Prefix in tr181/IP.uc: a stored row keeps its number
// and its address whatever order netifd reports, and the other addresses
// follow the stored rows. The netifd status comes from a ubus mock.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import { model } from 'ubbf.tr181.IP';

// Answers network.interface.<name> status from an interface name to status
// map.
function netifd_set(netifd) {
	mock.global.patch('ubus', { behavior: { call: (object, method) => {
		let m = match(object, /^network\.interface\.(.+)$/);
		return (m && method == 'status') ? netifd[m[1]] : null;
	} } });
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

function wan_netifd(ipv6) {
	return {
		wan: { up: true, device: 'eth1', 'ipv4-address': [ { address: '172.16.100.2', mask: 24 } ] },
		wan6: { up: true, 'ipv6-address': ipv6, 'ipv6-prefix': [ PD ] }
	};
}

const lan = {
	Name: 'lan', Upstream: 'false', Enable: 'true',
	IPv4Address: { '1': { Enable: 'true', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0', AddressingType: 'Static' } },
	IPv6Address: { '2': { Enable: 'true', IPAddress: '2001:db8:5::1', Origin: 'Static' } },
	IPv6Prefix: { '1': { Enable: 'true', ParentPrefix: 'Device.IP.Interface.1.IPv6Prefix.1', ChildPrefixBits: '64' } }
};

const lan_netifd = {
	...wan_netifd([ LEASE, SLAAC ]),
	lan: {
		up: true, device: 'br-lan',
		'ipv4-address': [ { address: '192.168.1.2', mask: 24 }, { address: '192.168.1.1', mask: 24 } ],
		'ipv6-address': [ { address: '2001:db8:5:0::1', mask: 64 } ],
		'ipv6-prefix-assignment': [ {
			address: '2001:db8:200::', mask: 64, preferred: 1000, valid: 3000,
			'local-address': { address: '2001:db8:200::1', mask: 64 }
		} ]
	}
};

describe('IP.Interface address numbering', () => {
	beforeEach(() => state_clear());

	it('gives the WAN rows the DHCP and DHCPv6 leases', () => {
		netifd_set(wan_netifd([ LEASE, SLAAC ]));

		let r = iface_get({ config: wan, instance: 1 });
		assert.match({ '1': '172.16.100.2' }, addresses(r.IPv4Address));
		assert.match({ '1': LEASE.address, '2': SLAAC.address }, addresses(r.IPv6Address));
		assert.match('2', r.IPv6AddressNumberOfEntries);
		assert.match({ '1': '2001:db8:200::/60' }, addresses(r.IPv6Prefix));
		assert.match('172.16.100.2', ipv4_get({ config: wan.IPv4Address['1'], parent: wan, instance: 1 }).IPAddress);
		assert.match(LEASE.address, ipv6_get({ config: wan.IPv6Address['1'], parent: wan, instance: 1 }).IPAddress);
		assert.match('2001:db8:200::/60', prefix_get({ parent: wan, instance: 1 }).Prefix);
	});

	it('keeps the numbers when netifd reorders or loses the lease', () => {
		netifd_set(wan_netifd([ LEASE, SLAAC ]));
		iface_get({ config: wan, instance: 1 });

		netifd_set(wan_netifd([ SLAAC, LEASE ]));
		let r = iface_get({ config: wan, instance: 1 });
		assert.match({ '1': LEASE.address, '2': SLAAC.address }, addresses(r.IPv6Address), 'netifd order does not move the lease');

		// A lease outage: the SLAAC address does not take the DHCPv6 row.
		netifd_set(wan_netifd([ SLAAC ]));
		r = iface_get({ config: wan, instance: 1 });
		assert.match({ '2': SLAAC.address }, addresses(r.IPv6Address));
		assert.match('Invalid', ipv6_get({ config: wan.IPv6Address['1'], parent: wan, instance: 1 }).IPAddressStatus);
	});

	it('keeps the stored LAN rows and numbers the found addresses after them', () => {
		netifd_set(lan_netifd);

		let r = iface_get({ config: lan, instance: 2 });
		assert.match({ '1': '192.168.1.1', '2': '192.168.1.2' }, addresses(r.IPv4Address));
		assert.match({ '2': '2001:db8:5:0::1', '3': '2001:db8:200::1' }, addresses(r.IPv6Address));
		assert.match('Child', r.IPv6Address['3'].Origin);
		assert.match('192.168.1.1', ipv4_get({ config: lan.IPv4Address['1'], parent: lan, instance: 1 }).IPAddress);
		assert.match('2001:db8:200::/64', prefix_get({ config: lan.IPv6Prefix['1'], parent: lan, instance: 1 }).Prefix);
	});
});
