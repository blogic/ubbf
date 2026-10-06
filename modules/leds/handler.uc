'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;

const fs = require('fs');
const led_lib = require('led');

const schema = ubbf_module.schema;

const LEDS_DIR = '/sys/class/leds';

// RGB of the colour names in include/dt-bindings/leds/common.h that name
// one colour; ir, multicolor and rgb do not.
const LED_COLORS = {
	white: 'FFFFFF',
	red: 'FF0000',
	green: '00FF00',
	blue: '0000FF',
	amber: 'FFBF00',
	violet: '8000FF',
	yellow: 'FFFF00',
	purple: '800080',
	orange: 'FFA500',
	pink: 'FFC0CB',
	cyan: '00FFFF',
	lime: 'BFFF00'
};

/**
 * Lists the LED names, sorted, so the instance numbers follow the names.
 *
 * @returns {array} LED directory names in /sys/class/leds
 */
function leds_list() {
	return sort(fs.lsdir(LEDS_DIR) ?? []);
}

/**
 * Splits a Linux LED name `<device>:<color>:<function>` into its segments.
 *
 * @param {string} name - LED name in /sys/class/leds/
 * @returns {object} `color` and `purpose` (the function segment), '' where
 *                   the name has none
 */
function led_name_parse(name) {
	let parts = split(name, ':');
	let n = length(parts);

	return {
		color: (n > 1) ? parts[n - 2] : '',
		purpose: (n > 1) ? parts[n - 1] : ''
	};
}

/**
 * Finds the network device that drives an LED in the board description:
 * an entry of `led` in /etc/board.json with type netdev. board.json holds
 * the board's intent, so the answer stays while the LED is disabled and
 * its trigger is off.
 *
 * @param {string} name - LED name in /sys/class/leds/
 * @returns {string|null} Device name, for example lan1
 */
function led_board_device(name) {
	let board;
	try {
		board = json(fs.readfile('/etc/board.json') ?? 'null');
	}
	catch (e) {
		return null;
	}

	for (let id, led in (board?.led ?? {}))
		if (led?.sysfs == name && led?.type == 'netdev' && led?.device)
			return led.device;

	return null;
}

/**
 * Builds the reference to the Ethernet interface that drives an LED.
 *
 * @param {string} name - LED name in /sys/class/leds/
 * @param {object} root - Root data model object
 * @returns {string} Device.Ethernet.Interface.{i}, or '' for none
 */
function controlling_peripheral(name, root) {
	let device = led_board_device(name);
	if (!device)
		return '';

	for (let key, iface in (root?.Device?.Ethernet?.Interface ?? {}))
		if (iface?.Name == device)
			return `Device.Ethernet.Interface.${key}`;

	return '';
}

/**
 * Reads LED data from sysfs and converts to TR-181 format.
 *
 * @param {string} name - LED name in /sys/class/leds/
 * @param {object} root - Root data model object
 * @returns {object|null} TR-181 LED object with status and properties
 */
function led_to_object(name, root) {
	let info = led_lib.read_info(name);
	if (!info)
		return null;

	info.Alias = ubbf.alias_from_name(name);
	info.Reason = led_name_parse(name).purpose;
	info.ControllingPeripheral = controlling_peripheral(name, root);
	return info;
}

/**
 * Get handler for Device.LEDs.
 *
 * @param {object} ctx - Context object
 * @returns {object} LEDs properties with entry count
 */
function leds_get(ctx) {
	let stored = ubbf.instance_count(ctx.config?.LED);

	return {
		LEDNumberOfEntries: sprintf('%d', stored || length(leds_list()))
	};
}

/**
 * Get handler for Device.LEDs.LED.{i}.
 *
 * A stored row (ubbf-leds-rows writes one per LED) names its LED in Name.
 * Enable and Status come from sysfs: a disabled LED is dark and has no
 * trigger. Without stored rows the LEDs are listed from sysfs.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single LED or enumerated LEDs
 */
function led_get(ctx) {
	if (ctx.config) {
		if (!ctx.config.Name)
			return null;

		let info = led_to_object(ctx.config.Name, ctx.root);
		if (!info)
			return null;

		return { ...info, Alias: ctx.config.Alias ?? info.Alias };
	}

	let leds = leds_list();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(leds, (name) => led_to_object(name, ctx.root));

	let led = ubbf.get_by_instance(leds, ctx.instance);
	if (!led)
		return null;
	return led_to_object(led, ctx.root);
}

/**
 * Get handler for Device.LEDs.LED.{i}.CurrentCycleElement.
 *
 * No cycle runs, so the element reference is empty. Color is the colour
 * of the LED while it is in use, '' while it is dark or has no colour.
 *
 * @param {object} ctx - Context with the LED instance number
 * @returns {object|null} Current cycle element of the LED
 */
function current_cycle_element_get(ctx) {
	let led = ctx.parent?.Name ?? ubbf.get_by_instance(leds_list(), ctx.instance);
	if (!led)
		return null;

	let info = led_lib.read_info(led);
	let color = (info?.Status == 'InUse') ? LED_COLORS[led_name_parse(led).color] : null;

	return {
		CycleElementReference: '',
		Color: color ?? '',
		Duration: '0'
	};
}

/**
 * Get handler for Device.LEDs.LED.{i}.CycleElement.{i}.
 *
 * LED cycles are not implemented, so the table has no rows.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Empty table in enumerate mode, else null
 */
function cycle_element_get(ctx) {
	return (ctx.instance == null) ? {} : null;
}

model['Device.LEDs'] = {
	schema: schema('LEDs'),
	get: leds_get
};

model['Device.LEDs.LED'] = {
};

model['Device.LEDs.LED.{i}'] = {
	schema: schema('LED'),
	get: led_get
};

model['Device.LEDs.LED.{i}.CurrentCycleElement'] = {
	schema: schema('LED_CurrentCycleElement'),
	get: current_cycle_element_get
};

model['Device.LEDs.LED.{i}.CycleElement'] = {
};

// A cycle needs a render to the kernel pattern trigger, which does not
// exist, so a controller cannot add a row.
model['Device.LEDs.LED.{i}.CycleElement.{i}'] = {
	schema: schema('LED_CycleElement'),
	get: cycle_element_get,
	maxInstances: 0
};
