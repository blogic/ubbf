'use strict';

import * as schemas from 'ubbf.schemas.PCP';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.PCP.
 *
 * @param {object} ctx - Context with config
 * @returns {object} PCP root properties
 */
function pcp_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		SupportedVersions: "0,1,2",
		OptionList: "1,3",
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client))
	};
}

/**
 * Get handler for Device.PCP.Client.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} PCP client properties
 */
function client_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Server))
	};
}

/**
 * Get handler for Device.PCP.Client.{i}.Server.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} PCP server properties with mapping counts
 */
function server_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InboundMappingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InboundMapping)),
		OutboundMappingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.OutboundMapping))
	};
}

/**
 * Get handler for Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} InboundMapping properties with filter count
 */
function inbound_mapping_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		FilterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Filter))
	};
}

export const model = {
	'Device.PCP': {
		schema: schemas.PCP,
		get: pcp_get
	},

	'Device.PCP.Client': {
	},

	'Device.PCP.Client.{i}': {
		schema: schemas.Client,
		get: client_get
	},

	'Device.PCP.Client.{i}.Server': {
	},

	'Device.PCP.Client.{i}.Server.{i}': {
		schema: schemas.Client_Server,
		get: server_get
	},

	'Device.PCP.Client.{i}.Server.{i}.InboundMapping': {
	},

	'Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}': {
		schema: schemas.Server_InboundMapping,
		get: inbound_mapping_get
	},

	'Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.Filter': {
	},

	'Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.Filter.{i}': {
		schema: schemas.InboundMapping_Filter
	},

	'Device.PCP.Client.{i}.Server.{i}.OutboundMapping': {
	},

	'Device.PCP.Client.{i}.Server.{i}.OutboundMapping.{i}': {
		schema: schemas.Server_OutboundMapping
	},

	'Device.PCP.Client.{i}.UPnPIWF': {
		schema: schemas.Client_UPnPIWF
	},

	'Device.PCP.Client.{i}.PCPProxy': {
		schema: schemas.Client_PCPProxy
	}
};
