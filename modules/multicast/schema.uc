'use strict';

// Schema definitions for the Device.X_UBBF.MulticastProxy domain.
//
// Included by handler.uc with { schemas } as the scope; there is nothing to
// export from an included file, so each definition is added to that object.

schemas.MulticastProxy = {
	path: 'Device.X_UBBF.MulticastProxy.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Status': dm_type.STRING,
		'Backend': dm_type.STRING | dm_type.WRITABLE,
		'ProxyNumberOfEntries': dm_type.UINT,
		'SnoopingNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'Enable': 'false',
		'Status': 'Disabled',
		'Backend': 'igmpproxy',
		'ProxyNumberOfEntries': '0',
		'SnoopingNumberOfEntries': '0'
	}
};

schemas.Proxy = {
	path: 'Device.X_UBBF.MulticastProxy.Proxy.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Status': dm_type.STRING,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'UpstreamInterface': dm_type.STRING | dm_type.WRITABLE,
		'Scope': dm_type.STRING | dm_type.WRITABLE,
		'AltNet': dm_type.STRING | dm_type.WRITABLE,
		'InterfaceNumberOfEntries': dm_type.UINT,
		'ActiveGroupNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'Enable': 'false',
		'Status': 'Disabled',
		'Alias': '',
		'UpstreamInterface': '',
		'Scope': 'Global',
		'AltNet': '0.0.0.0/0',
		'InterfaceNumberOfEntries': '0',
		'ActiveGroupNumberOfEntries': '0'
	}
};

schemas.Proxy_Interface = {
	path: 'Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'Status': dm_type.STRING
	},
	defaults: {
		'Enable': 'false',
		'Interface': '',
		'Status': 'Disabled'
	}
};

schemas.Proxy_ActiveGroup = {
	path: 'Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.',
	schema: {
		'GroupAddress': dm_type.STRING,
		'ClientNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'GroupAddress': '',
		'ClientNumberOfEntries': '0'
	}
};

schemas.Proxy_ActiveGroup_Client = {
	path: 'Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client.{i}.',
	schema: {
		'SourceAddress': dm_type.STRING,
		'Interface': dm_type.STRING,
		'Timeout': dm_type.UINT
	},
	defaults: {
		'SourceAddress': '',
		'Interface': '',
		'Timeout': '0'
	}
};

schemas.Snooping = {
	path: 'Device.X_UBBF.MulticastProxy.Snooping.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Status': dm_type.STRING,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'IGMPVersion': dm_type.STRING | dm_type.WRITABLE,
		'MLDVersion': dm_type.STRING | dm_type.WRITABLE,
		'Mode': dm_type.STRING | dm_type.WRITABLE,
		'QueryInterval': dm_type.UINT | dm_type.WRITABLE,
		'QueryResponseInterval': dm_type.UINT | dm_type.WRITABLE,
		'LastMemberQueryInterval': dm_type.UINT | dm_type.WRITABLE,
		'Robustness': dm_type.UINT | dm_type.WRITABLE,
		'ImmediateLeave': dm_type.BOOL | dm_type.WRITABLE,
		'ActiveGroupNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'Enable': 'false',
		'Status': 'Disabled',
		'Alias': '',
		'Interface': '',
		'IGMPVersion': 'V3',
		'MLDVersion': 'V2',
		'Mode': 'Standard',
		'QueryInterval': '125',
		'QueryResponseInterval': '100',
		'LastMemberQueryInterval': '10',
		'Robustness': '2',
		'ImmediateLeave': 'false',
		'ActiveGroupNumberOfEntries': '0'
	}
};
