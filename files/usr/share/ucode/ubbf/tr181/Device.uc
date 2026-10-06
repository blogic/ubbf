'use strict';

import * as schemas from 'ubbf.schemas.Device';
import * as ubus from 'ubus';
import { log_warn } from 'ubbf.utils.logging';
import { interfacestack_count } from 'ubbf.tr181.InterfaceStack';
import * as ubbf from 'ubbf';

/**
 * Handles Device.Reboot() operation.
 *
 * @param {object} input - Operation input parameters
 * @param {string} command_key - Command key for tracking
 * @returns {object} Empty result object
 */
function reboot_op(input, command_key) {
	log_warn('reboot: initiated command_key=%s', command_key ?? '');
	ubus?.call('bbf-device', 'reboot', {
		command_key: command_key ?? '',
		local: false
	});
	return {};
}

/**
 * Handles Device.FactoryReset() operation.
 *
 * @param {object} input - Operation input parameters
 * @param {string} command_key - Command key for tracking
 * @returns {object} Empty result object
 */
function factory_reset_op(input, command_key) {
	log_warn('factory_reset: initiated command_key=%s', command_key ?? '');
	ubus?.call('bbf-device', 'factory_reset', {
		command_key: command_key ?? '',
		local: false
	});
	return {};
}

/**
 * Get handler for Device.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Device root properties
 */
function device_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceStackNumberOfEntries: sprintf('%d', interfacestack_count(ctx.root))
	};
}

export const model = {
	'Device': {
		schema: schemas.Device,
		get: device_get
	},

	// Vendor root shared by QoSify, TESTBED and the ubbf-mod-* modules that
	// hang under it; owned here so no module depends on another for its
	// parent.
	'Device.X_UBBF': {
	}
};

export const operations = {
	'Device.Reboot()': {
		type: 'sync',
		handler: reboot_op
	},
	'Device.FactoryReset()': {
		type: 'sync',
		handler: factory_reset_op
	}
};
