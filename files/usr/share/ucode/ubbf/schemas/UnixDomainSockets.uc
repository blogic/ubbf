'use strict';

export const UnixDomainSockets = {
	path: "Device.UnixDomainSockets.",
	schema: {
		"UnixDomainSocketNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"UnixDomainSocketNumberOfEntries": "0"
	}
};

export const UnixDomainSocket = {
	path: "Device.UnixDomainSockets.UnixDomainSocket.{i}.",
	schema: {
		"Alias": dm_type.STRING,
		"Mode": dm_type.STRING,
		"Path": dm_type.STRING
	},
	defaults: {
		"Alias": "",
		"Mode": "",
		"Path": ""
	}
};
