// Host test of Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.
// UnassociatedSTA.{i} in modules/easymesh: umapd keeps the measurements of a
// station per operating class, and TR-181 allows one row per MACAddress, with
// the class and channel of the last detection. A station held in two classes
// of one radio gives one row: the measurement taken last (report timestamp
// less Time_Delta, EasyMesh 6.1 Table 49) wins; on a tie the class the
// radio's Operating Channel Report names, then the first one seen.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';

const AL = '02:00:00:00:00:a1';
const R5 = '02:00:00:00:05:00';
const R24 = '02:00:00:00:02:00';
const STA_A = '0a:00:00:00:00:01';
const STA_B = '0a:00:00:00:00:02';
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
			radios_bss_sort: () => [
				{ radio_unique_identifier: R5, bss: [] },
				{ radio_unique_identifier: R24, bss: [] }
			],
			client_query_get: () => null
		},
		capabilities: { capability_radios_get },
		wifi_radio: { radio_instances_for_bands }
	}
};

const em = { easymesh_model: {}, al_index_map: () => ({}), ap_by_ssid_ref_find: () => null };
const DIR = sourcepath(0, true) + '/../modules/easymesh';
include(DIR + '/objectdata.uc', { ubbf_module: api, em });

function entry(mac, channel, rcpi, timestamp, time_delta) {
	return { mac_address: mac, channel, time_delta, uplink_rcpi: rcpi, timestamp };
}

// current: the classes of the 5 GHz radio's Operating Channel Report
function rows(unassoc, current) {
	const capability = {
		unassoc_sta_metrics: unassoc,
		radios: {
			[R5]: {
				basic_capabilities: { opclasses_supported: [ { opclass: 115 }, { opclass: 128 } ] },
				operating_classes: map(current ?? [], (c) => ({ class: c, channel: 36 }))
			},
			[R24]: {
				basic_capabilities: { opclasses_supported: [ { opclass: 81 } ] }
			}
		}
	};
	const dev = em.device_to_object({ al_address: AL }, { capability }, false, {}, {}, {});
	let out = {};

	for (let idx, radio in dev.Radio) {
		let ruid = idx == '1' ? R5 : R24;
		out[ruid] = {
			count: radio.UnassociatedSTANumberOfEntries,
			rows: map(values(radio.UnassociatedSTA ?? {}), (s) =>
				[ s.MACAddress, s.OperatingClass, s.Channel ])
		};
	}
	return out;
}

describe('Radio UnassociatedSTA', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('gives one row per station in one class', () => {
		const out = rows({ '115': { sta_entries: [ entry(STA_A, 36, 80, T, 0), entry(STA_B, 40, 90, T, 0) ] } });

		assert.match('2', out[R5].count);
		assert.match([ [ STA_A, '115', '36' ], [ STA_B, '115', '40' ] ], out[R5].rows);
	});

	it('gives the newer report of two classes of one radio', () => {
		const out = rows({
			'115': { sta_entries: [ entry(STA_A, 36, 80, T + 1000, 0) ] },
			'128': { sta_entries: [ entry(STA_A, 42, 70, T, 0), entry(STA_B, 42, 90, T, 0) ] }
		});

		assert.match('2', out[R5].count, 'one row per MACAddress');
		assert.match([ [ STA_A, '115', '36' ], [ STA_B, '128', '42' ] ], out[R5].rows);

		const later = rows({
			'115': { sta_entries: [ entry(STA_A, 36, 80, T, 0), entry(STA_B, 40, 90, T, 0) ] },
			'128': { sta_entries: [ entry(STA_A, 42, 70, T + 1000, 0) ] }
		});
		assert.match([ [ STA_A, '128', '42' ], [ STA_B, '115', '40' ] ], later[R5].rows,
			'the later class wins in either order, and the row keeps its place');
	});

	it('dates the measurement by the report timestamp less Time_Delta', () => {
		const out = rows({
			'115': { sta_entries: [ entry(STA_A, 36, 80, T + 1000, 1500) ] },
			'128': { sta_entries: [ entry(STA_A, 42, 70, T, 0) ] }
		});
		assert.match([ [ STA_A, '128', '42' ] ], out[R5].rows, 'measured at T - 500 against T');

		const same_second = rows({
			'115': { sta_entries: [ entry(STA_A, 36, 80, T, 200) ] },
			'128': { sta_entries: [ entry(STA_A, 42, 70, T, 100) ] }
		});
		assert.match([ [ STA_A, '128', '42' ] ], same_second[R5].rows, 'one timestamp, the smaller delta wins');
	});

	it('gives a tie to the class of the Operating Channel Report, then to the first seen', () => {
		const unassoc = {
			'115': { sta_entries: [ entry(STA_A, 36, 80, T, 0) ] },
			'128': { sta_entries: [ entry(STA_A, 42, 70, T, 0) ] }
		};

		assert.match([ [ STA_A, '128', '42' ] ], rows(unassoc, [ 128 ])[R5].rows, 'current class 128');
		assert.match([ [ STA_A, '115', '36' ] ], rows(unassoc, [ 115 ])[R5].rows, 'current class 115');
		assert.match([ [ STA_A, '115', '36' ] ], rows(unassoc, [])[R5].rows, 'no report: first seen');
		assert.match([ [ STA_A, '115', '36' ] ], rows(unassoc, [ 115, 128 ])[R5].rows, 'both current: first seen');
	});

	it('keeps a row of each radio for a station two radios measured', () => {
		const out = rows({
			'115': { sta_entries: [ entry(STA_A, 36, 80, T, 0) ] },
			'81': { sta_entries: [ entry(STA_A, 6, 60, T + 1000, 0) ] }
		});

		assert.match([ [ STA_A, '115', '36' ] ], out[R5].rows, '5 GHz radio');
		assert.match([ [ STA_A, '81', '6' ] ], out[R24].rows, '2.4 GHz radio');
	});
});
