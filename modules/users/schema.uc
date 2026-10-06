'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.Users = {
	path: "Device.Users.",
	schema: {
		"UserNumberOfEntries": dm_type.UINT,
		"GroupNumberOfEntries": dm_type.UINT,
		"RoleNumberOfEntries": dm_type.UINT,
		"SupportedShellNumberOfEntries": dm_type.UINT,
		"SupportedCapabilities": dm_type.STRING,
		"CheckCredentialsDiagnostics()": {
			type: 'sync',
			input: [
				'Username',
				'Password'
			],
			output: [
				'Status'
			]
		}
	},
	defaults: {
		"UserNumberOfEntries": "0",
		"GroupNumberOfEntries": "0",
		"RoleNumberOfEntries": "0",
		"SupportedShellNumberOfEntries": "0",
		"SupportedCapabilities": ""
	}
};

schemas.User = {
	path: "Device.Users.User.{i}.",
	schema: {
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"UserID": dm_type.UINT | dm_type.WRITABLE,
		"Username": dm_type.STRING | dm_type.WRITABLE,
		"Password": dm_type.STRING | dm_type.WRITABLE,
		"GroupParticipation": dm_type.STRING | dm_type.WRITABLE,
		"RoleParticipation": dm_type.STRING | dm_type.WRITABLE,
		"StaticUser": dm_type.BOOL,
		"Language": dm_type.STRING | dm_type.WRITABLE,
		"Shell": dm_type.STRING | dm_type.WRITABLE,
		"HomeDirectory": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Alias": "",
		"Enable": "false",
		"UserID": "0",
		"Username": "",
		"Password": "",
		"GroupParticipation": "",
		"RoleParticipation": "",
		"StaticUser": "false",
		"Language": "",
		"Shell": "",
		"HomeDirectory": ""
	},
	since: {
		"HomeDirectory": "2.21"
	},
	constraints: {
		"Alias": { max_length: 64 },
		"HomeDirectory": { max_length: 2048 },
		"Username": { max_length: 64 },
		"Password": { secured: true, max_length: 64 },
		"GroupParticipation": { list: true, list_max_length: 1024 },
		"RoleParticipation": { list: true, list_max_length: 1024 },
		"Language": { max_length: 16 }
	}
};

schemas.Group = {
	path: "Device.Users.Group.{i}.",
	schema: {
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"GroupID": dm_type.UINT | dm_type.WRITABLE,
		"Groupname": dm_type.STRING | dm_type.WRITABLE,
		"RoleParticipation": dm_type.STRING | dm_type.WRITABLE,
		"StaticGroup": dm_type.BOOL
	},
	defaults: {
		"Alias": "",
		"Enable": "true",
		"GroupID": "0",
		"Groupname": "",
		"RoleParticipation": "",
		"StaticGroup": "false"
	},
	constraints: {
		"Alias": { max_length: 64 },
		"Groupname": { max_length: 64 },
		"RoleParticipation": { list: true, list_max_length: 1024 }
	}
};

schemas.Role = {
	path: "Device.Users.Role.{i}.",
	schema: {
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"RoleID": dm_type.UINT | dm_type.WRITABLE,
		"RoleName": dm_type.STRING | dm_type.WRITABLE,
		"StaticRole": dm_type.BOOL,
		"RequiredCapabilities": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Alias": "",
		"Enable": "true",
		"RoleID": "0",
		"RoleName": "",
		"StaticRole": "false",
		"RequiredCapabilities": ""
	},
	constraints: {
		"Alias": { max_length: 64 },
		"RoleName": { max_length: 64 },
		"RequiredCapabilities": { list: true }
	}
};

schemas.LANConfigSecurity = {
	path: "Device.LANConfigSecurity.",
	schema: {
		"ConfigPassword": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"ConfigPassword": ""
	},
	constraints: {
		"ConfigPassword": { secured: true, max_length: 64 }
	}
};

schemas.SupportedShell = {
	path: "Device.Users.SupportedShell.{i}.",
	schema: {
		"Alias": dm_type.STRING,
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Name": dm_type.STRING
	},
	defaults: {
		"Alias": "",
		"Enable": "true",
		"Name": ""
	}
};
