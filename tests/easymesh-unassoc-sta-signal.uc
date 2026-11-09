// Host test of SignalStrength of Device.WiFi.DataElements.Network.Device.{i}.
// Radio.{i}.UnassociatedSTA.{i} in modules/easymesh: the row carries the
// uplink RCPI that umapd's get_agent exports as uplink_rcpi. umapd gives null
// for an RCPI in the reserved range, and such an entry gives no row.
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
		dhcp: { ipv6_leases_get: () => ({}) },
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

// The entries as umapd's get_agent exports them (linkmetric.uc unassoc_sta_metrics_store()),
// keyed by operating class. operating_classes is the radio's Operating Channel Report.
function radio_read(unassoc_sta_metrics, operating_classes) {
	const opclasses_supported = map(keys(unassoc_sta_metrics), (oc) => ({ opclass: int(oc) }));
	const capability = {
		unassoc_sta_metrics,
		radios: { [RUID]: { basic_capabilities: { opclasses_supported }, operating_classes } }
	};
	const dev = em.device_to_object({ al_address: AL }, { capability }, false, {}, {}, {});

	return dev.Radio['1'];
}

function signal_rows(radio) {
	return map(values(radio.UnassociatedSTA ?? {}), (s) => [ s.MACAddress, s.SignalStrength ]);
}

function signal_read_classes(unassoc_sta_metrics) {
	return signal_rows(radio_read(unassoc_sta_metrics));
}

function signal_read(sta_entries) {
	return signal_read_classes({ '115': { timestamp: T, sta_entries } });
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

	it('carries an RCPI of 0', () => {
		assert.match([ [ '0a:00:00:00:00:04', '0' ] ], signal_read([
			{ mac_address: '0a:00:00:00:00:04', channel: 36, time_delta: 0, uplink_rcpi: 0, timestamp: T }
		]));
	});

	it('gives no row where umapd gives no RCPI', () => {
		const radio = radio_read({ '115': { timestamp: T, sta_entries: [
			{ mac_address: '0a:00:00:00:00:03', channel: 36, time_delta: 0, uplink_rcpi: null, timestamp: T },
			{ mac_address: '0a:00:00:00:00:01', channel: 36, time_delta: 0, uplink_rcpi: 180, timestamp: T }
		] } });

		assert.match([ [ '0a:00:00:00:00:01', '180' ] ], signal_rows(radio));
		assert.match('1', radio.UnassociatedSTANumberOfEntries);
	});

	it('gives no row where umapd gives no RCPI in the class of the Operating Channel Report', () => {
		const radio = radio_read({ '115': { timestamp: T, sta_entries: [
			{ mac_address: '0a:00:00:00:00:03', channel: 36, time_delta: 0, uplink_rcpi: null, timestamp: T },
			{ mac_address: '0a:00:00:00:00:01', channel: 36, time_delta: 0, uplink_rcpi: 180, timestamp: T }
		] } }, [ { class: 115, channel: 36 } ]);

		assert.match([ [ '0a:00:00:00:00:01', '180' ] ], signal_rows(radio));
		assert.match('1', radio.UnassociatedSTANumberOfEntries);
	});

	it('keeps an older RCPI where a newer reading has none', () => {
		assert.match([ [ '0a:00:00:00:00:03', '150' ] ], signal_read_classes({
			'115': { timestamp: T, sta_entries: [
				{ mac_address: '0a:00:00:00:00:03', channel: 36, time_delta: 0, uplink_rcpi: 150, timestamp: T }
			] },
			'118': { timestamp: T + 5000, sta_entries: [
				{ mac_address: '0a:00:00:00:00:03', channel: 52, time_delta: 0, uplink_rcpi: null, timestamp: T + 5000 }
			] }
		}));
		assert.match([ [ '0a:00:00:00:00:03', '150' ] ], signal_read_classes({
			'118': { timestamp: T + 5000, sta_entries: [
				{ mac_address: '0a:00:00:00:00:03', channel: 52, time_delta: 0, uplink_rcpi: null, timestamp: T + 5000 }
			] },
			'115': { timestamp: T, sta_entries: [
				{ mac_address: '0a:00:00:00:00:03', channel: 36, time_delta: 0, uplink_rcpi: 150, timestamp: T }
			] }
		}));
	});
});
