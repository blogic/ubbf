// Host test of the IPv4 address render in render/templates/ip.uc: every
// enabled static IPv4Address row of an interface reaches netifd, which
// reads ipaddr as a list.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';

const TEMPLATE = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/ip.uc';

function render(addresses) {
	let config = { Device: { IP: {
		IPv4Enable: 'true',
		Interface: { '1': { Enable: 'true', Name: 'lan', IPv4Enable: 'true', IPv4Address: addresses } }
	} } };
	let output = [];

	include(TEMPLATE, { ...h, output, config, ubbf, render_state: {},
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		lower_layer_resolve_vlan: () => null, device_state_set: () => null });

	return {
		proto: map(filter(output, (l) => match(l, /^set network\.lan\.proto=/)), (l) => split(l, '=')[1]),
		ipaddr: map(filter(output, (l) => match(l, /network\.lan\.ipaddr=/)), (l) => l)
	};
}

describe('IPv4 address render', () => {
	it('lists every enabled static address on a static interface', () => {
		let two = render({
			'1': { Enable: 'true', AddressingType: 'Static', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0' },
			'2': { Enable: 'true', AddressingType: 'Static', IPAddress: '10.0.0.1', SubnetMask: '255.0.0.0' },
			'3': { Enable: 'false', AddressingType: 'Static', IPAddress: '172.16.0.1', SubnetMask: '255.255.0.0' }
		});
		assert.match([
			"add_list network.lan.ipaddr='192.168.1.1/24'",
			"add_list network.lan.ipaddr='10.0.0.1/8'"
		], two.ipaddr);
		assert.match([ "'static'" ], two.proto);
	});

	it('renders one address as a list of one', () => {
		let one = render({ '1': { Enable: 'true', AddressingType: 'Static', IPAddress: '192.168.1.1', SubnetMask: '255.255.255.0' } });
		assert.match([ "add_list network.lan.ipaddr='192.168.1.1/24'" ], one.ipaddr);
	});
});
