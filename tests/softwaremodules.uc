// Host test of the softwaremodules module on the native dispatcher: the
// rows read from uxc and apk with stable instance numbers, and writes into
// those rows, which reach uxc only when the transaction commits. The
// stand-ins for uxc and apk in tests/bin log each call to $SM_LOG; uxc
// lists $SM_LIST when that file exists.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as fs from 'fs';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { popen_async } from 'ubbf.utils.process';

const LOG = getenv('SM_LOG');
const LIST = getenv('SM_LIST');

function calls_take() {
	let lines = filter(split(fs.readfile(LOG) ?? '', '\n'), (l) => l != '');
	fs.writefile(LOG, '');
	return filter(lines, (l) => !match(l, /^(uxc (list|--version)|apk query)/));
}

function registration(name) {
	return { id: name, state: 'stopped',
		'org.openwrt.uxc': { name, package: `container-${name}`, publisher: 'example.org' } };
}

function rows(tree, table, field) {
	let out = {};
	let t = tree?.[table] ?? {};
	for (let n in sort(keys(t), (a, b) => int(a) - int(b)))
		out[n] = t[n][field];
	return out;
}

// With UBBF_BUILD_DIR the entries name the compiled table, as on a device;
// without it they carry the schema objects.
function schema_table() {
	let schemas = {};
	include('../modules/softwaremodules/schema.uc', { schemas });

	let build_dir = getenv('UBBF_BUILD_DIR');
	let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-softwaremodules.so') ?? []);
	return { schemas, table };
}

describe('softwaremodules on the native dispatcher', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
	});

	it('numbers the units stably and passes writes to uxc at the commit', () => {
		let s = schema_table();
		let schemas = s.schemas, table = s.table;
		let commit_hook, abort_hook;
		let events = [];
		let applied = [];
		let cache = {};

		// obuspa provides this global; the module reports DUStateChange! with it.
		global.usp_datamodel_event = (path, args) => push(events, [ path, args.CurrentState ]);

		const api = {
			ubbf: proto({
				datetime_format: (t) => t ? sprintf('%d', t) : '0001-01-01T00:00:00Z',
				cache_call: (fn, ...args) => fn(...args),
				cache_invalidate: (fn) => { cache[fn] = true; }
			}, ubbf),
			utils: {
				process: { popen_async }
			},
			schema: (k) => table ? `softwaremodules.${k}` : schemas[k],
			schema_defaults: (k) => table ? ubbf.schema_defaults(`softwaremodules.${k}`) : schemas[k]?.defaults,
			on_commit: (fn) => { commit_hook = fn; },
			on_abort: (fn) => { abort_hook = fn; },
			config_apply: (ops) => { push(applied, ...ops); return { success: true }; },
			model: {},
			operations: {}
		};
		include('../modules/softwaremodules/handler.uc', { ubbf_module: api });

		let dm = ubbf.create();
		assert.match(true, dm.register(api.model), 'model registers');
		dm.load('/dev/null');
		dm.set_config({ Device: { SoftwareModules: {} } });
		dm.runtime_reload();
		fs.writefile(LOG, '');

		let sm = dm.get_subtree_with_state('Device.SoftwareModules');
		assert.match({ '1': 'db', '2': 'web' }, rows(sm, 'ExecutionUnit', 'Name'), 'execution units, numbered in name order at first');
		assert.match({ '1': 'container-db', '2': 'container-web' }, rows(sm, 'DeploymentUnit', 'DUID'), 'deployment units');
		assert.match('2', sm?.ExecutionUnitNumberOfEntries, 'ExecutionUnitNumberOfEntries');

		// A write reaches uxc only when the transaction commits.
		dm.trans_start();
		assert.match(0, dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.2.AutoStart': 'true' }), 'write into a live row');
		assert.match([], calls_take(), 'nothing reaches uxc before the commit');
		dm.trans_commit();
		commit_hook();
		assert.match([ 'uxc enable web' ], calls_take(), 'the write reaches uxc at the commit');
		assert.match(true, sort(keys(cache)) != [], 'the cache of the stack is dropped');

		dm.trans_start();
		assert.match(0, dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.1.AutoRestart.Enable': 'true' }),
			'write into a nested object');
		dm.trans_abort();
		abort_hook();
		commit_hook();
		assert.match([], calls_take(), 'an aborted write never reaches uxc');

		dm.runtime_reload();
		sm = dm.get_subtree_with_state('Device.SoftwareModules');
		assert.match({ '1': 'db', '2': 'web' }, rows(sm, 'ExecutionUnit', 'Name'), 'both rows after the write');
		assert.match('true', dm.config()?.Device?.SoftwareModules?.ExecutionUnit?.['2']?.AutoStart, 'the written row is stored');
		assert.match('Idle', sm?.ExecutionUnit?.['2']?.Status, 'the stored row shows the stack');

		dm.trans_start();
		let rc = dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.7.AutoStart': 'true' });
		dm.trans_abort();
		abort_hook();
		assert.match(true, rc < 0, 'write into a row that does not exist');
		assert.match([], calls_take(), 'nothing reaches uxc');

		dm.trans_start();
		assert.match(0, dm.params_set({ 'Device.SoftwareModules.ExecEnv.1.Enable': 'false' }), 'ExecEnv Enable');
		dm.trans_commit();
		commit_hook();
		assert.match([ 'uxc disable-all' ], calls_take(), 'ExecEnv Enable reaches uxc');

		// A new registration that sorts first takes a new number; the others
		// keep theirs.
		fs.writefile(LIST, sprintf('%J', [ registration('app'), registration('db'), registration('web') ]));
		dm.runtime_reload();
		sm = dm.get_subtree_with_state('Device.SoftwareModules');
		assert.match({ '1': 'db', '2': 'web', '3': 'app' }, rows(sm, 'ExecutionUnit', 'Name'), 'numbers stay when a unit comes');
		assert.match({ '1': 'container-db', '2': 'container-web', '3': 'container-app' }, rows(sm, 'DeploymentUnit', 'DUID'),
			'deployment unit numbers stay');

		fs.writefile(LIST, sprintf('%J', [ registration('app'), registration('web') ]));
		dm.runtime_reload();
		sm = dm.get_subtree_with_state('Device.SoftwareModules');
		assert.match({ '2': 'web', '3': 'app' }, rows(sm, 'ExecutionUnit', 'Name'), 'numbers stay when a unit goes');

		dm.trans_start();
		assert.match(true, !!dm.object_del('Device.SoftwareModules.ExecutionUnit.1'), 'delete of the stored row of a gone unit');
		dm.trans_commit();

		// Uninstall() deletes the stored row of a unit that goes with the package.
		fs.writefile('/etc/ubbf/config.json',
			sprintf('%J', { Device: { SoftwareModules: { ExecutionUnit: { '2': { AutoStart: 'true' } } } } }));
		let done;
		uloop.init();
		api.operations['Device.SoftwareModules.DeploymentUnit.{i}.Uninstall()'].handler({}, 1,
			(inst, err) => { done = err; uloop.end(); }, [ 2 ], '');
		uloop.timer(10000, () => uloop.end());
		uloop.run();
		assert.match(0, done, 'Uninstall() completes');
		assert.match([ 'apk del container-web' ], calls_take(), 'Uninstall() runs apk del');
		assert.match([ [ 'Device.SoftwareModules.DUStateChange!', 'Uninstalled' ] ], events, 'Uninstall() reports DUStateChange!');
		assert.match([ { op: 'del', path: 'Device.SoftwareModules.ExecutionUnit.2.' } ], applied, 'Uninstall() deletes the stored row');
	});
});
