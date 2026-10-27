// Host test of ip_interface_members() in ifstats.c of ubbf.so: the
// netdevs behind the LowerLayers of an IP.Interface.
'use strict';

import { describe, it, assert } from 'utest';
import { ip_interface_members } from 'ubbf';

const root = { Device: {
	Ethernet: { Interface: {
		'1': { Name: 'lan1' },
		'2': { Name: 'lan2' },
		'3': { Name: 'wan' },
		'4': { Name: 'lan3' }
	} },
	Bridging: { Bridge: { '1': { Port: {
		'1': { Enable: 'true', ManagementPort: 'true', Name: 'br-lan' },
		'2': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.1' },
		'3': { Enable: 'true', LowerLayers: 'Device.Ethernet.Interface.2,Device.Ethernet.Interface.1' },
		'4': { Enable: 'false', LowerLayers: 'Device.Ethernet.Interface.4' }
	} } } }
} };

function members(lower_layers) {
	return ip_interface_members(root, { LowerLayers: lower_layers });
}

describe('ip_interface_members', () => {
	it('gives the enabled ports of a bridge once each', () => {
		assert.match([ 'lan1', 'lan2' ], members('Device.Bridging.Bridge.1.Port.1'));
		assert.match([ 'lan1', 'lan2' ], members('Device.Bridging.Bridge.1.Port.1.'), 'trailing dot');
	});

	it('gives the netdev of a link', () => {
		assert.match([ 'wan' ], members('Device.Ethernet.Interface.3'));
	});

	it('gives the netdevs of a list of lower layers in order', () => {
		assert.match([ 'lan1', 'lan2', 'wan' ], members('Device.Bridging.Bridge.1.Port.1,Device.Ethernet.Interface.3'));
		assert.match([ 'wan', 'lan3' ], members('Device.Ethernet.Interface.3, Device.Ethernet.Interface.4'));
	});

	it('gives no netdev without a lower layer or a root', () => {
		assert.match([], members(''));
		assert.match([], ip_interface_members(null, { LowerLayers: 'Device.Ethernet.Interface.3' }));
	});
});
