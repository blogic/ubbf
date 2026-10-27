'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.
//
// The ubbf-device plugin device/plugins/hardware.uc (files/ of this module)
// holds the button state and the trigger timing, and writes the stored
// cpufreq settings to sysfs; this handler reads its state over ubus.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;

const ubus = require('ubus');

let hardware = {};
include(sourcepath(0, true) + '/hardware.uc', { hardware });

const GOVERNORS = [ 'conservative', 'userspace', 'powersave', 'ondemand', 'performance', 'schedutil' ];

/**
 * Asks the ubbf-device plugin for the button state.
 *
 * @returns {object} { buttons: { name: 'Pressed'|'Released' }, active: [ 'b.t' ] }
 */
function device_status_fetch() {
	return ubus.call('bbf-device', 'hardware_status', {}) ?? { buttons: {}, active: [] };
}

/**
 * Returns the button state, cached for one request.
 *
 * @returns {object} State from device_status_fetch()
 */
function device_status_get() {
	return utils.cache.call(device_status_fetch);
}

/**
 * Enumerates the rows the device makes, without those the configuration
 * stores: the dispatcher reads a stored row in stored mode, and the live
 * row would hide it (writable_rows, docs/MODULE-GUIDELINES.md).
 *
 * @param {array} items - Items in instance order
 * @param {function} to_object - Converter of an item
 * @param {object|null} stored - Stored rows of the table
 * @returns {object} Rows keyed by instance number
 */
function rows_enumerate(items, to_object, stored) {
	let rows = ubbf.enumerate_instances(items, to_object);

	for (let n in keys(stored ?? {}))
		delete rows[n];

	return rows;
}

/**
 * Converts a CPU number to a Device.Hardware.CPUs.CPU row.
 *
 * @param {number} cpu - CPU number
 * @returns {object} Row
 */
function cpu_to_object(cpu) {
	return { Alias: sprintf('cpe-CPU%d', cpu + 1) };
}

/**
 * Get handler for Device.Hardware.CPUs.CPU.{i}: one row per CPU of sysfs,
 * instance CPU number + 1.
 *
 * @param {object} ctx - Context with instance and config
 * @returns {object|null} Row, all rows in enumerate mode, or null
 */
function cpu_get(ctx) {
	let cpus = hardware.cpus_list();

	if (ctx.instance == null)
		return rows_enumerate(cpus, cpu_to_object, ctx.root?.Device?.Hardware?.CPUs?.CPU);

	let cpu = ubbf.get_by_instance(cpus, ctx.instance);
	if (cpu == null)
		return null;

	return { ...cpu_to_object(cpu), ...ubbf.ctx_config(ctx) };
}

/**
 * Splits a space separated sysfs list.
 *
 * @param {string|null} value - Attribute value
 * @returns {array} Items
 */
function words(value) {
	return filter(split(value ?? '', ' '), (w) => w != '');
}

/**
 * Reads the live DVFS state of a CPU from cpufreq.
 *
 * @param {number|null} cpu - CPU number
 * @returns {object} DVFS object, Unsupported without cpufreq
 */
function dvfs_read(cpu) {
	let dir = (cpu == null) ? null : hardware.cpufreq_dir(cpu);
	if (!dir)
		return { ...schema_defaults('DVFS') };

	let read = (name) => hardware.cpufreq_read(dir, name);

	return {
		...schema_defaults('DVFS'),
		Enable: 'true',
		Status: 'Enabled',
		Supported: 'true',
		CurrentFrequency: read('scaling_cur_freq') ?? '0',
		MinFrequency: read('cpuinfo_min_freq') ?? '0',
		MaxFrequency: read('cpuinfo_max_freq') ?? '0',
		ScalingMinFrequency: read('scaling_min_freq') ?? '0',
		ScalingMaxFrequency: read('scaling_max_freq') ?? '0',
		ScalingAvailableFrequencies: join(',', words(read('scaling_available_frequencies'))),
		ScalingGovernor: read('scaling_governor') ?? '',
		ScalingAvailableGovernors: join(',', filter(words(read('scaling_available_governors')),
			(g) => index(GOVERNORS, g) >= 0))
	};
}

/**
 * Get handler for Device.Hardware.CPUs.CPU.{i}.DVFS: the live cpufreq
 * values. The plugin writes the stored settings to sysfs after each
 * commit, so the live values show them.
 *
 * @param {object} ctx - Context with the instance of the CPU
 * @returns {object} DVFS object
 */
function dvfs_get(ctx) {
	return dvfs_read(ubbf.get_by_instance(hardware.cpus_list(), ctx.instances?.[0]));
}

/**
 * Checks a scaling frequency against the limits of the CPU (TR-181:
 * between MinFrequency and MaxFrequency, in ScalingAvailableFrequencies,
 * ScalingMinFrequency below ScalingMaxFrequency).
 *
 * @param {object} ctx - Set context
 * @param {object} live - Live DVFS object
 * @returns {number} 0, or -USP_ERR_INVALID_VALUE
 */
function frequency_check(ctx, live) {
	let value = ubbf.to_int(ctx.value);
	if (value == null || value < +live.MinFrequency || value > +live.MaxFrequency)
		return -USP_ERR_INVALID_VALUE;

	let available = ubbf.csv_to_list(live.ScalingAvailableFrequencies, '');
	if (length(available) && index(available, sprintf('%d', value)) < 0)
		return -USP_ERR_INVALID_VALUE;

	let min = (ctx.param == 'ScalingMinFrequency') ? value
		: ubbf.to_int(ctx.config?.ScalingMinFrequency ?? live.ScalingMinFrequency);
	let max = (ctx.param == 'ScalingMaxFrequency') ? value
		: ubbf.to_int(ctx.config?.ScalingMaxFrequency ?? live.ScalingMaxFrequency);

	return (min < max) ? 0 : -USP_ERR_INVALID_VALUE;
}

/**
 * Set handler for Device.Hardware.CPUs.CPU.{i}.DVFS. Linux has no switch
 * that turns frequency scaling off, so Enable accepts only true (decision
 * of 2026-10-18).
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or -USP_ERR_INVALID_VALUE
 */
function dvfs_set(ctx) {
	let live = dvfs_read(ubbf.get_by_instance(hardware.cpus_list(), ctx.instance));

	switch (ctx.param) {
	case 'Enable':
		return ubbf.to_bool(ctx.value) ? 0 : -USP_ERR_INVALID_VALUE;

	case 'ScalingMinFrequency':
	case 'ScalingMaxFrequency':
		if (live.Supported != 'true')
			return -USP_ERR_INVALID_VALUE;
		return frequency_check(ctx, live);

	case 'ScalingGovernor':
		return index(ubbf.csv_to_list(live.ScalingAvailableGovernors, ''), ctx.value) >= 0
			? 0 : -USP_ERR_INVALID_VALUE;
	}

	return 0;
}

/**
 * Converts a button of the device tree to a Device.Hardware.Buttons.Button
 * row. A button whose key code gpio-button-hotplug does not map sends no
 * event, so its Status is Error_Misconfigured.
 *
 * @param {object} button - Button from hardware.buttons_list()
 * @returns {object} Row
 */
function button_to_object(button) {
	let state = device_status_get().buttons?.[button.name];

	return {
		...schema_defaults('Button'),
		Alias: ubbf.alias_from_name(button.name ?? button.key),
		Name: button.name ?? button.key,
		Status: button.name ? (state ?? 'Released') : 'Error_Misconfigured',
		InputFile: button.device ? 'file://' + button.device : ''
	};
}

/**
 * Get handler for Device.Hardware.Buttons.Button.{i}: one row per button of
 * the gpio-keys nodes, in device tree order. A stored row keeps the Name a
 * controller wrote.
 *
 * @param {object} ctx - Context with instance and config
 * @returns {object|null} Row, all rows in enumerate mode, or null
 */
function button_get(ctx) {
	let buttons = hardware.buttons_list();

	if (ctx.instance == null)
		return rows_enumerate(buttons, button_to_object, ctx.root?.Device?.Hardware?.Buttons?.Button);

	let button = ubbf.get_by_instance(buttons, ctx.instance);
	if (!button)
		return null;

	let row = button_to_object(button);
	let config = ubbf.ctx_config(ctx);

	return {
		...config,
		...row,
		Name: config.Name ?? row.Name,
		TriggerConditionNumberOfEntries: sprintf('%d', ubbf.instance_count(config.TriggerCondition))
	};
}

/**
 * Set handler for the tables the device makes (CPU.{i}, Button.{i}): it
 * lets the dispatcher store a row the device makes, for Alias and Name.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0
 */
function row_set(ctx) {
	return 0;
}

/**
 * Get handler for Device.Hardware.Buttons.Button.{i}.TriggerCondition.{i}:
 * the stored row, Active from the ubbf-device plugin.
 *
 * @param {object} ctx - Context with config and the instance numbers
 * @returns {object|null} Row
 */
function trigger_get(ctx) {
	if (!ctx.config)
		return null;

	let key = join('.', ctx.instances ?? []);
	let active = index(device_status_get().active ?? [], key) >= 0;

	return {
		...schema_defaults('TriggerCondition'),
		...ctx.config,
		Active: active ? 'true' : 'false'
	};
}

/**
 * Handler of Push() and Release(): the plugin simulates the button, runs
 * /etc/rc.button/<name> as procd does for a real press, and evaluates the
 * trigger conditions.
 *
 * @param {string} action - 'push' or 'release'
 * @returns {function} Async operation handler
 */
function simulate_op(action) {
	return (input, instance, complete, instances, command_key, root) => {
		let button = ubbf.get_by_instance(hardware.buttons_list(), instances?.[0]);
		if (!button?.name) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'the button sends no events', {});
			return;
		}

		let duration = ubbf.to_int(input?.Duration ?? '0');
		if (duration == null || duration < 0) {
			complete(instance, USP_ERR_INVALID_COMMAND_ARGS, 'Duration must be a number of milliseconds', {});
			return;
		}

		let res = ubus.call('bbf-device', 'button_simulate', { button: button.name, action, duration });
		if (res == null) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'ubbf-device did not answer', {});
			return;
		}

		utils.cache.invalidate(device_status_fetch);
		complete(instance, 0, null, {});
	};
}

model['Device.Hardware'] = {
	schema: schema('Hardware'),
	since: '2.20'
};

model['Device.Hardware.CPUs'] = {
	schema: schema('CPUs'),
	since: '2.20'
};

model['Device.Hardware.CPUs.CPU'] = {};

model['Device.Hardware.CPUs.CPU.{i}'] = {
	schema: schema('CPU'),
	get: cpu_get,
	set: row_set,
	runtime_instances: true,
	writable_rows: true,
	since: '2.20'
};

model['Device.Hardware.CPUs.CPU.{i}.DVFS'] = {
	schema: schema('DVFS'),
	get: dvfs_get,
	set: dvfs_set,
	since: '2.20'
};

model['Device.Hardware.Buttons'] = {
	schema: schema('Buttons'),
	since: '2.21'
};

model['Device.Hardware.Buttons.Button'] = {};

model['Device.Hardware.Buttons.Button.{i}'] = {
	schema: schema('Button'),
	get: button_get,
	set: row_set,
	runtime_instances: true,
	writable_rows: true,
	since: '2.21'
};

model['Device.Hardware.Buttons.Button.{i}.TriggerCondition'] = {};

model['Device.Hardware.Buttons.Button.{i}.TriggerCondition.{i}'] = {
	schema: schema('TriggerCondition'),
	get: trigger_get,
	since: '2.21'
};

operations['Device.Hardware.Buttons.Button.{i}.Push()'] = {
	type: 'async',
	handler: simulate_op('push')
};

operations['Device.Hardware.Buttons.Button.{i}.Release()'] = {
	type: 'async',
	handler: simulate_op('release')
};
