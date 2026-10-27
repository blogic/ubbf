'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.UserInterface = {
	path: "Device.UserInterface.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"PasswordRequired": dm_type.BOOL | dm_type.WRITABLE,
		"HTTPAccessSupportedProtocols": dm_type.STRING,
		"HTTPAccessNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "true",
		"PasswordRequired": "true",
		"HTTPAccessSupportedProtocols": "HTTP,HTTPS",
		"HTTPAccessNumberOfEntries": "0"
	}
};

schemas.HTTPAccess = {
	path: "Device.UserInterface.HTTPAccess.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Order": dm_type.UINT | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"AccessType": dm_type.STRING | dm_type.WRITABLE,
		"AllowedRoles": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"Port": dm_type.UINT | dm_type.WRITABLE,
		"Protocol": dm_type.STRING | dm_type.WRITABLE,
		"Certificate": dm_type.STRING | dm_type.WRITABLE,
		"CABundle": dm_type.STRING | dm_type.WRITABLE,
		"AllowAllIPv4": dm_type.BOOL | dm_type.WRITABLE,
		"IPv4AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
		"AllowAllIPv6": dm_type.BOOL | dm_type.WRITABLE,
		"IPv6AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
		"AutoDisableDuration": dm_type.UINT | dm_type.WRITABLE,
		"TimeLeft": dm_type.UINT,
		"ActivationDate": dm_type.DATETIME,
		"SessionNumberOfEntries": dm_type.UINT,
		"X_UBBF_TLSMinVersion": dm_type.STRING | dm_type.WRITABLE,
		"CreateWebSession()": {
			type: 'sync',
			input: [
				'AbsoluteTimeout',
				'IdleTimeout'
			],
			output: [
				'SessionID',
				'Path'
			]
		}
	},
	defaults: {
		"Enable": "true",
		"Alias": "",
		"Order": "0",
		"Status": "Down",
		"AccessType": "LocalAccess",
		"AllowedRoles": "",
		"Interface": "",
		"Port": "443",
		"Protocol": "HTTPS",
		"Certificate": "",
		"CABundle": "",
		"AllowAllIPv4": "false",
		"IPv4AllowedSourcePrefix": "",
		"AllowAllIPv6": "false",
		"IPv6AllowedSourcePrefix": "",
		"AutoDisableDuration": "0",
		"TimeLeft": "0",
		"ActivationDate": "0001-01-01T00:00:00Z",
		"SessionNumberOfEntries": "0",
		"X_UBBF_TLSMinVersion": "1.2"
	},
	constraints: {
		"Alias": { max_length: 64 },
		"Order": { min: 1 },
		"AccessType": { enum: [ "RemoteAccess", "LocalAccess" ] },
		"AllowedRoles": { list: true, max_length: 256 },
		"Interface": { max_length: 256 },
		"Port": { min: 1, max: 65535 },
		"Protocol": { enum: [ "HTTP", "HTTPS" ] },
		"IPv4AllowedSourcePrefix": { list: true, list_max_length: 1024 },
		"IPv6AllowedSourcePrefix": { list: true, list_max_length: 1024 },
		"X_UBBF_TLSMinVersion": { enum: [ "1.2", "1.3" ] }
	}
};

schemas.HTTPAccess_Session = {
	path: "Device.UserInterface.HTTPAccess.{i}.Session.{i}.",
	schema: {
		"SessionID": dm_type.STRING,
		"User": dm_type.STRING,
		"IPAddress": dm_type.STRING,
		"Port": dm_type.UINT,
		"Protocol": dm_type.STRING,
		"StartDate": dm_type.DATETIME,
		"Delete()": { type: 'sync', input: [] }
	},
	defaults: {
		"SessionID": "",
		"User": "",
		"IPAddress": "",
		"Port": "0",
		"Protocol": "",
		"StartDate": "0001-01-01T00:00:00Z"
	},
	addable: false
};
