// Host test of the softwaremodules module on the native dispatcher: the
// rows read from uxc and apk with stable instance numbers, and writes into
// those rows, which reach uxc only when the transaction commits.
// tests/softwaremodules/bin holds stand-ins for uxc and apk, which log each
// call to $SM_LOG; uxc lists $SM_LIST when that file exists. The instance
// map lives in /etc/ubbf, so run it in a private mount namespace from the
// repository root, with the native module built for the host:
//   unshare -rm sh -c 'mount -t tmpfs none /etc/ubbf && mount -t tmpfs none /tmp/ubbf &&
//     PATH="$PWD/tests/softwaremodules/bin:$PATH" SM_LOG=/tmp/ubbf/sm.log
//     SM_LIST=/tmp/ubbf/sm-list.json UBBF_BUILD_DIR=<host build>
//     ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode"
//     -L "<host build>/*.so" tests/softwaremodules.uc'
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { cmd_build, popen_async } from 'ubbf.utils.process';
import { instance_numbers, instance_key, instance_rows, instance_seed, instance_prune } from 'ubbf.utils.instance-map';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

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

// With UBBF_BUILD_DIR the entries name the compiled table, as on a device;
// without it they carry the schema objects.
let schemas = {};
include('../modules/softwaremodules/schema.uc', { schemas });

let build_dir = getenv('UBBF_BUILD_DIR');
let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-softwaremodules.so') ?? []);
printf('schemas: %s\n', table ? 'compiled table' : 'objects');

let commit_hook, abort_hook;
let events = [];

// obuspa provides this global; the module reports DUStateChange! with it.
global.usp_datamodel_event = (path, args) => push(events, [ path, args.CurrentState ]);
let applied = [];
let cache = {};

const api = {
	ubbf,
	utils: {
		cache: {
			call: (fn, ...args) => fn(...args),
			invalidate: (fn) => { cache[fn] = true; }
		},
		helpers: { datetime_format: (t) => t ? sprintf('%d', t) : '0001-01-01T00:00:00Z' },
		logging: { log_err: () => null, log_info: () => null, log_warn: () => null },
		process: { cmd_build, popen_async },
		'instance-map': { instance_numbers, instance_key, instance_rows, instance_seed, instance_prune }
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
check('model registers', dm.register(api.model), true);
dm.load('/dev/null');
dm.set_config({ Device: { SoftwareModules: {} } });
dm.runtime_reload();
fs.writefile(LOG, '');

function rows(tree, table, field) {
	let out = {};
	let t = tree?.[table] ?? {};
	for (let n in sort(keys(t), (a, b) => int(a) - int(b)))
		out[n] = t[n][field];
	return out;
}

let sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('execution units, numbered in name order at first', rows(sm, 'ExecutionUnit', 'Name'), { '1': 'db', '2': 'web' });
check('deployment units', rows(sm, 'DeploymentUnit', 'DUID'), { '1': 'container-db', '2': 'container-web' });
check('ExecutionUnitNumberOfEntries', sm?.ExecutionUnitNumberOfEntries, '2');

// A write reaches uxc only when the transaction commits.
dm.trans_start();
check('write into a live row', dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.2.AutoStart': 'true' }), 0);
check('nothing reaches uxc before the commit', calls_take(), []);
dm.trans_commit();
commit_hook();
check('the write reaches uxc at the commit', calls_take(), [ 'uxc enable web' ]);
check('the cache of the stack is dropped', sort(keys(cache)) != [], true);

dm.trans_start();
check('write into a nested object', dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.1.AutoRestart.Enable': 'true' }), 0);
dm.trans_abort();
abort_hook();
commit_hook();
check('an aborted write never reaches uxc', calls_take(), []);

dm.runtime_reload();
sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('both rows after the write', rows(sm, 'ExecutionUnit', 'Name'), { '1': 'db', '2': 'web' });
check('the written row is stored', dm.config()?.Device?.SoftwareModules?.ExecutionUnit?.['2']?.AutoStart, 'true');
check('the stored row shows the stack', sm?.ExecutionUnit?.['2']?.Status, 'Idle');

dm.trans_start();
let rc = dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.7.AutoStart': 'true' });
dm.trans_abort();
abort_hook();
check('write into a row that does not exist', rc < 0, true);
check('nothing reaches uxc', calls_take(), []);

dm.trans_start();
check('ExecEnv Enable', dm.params_set({ 'Device.SoftwareModules.ExecEnv.1.Enable': 'false' }), 0);
dm.trans_commit();
commit_hook();
check('ExecEnv Enable reaches uxc', calls_take(), [ 'uxc disable-all' ]);

// A new registration that sorts first takes a new number; the others keep theirs.
fs.writefile(LIST, sprintf('%J', [ registration('app'), registration('db'), registration('web') ]));
dm.runtime_reload();
sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('numbers stay when a unit comes', rows(sm, 'ExecutionUnit', 'Name'), { '1': 'db', '2': 'web', '3': 'app' });
check('deployment unit numbers stay', rows(sm, 'DeploymentUnit', 'DUID'),
	{ '1': 'container-db', '2': 'container-web', '3': 'container-app' });

fs.writefile(LIST, sprintf('%J', [ registration('app'), registration('web') ]));
dm.runtime_reload();
sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('numbers stay when a unit goes', rows(sm, 'ExecutionUnit', 'Name'), { '2': 'web', '3': 'app' });

dm.trans_start();
check('delete of the stored row of a gone unit', !!dm.object_del('Device.SoftwareModules.ExecutionUnit.1'), true);
dm.trans_commit();

// Uninstall() deletes the stored row of a unit that goes with the package.
fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: { SoftwareModules: { ExecutionUnit: { '2': { AutoStart: 'true' } } } } }));
let done;
uloop.init();
api.operations['Device.SoftwareModules.DeploymentUnit.{i}.Uninstall()'].handler({}, 1,
	(inst, err) => { done = err; uloop.end(); }, [ 2 ], '');
uloop.timer(10000, () => uloop.end());
uloop.run();
check('Uninstall() completes', done, 0);
check('Uninstall() runs apk del', calls_take(), [ 'apk del container-web' ]);
check('Uninstall() reports DUStateChange!', events, [ [ 'Device.SoftwareModules.DUStateChange!', 'Uninstalled' ] ]);
check('Uninstall() deletes the stored row', applied, [ { op: 'del', path: 'Device.SoftwareModules.ExecutionUnit.2.' } ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
