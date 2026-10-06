'use strict';

import * as schemas from 'ubbf.schemas.QoS';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.QoS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} QoS properties with instance counts
 */
function qos_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ClassificationNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Classification)),
		PolicerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Policer)),
		QueueNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Queue)),
		QueueStatsNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.QueueStats)),
		ShaperNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Shaper))
	};
}

export const model = {
	'Device.QoS': {
		schema: schemas.QoS,
		get: qos_get
	},

	'Device.QoS.Classification': {
	},

	'Device.QoS.Classification.{i}': {
		schema: schemas.Classification
	},

	'Device.QoS.Policer': {
	},

	'Device.QoS.Policer.{i}': {
		schema: schemas.Policer
	},

	'Device.QoS.Queue': {
	},

	'Device.QoS.Queue.{i}': {
		schema: schemas.Queue
	},

	'Device.QoS.QueueStats': {
	},

	'Device.QoS.QueueStats.{i}': {
		schema: schemas.QueueStats
	},

	'Device.QoS.Shaper': {
	},

	'Device.QoS.Shaper.{i}': {
		schema: schemas.Shaper
	}
};
