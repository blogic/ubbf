'use strict';

import * as ubus from 'ubus';
import * as cache from 'ubbf.utils.cache';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { datetime_format } from 'ubbf.utils.helpers';
import * as ubbf from 'ubbf';

/**
 * Fetches cached temperature data from bbf-device daemon.
 *
 * @returns {object} Daemon response with sensors array
 */
function daemon_status_get() {
	return cache.call(function() {
		return ubus.call('bbf-device', 'temperature_status', {}) ?? {};
	});
}

/**
 * Maps a daemon sensor object to TR-181 TemperatureSensor parameters.
 *
 * @param {object} sensor - Sensor object from daemon
 * @returns {object} TR-181 formatted parameter object
 */
function zone_to_object(sensor) {
	return {
		Alias: ubbf.alias_from_name(sensor.name),
		Enable: sensor.enabled ? 'true' : 'false',
		Status: sensor.enabled ? 'Enabled' : 'Disabled',
		ResetTime: datetime_format(sensor.reset_time),
		Name: sensor.name,
		Value: sprintf('%d', sensor.value),
		LastUpdate: datetime_format(sensor.last_update),
		MinValue: sprintf('%d', sensor.min_value),
		MinTime: datetime_format(sensor.min_time),
		MaxValue: sprintf('%d', sensor.max_value),
		MaxTime: datetime_format(sensor.max_time),
		LowAlarmValue: sprintf('%d', sensor.low_alarm_value),
		LowAlarmTime: datetime_format(sensor.low_alarm_time),
		HighAlarmValue: sprintf('%d', sensor.high_alarm_value),
		HighAlarmTime: datetime_format(sensor.high_alarm_time),
		PollingInterval: sprintf('%d', sensor.polling_interval)
	};
}

/**
 * Get handler for Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Temperature sensor properties or all sensors
 */
function sensor_get(ctx) {
	let status = daemon_status_get();
	let list = status?.sensors ?? [];

	if (ctx.instance == null)
		return ubbf.enumerate_instances(list, zone_to_object);

	let sensor = ubbf.get_by_instance(list, ctx.instance);
	if (!sensor)
		return null;

	return zone_to_object(sensor);
}

/**
 * Set handler for Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}.
 *
 * @param {object} ctx - Context with instance and updated config
 */
function sensor_set(ctx) {
	let config = ctx.config ?? {};
	ubus.call('bbf-device', 'temperature_configure', {
		index: ctx.instance - 1,
		enabled: ubbf.to_bool(config.Enable ?? 'true'),
		low_alarm_value: int(config.LowAlarmValue ?? '-274'),
		high_alarm_value: int(config.HighAlarmValue ?? '-274'),
		polling_interval: int(config.PollingInterval ?? '0')
	});
}

/**
 * Get handler for Device.DeviceInfo.TemperatureStatus.
 *
 * @param {object} ctx - Context
 * @returns {object} Temperature status with sensor count
 */
function status_get(ctx) {
	let status = daemon_status_get();
	let list = status?.sensors ?? [];

	return {
		TemperatureSensorNumberOfEntries: sprintf('%d', length(list))
	};
}

/**
 * Sync operation handler for TemperatureSensor.{i}.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function reset_op(input, command_key, instances) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let result = ubus.call('bbf-device', 'temperature_reset', { index: idx - 1 });
	if (!result || result.error)
		return null;

	return {};
}

export const model = {
	'Device.DeviceInfo.TemperatureStatus': {
		schema: schemas.TemperatureStatus,
		get: status_get
	},

	'Device.DeviceInfo.TemperatureStatus.TemperatureSensor': {
	},

	'Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}': {
		schema: schemas.TemperatureStatus_TemperatureSensor,
		get: sensor_get,
		set: sensor_set
	}
};

export const operations = {
	'Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}.Reset()': {
		type: 'sync',
		handler: reset_op
	}
};
