'use strict';

import * as schemas from 'ubbf.schemas.Routing';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.Routing.Router.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Router properties with enable status
 */
function router_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...ctx.config,
		Enable: 'true',
		Status: 'Enabled',
		IPv4ForwardingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.IPv4Forwarding)),
		IPv6ForwardingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.IPv6Forwarding))
	};
}

/**
 * Get handler for Device.Routing.Router.{i}.IPv4Forwarding.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} IPv4 forwarding entry properties
 */
function ipv4_forwarding_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...ctx.config,
		StaticRoute: 'true',
		Origin: 'Static'
	};
}

/**
 * Get handler for Device.Routing.Router.{i}.IPv6Forwarding.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} IPv6 forwarding entry properties
 */
function ipv6_forwarding_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...ctx.config,
		Origin: 'Static',
		ExpirationTime: '9999-12-31T23:59:59Z'
	};
}

/**
 * Get handler for Device.Routing.RouteInformation.InterfaceSetting.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Route information properties with status
 */
function route_info_get(ctx) {
	if (!ctx.config)
		return null;

	// Interface is a Device.IP.Interface path reference; this object has
	// no Name/Alias parameters in the schema
	let iface_ref = ctx.config.Interface;
	let iface = iface_ref ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref)) : null;
	let iface_name = iface?.Name;
	if (!iface_name)
		return { ...ctx.config };

	let iface_status = ubus?.call('network.interface.' + iface_name, 'status', {});
	if (!iface_status)
		return { ...ctx.config };

	let status = 'NoForwardingEntry';
	let routes = iface_status.route;
	if (routes && length(routes) > 0)
		status = 'ForwardingEntryCreated';

	return {
		...ctx.config,
		Status: status
	};
}

/**
 * Get handler for Device.Routing.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Routing properties with instance counts
 */
function routing_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		RouterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Router))
	};
}

/**
 * Get handler for Device.Routing.RouteInformation.
 *
 * @param {object} ctx - Context with config
 * @returns {object} RouteInformation properties with instance counts
 */
function route_information_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
	};
}

export const model = {
	'Device.Routing': {
		schema: schemas.Routing,
		get: routing_get
	},

	'Device.Routing.Router': {
	},

	'Device.Routing.Router.{i}': {
		schema: schemas.Router,
		get: router_get
	},

	'Device.Routing.Router.{i}.IPv4Forwarding': {
	},

	'Device.Routing.Router.{i}.IPv4Forwarding.{i}': {
		schema: schemas.Router_IPv4Forwarding,
		get: ipv4_forwarding_get,
		enable_status_derive: true
	},

	'Device.Routing.Router.{i}.IPv6Forwarding': {
	},

	'Device.Routing.Router.{i}.IPv6Forwarding.{i}': {
		schema: schemas.Router_IPv6Forwarding,
		get: ipv6_forwarding_get,
		enable_status_derive: true
	},

	'Device.Routing.RouteInformation': {
		schema: schemas.RouteInformation,
		get: route_information_get
	},

	'Device.Routing.RouteInformation.InterfaceSetting': {
	},

	'Device.Routing.RouteInformation.InterfaceSetting.{i}': {
		schema: schemas.RouteInformation_InterfaceSetting,
		get: route_info_get
	}
};
