'use strict';

import * as ubbf from 'ubbf';

/**
 * Get handler for Device.Hosts.AccessControl.{i}.
 *
 * @param {object} ctx - Context with instance number
 * @returns {object} AccessControl entry with computed ScheduleNumberOfEntries
 */
function access_control_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ScheduleNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Schedule))
	};
}

/**
 * Get handler for Device.Hosts.
 *
 * The Host table comes from the module ubbf-mod-hosts. When the module
 * enumerates rows, the dispatcher overwrites HostNumberOfEntries with their
 * count; without the module the table is empty.
 *
 * @param {object} ctx - Context object
 * @returns {object} Hosts container counts
 */
function hosts_get(ctx) {
	return {
		...ubbf.schema_defaults('Hosts.Hosts'),
		...ubbf.ctx_config(ctx),
		HostNumberOfEntries: '0',
		AccessControlNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AccessControl))
	};
}

export const model = {
	'Device.Hosts': {
		schema: 'Hosts.Hosts',
		get: hosts_get
	},

	'Device.Hosts.AccessControl': {
	},

	'Device.Hosts.AccessControl.{i}': {
		schema: 'Hosts.AccessControl',
		get: access_control_get
	},

	'Device.Hosts.AccessControl.{i}.Schedule': {
		until: '2.21'
	},

	'Device.Hosts.AccessControl.{i}.Schedule.{i}': {
		schema: 'Hosts.AccessControl_Schedule',
		until: '2.21'
	}
};
