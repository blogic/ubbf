'use strict';

export const UserInterface = {
	path: "Device.UserInterface.",
	schema: {
		"Enable": dm_type.BOOL,
		"HTTPAccessNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "true",
		"HTTPAccessNumberOfEntries": "0"
	}
};

export const HTTPAccess = {
	path: "Device.UserInterface.HTTPAccess.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"Port": dm_type.UINT | dm_type.WRITABLE,
		"Protocol": dm_type.STRING,
		"Certificate": dm_type.STRING | dm_type.WRITABLE,
		"PrivateKey": dm_type.STRING | dm_type.WRITABLE,
		"SessionNumberOfEntries": dm_type.UINT,
		"X_UBBF_TLSMinVersion": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "true",
		"Alias": "",
		"Interface": "",
		"Port": "80",
		"Protocol": "HTTP",
		"Certificate": "",
		"PrivateKey": "",
		"SessionNumberOfEntries": "0",
		"X_UBBF_TLSMinVersion": "1.2"
	},
	constraints: {
		"X_UBBF_TLSMinVersion": { enum: [ "1.2", "1.3" ] }
	}
};

export const HTTPAccess_Session = {
	path: "Device.UserInterface.HTTPAccess.{i}.Session.{i}.",
	schema: {
		"IPAddress": dm_type.STRING,
		"Port": dm_type.UINT
	},
	defaults: {
		"IPAddress": "",
		"Port": "0"
	}
};
