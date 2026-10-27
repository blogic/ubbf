// Host test of the schedules module on the native dispatcher, and of the
// generic ScheduleRef handling of the core: the check that datamodel.uc
// installs on every object with ScheduleRef, and the removal of references
// to a deleted row. Run from the repository root with the native module
// built for the host:
//   UBBF_BUILD_DIR=<host build> ucode -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/schedules.uc
'use strict';

import * as ubbf from 'ubbf';
import { AccessControl } from 'ubbf.schemas.Hosts';
import { schedule_refs_check, schedule_refs_prune } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

// With UBBF_BUILD_DIR the entries name the compiled table, as on a device;
// without it they carry the schema objects.
let schemas = {};
include('../modules/schedules/schema.uc', { schemas });

let build_dir = getenv('UBBF_BUILD_DIR');
let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-schedules.so') ?? []);
printf('schemas: %s\n', table ? 'compiled table' : 'objects');

const api = {
	ubbf,
	schema: (k) => table ? `schedules.${k}` : schemas[k],
	schema_defaults: (k) => table ? ubbf.schema_defaults(`schedules.${k}`) : schemas[k]?.defaults,
	model: {},
	operations: {}
};
include('../modules/schedules/handler.uc', { ubbf_module: api });

let installed = false;

api.model['Device.Hosts'] = {};
api.model['Device.Hosts.AccessControl'] = {};
api.model['Device.Hosts.AccessControl.{i}'] = {
	schema: AccessControl,
	// the ScheduleRef check that datamodel.uc installs on such an entry
	set: (ctx) => (ctx.param == 'ScheduleRef') ? schedule_refs_check(ctx.value, ctx.root, installed) : 0
};

let dm = ubbf.create();
check('model registers', dm.register(api.model), true);
dm.load('/dev/null');
dm.set_config({ Device: {
	Schedules: {},
	Hosts: { AccessControl: { '1': { Enable: 'true', PhysAddress: '02:00:00:00:00:01' } } }
} });
dm.runtime_reload();

function write(params) {
	dm.trans_start();
	let rc = dm.params_set(params);
	if (rc < 0) {
		dm.trans_abort();
		return rc;
	}
	dm.trans_commit();
	dm.runtime_reload();
	return rc;
}

dm.trans_start();
let inst = dm.object_add('Device.Schedules.Schedule');
dm.trans_commit();
dm.runtime_reload();
check('a row is added', inst, 1);

let sm = dm.get_subtree_with_state('Device.Schedules');
check('the core gives the Alias', sm?.Schedule?.['1']?.Alias, 'cpe-Schedule1');
check('ScheduleNumberOfEntries', sm?.ScheduleNumberOfEntries, '1');
check('a new row is disabled', [ sm?.Schedule?.['1']?.Status, sm?.Schedule?.['1']?.TimeLeft ], [ 'Inactive', '0' ]);

check('a malformed StartTime is refused', write({ 'Device.Schedules.Schedule.1.StartTime': '7:00' }) < 0, true);
check('an unknown day is refused', write({ 'Device.Schedules.Schedule.1.Day': 'Funday' }) < 0, true);

check('a whole week schedule', write({
	'Device.Schedules.Schedule.1.Enable': 'true',
	'Device.Schedules.Schedule.1.StartTime': '00:00',
	'Device.Schedules.Schedule.1.Duration': '604800'
}), 0);
sm = dm.get_subtree_with_state('Device.Schedules');
check('it is active and never changes', [ sm?.Schedule?.['1']?.Status, sm?.Schedule?.['1']?.TimeLeft ], [ 'Active', '0' ]);

write({ 'Device.Schedules.Enable': 'false' });
check('StackDisabled while scheduling is off',
	dm.get_subtree_with_state('Device.Schedules')?.Schedule?.['1']?.Status, 'StackDisabled');
write({ 'Device.Schedules.Enable': 'true' });

write({ 'Device.Schedules.Schedule.1.StartTime': '' });
check('a daily allowance is an error',
	dm.get_subtree_with_state('Device.Schedules')?.Schedule?.['1']?.Status, 'Error');

const REF = 'Device.Hosts.AccessControl.1.ScheduleRef';

check('without the module a reference is refused',
	write({ [REF]: 'Device.Schedules.Schedule.1' }), -USP_ERR_INVALID_VALUE);
check('without the module an empty value is accepted', write({ [REF]: '' }), 0);

installed = true;
check('a reference to a missing row is refused',
	write({ [REF]: 'Device.Schedules.Schedule.2' }), -USP_ERR_INVALID_VALUE);
check('a reference to the row is accepted', write({ [REF]: 'Device.Schedules.Schedule.1' }), 0);
check('another parameter is not checked', write({ 'Device.Hosts.AccessControl.1.HostName': 'pc' }), 0);

dm.trans_start();
dm.object_add('Device.Schedules.Schedule');
dm.trans_commit();
write({ [REF]: 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.2' });

dm.trans_start();
dm.object_del('Device.Schedules.Schedule.1');
dm.trans_commit();
check('prune reports a change', schedule_refs_prune(dm.config()), true);
check('the reference to the deleted row is gone',
	dm.config()?.Device?.Hosts?.AccessControl?.['1']?.ScheduleRef, 'Device.Schedules.Schedule.2');
check('prune again changes nothing', schedule_refs_prune(dm.config()), false);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
