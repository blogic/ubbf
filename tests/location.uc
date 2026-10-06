// Host test of the location module handler. Run from the repository root
// with the native module built for the host; tests/location/ holds
// stand-ins for the ubus and uci modules, which the handler requires:
//   ucode -L "$PWD/tests/location/*.uc" -L "$PWD/files/usr/share/ucode/*.uc" \
//     -L "<host build>/*.so" tests/location.uc
'use strict';

import * as ubbf from 'ubbf';
import { datetime_format } from 'ubbf.utils.helpers';

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%J', got);
	let exp_json = sprintf('%J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

function assert_match(name, got, pattern) {
	if (type(got) == 'string' && match(got, pattern)) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  got: %J\n', name, got);
}

let identity = { ManufacturerOUI: '2005B6', SerialNumber: 'FF8618' };

/**
 * Loads the handler for one management protocol.
 *
 * @param {string} protocol - 'usp' or 'cwmp'
 * @returns {object} Model entry of Device.DeviceInfo.Location.{i}
 */
function handler_load(protocol) {
	let api = {
		ubbf,
		utils: {
			cache: { call: (fn, ...args) => fn(...args) },
			helpers: { datetime_format },
			deviceinfo: { deviceinfo_get: () => identity },
			logging: { log_warn: () => null },
			protocol: { ACTIVE_PROTOCOL: protocol }
		},
		schema: (k) => k,
		model: {}
	};

	include('../modules/location/handler.uc', { ubbf_module: api });

	return api.model['Device.DeviceInfo.Location.{i}'];
}

let entry = handler_load('usp');

assert_eq('entry: runtime rows next to one stored row',
	[ entry.runtime_instances, entry.maxInstances ], [ true, 1 ]);

global.GPS_REPLY = null;
assert_eq('no daemon: no runtime row', entry.get({ instance: null, config: null }), {});
assert_eq('no daemon: no GPS row', entry.get({ instance: 10000, config: null }), null);

global.GPS_REPLY = { signal: false };
assert_eq('no fix: one GPS row without a position', entry.get({ instance: null, config: null }), {
	'10000': {
		Source: 'GPS',
		AcquiredTime: '0001-01-01T00:00:00Z',
		ExternalSource: '',
		ExternalProtocol: '',
		DataObject: ''
	}
});
assert_eq('no fix: another instance is not the GPS row', entry.get({ instance: 1, config: null }), null);

global.GPS_REPLY = { age: 3, latitude: '52.520008', longitude: '13.404954', date: '2026-10-18', time: '12:35:19', valid: true };
let row = entry.get({ instance: 10000, config: null });
assert_eq('fix: receiver date and time', row.AcquiredTime, '2026-10-18T12:35:19Z');
assert_match('fix: entity', row.DataObject, /<presence [^>]* entity="mac:2005b6ff8618">/);
assert_match('fix: device ID', row.DataObject, /<dm:deviceID>mac:2005b6ff8618<\/dm:deviceID>/);
assert_match('fix: WGS 84 point', row.DataObject, /<gml:pos>52.520008 13.404954<\/gml:pos>/);
assert_match('fix: timestamp', row.DataObject, /<dm:timestamp>2026-10-18T12:35:19Z<\/dm:timestamp>/);

global.GPS_REPLY = { age: 3, latitude: '52.5', longitude: '13.4', valid: false };
row = entry.get({ instance: 10000, config: null });
assert_eq('lost fix: last position kept', length(row.DataObject) > 0, true);
let expected = [ datetime_format(time() - 4), datetime_format(time() - 3) ];
assert_eq('no date: fix time from age', index(expected, row.AcquiredTime) >= 0, true);

identity = { ManufacturerOUI: '2005B6', SerialNumber: 'a"b<c' };
row = entry.get({ instance: 10000, config: null });
assert_match('identity: escaped', row.DataObject, /entity="mac:2005b6a&quot;b&lt;c"/);

identity = {};
row = entry.get({ instance: 10000, config: null });
assert_eq('no identity: no document', row.DataObject, '');
identity = { ManufacturerOUI: '2005B6', SerialNumber: 'FF8618' };

let stored = {
	Source: 'External',
	AcquiredTime: '0001-01-01T00:00:00Z',
	ExternalSource: '',
	ExternalProtocol: 'CWMP',
	DataObject: ''
};

let ctx = { param: 'DataObject', value: '<presence/>', instance: 1, config: stored };
assert_eq('set: accepted', entry.set(ctx), 0);
assert_match('set: acquired now', stored.AcquiredTime, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/);
assert_eq('set: USP controller', stored.ExternalSource, 'proto::uacs');

stored.DataObject = '<presence/>';
row = entry.get({ instance: 1, config: stored });
assert_eq('stored: external row', [ row.Source, row.ExternalProtocol, row.ExternalSource, row.DataObject ],
	[ 'External', 'USP', 'proto::uacs', '<presence/>' ]);

let before = stored.AcquiredTime;
stored.AcquiredTime = 'unchanged';
entry.set({ param: 'Alias', value: 'x', instance: 1, config: stored });
assert_eq('set: other parameter keeps the time', stored.AcquiredTime, 'unchanged');
stored.AcquiredTime = before;

assert_eq('del: GPS row refused', entry.del({ path: 'Device.DeviceInfo.Location.10000.', instance: 10000 }),
	-USP_ERR_OBJECT_NOT_DELETABLE);
assert_eq('del: stored row goes to the dispatcher', entry.del({ path: 'Device.DeviceInfo.Location.1.', instance: 1 }), null);

let cwmp_entry = handler_load('cwmp');
let cwmp_row = { DataObject: '' };
cwmp_entry.set({ param: 'DataObject', value: '<presence/>', instance: 1, config: cwmp_row });
assert_eq('cwmp: ACS URL', cwmp_row.ExternalSource, 'http://acs.example:7547/');
assert_eq('cwmp: protocol', cwmp_entry.get({ instance: 1, config: cwmp_row }).ExternalProtocol, 'CWMP');

printf('%d passed, %d failed\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
