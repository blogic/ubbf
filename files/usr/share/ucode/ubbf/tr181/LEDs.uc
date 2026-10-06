'use strict';

import { lsdir } from 'fs';
import * as schemas from 'ubbf.schemas.LEDs';
import * as ubbf from 'ubbf';

/**
 * Reads LED data from sysfs and converts to TR-181 format.
 *
 * @param {string} name - LED name in /sys/class/leds/
 * @returns {object} TR-181 LED object with status and properties
 */
function led_to_object(name) {
	let info = ubbf.led_read_info(name);
	if (info)
		info.Alias = ubbf.alias_from_name(name);
	return info;
}

/**
 * Get handler for Device.LEDs.
 *
 * @param {object} ctx - Context object
 * @returns {object} LEDs properties with entry count
 */
function leds_get(ctx) {
	let leds = lsdir('/sys/class/leds');

	return {
		LEDNumberOfEntries: sprintf('%d', length(leds))
	};
}

/**
 * Get handler for Device.LEDs.LED.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single LED or enumerated LEDs
 */
function led_get(ctx) {
	let leds = lsdir('/sys/class/leds');

	if (ctx.instance == null)
		return ubbf.enumerate_instances(leds, led_to_object);

	let led = ubbf.get_by_instance(leds, ctx.instance);
	if (!led)
		return null;
	return led_to_object(led);
}

export const model = {
	'Device.LEDs': {
		schema: schemas.LEDs,
		get: leds_get
	},
	'Device.LEDs.LED': {
	},
	'Device.LEDs.LED.{i}': {
		schema: schemas.LED,
		get: led_get
	}
};
