'use strict';

import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.LANConfigSecurity';

/**
 * Set handler for Device.LANConfigSecurity.
 *
 * @param {object} ctx - Context with path, param, value, root
 * @returns {number} 0 on success, -1 on failure
 */
function lanconfigsecurity_set(ctx) {
	if (ctx.param != 'ConfigPassword' || !ctx.value)
		return 0;

	let result = ubus?.call('ubbf-ui', 'change_password', {
		password: ctx.value
	});

	if (!result || result.error)
		return -1;

	let config = ctx.root?.Device?.LANConfigSecurity;
	if (config)
		config.ConfigPassword = "";

	return 0;
}

export const model = {
	'Device.LANConfigSecurity': {
		schema: schemas.LANConfigSecurity,
		set: lanconfigsecurity_set
	}
};
