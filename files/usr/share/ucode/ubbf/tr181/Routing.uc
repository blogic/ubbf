'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import {
	router_table_id, forwarding_policy_set, policy_resolve, source_prefix, source_tables
} from 'ubbf.utils.routing';

/**
 * Get handler for Device.Routing.Router.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Router properties with enable status
 */
function router_get(ctx) {
	if (!ctx.config)
		return null;

	let table = router_table_id(ctx.instance);

	return {
		...ctx.config,
		Enable: 'true',
		Status: (table != null) ? 'Enabled' : 'Error',
		ID: sprintf('%d', table ?? 0),
		IPv4ForwardingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.IPv4Forwarding)),
		IPv6ForwardingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.IPv6Forwarding))
	};
}

/**
 * Returns the Status of a forwarding row: a row with a ForwardingPolicy is
 * not written (routing.uc), since ubbf gives traffic no QoS class.
 *
 * @param {object} row - IPv4Forwarding or IPv6Forwarding row
 * @returns {string} Disabled, Error_Misconfigured or Enabled
 */
function forwarding_status(row) {
	if (!ubbf.to_bool(row.Enable))
		return 'Disabled';

	return forwarding_policy_set(row) ? 'Error_Misconfigured' : 'Enabled';
}

/**
 * Returns the instance number of a Router row of the runtime tree.
 *
 * @param {object} root - Runtime tree
 * @param {object} row - Router row, ctx.parent of a forwarding row
 * @returns {string|null} Instance number, or null
 */
function router_instance(root, row) {
	for (let n, router in root?.Device?.Routing?.Router ?? {})
		if (router === row)
			return n;

	return null;
}

/**
 * Returns the Status of an IPv4Forwarding row. A row with a source
 * (TR-181 2.20) also needs a valid source prefix and a source table.
 *
 * @param {object} ctx - Context with config, parent and root
 * @returns {string} Disabled, Error_Misconfigured or Enabled
 */
function ipv4_forwarding_status(ctx) {
	let status = forwarding_status(ctx.config);
	let src = source_prefix(ctx.config);
	if (status != 'Enabled' || src == '')
		return status;
	if (src == null)
		return 'Error_Misconfigured';

	let n = router_instance(ctx.root, ctx.parent);
	return (n != null && source_tables(ctx.root)[`${n}|${src}`]) ? status : 'Error_Misconfigured';
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
		Status: ipv4_forwarding_status(ctx),
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
		Status: forwarding_status(ctx.config),
		Origin: 'Static',
		ExpirationTime: '9999-12-31T23:59:59Z'
	};
}

/**
 * Get handler for Device.Routing.Policy.{i} (TR-181 2.20).
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Policy properties with Status
 */
function policy_get(ctx) {
	if (!ctx.config)
		return null;

	let status = 'Disabled';
	if (ubbf.to_bool(ctx.config.Enable))
		status = policy_resolve(ctx.root, ctx.instance).error ? 'Error_Misconfigured' : 'Enabled';

	return { ...ctx.config, Status: status };
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
		RouterNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Router)),
		PolicyNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Policy))
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
		schema: 'Routing.Routing',
		get: routing_get
	},

	'Device.Routing.Router': {
	},

	'Device.Routing.Router.{i}': {
		schema: 'Routing.Router',
		get: router_get
	},

	'Device.Routing.Router.{i}.IPv4Forwarding': {
	},

	'Device.Routing.Router.{i}.IPv4Forwarding.{i}': {
		schema: 'Routing.Router_IPv4Forwarding',
		get: ipv4_forwarding_get
	},

	'Device.Routing.Router.{i}.IPv6Forwarding': {
	},

	'Device.Routing.Router.{i}.IPv6Forwarding.{i}': {
		schema: 'Routing.Router_IPv6Forwarding',
		get: ipv6_forwarding_get
	},

	'Device.Routing.Policy': {
		since: '2.20'
	},

	'Device.Routing.Policy.{i}': {
		schema: 'Routing.Policy',
		get: policy_get,
		since: '2.20'
	},

	'Device.Routing.RouteInformation': {
		schema: 'Routing.RouteInformation',
		get: route_information_get
	},

	'Device.Routing.RouteInformation.InterfaceSetting': {
	},

	'Device.Routing.RouteInformation.InterfaceSetting.{i}': {
		schema: 'Routing.RouteInformation_InterfaceSetting',
		get: route_info_get
	}
};
