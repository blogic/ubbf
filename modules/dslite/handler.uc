'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

let schemas = {};
include('schema.uc', { schemas });

/**
 * Maps netifd status to TR-181 DSLite Status.
 *
 * @param {boolean} enabled - Whether the interface setting is enabled
 * @param {object} status - Netifd interface status
 * @returns {string} 'Disabled', 'Enabled', or 'Error'
 */
function status_map(enabled, status) {
	if (!enabled)
		return 'Disabled';

	if (!status)
		return 'Error';

	let uptime = int(status.uptime);
	if (uptime != null && uptime > 0)
		return 'Enabled';

	return 'Error';
}

/**
 * Get handler for Device.DSLite.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DSLite properties with instance count
 */
function dslite_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
	};
}

/**
 * Get handler for Device.DSLite.InterfaceSetting.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} InterfaceSetting properties with runtime status
 */
function interface_setting_get(ctx) {
	if (!ctx.config)
		return null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let ifname = sprintf('dslite_%s', ctx.instance);
	let status = enabled ? utils.netifd.netifd_status_get(ifname) : null;

	let endpoint_in_use = '';
	if (enabled && status) {
		// mirror the peeraddr precedence in render.uc
		// so the reported endpoint matches what netifd actually uses
		let prec = ctx.config.EndpointAddressTypePrecedence;
		if (prec == 'FQDN')
			endpoint_in_use = ctx.config.EndpointName ?? '';
		else if (prec == 'IPv6Address')
			endpoint_in_use = ctx.config.EndpointAddress ?? '';
		else
			endpoint_in_use = (ctx.config.EndpointAddress && ctx.config.EndpointAddress != '')
				? ctx.config.EndpointAddress : (ctx.config.EndpointName ?? '');
	}

	return {
		...ubbf.ctx_config(ctx),
		Status: status_map(enabled, status),
		EndpointAddressInUse: endpoint_in_use
	};
}

model['Device.DSLite'] = {
	schema: schemas.DSLite,
	get: dslite_get
};

model['Device.DSLite.InterfaceSetting'] = {
};

model['Device.DSLite.InterfaceSetting.{i}'] = {
	schema: schemas.InterfaceSetting,
	get: interface_setting_get
};
