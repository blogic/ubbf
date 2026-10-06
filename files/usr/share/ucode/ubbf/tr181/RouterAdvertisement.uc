'use strict';

import * as schemas from 'ubbf.schemas.RouterAdvertisement';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

/**
 * Get handler for Device.RouterAdvertisement.InterfaceSetting.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Interface setting properties with status
 */
function interface_setting_get(ctx) {
	if (!ctx.config)
		return null;

	if (!ubbf.to_bool(ctx.config.Enable))
		return { ...ctx.config, Status: 'Disabled' };

	// rows carry an Interface reference, not a netifd name; resolve it
	let iface_ref = ctx.config.Interface;
	let iface = iface_ref ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref)) : null;
	let iface_name = iface?.Name;
	if (!iface_name)
		return { ...ctx.config, Status: 'Error_Misconfigured' };

	let iface_status = ubus?.call('network.interface.' + iface_name, 'status', {});
	if (iface_status && !iface_status.up)
		return { ...ctx.config, Status: 'Error' };

	return { ...ctx.config, Status: 'Enabled' };
}

/**
 * Get handler for Device.RouterAdvertisement.
 *
 * @param {object} ctx - Context with config
 * @returns {object} RouterAdvertisement properties with instance counts
 */
function router_advertisement_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
	};
}

export const model = {
	'Device.RouterAdvertisement': {
		schema: schemas.RouterAdvertisement,
		get: router_advertisement_get
	},

	'Device.RouterAdvertisement.InterfaceSetting': {
	},

	'Device.RouterAdvertisement.InterfaceSetting.{i}': {
		schema: schemas.InterfaceSetting,
		get: interface_setting_get
	},

	'Device.RouterAdvertisement.InterfaceSetting.{i}.Option': {
	},

	'Device.RouterAdvertisement.InterfaceSetting.{i}.Option.{i}': {
		schema: schemas.InterfaceSetting_Option
	}
};
