'use strict';

import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import * as ubbf from 'ubbf';

/**
 * Counts CPU cores from /proc/stat (excluding the aggregate row).
 *
 * @returns {number} Number of CPU cores
 */
function cpu_count() {
	let stats = ubbf.cpu_stats();
	let count = 0;
	for (let key in stats)
		if (key != 'cpu')
			count++;
	return count;
}

/**
 * Enumerates all processes as keyed TR-181 instances.
 *
 * @returns {object} Keyed object of process instances
 */
function enumerate_processes() {
	let result = {};
	let entries = fs.lsdir('/proc');
	if (!entries)
		return result;

	for (let entry in entries) {
		if (!match(entry, /^[0-9]+$/))
			continue;

		let pid = int(entry);
		let info = ubbf.process_info(pid);
		if (!info)
			continue;

		result[sprintf('%d', pid)] = {
			...schemas.ProcessStatus_Process.defaults,
			...info
		};
	}

	return result;
}

/**
 * Enumerates all CPUs as keyed TR-181 instances.
 *
 * @returns {object} Keyed object of CPU instances
 */
function enumerate_cpus() {
	let result = {};
	let uptime = sprintf('%d', ubbf.uptime_read());
	let stats = ubbf.cpu_stats();

	for (let key, val in stats) {
		let m = match(key, /^cpu([0-9]+)$/);
		if (!m)
			continue;
		let cpu_num = int(m[1]);
		result[sprintf('%d', cpu_num + 1)] = {
			...schemas.ProcessStatus_CPU.defaults,
			...val,
			Alias: sprintf('cpe-cpu%d', cpu_num + 1),
			Name: sprintf('cpu%d', cpu_num),
			UpTime: uptime
		};
	}

	return result;
}

/**
 * Reads the 1, 5 and 15 minute load averages from /proc/loadavg.
 *
 * @returns {string} Comma-separated averages, or "" on read failure.
 */
function load_average_read() {
	let data = ubbf.readfile_trim('/proc/loadavg');
	if (!data)
		return '';

	let fields = split(data, /\s+/);
	if (length(fields) < 3)
		return '';

	return sprintf('%s,%s,%s', fields[0], fields[1], fields[2]);
}

/**
 * Get handler for Device.DeviceInfo.ProcessStatus.
 *
 * @param {object} ctx - Context
 * @returns {object} Process status with CPU and process data
 */
function process_status_get(ctx) {
	let cpu_overall = ubbf.cpu_stats().cpu;
	let cpu_usage = cpu_overall ? int(cpu_overall.CPUUtilization) : 0;
	return {
		CPUUsage: sprintf('%d', cpu_usage),
		ProcessNumberOfEntries: sprintf('%d', ubbf.process_count()),
		CPUNumberOfEntries: sprintf('%d', cpu_count()),
		X_UBBF_LoadAverage: load_average_read()
	};
}

/**
 * Get handler for Device.DeviceInfo.ProcessStatus.Process.{i}.
 *
 * @param {object} ctx - Context with instance (PID)
 * @returns {object|null} Process properties
 */
function process_get(ctx) {
	if (ctx.instance == null)
		return enumerate_processes();

	return ubbf.process_info(ctx.instance);
}

/**
 * Get handler for Device.DeviceInfo.ProcessStatus.CPU.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} CPU properties
 */
function cpu_get(ctx) {
	if (ctx.instance == null)
		return enumerate_cpus();

	let cpu_num = ctx.instance - 1;
	let stats = ubbf.cpu_stats()[sprintf('cpu%d', cpu_num)];
	if (!stats)
		return null;

	return {
		...stats,
		Alias: sprintf('cpe-cpu%d', cpu_num + 1),
		Name: sprintf('cpu%d', cpu_num),
		UpTime: sprintf('%d', ubbf.uptime_read())
	};
}

export const model = {
	'Device.DeviceInfo.ProcessStatus': {
		schema: schemas.ProcessStatus,
		get: process_status_get
	},

	'Device.DeviceInfo.ProcessStatus.Process': {
	},

	'Device.DeviceInfo.ProcessStatus.Process.{i}': {
		schema: schemas.ProcessStatus_Process,
		get: process_get
	},

	'Device.DeviceInfo.ProcessStatus.CPU': {
	},

	'Device.DeviceInfo.ProcessStatus.CPU.{i}': {
		schema: schemas.ProcessStatus_CPU,
		get: cpu_get
	}
};
