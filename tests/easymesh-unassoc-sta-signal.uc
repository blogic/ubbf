// Host test of SignalStrength of Device.WiFi.DataElements.Network.Device.{i}.
// Radio.{i}.UnassociatedSTA.{i} in modules/easymesh: the row carries the
// uplink RCPI that umapd's get_agent exports as uplink_rcpi. umapd gives null
// for an RCPI in the reserved range, and the row then reads 0.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';

const AL = '02:00:00:00:00:a1';
const RUID = '02:00:00:00:05:00';
const T = 1700000000000;

const api = {
	ubbf,
	model: {},
	operations: {},
	schema: (k) => k,
	utils: {
		'wifi-dataelements': {
			topology_devices_get: () => [ { al_address: AL } ],
			local_device_get: () => ({ al_address: AL }),
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			local_api_data_get: () => ({}),
			steering_stats_get: () => ({}),
			steering_history_get: () => ({}),
			radios_bss_sort: () => [ { radio_unique_identifier: RUID, bss: [] } ],
			client_query_get: () => null
		},
		capabilities: { capability_radios_get },
		wifi_radio: { radio_instances_for_bands }
	}
};

const em = { easymesh_model: {}, al_index_map: () => ({}), ap_by_ssid_ref_find: () => null };
const DIR = sourcepath(0, true) + '/../modules/easymesh';
include(DIR + '/objectdata.uc', { ubbf_module: api, em });

// The entry as umapd's get_agent exports it (linkmetric.uc unassoc_sta_metrics_store()).
function signal_read(sta_entries) {
	const capability = {
		unassoc_sta_metrics: { '115': { timestamp: T, sta_entries } },
		radios: { [RUID]: { basic_capabilities: { opclasses_supported: [ { opclass: 115 } ] } } }
	};
	const dev = em.device_to_object({ al_address: AL }, { capability }, false, {}, {}, {});

	return map(values(dev.Radio['1'].UnassociatedSTA ?? {}), (s) => [ s.MACAddress, s.SignalStrength ]);
}

describe('Radio UnassociatedSTA SignalStrength', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('carries the uplink RCPI of get_agent', () => {
		assert.match([ [ '0a:00:00:00:00:01', '180' ], [ '0a:00:00:00:00:02', '220' ] ], signal_read([
			{ mac_address: '0a:00:00:00:00:01', channel: 36, time_delta: 0, uplink_rcpi: 180, timestamp: T },
			{ mac_address: '0a:00:00:00:00:02', channel: 36, time_delta: 0, uplink_rcpi: 220, timestamp: T }
		]));
	});

	it('reads 0 where umapd gives no RCPI', () => {
		assert.match([ [ '0a:00:00:00:00:03', '0' ] ], signal_read([
			{ mac_address: '0a:00:00:00:00:03', channel: 36, time_delta: 0, uplink_rcpi: null, timestamp: T }
		]));
	});
});
