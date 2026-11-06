// Host test of CoordinatedCACAllowed of Device.WiFi.DataElements.Network.Device
// in modules/easymesh: umapd's controller sends no CAC Request (EasyMesh 6.1
// 8.2.2), so the parameter reads false whatever a Policy Data text names, the
// schema refuses true before any store, and a row the configuration does not
// hold stays refused for every parameter.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';

const AL = '02:00:00:00:00:a1';

const api = {
	ubbf,
	model: {},
	operations: {},
	utils: {
		'wifi-dataelements': {
			topology_devices_get: () => [ { al_address: AL } ],
			local_device_get: () => ({ al_address: AL }),
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			local_api_data_get: () => ({}),
			steering_stats_get: () => ({}),
			steering_history_get: () => ({}),
			radios_bss_sort: () => [],
			client_query_get: () => null
		},
		capabilities: { capability_radios_get },
		wifi_radio: { radio_instances_for_bands }
	}
};

let schemas = {};
const DIR = sourcepath(0, true) + '/../modules/easymesh';
include(DIR + '/schema.uc', { schemas });
api.schema = (k) => schemas[k];

const em = { easymesh_model: {}, al_index_map: () => ({}), ap_by_ssid_ref_find: () => null };
include(DIR + '/objectdata.uc', { ubbf_module: api, em });
include(DIR + '/operations.uc', { ubbf_module: api, em });
include(DIR + '/dataelements.uc', { ubbf_module: api, em });

const PATH = 'Device.WiFi.DataElements.Network.Device.1.';
const INVALID_VALUE = -4;

// table: 'none' for a Network without a Device key (the baseline
// configuration), 'empty' for an empty Device table, 'row' for a stored row
function dm_new(table) {
	let network = { X_UBBF_EasyMesh: { Controller: { Enable: 'true' } } };

	if (table == 'empty')
		network.Device = {};
	else if (table == 'row')
		network.Device = { '1': { Tag: 'stored' } };

	let dm = ubbf.create();
	assert.match(true, dm.register(api.model), 'model registers');
	dm.load('/dev/null');
	dm.set_config({ Device: { WiFi: { DataElements: { Network: network } } } });
	dm.runtime_reload();
	return dm;
}

function write(dm, param, value) {
	dm.trans_start();
	const rc = dm.params_set({ [PATH + param]: value });
	if (rc < 0)
		dm.trans_abort();
	else
		dm.trans_commit();
	return rc;
}

function stored_device(dm) {
	return dm.config()?.Device?.WiFi?.DataElements?.Network?.Device;
}

function device_read(policy, config_policy) {
	const easymesh = { ConfigPolicy: { [AL]: config_policy } };
	const api_data = { capability: {}, policy: { policy } };

	return em.device_to_object({ al_address: AL }, api_data, false, easymesh, {}, {});
}

describe('Network.Device CoordinatedCACAllowed', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('reads false, also where a Policy Data text names coordinated CAC', () => {
		const text = { steering: { coordinated_cac_allowed: true } };

		assert.match('false', device_read({}).CoordinatedCACAllowed);
		assert.match('false', device_read(text, text).CoordinatedCACAllowed);
	});

	for (let table in [ 'none', 'empty', 'row' ]) {
		it(`refuses true and 1 as invalid values and stores nothing (Device table ${table})`, () => {
			const dm = dm_new(table);
			const before = sprintf('%J', stored_device(dm));

			assert.match(INVALID_VALUE, write(dm, 'CoordinatedCACAllowed', 'true'), 'true');
			assert.match(INVALID_VALUE, write(dm, 'CoordinatedCACAllowed', '1'), '1');
			assert.match(before, sprintf('%J', stored_device(dm)), 'stored configuration unchanged');
		});
	}

	it('accepts false and 0 in a stored row', () => {
		const dm = dm_new('row');

		assert.match(0, write(dm, 'CoordinatedCACAllowed', 'false'), 'false');
		assert.match(0, write(dm, 'CoordinatedCACAllowed', '0'), '0');
		assert.match('0', stored_device(dm)?.['1']?.CoordinatedCACAllowed, 'stored');
	});

	for (let table in [ 'none', 'empty' ]) {
		it(`refuses every write into a row the configuration does not hold (Device table ${table})`, () => {
			for (let w in [
				[ 'CoordinatedCACAllowed', 'false' ],
				[ 'ReportIndependentScans', 'true' ],
				[ 'APMetricsReportingInterval', '7' ]
			]) {
				const dm = dm_new(table);
				const before = sprintf('%J', stored_device(dm));

				assert.match(true, write(dm, w[0], w[1]) < 0, w[0]);
				assert.match(before, sprintf('%J', stored_device(dm)), `${w[0]}: nothing stored`);
			}
		});
	}

	it('leaves the writes of the other parameters of a stored row', () => {
		const dm = dm_new('row');

		assert.match(0, write(dm, 'ReportIndependentScans', 'true'), 'ReportIndependentScans');
		assert.match('true', stored_device(dm)?.['1']?.ReportIndependentScans, 'stored');
	});
});
