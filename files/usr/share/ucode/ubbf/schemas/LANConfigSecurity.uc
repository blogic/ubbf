'use strict';

export const LANConfigSecurity = {
	path: "Device.LANConfigSecurity.",
	schema: {
		"ConfigPassword": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"ConfigPassword": ""
	},
	constraints: {
		"ConfigPassword": { secured: true }
	}
};
