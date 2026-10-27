// Host test of the location module handler (Device.DeviceInfo.Location.{i}):
// the GPS row that the instance map numbers after the stored row, its
// position document, and the External row that a controller writes. The
// gpsd answer comes from a ubus mock, the controller identity from a uci
// mock.
'use strict';

import { describe, it, assert, mock, beforeEach, regex } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { datetime_format } from 'ubbf';

const UCI = {
	cwmp: { acs: { '.type': 'acs', url: 'http://acs.example:7547/' } },
	obuspa: { acs: { '.type': 'acs', endpoint_id: 'proto::uacs' } }
};

// Answers gps info with env.gps; env.identity is the DeviceInfo of the
// device.
function env_new() {
	let env = { gps: null, identity: { ManufacturerOUI: '2005B6', SerialNumber: 'FF8618' } };

	mock.global.patch('ubus', { behavior: {
		call: (object, method, args) => (object == 'gps' && method == 'info') ? env.gps : null
	} });
	mock.global.patch('uci', { data: UCI });
	return env;
}

/**
 * Loads the handler for one management protocol. The handler requires ubus
 * and uci when it loads, so it loads after the mocks.
 *
 * @param {object} env - Test state from env_new()
 * @param {string} protocol - 'usp' or 'cwmp'
 * @returns {object} Model entry of Device.DeviceInfo.Location.{i}
 */
function handler_load(env, protocol) {
	let api = {
		ubbf: proto({ cache_call: (fn, ...args) => fn(...args), active_protocol: () => protocol,
			deviceinfo_get: () => env.identity }, ubbf),
		utils: {},
		schema: (k) => k,
		model: {}
	};

	include('../modules/location/handler.uc', { ubbf_module: api });

	return api.model['Device.DeviceInfo.Location.{i}'];
}

describe('location handler', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('gives runtime rows next to one stored row', () => {
		let entry = handler_load(env_new(), 'usp');

		assert.match([ true, 1 ], [ entry.runtime_instances, entry.maxInstances ], 'entry: runtime rows next to one stored row');
	});

	it('has no GPS row without the GPS daemon', () => {
		let entry = handler_load(env_new(), 'usp');

		assert.match({}, entry.get({ instance: null, config: null }), 'no daemon: no runtime row');
		assert.match(null, entry.get({ instance: 2, config: null }), 'no daemon: no GPS row');
	});

	// The GPS row follows the stored row of the controller, and only the
	// stored row can be deleted.
	it('reads the GPS row after the stored row and refuses its delete', () => {
		let env = env_new();
		let entry = handler_load(env, 'usp');

		env.gps = { signal: false };
		let lroot = { Device: { DeviceInfo: { Location: { '1': { Source: 'External' } } } } };
		assert.match({
			'2': {
				Source: 'GPS',
				AcquiredTime: '0001-01-01T00:00:00Z',
				ExternalSource: '',
				ExternalProtocol: '',
				DataObject: ''
			}
		}, entry.get({ instance: null, config: null, root: lroot }), 'no fix: one GPS row without a position, after the stored row');
		assert.match(null, entry.get({ instance: 1, config: null }), 'no fix: another instance is not the GPS row');

		env.gps = { age: 3, latitude: '52.520008', longitude: '13.404954', date: '2026-10-18', time: '12:35:19', valid: true };
		let row = entry.get({ instance: 2, config: null });
		assert.match('2026-10-18T12:35:19Z', row.AcquiredTime, 'fix: receiver date and time');
		assert.match(regex(/<presence [^>]* entity="mac:2005b6ff8618">/), row.DataObject, 'fix: entity');
		assert.match(regex(/<dm:deviceID>mac:2005b6ff8618<\/dm:deviceID>/), row.DataObject, 'fix: device ID');
		assert.match(regex(/<gml:pos>52.520008 13.404954<\/gml:pos>/), row.DataObject, 'fix: WGS 84 point');
		assert.match(regex(/<dm:timestamp>2026-10-18T12:35:19Z<\/dm:timestamp>/), row.DataObject, 'fix: timestamp');

		env.gps = { age: 3, latitude: '52.5', longitude: '13.4', valid: false };
		row = entry.get({ instance: 2, config: null });
		assert.match(true, length(row.DataObject) > 0, 'lost fix: last position kept');
		let expected = [ datetime_format(time() - 4), datetime_format(time() - 3) ];
		assert.match(true, index(expected, row.AcquiredTime) >= 0, 'no date: fix time from age');

		env.identity = { ManufacturerOUI: '2005B6', SerialNumber: 'a"b<c' };
		row = entry.get({ instance: 2, config: null });
		assert.match(regex(/entity="mac:2005b6a&quot;b&lt;c"/), row.DataObject, 'identity: escaped');

		env.identity = {};
		row = entry.get({ instance: 2, config: null });
		assert.match('', row.DataObject, 'no identity: no document');

		assert.match(-USP_ERR_OBJECT_NOT_DELETABLE, entry.del({ path: 'Device.DeviceInfo.Location.2.', instance: 2 }),
			'del: GPS row refused');
		assert.match(null, entry.del({ path: 'Device.DeviceInfo.Location.1.', instance: 1 }), 'del: stored row goes to the dispatcher');
	});

	it('stamps the External row that a USP controller writes', () => {
		let entry = handler_load(env_new(), 'usp');
		let stored = {
			Source: 'External',
			AcquiredTime: '0001-01-01T00:00:00Z',
			ExternalSource: '',
			ExternalProtocol: 'CWMP',
			DataObject: ''
		};

		let ctx = { param: 'DataObject', value: '<presence/>', instance: 1, config: stored };
		assert.match(0, entry.set(ctx), 'set: accepted');
		assert.match(regex(/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/), stored.AcquiredTime, 'set: acquired now');
		assert.match('proto::uacs', stored.ExternalSource, 'set: USP controller');

		stored.DataObject = '<presence/>';
		let row = entry.get({ instance: 1, config: stored });
		assert.match([ 'External', 'USP', 'proto::uacs', '<presence/>' ],
			[ row.Source, row.ExternalProtocol, row.ExternalSource, row.DataObject ], 'stored: external row');

		stored.AcquiredTime = 'unchanged';
		entry.set({ param: 'Alias', value: 'x', instance: 1, config: stored });
		assert.match('unchanged', stored.AcquiredTime, 'set: other parameter keeps the time');
	});

	it('names the ACS for an External row under CWMP', () => {
		let cwmp_entry = handler_load(env_new(), 'cwmp');
		let cwmp_row = { DataObject: '' };

		cwmp_entry.set({ param: 'DataObject', value: '<presence/>', instance: 1, config: cwmp_row });
		assert.match('http://acs.example:7547/', cwmp_row.ExternalSource, 'cwmp: ACS URL');
		assert.match('CWMP', cwmp_entry.get({ instance: 1, config: cwmp_row }).ExternalProtocol, 'cwmp: protocol');
	});
});
