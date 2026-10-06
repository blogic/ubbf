'use strict';

import * as schemas from 'ubbf.schemas.DeviceInfo';
import * as ubbf from 'ubbf';

/**
 * Counts CPU cores from /proc/stat.
 *
 * @returns {number} Number of CPU cores (minimum 1)
 */
export function processor_count() {
	let count = 0;
	for (let key in ubbf.cpu_stats())
		if (key != 'cpu')
			count++;
	return count > 0 ? count : 1;
};

/**
 * Converts a processor index to TR-181 object format.
 *
 * @param {number} idx - 0-based processor index
 * @param {string} arch - Architecture string
 * @returns {object} TR-181 Processor object
 */
function processor_to_object(idx, arch) {
	return {
		Alias: sprintf('cpe-processor%d', idx + 1),
		Architecture: arch
	};
}

/**
 * Builds array of processor indices.
 *
 * @returns {array} Array of 0-based processor indices
 */
function processors_build() {
	let count = processor_count();
	let processors = [];
	for (let i = 0; i < count; i++)
		push(processors, i);
	return processors;
}

/**
 * Get handler for Device.DeviceInfo.Processor.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Processor properties
 */
function get(ctx) {
	let arch = ubbf.arch_get();
	let processors = processors_build();
	let to_object = (idx) => processor_to_object(idx, arch);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(processors, to_object);

	let idx = ubbf.get_by_instance(processors, ctx.instance);
	if (idx == null)
		return null;

	return to_object(idx);
}

export const model = {
	'Device.DeviceInfo.Processor': {
	},

	'Device.DeviceInfo.Processor.{i}': {
		schema: schemas.Processor,
		get: get
	}
};
