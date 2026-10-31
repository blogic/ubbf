// Host test of the bridge's snooping versions in render/templates/bridging.uc
// and device.uc: netifd reads snoop_igmp_version and snoop_mld_version.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import { device_state_set } from 'ubbf.render.helpers';

const TEMPLATES = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates';

function device_render(render_state) {
	let output = [];

	include(`${TEMPLATES}/device.uc`, { ...h, output, render_state, config: {},
		services: { set_enabled: () => null } });

	return output;
}

describe('bridge snooping versions', () => {
	it('sets IGMPv3 and MLDv2 on a bridge of the data model', () => {
		let render_state = { device: {} };
		let config = { Device: { Bridging: { Bridge: {
			'1': { Enable: 'true', Name: 'br-lan', Standard: '802.1D-2004' }
		} } } };

		include(`${TEMPLATES}/bridging.uc`, { ...h, output: [], render_state, config, ubbf,
			ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
			ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list, device_state_set,
			lower_layers_wifi: ubbf.lower_layers_wifi, port_snooped: ubbf.port_snooped });

		let dev = render_state.device['br-lan'];
		assert.match('3', dev.snoop_igmp_version);
		assert.match('2', dev.snoop_mld_version);
		assert.match(null, dev.igmp_version);
		assert.match(null, dev.mld_version);
	});

	it('writes the versions under the names netifd reads', () => {
		let lines = device_render({ device: { 'br-lan': {
			name: 'br-lan', type: 'bridge', snoop_igmp_version: '3', snoop_mld_version: '2'
		} } });

		assert.match([
			"set network.@device[-1].snoop_igmp_version='3'",
			"set network.@device[-1].snoop_mld_version='2'"
		], filter(lines, (l) => match(l, /_version=/)));
	});
});
