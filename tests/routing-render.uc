// Host test of the render of Device.Routing (render/templates/routing.uc):
// a route of Router.1 goes to the main table without a table option, a
// route of Router.2 to table 101, and a route with a source to a source
// table with an ip rule.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { generate } from 'ubbf.render.renderer';

const config = { Device: {
	IP: { Interface: { '1': { Enable: 'true', Name: 'wan', Upstream: 'true' }, '2': { Enable: 'true', Name: 'lan' } } },
	Routing: { Router: {
		'1': { Enable: 'true', IPv4Forwarding: {
			'1': { Enable: 'true', DestIPAddress: '10.1.0.0', DestSubnetMask: '255.255.0.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' },
			'2': { Enable: 'true', DestIPAddress: '10.2.0.0', DestSubnetMask: '255.255.0.0',
			       SourceIPAddress: '192.168.1.0', SourceSubnetMask: '255.255.255.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' } } },
		'2': { Enable: 'true', IPv4Forwarding: {
			'1': { Enable: 'true', DestIPAddress: '10.3.0.0', DestSubnetMask: '255.255.0.0',
			       GatewayIPAddress: '192.0.2.1', Interface: 'Device.IP.Interface.1' } } }
	} }
} };

function sections(uci, type) {
	let out = [], cur;
	for (let line in split(uci, '\n')) {
		if (match(line, regexp(`^add network ${type}$`))) {
			cur = {};
			push(out, cur);
			continue;
		}
		let m = match(line, regexp(`^set network\\.@${type}\\[-1\\]\\.([a-z0-9_]+)='?([^']*)'?$`));
		if (cur && m)
			cur[m[1]] = m[2];
		else if (!match(line, /^set network\.@/))
			cur = null;
	}
	return out;
}

function uci_render() {
	return generate(config, [], true).uci;
}

function routes_by_target() {
	let by_target = {};
	for (let r in sections(uci_render(), 'route'))
		by_target[r.target] = r;
	return by_target;
}

describe('Device.Routing render', () => {
	beforeEach(() => mock.global.patch('uci', { data: {} }));

	it('puts a route of Router.1 in the main table without a table option', () => {
		let by_target = routes_by_target();
		assert.match([ '255.255.0.0', null ], [ by_target['10.1.0.0']?.netmask, by_target['10.1.0.0']?.table ]);
	});

	it('puts a route of Router.2 in table 101', () => {
		assert.match('101', routes_by_target()['10.3.0.0']?.table);
	});

	it('puts a route with a source in a source table', () => {
		assert.match('200', routes_by_target()['10.2.0.0']?.table);
	});

	it('adds an ip rule to the source table', () => {
		let rules = sections(uci_render(), 'rule');
		assert.match(1, length(filter(rules, (r) => r.src == '192.168.1.0/24' && r.lookup == '200')));
	});
});
