// Host test of the learned rows of Device.DNS.Client.Server and
// Device.DNS.Relay.Forwarding in tr181/DNS.uc: stable instance numbers
// above DNS_LEARNED_BASE, a writable Enable, read-only DNSServer and
// Interface, and the render of render/templates/dns.uc. The instance map
// lives in /tmp/ubbf, so run it in a private mount namespace; tests/ip/
// holds a stand-in for ubus (netifd status), tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp/ubbf && \
//     ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/dns-learned.uc'
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import * as dns from 'ubbf.utils.dns';
import { dns_relay_plan } from 'ubbf.render.ubbf_helpers';
import { model } from 'ubbf.tr181.DNS';
import * as dns_filter from 'ubbf.device.dns-filter';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const TEMPLATE = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/dns.uc';

const server = model['Device.DNS.Client.Server.{i}'];
const forwarding = model['Device.DNS.Relay.Forwarding.{i}'];

function root_make(servers, forwardings) {
	return { Device: {
		IP: { Interface: {
			'1': { Name: 'wan', Upstream: 'true' },
			'2': { Name: 'lan', Upstream: 'false', IPv6Enable: 'true' }
		} },
		DNS: {
			Client: { Server: servers ?? {} },
			Relay: { Forwarding: forwardings ?? {} }
		}
	} };
}

function fields(rows) {
	let out = {};
	for (let n, row in rows)
		out[n] = sprintf('%s %s %s %s %s', row.Type, row.DNSServer, row.Interface ?? '', row.Enable, row.Status);
	return out;
}

function learned(enable) {
	return { Enable: enable, Type: 'DHCPv4', Interface: 'Device.IP.Interface.1', DNSServer: '172.16.100.1' };
}

const STATIC = { '1': { Enable: 'true', DNSServer: '8.8.8.8', Type: 'Static' } };

global.netifd = {
	wan: { proto: 'dhcp', 'dns-server': [ '172.16.100.1' ] },
	wan6: { proto: 'dhcpv6', 'dns-server': [ '2001:db8:100::1' ] }
};

// The volatile map starts empty, as after a reboot.
let stored = learned('false');
let root = root_make({ '10005': stored });
check('after a reboot a stored learned row keeps its number',
	fields({ '10005': server.get({ instance: 10005, config: stored, root }) }),
	{ '10005': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 false Disabled' });
check('a new learned server takes a number after the stored ones', keys(server.get({ root })), [ '10006' ]);

check('the learned servers are numbered above the base', fields(server.get({ root: root_make(STATIC) })), {
	'10005': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 true Enabled',
	'10006': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled'
});

global.netifd.wan['dns-server'] = [];
check('a server keeps its number when another one goes', fields(server.get({ root: root_make(STATIC) })), {
	'10006': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled'
});
check('a stored learned row whose server is gone reads Disabled',
	server.get({ instance: 10005, config: learned('true'), root: root_make({ '10005': learned('true') }) }).Status,
	'Disabled');
global.netifd.wan['dns-server'] = [ '172.16.100.1' ];

let row = { Enable: 'false' };
root = root_make({ ...STATIC, '10005': row });
check('a write of Enable into a learned row is taken',
	server.set({ instance: 10005, param: 'Enable', value: 'false', config: row, root }), 0);
check('the first write stores the key of the learned row', row, learned('false'));

check('DNSServer of a learned row is read-only',
	server.set({ instance: 10005, param: 'DNSServer', value: '192.0.2.1', config: row, root }),
	-USP_ERR_PARAM_READ_ONLY);
check('Interface of a learned row is read-only',
	server.set({ instance: 10005, param: 'Interface', value: '', config: row, root }),
	-USP_ERR_PARAM_READ_ONLY);
check('DNSServer of a Static row stays writable',
	server.set({ instance: 1, param: 'DNSServer', value: '192.0.2.1', config: STATIC['1'], root }), 0);

check('the enumeration leaves out a stored learned row', keys(server.get({ root })), [ '10006' ]);
check('the stored Enable applies over the learned one',
	fields({ '10005': server.get({ instance: 10005, config: row, root }) }),
	{ '10005': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 false Disabled' });
check('a Static row reads its stored values',
	fields({ '1': server.get({ instance: 1, config: STATIC['1'], root }) }),
	{ '1': 'Static 8.8.8.8  true Enabled' });

check('the learned forwarders are numbered above the base', fields(forwarding.get({ root: root_make() })), {
	'10001': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 true Enabled',
	'10002': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled'
});

const relay = model['Device.DNS.Relay'];
const STATIC_FWD = { '1': { Enable: 'true', DNSServer: '192.0.2.53', Interface: '', Type: 'Static' } };
const LEARNED_FWD = { Enable: 'false', Type: 'DHCPv4', Interface: 'Device.IP.Interface.1', DNSServer: '172.16.100.1' };

check('ForwardNumberOfEntries counts the Static and the learned forwarders',
	relay.get({ config: { Forwarding: STATIC_FWD }, root: root_make() }).ForwardNumberOfEntries, '3');
check('a stored learned forwarder is counted once',
	relay.get({ config: { Forwarding: { ...STATIC_FWD, '10001': LEARNED_FWD } }, root: root_make() }).ForwardNumberOfEntries,
	'3');

function render(servers, forwardings) {
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'wan', Upstream: 'true' }, '2': { Name: 'lan', Upstream: 'false' } } },
		DNS: {
			Client: { Enable: 'true', Server: servers },
			Relay: { Enable: 'true', Forwarding: forwardings ?? {} }
		}
	} };
	let output = [];

	include(TEMPLATE, { ...h, ...dns, output, config, ubbf,
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		interface_to_name: ubbf.interface_to_name, dns_relay_plan,
		services: { set_enabled: () => null } });

	return filter(output, (l) => match(l, /dns_localhost\.(server|resolvfile|localuse)|dns_relay_/));
}

check('without a disabled learned server dnsmasq reads resolv.conf.auto', render({}), [
	`set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_AUTO}'`
]);
check('a disabled learned server makes dnsmasq read the filtered copy', render({ '10005': learned('false') }), [
	`set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_FILTERED}'`,
	'set dhcp.dns_localhost.localuse=1'
]);
check('an enabled Static server replaces the learned ones', render({ ...STATIC, '10005': learned('false') }), [
	"add_list dhcp.dns_localhost.server='8.8.8.8'"
]);
check('a stored learned forwarder is not a relay of its own', render({}, {
	'10001': { Enable: 'true', Type: 'DHCPv4', Interface: 'Device.IP.Interface.1', DNSServer: '172.16.100.1' }
}), [
	`set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_AUTO}'`
]);

function relay_render(relay) {
	let config = { Device: {
		Ethernet: { Link: { '1': { Name: 'wan' } } },
		IP: { Interface: {
			'1': { Name: 'wan', Upstream: 'true', LowerLayers: 'Device.Ethernet.Link.1' },
			'2': { Name: 'lan', Upstream: 'false' },
			'3': { Name: 'guest', Upstream: 'false' }
		} },
		DNS: { Client: { Enable: 'true' }, Relay: { Enable: 'true', ...relay } }
	} };
	let output = [];

	include(TEMPLATE, { ...h, ...dns, output, config, ubbf,
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		interface_to_name: ubbf.interface_to_name, dns_relay_plan,
		services: { set_enabled: () => null } });

	return filter(output, (l) => match(l, /dns_relay_[a-z]+\.(port|server)/));
}

const FWD = {
	'1': { Enable: 'true', DNSServer: '192.0.2.1', Interface: 'Device.IP.Interface.1', Type: 'Static' },
	'2': { Enable: 'true', DNSServer: '192.0.2.2', Interface: '', Type: 'Static' }
};

check('without Relay.Config each downstream interface relays to every forwarder', relay_render({ Forwarding: FWD }), [
	'set dhcp.dns_relay_lan.port=5301',
	"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
	"add_list dhcp.dns_relay_lan.server='192.0.2.2'",
	'set dhcp.dns_relay_guest.port=5302',
	"add_list dhcp.dns_relay_guest.server='192.0.2.1@wan'",
	"add_list dhcp.dns_relay_guest.server='192.0.2.2'"
]);
check('a Relay.Config row serves its Interface with its Forwarders', relay_render({ Forwarding: FWD, Config: {
	'1': { Interface: 'Device.IP.Interface.2', Forwarders: 'Device.DNS.Relay.Forwarding.2' }
} }), [
	'set dhcp.dns_relay_lan.port=5301',
	"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
]);
check('a Relay.Config row without Interface serves the interfaces no other row names', relay_render({ Forwarding: FWD, Config: {
	'1': { Interface: '', Forwarders: '' },
	'2': { Interface: 'Device.IP.Interface.3', Forwarders: 'Device.DNS.Relay.Forwarding.1' }
} }), [
	'set dhcp.dns_relay_guest.port=5301',
	"add_list dhcp.dns_relay_guest.server='192.0.2.1@wan'",
	'set dhcp.dns_relay_lan.port=5302',
	"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
	"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
]);
check('a forwarder whose Interface does not exist is left out', relay_render({ Forwarding: {
	...FWD, '3': { Enable: 'true', DNSServer: '192.0.2.3', Interface: 'Device.IP.Interface.999', Type: 'Static' }
}, Config: { '1': { Interface: 'Device.IP.Interface.2', Forwarders: '' } } }), [
	'set dhcp.dns_relay_lan.port=5301',
	"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
	"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
]);
check('a disabled relay renders no instance', relay_render({ Enable: 'false', Forwarding: FWD }), []);

check('device/dns-filter.uc compiles', type(dns_filter.init), 'function');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
