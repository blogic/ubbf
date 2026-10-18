// Host test of the softwaremodules module on the native dispatcher: the
// rows read from uxc and apk, and writes into those rows. tests/softwaremodules/bin
// holds stand-ins for uxc and apk, which log each call to $SM_LOG. Run from
// the repository root with the native module built for the host:
//   PATH="$PWD/tests/softwaremodules/bin:$PATH" SM_LOG=/tmp/sm.log UBBF_BUILD_DIR=<host build> \
//     ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/softwaremodules.uc
'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { cmd_build, popen_async } from 'ubbf.utils.process';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const LOG = getenv('SM_LOG');

function calls_take() {
	let lines = filter(split(fs.readfile(LOG) ?? '', '\n'), (l) => l != '');
	fs.writefile(LOG, '');
	return filter(lines, (l) => !match(l, /^(uxc (list|--version)|apk query)/));
}

// With UBBF_BUILD_DIR the entries name the compiled table, as on a device;
// without it they carry the schema objects.
let schemas = {};
include('../modules/softwaremodules/schema.uc', { schemas });

let build_dir = getenv('UBBF_BUILD_DIR');
let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-softwaremodules.so') ?? []);
printf('schemas: %s\n', table ? 'compiled table' : 'objects');

const api = {
	ubbf,
	utils: {
		cache: { call: (fn, ...args) => fn(...args), invalidate: () => null },
		helpers: { datetime_format: (t) => t ? sprintf('%d', t) : '0001-01-01T00:00:00Z' },
		logging: { log_err: () => null, log_info: () => null, log_warn: () => null },
		process: { cmd_build, popen_async }
	},
	schema: (k) => table ? `softwaremodules.${k}` : schemas[k],
	schema_defaults: (k) => table ? ubbf.schema_defaults(`softwaremodules.${k}`) : schemas[k]?.defaults,
	on_commit: () => null,
	config_apply: () => ({ success: true }),
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

let sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('execution units by name', map(sort(keys(sm?.ExecutionUnit ?? {})), (k) => sm.ExecutionUnit[k].Name), [ 'db', 'web' ]);
check('deployment units', map(sort(keys(sm?.DeploymentUnit ?? {})), (k) => sm.DeploymentUnit[k].DUID),
	[ 'container-db', 'container-web' ]);
check('ExecutionUnitNumberOfEntries', sm?.ExecutionUnitNumberOfEntries, '2');

dm.trans_start();
let rc = dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.2.AutoStart': 'true' });
dm.trans_commit();
check('write into a live row', rc, 0);
check('the write reaches uxc', calls_take(), [ 'uxc enable web' ]);

dm.runtime_reload();
sm = dm.get_subtree_with_state('Device.SoftwareModules');
check('both rows after the write', map(sort(keys(sm?.ExecutionUnit ?? {})), (k) => sm.ExecutionUnit[k].Name), [ 'db', 'web' ]);
check('no stored copy of the table', dm.config()?.Device?.SoftwareModules?.ExecutionUnit, null);

dm.trans_start();
rc = dm.params_set({ 'Device.SoftwareModules.ExecutionUnit.7.AutoStart': 'true' });
dm.trans_abort();
check('write into a row that does not exist', rc < 0, true);
check('nothing reaches uxc', calls_take(), []);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
