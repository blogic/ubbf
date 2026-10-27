// Host test of the hardware module on the native dispatcher: the CPU rows
// and their DVFS values from cpufreq with the checks of a write, and the
// button rows from the gpio-keys nodes of the device tree, with stored
// Name and TriggerCondition rows. ubbf-device does not run, so the button
// state is the default. Run from the repository root in a private mount
// namespace, with the native module built for the host:
//   unshare -rm sh -c 'mount -t tmpfs none /sys && UBBF_BUILD_DIR=<host build> \
//     ucode -L "$PWD/tests/hardware/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/hardware.uc'
'use strict';

import * as ubbf from 'ubbf';
import { build } from 'hardware_fixtures';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

build();

let schemas = {};
include('../modules/hardware/schema.uc', { schemas });

let build_dir = getenv('UBBF_BUILD_DIR');
let table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-hardware.so') ?? []);
printf('schemas: %s\n', table ? 'compiled table' : 'objects');

const api = {
	ubbf,
	utils: { cache: { call: (fn, ...args) => fn(...args), invalidate: () => null } },
	schema: (k) => table ? `hardware.${k}` : schemas[k],
	schema_defaults: (k) => table ? ubbf.schema_defaults(`hardware.${k}`) : schemas[k]?.defaults,
	model: {},
	operations: {}
};
include('../modules/hardware/handler.uc', { ubbf_module: api });

let dm = ubbf.create();
check('model registers', dm.register(api.model), true);
dm.load('/dev/null');
dm.set_config({ Device: { Hardware: { CPUs: {}, Buttons: {} } } });
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

let hw = dm.get_subtree_with_state('Device.Hardware');
check('CPUNumberOfEntries', hw?.CPUs?.CPUNumberOfEntries, '3');
check('the CPU rows', map(sort(keys(hw?.CPUs?.CPU ?? {})), (k) => hw.CPUs.CPU[k].Alias),
	[ 'cpe-CPU1', 'cpe-CPU2', 'cpe-CPU3' ]);

let dvfs = hw?.CPUs?.CPU?.['1']?.DVFS;
check('DVFS of a CPU with cpufreq', [ dvfs?.Supported, dvfs?.Status, dvfs?.Enable, dvfs?.CurrentFrequency,
	dvfs?.MinFrequency, dvfs?.MaxFrequency, dvfs?.ScalingGovernor ],
	[ 'true', 'Enabled', 'true', '875000', '437500', '1750000', 'schedutil' ]);
check('the frequencies are a list', dvfs?.ScalingAvailableFrequencies, '437500,875000,1312500,1750000');
check('the governors are a list', dvfs?.ScalingAvailableGovernors, 'ondemand,userspace,performance,schedutil');
check('DVFS of a CPU without cpufreq', [ hw?.CPUs?.CPU?.['3']?.DVFS?.Supported, hw?.CPUs?.CPU?.['3']?.DVFS?.Status ],
	[ 'false', 'Unsupported' ]);

const D = 'Device.Hardware.CPUs.CPU.1.DVFS.';
check('Enable false is refused', write({ [D + 'Enable']: 'false' }), -USP_ERR_INVALID_VALUE);
check('Enable true is accepted', write({ [D + 'Enable']: 'true' }), 0);
check('a frequency outside the list is refused', write({ [D + 'ScalingMaxFrequency']: '1000000' }),
	-USP_ERR_INVALID_VALUE);
check('a frequency above MaxFrequency is refused', write({ [D + 'ScalingMaxFrequency']: '2000000' }),
	-USP_ERR_INVALID_VALUE);
check('ScalingMaxFrequency at ScalingMinFrequency is refused', write({ [D + 'ScalingMaxFrequency']: '437500' }),
	-USP_ERR_INVALID_VALUE);
check('a valid ScalingMaxFrequency', write({ [D + 'ScalingMaxFrequency']: '1312500' }), 0);
check('ScalingMinFrequency above the stored maximum is refused',
	write({ [D + 'ScalingMinFrequency']: '1750000' }), -USP_ERR_INVALID_VALUE);
check('an unknown governor is refused', write({ [D + 'ScalingGovernor']: 'conservative' }), -USP_ERR_INVALID_VALUE);
check('a known governor', write({ [D + 'ScalingGovernor']: 'performance' }), 0);
check('the write is stored for the plugin',
	dm.config()?.Device?.Hardware?.CPUs?.CPU?.['1']?.DVFS,
	{ Enable: 'true', ScalingMaxFrequency: '1312500', ScalingGovernor: 'performance' });
check('a frequency on a CPU without cpufreq is refused',
	write({ 'Device.Hardware.CPUs.CPU.3.DVFS.ScalingMaxFrequency': '875000' }), -USP_ERR_INVALID_VALUE);

let b = hw?.Buttons?.Button ?? {};
check('ButtonNumberOfEntries', hw?.Buttons?.ButtonNumberOfEntries, '3');
check('the buttons in device tree order', map(sort(keys(b)), (k) => [ b[k].Name, b[k].Status, b[k].Alias ]), [
	[ 'key-mystery', 'Error_Misconfigured', 'cpe-key-mystery' ],
	[ 'reset', 'Released', 'cpe-reset' ],
	[ 'wps', 'Released', 'cpe-wps' ]
]);
check('InputFile names the gpio-keys device', b['2']?.InputFile, 'file:///sys/devices/platform/gpio-keys');
check('Label and Location are not supported', [ b['2']?.Label, b['2']?.Location ], [ null, null ]);

check('a Name write into a button', write({ 'Device.Hardware.Buttons.Button.3.Name': 'pairing' }), 0);
check('the button keeps the written Name',
	dm.get_subtree_with_state('Device.Hardware.Buttons')?.Button?.['3']?.Name, 'pairing');

dm.trans_start();
let t = dm.object_add('Device.Hardware.Buttons.Button.2.TriggerCondition');
dm.trans_commit();
dm.runtime_reload();
check('a trigger condition is added below a button', t, 1);
let row = dm.get_subtree_with_state('Device.Hardware.Buttons')?.Button?.['2'];
check('the trigger row', [ row?.TriggerConditionNumberOfEntries, row?.TriggerCondition?.['1']?.Alias,
	row?.TriggerCondition?.['1']?.Active, row?.TriggerCondition?.['1']?.Type ],
	[ '1', 'cpe-TriggerCondition1', 'false', 'Pressed' ]);
check('an unknown Type is refused',
	write({ 'Device.Hardware.Buttons.Button.2.TriggerCondition.1.Type': 'DoubleClick' }) < 0, true);

dm.trans_start();
check('no trigger condition below a button that does not exist',
	dm.object_add('Device.Hardware.Buttons.Button.9.TriggerCondition'), 0);
dm.trans_abort();

function operate(path, n, input) {
	let res;
	api.operations[path].handler(input, 1, (inst, err, msg, out) => { res = [ err, msg ]; }, [ n ], '', null);
	return res;
}

const PUSH = 'Device.Hardware.Buttons.Button.{i}.Push()';
check('Push() of a button without events', operate(PUSH, 1, {}),
	[ USP_ERR_COMMAND_FAILURE, 'the button sends no events' ]);
check('Push() with a bad Duration', operate(PUSH, 2, { Duration: 'x' })?.[0], USP_ERR_INVALID_COMMAND_ARGS);
check('Push() without ubbf-device', operate(PUSH, 2, { Duration: '100' }),
	[ USP_ERR_COMMAND_FAILURE, 'ubbf-device did not answer' ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
