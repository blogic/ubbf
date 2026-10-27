// Host test of the bridge port helpers of ubbf.so
// (Device.Bridging.Bridge.{i}.Port.{i}.IGMP and MLD).
'use strict';

import { describe, it, assert } from 'utest';
import { port_snooped, lower_layers_wifi } from 'ubbf';

describe('bridge port snooping', () => {
	it('snoops a port without the 2.21 values or without a row', () => {
		assert.match(true, port_snooped({ Enable: 'true' }));
		assert.match(true, port_snooped(null));
	});

	it('snoops a port with IGMP and MLD true', () => {
		assert.match(true, port_snooped({ IGMP: 'true', MLD: 'true' }));
		assert.match(true, port_snooped({ IGMP: '1', MLD: '1' }));
	});

	it('does not snoop a port with IGMP or MLD false', () => {
		assert.match(false, port_snooped({ IGMP: 'false', MLD: 'true' }));
		assert.match(false, port_snooped({ IGMP: 'true', MLD: 'false' }));
		assert.match(false, port_snooped({ IGMP: 'false', MLD: 'false' }));
		assert.match(false, port_snooped({ MLD: '0' }));
	});
});

describe('bridge port lower layers', () => {
	it('is WiFi when every lower layer is an SSID', () => {
		assert.match(true, lower_layers_wifi('Device.WiFi.SSID.1'));
		assert.match(true, lower_layers_wifi('Device.WiFi.SSID.1,Device.WiFi.SSID.2'));
	});

	it('is not WiFi with a link or without lower layers', () => {
		assert.match(false, lower_layers_wifi('Device.Ethernet.Link.2'));
		assert.match(false, lower_layers_wifi('Device.WiFi.SSID.1,Device.Ethernet.Link.2'));
		assert.match(false, lower_layers_wifi(''));
	});
});
