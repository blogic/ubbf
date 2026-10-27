// Host test of the hardware module on the native dispatcher: the CPU rows
// and their DVFS values from cpufreq with the checks of a write, and the
// button rows from the gpio-keys nodes of the device tree, with stored
// Name and TriggerCondition rows. ubbf-device does not run, so the button
// state is the default.
'use strict';

import { describe, it, assert, setup } from 'utest';
import * as ubbf from 'ubbf';
import { state_clear } from 'test_env';
import { build } from '../hardware/hardware_fixtures.uc';

let schemas = {};
include('../../modules/hardware/schema.uc', { schemas });

const build_dir = getenv('UBBF_BUILD_DIR');
const table = build_dir && length(ubbf.schema_tables_load(build_dir + '/schema-hardware.so') ?? []);

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args), cache_invalidate: () => null }, ubbf),
	utils: {},
	schema: (k) => table ? `hardware.${k}` : schemas[k],
	schema_defaults: (k) => table ? ubbf.schema_defaults(`hardware.${k}`) : schemas[k]?.defaults,
	model: {},
	operations: {}
};
include('../../modules/hardware/handler.uc', { ubbf_module: api });

const D = 'Device.Hardware.CPUs.CPU.1.DVFS.';
const PUSH = 'Device.Hardware.Buttons.Button.{i}.Push()';

function dm_new() {
	let dm = ubbf.create();
	assert.match(true, dm.register(api.model), 'model registers');
	dm.load('/dev/null');
	dm.set_config({ Device: { Hardware: { CPUs: {}, Buttons: {} } } });
	dm.runtime_reload();
	return dm;
}

function write(dm, params) {
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

function operate(path, n, input) {
	let res;
	api.operations[path].handler(input, 1, (inst, err, msg, out) => { res = [ err, msg ]; }, [ n ], '', null);
	return res;
}

setup(() => {
	state_clear();
	build();
});

describe('Hardware CPUs', () => {
	it('lists the CPUs with the DVFS values of cpufreq', () => {
		let hw = dm_new().get_subtree_with_state('Device.Hardware');
		assert.match('3', hw?.CPUs?.CPUNumberOfEntries);
		assert.match([ 'cpe-CPU1', 'cpe-CPU2', 'cpe-CPU3' ],
			map(sort(keys(hw?.CPUs?.CPU ?? {})), (k) => hw.CPUs.CPU[k].Alias));

		let dvfs = hw?.CPUs?.CPU?.['1']?.DVFS;
		assert.match([ 'true', 'Enabled', 'true', '875000', '437500', '1750000', 'schedutil' ],
			[ dvfs?.Supported, dvfs?.Status, dvfs?.Enable, dvfs?.CurrentFrequency,
				dvfs?.MinFrequency, dvfs?.MaxFrequency, dvfs?.ScalingGovernor ]);
		assert.match('437500,875000,1312500,1750000', dvfs?.ScalingAvailableFrequencies);
		assert.match('ondemand,userspace,performance,schedutil', dvfs?.ScalingAvailableGovernors);
		assert.match([ 'false', 'Unsupported' ],
			[ hw?.CPUs?.CPU?.['3']?.DVFS?.Supported, hw?.CPUs?.CPU?.['3']?.DVFS?.Status ]);
	});

	it('checks a DVFS write and stores it for the plugin', () => {
		let dm = dm_new();
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'Enable']: 'false' }));
		assert.match(0, write(dm, { [D + 'Enable']: 'true' }));
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'ScalingMaxFrequency']: '1000000' }),
			'a frequency outside the list is refused');
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'ScalingMaxFrequency']: '2000000' }),
			'a frequency above MaxFrequency is refused');
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'ScalingMaxFrequency']: '437500' }),
			'ScalingMaxFrequency at ScalingMinFrequency is refused');
		assert.match(0, write(dm, { [D + 'ScalingMaxFrequency']: '1312500' }));
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'ScalingMinFrequency']: '1750000' }),
			'ScalingMinFrequency above the stored maximum is refused');
		assert.match(-USP_ERR_INVALID_VALUE, write(dm, { [D + 'ScalingGovernor']: 'conservative' }));
		assert.match(0, write(dm, { [D + 'ScalingGovernor']: 'performance' }));
		assert.match({ Enable: 'true', ScalingMaxFrequency: '1312500', ScalingGovernor: 'performance' },
			dm.config()?.Device?.Hardware?.CPUs?.CPU?.['1']?.DVFS);
		assert.match(-USP_ERR_INVALID_VALUE,
			write(dm, { 'Device.Hardware.CPUs.CPU.3.DVFS.ScalingMaxFrequency': '875000' }),
			'a frequency on a CPU without cpufreq is refused');
	});
});

describe('Hardware Buttons', () => {
	it('lists the gpio-keys buttons in device tree order', () => {
		let hw = dm_new().get_subtree_with_state('Device.Hardware');
		let b = hw?.Buttons?.Button ?? {};
		assert.match('3', hw?.Buttons?.ButtonNumberOfEntries);
		assert.match([
			[ 'key-mystery', 'Error_Misconfigured', 'cpe-key-mystery' ],
			[ 'reset', 'Released', 'cpe-reset' ],
			[ 'wps', 'Released', 'cpe-wps' ]
		], map(sort(keys(b)), (k) => [ b[k].Name, b[k].Status, b[k].Alias ]));
		assert.match('file:///sys/devices/platform/gpio-keys', b['2']?.InputFile);
		assert.match([ null, null ], [ b['2']?.Label, b['2']?.Location ], 'Label and Location are not supported');
	});

	it('keeps a written Name', () => {
		let dm = dm_new();
		assert.match(0, write(dm, { 'Device.Hardware.Buttons.Button.3.Name': 'pairing' }));
		assert.match('pairing', dm.get_subtree_with_state('Device.Hardware.Buttons')?.Button?.['3']?.Name);
	});

	it('adds a trigger condition below an existing button only', () => {
		let dm = dm_new();
		dm.trans_start();
		let t = dm.object_add('Device.Hardware.Buttons.Button.2.TriggerCondition');
		dm.trans_commit();
		dm.runtime_reload();
		assert.match(1, t);

		let row = dm.get_subtree_with_state('Device.Hardware.Buttons')?.Button?.['2'];
		assert.match([ '1', 'cpe-TriggerCondition1', 'false', 'Pressed' ],
			[ row?.TriggerConditionNumberOfEntries, row?.TriggerCondition?.['1']?.Alias,
				row?.TriggerCondition?.['1']?.Active, row?.TriggerCondition?.['1']?.Type ]);
		assert.match(true, write(dm, { 'Device.Hardware.Buttons.Button.2.TriggerCondition.1.Type': 'DoubleClick' }) < 0,
			'an unknown Type is refused');

		dm.trans_start();
		assert.match(0, dm.object_add('Device.Hardware.Buttons.Button.9.TriggerCondition'));
		dm.trans_abort();
	});

	it('refuses Push() without ubbf-device', () => {
		dm_new();
		assert.match([ USP_ERR_COMMAND_FAILURE, 'the button sends no events' ], operate(PUSH, 1, {}));
		assert.match(USP_ERR_INVALID_COMMAND_ARGS, operate(PUSH, 2, { Duration: 'x' })?.[0]);
		assert.match([ USP_ERR_COMMAND_FAILURE, 'ubbf-device did not answer' ], operate(PUSH, 2, { Duration: '100' }));
	});
});
