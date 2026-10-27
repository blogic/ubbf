'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.
//
// The core handles ScheduleRef of every object: the check on a write, the
// removal of references to a deleted row, and the rules in the firewall
// templates (utils/schedule.uc). This module provides the table.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;

/**
 * Tells whether scheduling is on: Device.Schedules.Enable of a tree.
 *
 * @param {object} root - Configuration or runtime tree
 * @returns {boolean} True when scheduling is on
 */
function stack_enabled(root) {
	return ubbf.to_bool(root?.Device?.Schedules?.Enable ?? 'true');
}

/**
 * Get handler for Device.Schedules.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Schedules with ScheduleNumberOfEntries
 */
function schedules_get(ctx) {
	return {
		...schema_defaults('Schedules'),
		...ubbf.ctx_config(ctx),
		ScheduleNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Schedule))
	};
}

/**
 * Get handler for Device.Schedules.Schedule.{i}: Status and TimeLeft at the
 * current local time.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} Schedule row, or null when it does not exist
 */
function schedule_get(ctx) {
	if (!ctx.config)
		return null;

	let row = { ...schema_defaults('Schedule'), ...ctx.config };
	let state = utils.schedule.schedule_state(row, stack_enabled(ctx.root),
		utils.schedule.week_seconds(localtime(time())));

	return { ...row, Status: state.status, TimeLeft: sprintf('%d', state.time_left) };
}

/**
 * Set handler for Device.Schedules.Schedule.{i}: StartTime must be empty or
 * hh:mm (TR-181 pattern).
 *
 * @param {object} ctx - Context with param and value
 * @returns {number} 0, or -USP_ERR_INVALID_VALUE to refuse
 */
function schedule_set(ctx) {
	if (ctx.param == 'StartTime' && !utils.schedule.start_time_valid(ctx.value))
		return -USP_ERR_INVALID_VALUE;

	return 0;
}

model['Device.Schedules'] = {
	schema: schema('Schedules'),
	get: schedules_get
};

model['Device.Schedules.Schedule'] = {};

model['Device.Schedules.Schedule.{i}'] = {
	schema: schema('Schedule'),
	get: schedule_get,
	set: schedule_set
};
