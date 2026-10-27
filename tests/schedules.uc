// Host test of the schedules module on the native dispatcher, and of the
// generic ScheduleRef handling of the core: the check that datamodel.uc
// installs on every object with ScheduleRef, and the removal of references
// to a deleted row.
'use strict';

import { describe, it, beforeEach, assert } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { AccessControl } from 'ubbf.schemas.Hosts';
import { schedule_refs_check, schedule_refs_prune } from 'ubbf';

const REF = 'Device.Hosts.AccessControl.1.ScheduleRef';

// With UBBF_BUILD_DIR the entries name the compiled table, as on a device;
// without it they carry the schema objects.
function module_load() {
	let schemas = {};
	include('../modules/schedules/schema.uc', { schemas });

	let build_dir = getenv('UBBF_BUILD_DIR');
	let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-schedules.so') ?? []);

	let api = {
		ubbf,
		schema: (k) => table ? `schedules.${k}` : schemas[k],
		schema_defaults: (k) => table ? ubbf.schema_defaults(`schedules.${k}`) : schemas[k]?.defaults,
		model: {},
		operations: {}
	};
	include('../modules/schedules/handler.uc', { ubbf_module: api });

	return api;
}

describe('schedules module', () => {
	beforeEach(() => state_clear());

	it('serves Schedule rows and checks and prunes ScheduleRef', () => {
		let api = module_load();
		let installed = false;

		api.model['Device.Hosts'] = {};
		api.model['Device.Hosts.AccessControl'] = {};
		api.model['Device.Hosts.AccessControl.{i}'] = {
			schema: AccessControl,
			// the ScheduleRef check that datamodel.uc installs on such an entry
			set: (ctx) => (ctx.param == 'ScheduleRef') ? schedule_refs_check(ctx.value, ctx.root, installed) : 0
		};

		let dm = ubbf.create();
		assert.match(true, dm.register(api.model), 'model registers');
		dm.load('/dev/null');
		dm.set_config({ Device: {
			Schedules: {},
			Hosts: { AccessControl: { '1': { Enable: 'true', PhysAddress: '02:00:00:00:00:01' } } }
		} });
		dm.runtime_reload();

		let write = (params) => {
			dm.trans_start();
			let rc = dm.params_set(params);
			if (rc < 0) {
				dm.trans_abort();
				return rc;
			}
			dm.trans_commit();
			dm.runtime_reload();
			return rc;
		};

		dm.trans_start();
		let inst = dm.object_add('Device.Schedules.Schedule');
		dm.trans_commit();
		dm.runtime_reload();
		assert.match(1, inst, 'a row is added');

		let sm = dm.get_subtree_with_state('Device.Schedules');
		assert.match('cpe-Schedule1', sm?.Schedule?.['1']?.Alias, 'the core gives the Alias');
		assert.match('1', sm?.ScheduleNumberOfEntries, 'ScheduleNumberOfEntries');
		assert.match([ 'Inactive', '0' ], [ sm?.Schedule?.['1']?.Status, sm?.Schedule?.['1']?.TimeLeft ], 'a new row is disabled');

		assert.match(true, write({ 'Device.Schedules.Schedule.1.StartTime': '7:00' }) < 0, 'a malformed StartTime is refused');
		assert.match(true, write({ 'Device.Schedules.Schedule.1.Day': 'Funday' }) < 0, 'an unknown day is refused');

		assert.match(0, write({
			'Device.Schedules.Schedule.1.Enable': 'true',
			'Device.Schedules.Schedule.1.StartTime': '00:00',
			'Device.Schedules.Schedule.1.Duration': '604800'
		}), 'a whole week schedule');
		sm = dm.get_subtree_with_state('Device.Schedules');
		assert.match([ 'Active', '0' ], [ sm?.Schedule?.['1']?.Status, sm?.Schedule?.['1']?.TimeLeft ],
			'it is active and never changes');

		write({ 'Device.Schedules.Enable': 'false' });
		assert.match('StackDisabled', dm.get_subtree_with_state('Device.Schedules')?.Schedule?.['1']?.Status,
			'StackDisabled while scheduling is off');
		write({ 'Device.Schedules.Enable': 'true' });

		write({ 'Device.Schedules.Schedule.1.StartTime': '' });
		assert.match('Error', dm.get_subtree_with_state('Device.Schedules')?.Schedule?.['1']?.Status,
			'a daily allowance is an error');

		assert.match(-USP_ERR_INVALID_VALUE, write({ [REF]: 'Device.Schedules.Schedule.1' }),
			'without the module a reference is refused');
		assert.match(0, write({ [REF]: '' }), 'without the module an empty value is accepted');

		installed = true;
		assert.match(-USP_ERR_INVALID_VALUE, write({ [REF]: 'Device.Schedules.Schedule.2' }),
			'a reference to a missing row is refused');
		assert.match(0, write({ [REF]: 'Device.Schedules.Schedule.1' }), 'a reference to the row is accepted');
		assert.match(0, write({ 'Device.Hosts.AccessControl.1.HostName': 'pc' }), 'another parameter is not checked');

		dm.trans_start();
		dm.object_add('Device.Schedules.Schedule');
		dm.trans_commit();
		write({ [REF]: 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.2' });

		dm.trans_start();
		dm.object_del('Device.Schedules.Schedule.1');
		dm.trans_commit();
		assert.match(true, schedule_refs_prune(dm.config()), 'prune reports a change');
		assert.match('Device.Schedules.Schedule.2', dm.config()?.Device?.Hosts?.AccessControl?.['1']?.ScheduleRef,
			'the reference to the deleted row is gone');
		assert.match(false, schedule_refs_prune(dm.config()), 'prune again changes nothing');
	});
});
