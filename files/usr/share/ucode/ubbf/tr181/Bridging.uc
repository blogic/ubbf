'use strict';

import * as schemas from 'ubbf.schemas.Bridging';
import * as ubbf from 'ubbf';
import { ifop_status_derive, bridge_status_derive } from 'ubbf.utils.status';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';

/**
 * Get handler for Device.Bridging.Bridge.{i}.
 *
 * @param {object} ctx - Context with config and instance info
 * @returns {object|null} Bridge properties with runtime status
 */
function bridge_get(ctx) {
	if (!ctx.config || !ctx.config.Name)
		return null;

	return {
		...schemas.Bridge.defaults,
		...ubbf.ctx_config(ctx),
		Status: bridge_status_derive(ctx.config.Enable, ctx.config.Name)
	};
}

/**
 * Get handler for Device.Bridging.Bridge.{i}.STP.
 *
 * @param {object} ctx - Context with config and instance info
 * @returns {object|null} STP properties with status
 */
function bridge_stp_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...schemas.Bridge_STP.defaults,
		...ctx.config
	};
}

/**
 * Resolves a bridge port's underlying kernel netdev.
 *
 * Port.Name is a TR-181 label chosen by the default config (e.g. "lanport1")
 * and is not a kernel netdev. The real netdev is the first entry of
 * LowerLayers, falling back to Port.Name for the management port where
 * LowerLayers is empty and Name is the bridge device itself.
 *
 * @param {object} port - Port data (config or parent)
 * @param {object} [root] - Root data model, required to resolve LowerLayers
 * @returns {string|null} Kernel netdev name, or null when unresolvable
 */
function port_netdev_resolve(port, root) {
	if (port?.LowerLayers && root) {
		let name = ubbf.lower_layer_resolve(root, port.LowerLayers);
		if (name)
			return name;
	}
	return port?.Name;
}

/**
 * Get handler for Device.Bridging.Bridge.{i}.Port.{i}.
 *
 * @param {object} ctx - Context with config and instance info
 * @returns {object|null} Port properties with runtime status
 */
function port_get(ctx) {
	if (!ctx.config)
		return null;

	let netdev = port_netdev_resolve(ctx.config, ctx.root);

	return {
		...schemas.Bridge_Port.defaults,
		...ctx.config,
		Status: ifop_status_derive(ctx.config.Enable, ctx.config.Name,
		                           ctx.config.LowerLayers, ctx.root),
		LastChange: last_change_get(netdev)
	};
}

/**
 * Get handler for Device.Bridging.Bridge.{i}.Port.{i}.Stats.
 *
 * @param {object} ctx - Context with config and parent info
 * @returns {object|null} Interface statistics
 */
function port_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let netdev = port_netdev_resolve(parent, ctx.root);
	if (!netdev)
		return null;

	return ifstats_get(netdev);
}

/**
 * Sync operation handler for Bridging.Bridge.{i}.Port.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match [bridge_idx, port_idx]
 * @returns {object|null} Empty object on success, null on failure
 */
function port_stats_reset(input, command_key, instances, root) {
	let bridge_idx = instances[0];
	let port_idx = instances[1];
	if (bridge_idx == null || port_idx == null)
		return null;

	let port = root?.Device?.Bridging?.Bridge?.['' + bridge_idx]?.Port?.['' + port_idx];
	let netdev = port_netdev_resolve(port, root);
	if (!netdev)
		return null;

	if (!ifstats_reset(netdev))
		return null;
	return {};
}

/**
 * Get handler for Device.Bridging.Bridge.{i}.VLAN.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} VLAN properties
 */
function vlan_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...schemas.Bridge_VLAN.defaults,
		...ctx.config
	};
}

/**
 * Get handler for Device.Bridging.Bridge.{i}.VLANPort.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} VLANPort properties
 */
function vlanport_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...schemas.Bridge_VLANPort.defaults,
		...ctx.config
	};
}

/**
 * Get handler for Device.Bridging.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Bridging properties with instance counts
 */
function bridging_get(ctx) {
	return {
		...schemas.Bridging.defaults,
		...ubbf.ctx_config(ctx),
		BridgeNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Bridge)),
		FilterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Filter)),
		ProviderBridgeNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.ProviderBridge))
	};
}

export const model = {
	'Device.Bridging': {
		schema: schemas.Bridging,
		get: bridging_get
	},

	'Device.Bridging.Bridge': {
	},

	'Device.Bridging.Bridge.{i}': {
		schema: schemas.Bridge,
		get: bridge_get
	},

	'Device.Bridging.Bridge.{i}.STP': {
		schema: schemas.Bridge_STP,
		get: bridge_stp_get,
		enable_status_derive: true
	},

	'Device.Bridging.Bridge.{i}.Port': {
	},

	'Device.Bridging.Bridge.{i}.Port.{i}': {
		schema: schemas.Bridge_Port,
		get: port_get
	},

	'Device.Bridging.Bridge.{i}.Port.{i}.Stats': {
		schema: schemas.Port_Stats,
		get: port_stats_get
	},

	'Device.Bridging.Bridge.{i}.VLAN': {
	},

	'Device.Bridging.Bridge.{i}.VLAN.{i}': {
		schema: schemas.Bridge_VLAN,
		get: vlan_get
	},

	'Device.Bridging.Bridge.{i}.VLANPort': {
	},

	'Device.Bridging.Bridge.{i}.VLANPort.{i}': {
		schema: schemas.Bridge_VLANPort,
		get: vlanport_get
	}
};

export const operations = {
	'Device.Bridging.Bridge.{i}.Port.{i}.Stats.Reset()': {
		type: 'sync',
		handler: port_stats_reset
	}
};
