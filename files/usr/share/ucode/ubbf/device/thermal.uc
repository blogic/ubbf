'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import * as uloop from 'uloop';

const TEMP_DEFAULT_POLL_MS = 30000;
const ABSOLUTE_ZERO = -274;

let sensors = {};
let temp_timer;

/**
 * Discovers thermal zones from sysfs and updates the sensors table.
 */
function thermal_zones_discover() {
	let found = {};
	let dir = fs.opendir('/sys/class/thermal');
	if (!dir)
		return;

	let entry;
	while ((entry = dir.read()) != null) {
		if (index(entry, 'thermal_zone') != 0)
			continue;

		let path = '/sys/class/thermal/' + entry;
		let name = ubbf.readfile_trim(path + '/type', '');
		if (name == '')
			continue;

		found[name] = path;

		if (sensors[name])
			continue;

		sensors[name] = {
			name,
			path,
			value: ABSOLUTE_ZERO,
			enabled: true,
			min_value: ABSOLUTE_ZERO,
			max_value: ABSOLUTE_ZERO,
			min_time: 0,
			max_time: 0,
			last_update: 0,
			reset_time: time(),
			low_alarm_value: ABSOLUTE_ZERO,
			high_alarm_value: ABSOLUTE_ZERO,
			low_alarm_time: 0,
			high_alarm_time: 0,
			polling_interval: 0
		};
	}
	dir.close();

	for (let name in sensors) {
		if (!(name in found))
			delete sensors[name];
	}
}

/**
 * Samples temperature for a single sensor and updates tracking state.
 *
 * @param {object} sensor - Sensor entry from the sensors table
 */
function thermal_zone_sample(sensor) {
	// sentinel below absolute zero in millidegrees, unreachable as a real reading
	let temp_raw = ubbf.readfile_int(sensor.path + '/temp', ABSOLUTE_ZERO * 1000);
	if (temp_raw == ABSOLUTE_ZERO * 1000)
		return;

	let temp = int(temp_raw / 1000);
	let now = time();

	sensor.value = temp;
	sensor.last_update = now;

	if (sensor.min_value == ABSOLUTE_ZERO || temp < sensor.min_value) {
		sensor.min_value = temp;
		sensor.min_time = now;
	}

	if (sensor.max_value == ABSOLUTE_ZERO || temp > sensor.max_value) {
		sensor.max_value = temp;
		sensor.max_time = now;
	}

	if (sensor.low_alarm_value != ABSOLUTE_ZERO &&
	    temp <= sensor.low_alarm_value && sensor.low_alarm_time == 0)
		sensor.low_alarm_time = now;

	if (sensor.high_alarm_value != ABSOLUTE_ZERO &&
	    temp >= sensor.high_alarm_value && sensor.high_alarm_time == 0)
		sensor.high_alarm_time = now;
}

/**
 * Polls all enabled sensors and reschedules the timer.
 */
function temperature_poll() {
	thermal_zones_discover();

	for (let name in sensors) {
		if (sensors[name].enabled)
			thermal_zone_sample(sensors[name]);
	}

	let interval = TEMP_DEFAULT_POLL_MS;
	for (let name in sensors) {
		let s = sensors[name];
		if (s.enabled && s.polling_interval > 0) {
			let ms = s.polling_interval * 1000;
			if (ms < interval)
				interval = ms;
		}
	}

	temp_timer = uloop.timer(interval, temperature_poll);
}

/**
 * Returns the sensors array in stable name-sorted order.
 *
 * @returns {array} Sorted sensor objects
 */
function sensors_sorted() {
	let names = sort(keys(sensors));
	return map(names, n => sensors[n]);
}

function temperature_status_handler(req) {
	return { sensors: sensors_sorted() };
}

function temperature_reset_handler(req) {
	let idx = req.args?.index;
	if (idx == null)
		return { error: 'index required' };

	let list = sensors_sorted();
	if (idx < 0 || idx >= length(list))
		return { error: 'invalid index' };

	let s = list[idx];
	let now = time();

	s.min_value = s.value;
	s.max_value = s.value;
	s.min_time = now;
	s.max_time = now;
	s.low_alarm_time = 0;
	s.high_alarm_time = 0;
	s.reset_time = now;

	return { success: true };
}

function temperature_configure_handler(req) {
	let idx = req.args?.index;
	if (idx == null)
		return { error: 'index required' };

	let list = sensors_sorted();
	if (idx < 0 || idx >= length(list))
		return { error: 'invalid index' };

	let s = list[idx];

	if (req.args?.enabled != null)
		s.enabled = req.args.enabled;

	if (req.args?.low_alarm_value != null) {
		if (req.args.low_alarm_value != s.low_alarm_value)
			s.low_alarm_time = 0;
		s.low_alarm_value = req.args.low_alarm_value;
	}

	if (req.args?.high_alarm_value != null) {
		if (req.args.high_alarm_value != s.high_alarm_value)
			s.high_alarm_time = 0;
		s.high_alarm_value = req.args.high_alarm_value;
	}

	if (req.args?.polling_interval != null)
		s.polling_interval = req.args.polling_interval;

	if (temp_timer) {
		temp_timer.cancel();
		temperature_poll();
	}

	return { success: true };
}

/**
 * Discovers thermal zones and starts the polling timer.
 */
export function init() {
	thermal_zones_discover();
	temperature_poll();
};

/**
 * Returns the ubus method table for thermal sensor operations.
 *
 * @returns {object} Method definitions for temperature_status/reset/configure
 */
export function ubus_methods() {
	return {
		temperature_status: {
			call: temperature_status_handler,
			args: {}
		},
		temperature_reset: {
			call: temperature_reset_handler,
			args: { index: 0 }
		},
		temperature_configure: {
			call: temperature_configure_handler,
			args: { index: 0, enabled: true, low_alarm_value: 0, high_alarm_value: 0, polling_interval: 0 }
		}
	};
};
