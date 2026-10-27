// Host test of the learned rows of Device.DNS.Client.Server and
// Device.DNS.Relay.Forwarding in tr181/DNS.uc: stable instance numbers
// after the stored rows, a writable Enable, read-only DNSServer and
// Interface, and the render of render/templates/dns.uc. The netifd status
// comes from a ubus mock.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import * as dns from 'ubbf.utils.dns';
import { dns_relay_plan } from 'ubbf.render.ubbf_helpers';
import { model } from 'ubbf.tr181.DNS';
import * as dns_filter from 'ubbf.device.dns-filter';
import { config_pins_take, instance_map_own } from 'ubbf';

// This process numbers rows, as the agent does.
instance_map_own(true);

const TEMPLATE = '/usr/share/ucode/ubbf/render/templates/dns.uc';

const server = model['Device.DNS.Client.Server.{i}'];
const forwarding = model['Device.DNS.Relay.Forwarding.{i}'];
const relay = model['Device.DNS.Relay'];

let netifd;

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

const STATIC_FWD = { '3': { Enable: 'true', DNSServer: '192.0.2.53', Interface: '', Type: 'Static' } };
const LEARNED_FWD = { Enable: 'false', Type: 'DHCPv4', Interface: 'Device.IP.Interface.1', DNSServer: '172.16.100.1' };

function template_render(config) {
	let output = [];

	include(TEMPLATE, { ...h, ...dns, output, config, ubbf, dns_learned_row: ubbf.dns_learned_row,
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		interface_to_name: ubbf.interface_to_name, dns_relay_plan,
		services: { set_enabled: () => null } });

	return output;
}

function render(servers, forwardings) {
	let output = template_render({ Device: {
		IP: { Interface: { '1': { Name: 'wan', Upstream: 'true' }, '2': { Name: 'lan', Upstream: 'false' } } },
		DNS: {
			Client: { Enable: 'true', Server: servers },
			Relay: { Enable: 'true', Forwarding: forwardings ?? {} }
		}
	} });

	return filter(output, (l) => match(l, /dns_localhost\.(server|resolvfile|localuse)|dns_relay_/));
}

function relay_render(relay) {
	let output = template_render({ Device: {
		Ethernet: { Link: { '1': { Name: 'wan' } } },
		IP: { Interface: {
			'1': { Name: 'wan', Upstream: 'true', LowerLayers: 'Device.Ethernet.Link.1' },
			'2': { Name: 'lan', Upstream: 'false' },
			'3': { Name: 'guest', Upstream: 'false' }
		} },
		DNS: { Client: { Enable: 'true' }, Relay: { Enable: 'true', ...relay } }
	} });

	return filter(output, (l) => match(l, /dns_relay_[a-z]+\.(port|server)/));
}

const FWD = {
	'1': { Enable: 'true', DNSServer: '192.0.2.1', Interface: 'Device.IP.Interface.1', Type: 'Static' },
	'2': { Enable: 'true', DNSServer: '192.0.2.2', Interface: '', Type: 'Static' }
};

describe('DNS learned rows', () => {
	beforeEach(() => {
		state_clear();
		netifd = {
			wan: { proto: 'dhcp', 'dns-server': [ '172.16.100.1' ] },
			wan6: { proto: 'dhcpv6', 'dns-server': [ '2001:db8:100::1' ] }
		};
		netifd_patch(netifd);
	});

	it('numbers the learned servers after the stored rows and keeps DNSServer and Interface read-only', () => {
		// The map starts empty, as after a reboot; the pin of config.json gives
		// the stored learned row its number back.
		config_pins_take({ _instances: { 'Device.DNS.Client.Server': { '5': 'DHCPv4|Device.IP.Interface.1|172.16.100.1' } } });
		let stored = learned('false');
		let root = root_make({ '5': stored });
		assert.match({ '5': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 false Disabled' },
			fields({ '5': server.get({ instance: 5, config: stored, root }) }),
			'after a reboot a stored learned row keeps its number');
		assert.match([ '6' ], keys(server.get({ root })), 'a new learned server takes a number after the stored ones');

		assert.match({
			'5': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 true Enabled',
			'6': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled'
		}, fields(server.get({ root: root_make(STATIC) })), 'the learned servers keep their numbers next to a Static row');

		netifd.wan['dns-server'] = [];
		netifd_patch(netifd);
		assert.match({ '6': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled' },
			fields(server.get({ root: root_make(STATIC) })), 'a server keeps its number when another one goes');
		assert.match('Disabled',
			server.get({ instance: 5, config: learned('true'), root: root_make({ '5': learned('true') }) }).Status,
			'a stored learned row whose server is gone reads Disabled');
		netifd.wan['dns-server'] = [ '172.16.100.1' ];
		netifd_patch(netifd);

		let row = { Enable: 'false' };
		root = root_make({ ...STATIC, '5': row });
		assert.match(0, server.set({ instance: 5, param: 'Enable', value: 'false', config: row, root }),
			'a write of Enable into a learned row is taken');
		assert.match(learned('false'), row, 'the first write stores the key of the learned row');

		assert.match(-USP_ERR_PARAM_READ_ONLY,
			server.set({ instance: 5, param: 'DNSServer', value: '192.0.2.1', config: row, root }),
			'DNSServer of a learned row is read-only');
		assert.match(-USP_ERR_PARAM_READ_ONLY,
			server.set({ instance: 5, param: 'Interface', value: '', config: row, root }),
			'Interface of a learned row is read-only');
		assert.match(0, server.set({ instance: 1, param: 'DNSServer', value: '192.0.2.1', config: STATIC['1'], root }),
			'DNSServer of a Static row stays writable');

		assert.match([ '6' ], keys(server.get({ root })), 'the enumeration leaves out a stored learned row');
		assert.match({ '5': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 false Disabled' },
			fields({ '5': server.get({ instance: 5, config: row, root }) }),
			'the stored Enable applies over the learned one');
		assert.match({ '1': 'Static 8.8.8.8  true Enabled' },
			fields({ '1': server.get({ instance: 1, config: STATIC['1'], root }) }),
			'a Static row reads its stored values');
	});

	it('numbers the learned forwarders from 1 and counts them with the Static ones', () => {
		assert.match({
			'1': 'DHCPv4 172.16.100.1 Device.IP.Interface.1 true Enabled',
			'2': 'DHCPv6 2001:db8:100::1 Device.IP.Interface.1 true Enabled'
		}, fields(forwarding.get({ root: root_make() })), 'the learned forwarders without stored rows start at 1');

		// A Static forwarder that a controller adds after them takes the next
		// number of the map, 3.
		assert.match('3', relay.get({ config: { Forwarding: STATIC_FWD }, root: root_make() }).ForwardNumberOfEntries,
			'ForwardNumberOfEntries counts the Static and the learned forwarders');
		assert.match('3',
			relay.get({ config: { Forwarding: { ...STATIC_FWD, '1': LEARNED_FWD } }, root: root_make() }).ForwardNumberOfEntries,
			'a stored learned forwarder is counted once');
	});
});

describe('DNS render of the learned servers', () => {
	beforeEach(() => {
		state_clear();
		netifd = {
			wan: { proto: 'dhcp', 'dns-server': [ '172.16.100.1' ] },
			wan6: { proto: 'dhcpv6', 'dns-server': [ '2001:db8:100::1' ] }
		};
		netifd_patch(netifd);
	});

	it('makes dnsmasq read resolv.conf.auto without a disabled learned server', () => {
		assert.match([ `set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_AUTO}'` ], render({}));
	});

	it('makes dnsmasq read the filtered copy for a disabled learned server', () => {
		assert.match([
			`set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_FILTERED}'`,
			'set dhcp.dns_localhost.localuse=1'
		], render({ '5': learned('false') }));
	});

	it('replaces the learned servers with an enabled Static server', () => {
		assert.match([ "add_list dhcp.dns_localhost.server='8.8.8.8'" ], render({ ...STATIC, '5': learned('false') }));
	});

	it('does not make a stored learned forwarder a relay of its own', () => {
		assert.match([ `set dhcp.dns_localhost.resolvfile='${dns.DNS_RESOLV_AUTO}'` ], render({}, {
			'1': { Enable: 'true', Type: 'DHCPv4', Interface: 'Device.IP.Interface.1', DNSServer: '172.16.100.1' }
		}));
	});
});

describe('DNS relay render', () => {
	it('relays each downstream interface to every forwarder without Relay.Config', () => {
		assert.match([
			'set dhcp.dns_relay_lan.port=5301',
			"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
			"add_list dhcp.dns_relay_lan.server='192.0.2.2'",
			'set dhcp.dns_relay_guest.port=5302',
			"add_list dhcp.dns_relay_guest.server='192.0.2.1@wan'",
			"add_list dhcp.dns_relay_guest.server='192.0.2.2'"
		], relay_render({ Forwarding: FWD }));
	});

	it('serves the Interface of a Relay.Config row with its Forwarders', () => {
		assert.match([
			'set dhcp.dns_relay_lan.port=5301',
			"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
		], relay_render({ Forwarding: FWD, Config: {
			'1': { Interface: 'Device.IP.Interface.2', Forwarders: 'Device.DNS.Relay.Forwarding.2' }
		} }));
	});

	it('serves the interfaces that no other row names with a Relay.Config row without Interface', () => {
		assert.match([
			'set dhcp.dns_relay_guest.port=5301',
			"add_list dhcp.dns_relay_guest.server='192.0.2.1@wan'",
			'set dhcp.dns_relay_lan.port=5302',
			"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
			"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
		], relay_render({ Forwarding: FWD, Config: {
			'1': { Interface: '', Forwarders: '' },
			'2': { Interface: 'Device.IP.Interface.3', Forwarders: 'Device.DNS.Relay.Forwarding.1' }
		} }));
	});

	it('leaves out a forwarder whose Interface does not exist', () => {
		assert.match([
			'set dhcp.dns_relay_lan.port=5301',
			"add_list dhcp.dns_relay_lan.server='192.0.2.1@wan'",
			"add_list dhcp.dns_relay_lan.server='192.0.2.2'"
		], relay_render({ Forwarding: {
			...FWD, '3': { Enable: 'true', DNSServer: '192.0.2.3', Interface: 'Device.IP.Interface.999', Type: 'Static' }
		}, Config: { '1': { Interface: 'Device.IP.Interface.2', Forwarders: '' } } }));
	});

	it('renders no instance for a disabled relay', () => {
		assert.match([], relay_render({ Enable: 'false', Forwarding: FWD }));
	});
});

describe('device/dns-filter.uc', () => {
	it('compiles', () => {
		assert.match('function', type(dns_filter.init));
	});
});
