// Host test of the PPPoE passthrough of the ppp module: LANInterface names
// the one LAN port that relays PPPoE, an Ethernet.Interface or a port of a
// bridge that is not its management port; the render writes the netdev of
// that port, and the set handler refuses any other reference.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { generate } from 'ubbf.render.renderer';

function config(lan_ref) {
	return { Device: {
		Ethernet: {
			Interface: {
				'1': { Enable: 'true', Name: 'wan' },
				'2': { Enable: 'true', Name: 'lan1' },
				'3': { Enable: 'true', Name: 'lan2' }
			},
			Link: {
				'1': { Enable: 'true', Name: 'wan', LowerLayers: 'Device.Ethernet.Interface.1' },
				'2': { Enable: 'true', Name: 'lan1', LowerLayers: 'Device.Ethernet.Interface.2' },
				'3': { Enable: 'true', Name: 'lan2', LowerLayers: 'Device.Ethernet.Interface.3' }
			}
		},
		Bridging: { Bridge: { '1': {
			Enable: 'true',
			Name: 'br-lan',
			Port: {
				'1': { Enable: 'true', Name: 'br-lan', ManagementPort: 'true',
					LowerLayers: 'Device.Bridging.Bridge.1.Port.2,Device.Bridging.Bridge.1.Port.3' },
				'2': { Enable: 'true', Name: 'lanport1', LowerLayers: 'Device.Ethernet.Link.2' },
				'3': { Enable: 'true', Name: 'lanport2', LowerLayers: 'Device.Ethernet.Link.3' }
			}
		} } },
		PPP: { Interface: { '1': {
			Enable: 'true',
			Name: 'pppwan',
			LowerLayers: 'Device.Ethernet.Link.1',
			PPPoE: { X_UBBF_Passthrough: { Enable: 'true', MaxSessions: '4', LANInterface: lan_ref } }
		} } }
	} };
}

function relay_lan_dev(lan_ref) {
	let uci = generate(config(lan_ref), [], true).uci;
	let m = match(uci, /pppoe-relay\.[A-Za-z0-9_]+\.lan_dev='([^']*)'/);
	return m ? m[1] : null;
}

let schemas = {};
include('../modules/ppp/schema.uc', { schemas });

const api = {
	ubbf: require('ubbf'),
	utils: {},
	schema: (k) => schemas[k],
	model: {},
	operations: {}
};
// The host has no rtnl module; the set handler does not use it.
const real_require = require;
include('../modules/ppp/handler.uc', {
	ubbf_module: api,
	require: (name) => (name == 'rtnl') ? {} : real_require(name)
});

function lan_set(value) {
	return api.model['Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough'].set({
		param: 'LANInterface', value, root: config('')
	});
}

describe('PPPoE passthrough LAN port', () => {
	beforeEach(() => mock.global.patch('uci', { data: {} }));

	it('relays on the one port that LANInterface names', () => {
		assert.match('lan2', relay_lan_dev('Device.Bridging.Bridge.1.Port.3'), 'a port of the bridge');
		assert.match('lan1', relay_lan_dev('Device.Ethernet.Interface.2'), 'an Ethernet interface');
	});

	it('relays nowhere for a reference that is not one LAN port', () => {
		assert.match(null, relay_lan_dev('Device.Bridging.Bridge.1'), 'a whole bridge');
		assert.match(null, relay_lan_dev('Device.Bridging.Bridge.1.Port.1'), 'the management port');
		assert.match(null, relay_lan_dev('Device.IP.Interface.1'), 'an IP interface');
		assert.match(null, relay_lan_dev(''), 'empty');
	});

	it('refuses a LANInterface that is not one LAN port', () => {
		assert.match(0, lan_set('Device.Bridging.Bridge.1.Port.2'), 'a port of the bridge');
		assert.match(0, lan_set('Device.Ethernet.Interface.3'), 'an Ethernet interface');
		assert.match(0, lan_set(''), 'empty');
		assert.match(-USP_ERR_INVALID_VALUE, lan_set('Device.Bridging.Bridge.1'), 'a whole bridge');
		assert.match(-USP_ERR_INVALID_VALUE, lan_set('Device.Bridging.Bridge.1.Port.1'), 'the management port');
		assert.match(-USP_ERR_INVALID_VALUE, lan_set('Device.Bridging.Bridge.1.Port.9'), 'a port that does not exist');
		assert.match(-USP_ERR_INVALID_VALUE, lan_set('Device.IP.Interface.1'), 'an IP interface');
	});
});
