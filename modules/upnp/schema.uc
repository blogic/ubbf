'use strict';

// Schema definitions for the Device.UPnP domain (TR-181 2.12).
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.
//
// TR-181 makes all ten flags of Device.UPnP.Device readWrite. Only Enable
// and UPnPIGD are writable here: the device implements no other UPnP
// device type (Capabilities reports 0 for them), so the other flags stay
// false and a write gives 7013.

schemas.UPnP = {
	path: 'Device.UPnP.',
	schema: {},
	defaults: {}
};

schemas.UPnP_Device = {
	path: 'Device.UPnP.Device.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'UPnPMediaServer': dm_type.BOOL,
		'UPnPMediaRenderer': dm_type.BOOL,
		'UPnPWLANAccessPoint': dm_type.BOOL,
		'UPnPQoSDevice': dm_type.BOOL,
		'UPnPQoSPolicyHolder': dm_type.BOOL,
		'UPnPIGD': dm_type.BOOL | dm_type.WRITABLE,
		'UPnPDMBasicMgmt': dm_type.BOOL,
		'UPnPDMConfigurationMgmt': dm_type.BOOL,
		'UPnPDMSoftwareMgmt': dm_type.BOOL,
		'X_UBBF_InterfaceNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'Enable': 'false',
		'UPnPMediaServer': 'false',
		'UPnPMediaRenderer': 'false',
		'UPnPWLANAccessPoint': 'false',
		'UPnPQoSDevice': 'false',
		'UPnPQoSPolicyHolder': 'false',
		'UPnPIGD': 'true',
		'UPnPDMBasicMgmt': 'false',
		'UPnPDMConfigurationMgmt': 'false',
		'UPnPDMSoftwareMgmt': 'false',
		'X_UBBF_InterfaceNumberOfEntries': '0'
	}
};

schemas.UPnP_Device_Interface = {
	path: 'Device.UPnP.Device.X_UBBF_Interface.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'Status': dm_type.STRING
	},
	defaults: {
		'Enable': 'false',
		'Alias': '',
		'Interface': '',
		'Status': 'Disabled'
	},
	constraints: {
		'Status': { enum: [ 'Disabled', 'Up', 'Down', 'Error' ] },
		'Interface': { max_length: 256 }
	}
};

schemas.UPnP_Device_IGD = {
	path: 'Device.UPnP.Device.IGD.',
	schema: {
		'MaxLeaseLifetime': dm_type.UINT | dm_type.WRITABLE,
		'CleanupInterval': dm_type.UINT | dm_type.WRITABLE,
		'AllowReservedAddress': dm_type.BOOL | dm_type.WRITABLE,
		'EnableIPv6': dm_type.BOOL | dm_type.WRITABLE
	},
	defaults: {
		'MaxLeaseLifetime': '86400',
		'CleanupInterval': '0',
		'AllowReservedAddress': 'false',
		'EnableIPv6': 'false'
	}
};

schemas.UPnP_Device_Capabilities = {
	path: 'Device.UPnP.Device.Capabilities.',
	schema: {
		'UPnPArchitecture': dm_type.UINT,
		'UPnPArchitectureMinorVer': dm_type.UINT,
		'UPnPMediaServer': dm_type.UINT,
		'UPnPMediaRenderer': dm_type.UINT,
		'UPnPWLANAccessPoint': dm_type.UINT,
		'UPnPBasicDevice': dm_type.UINT,
		'UPnPQoSDevice': dm_type.UINT,
		'UPnPQoSPolicyHolder': dm_type.UINT,
		'UPnPIGD': dm_type.UINT,
		'UPnPDMBasicMgmt': dm_type.UINT,
		'UPnPDMConfigurationMgmt': dm_type.UINT,
		'UPnPDMSoftwareMgmt': dm_type.UINT
	},
	defaults: {
		'UPnPArchitecture': '1',
		'UPnPArchitectureMinorVer': '1',
		'UPnPMediaServer': '0',
		'UPnPMediaRenderer': '0',
		'UPnPWLANAccessPoint': '0',
		'UPnPBasicDevice': '0',
		'UPnPQoSDevice': '0',
		'UPnPQoSPolicyHolder': '0',
		'UPnPIGD': '2',
		'UPnPDMBasicMgmt': '0',
		'UPnPDMConfigurationMgmt': '0',
		'UPnPDMSoftwareMgmt': '0'
	}
};

schemas.UPnP_Discovery = {
	path: 'Device.UPnP.Discovery.',
	schema: {
		'RootDeviceNumberOfEntries': dm_type.UINT,
		'DeviceNumberOfEntries': dm_type.UINT,
		'ServiceNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'RootDeviceNumberOfEntries': '0',
		'DeviceNumberOfEntries': '0',
		'ServiceNumberOfEntries': '0'
	}
};

const discovery_row = {
	'Status': dm_type.STRING,
	'UUID': dm_type.STRING,
	'USN': dm_type.STRING,
	'LeaseTime': dm_type.UINT,
	'Location': dm_type.STRING,
	'Server': dm_type.STRING,
	'Host': dm_type.STRING,
	'LastUpdate': dm_type.DATETIME
};

const discovery_defaults = {
	'Status': 'LeaseExpired',
	'UUID': '',
	'USN': '',
	'LeaseTime': '0',
	'Location': '',
	'Server': '',
	'Host': '',
	'LastUpdate': '0001-01-01T00:00:00Z'
};

schemas.UPnP_Discovery_RootDevice = {
	path: 'Device.UPnP.Discovery.RootDevice.{i}.',
	schema: { ...discovery_row },
	defaults: { ...discovery_defaults },
	addable: false
};

schemas.UPnP_Discovery_Device = {
	path: 'Device.UPnP.Discovery.Device.{i}.',
	schema: { ...discovery_row },
	defaults: { ...discovery_defaults },
	addable: false
};

schemas.UPnP_Discovery_Service = {
	path: 'Device.UPnP.Discovery.Service.{i}.',
	schema: {
		'Status': dm_type.STRING,
		'USN': dm_type.STRING,
		'LeaseTime': dm_type.UINT,
		'Location': dm_type.STRING,
		'Server': dm_type.STRING,
		'Host': dm_type.STRING,
		'LastUpdate': dm_type.DATETIME,
		'ParentDevice': dm_type.STRING
	},
	defaults: {
		'Status': 'LeaseExpired',
		'USN': '',
		'LeaseTime': '0',
		'Location': '',
		'Server': '',
		'Host': '',
		'LastUpdate': '0001-01-01T00:00:00Z',
		'ParentDevice': ''
	},
	addable: false
};

schemas.UPnP_Description = {
	path: 'Device.UPnP.Description.',
	schema: {
		'DeviceDescriptionNumberOfEntries': dm_type.UINT,
		'DeviceInstanceNumberOfEntries': dm_type.UINT,
		'ServiceInstanceNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'DeviceDescriptionNumberOfEntries': '0',
		'DeviceInstanceNumberOfEntries': '0',
		'ServiceInstanceNumberOfEntries': '0'
	}
};

schemas.UPnP_Description_DeviceDescription = {
	path: 'Device.UPnP.Description.DeviceDescription.{i}.',
	schema: {
		'URLBase': dm_type.STRING,
		'SpecVersion': dm_type.STRING,
		'Host': dm_type.STRING
	},
	defaults: {
		'URLBase': '',
		'SpecVersion': '',
		'Host': ''
	},
	addable: false
};

schemas.UPnP_Description_DeviceInstance = {
	path: 'Device.UPnP.Description.DeviceInstance.{i}.',
	schema: {
		'UDN': dm_type.STRING,
		'ParentDevice': dm_type.STRING,
		'DiscoveryDevice': dm_type.STRING,
		'DeviceType': dm_type.STRING,
		'FriendlyName': dm_type.STRING,
		'DeviceCategory': dm_type.STRING,
		'Manufacturer': dm_type.STRING,
		'ManufacturerOUI': dm_type.STRING,
		'ManufacturerURL': dm_type.STRING,
		'ModelDescription': dm_type.STRING,
		'ModelName': dm_type.STRING,
		'ModelNumber': dm_type.STRING,
		'ModelURL': dm_type.STRING,
		'SerialNumber': dm_type.STRING,
		'UPC': dm_type.STRING,
		'PresentationURL': dm_type.STRING
	},
	defaults: {
		'UDN': '',
		'ParentDevice': '',
		'DiscoveryDevice': '',
		'DeviceType': '',
		'FriendlyName': '',
		'DeviceCategory': '',
		'Manufacturer': '',
		'ManufacturerOUI': '',
		'ManufacturerURL': '',
		'ModelDescription': '',
		'ModelName': '',
		'ModelNumber': '',
		'ModelURL': '',
		'SerialNumber': '',
		'UPC': '',
		'PresentationURL': ''
	},
	addable: false
};

schemas.UPnP_Description_ServiceInstance = {
	path: 'Device.UPnP.Description.ServiceInstance.{i}.',
	schema: {
		'ParentDevice': dm_type.STRING,
		'ServiceId': dm_type.STRING,
		'ServiceDiscovery': dm_type.STRING,
		'ServiceType': dm_type.STRING,
		'SCPDURL': dm_type.STRING,
		'ControlURL': dm_type.STRING,
		'EventSubURL': dm_type.STRING
	},
	defaults: {
		'ParentDevice': '',
		'ServiceId': '',
		'ServiceDiscovery': '',
		'ServiceType': '',
		'SCPDURL': '',
		'ControlURL': '',
		'EventSubURL': ''
	},
	addable: false
};
