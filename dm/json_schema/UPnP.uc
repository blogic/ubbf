'use strict';

// Auto-generated schema definitions for UPnP domain
// Generated from TR-181 specifications

// Schema for Device.UPnP.Description.
export const Description = {
    path: "Device.UPnP.Description.",
    schema: {
        "DeviceDescriptionNumberOfEntries": dm_type.UINT,
        "DeviceInstanceNumberOfEntries": dm_type.UINT,
        "ServiceInstanceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DeviceDescriptionNumberOfEntries": "0",
        "DeviceInstanceNumberOfEntries": "0",
        "ServiceInstanceNumberOfEntries": "0"
    }
};

// Schema for Device.UPnP.Description.DeviceDescription.{i}.
export const Description_DeviceDescription = {
    path: "Device.UPnP.Description.DeviceDescription.{i}.",
    schema: {
        "URLBase": dm_type.STRING,
        "SpecVersion": dm_type.STRING,
        "Host": dm_type.STRING
    },
    defaults: {
        "URLBase": "",
        "SpecVersion": "",
        "Host": ""
    }
};

// Schema for Device.UPnP.Description.ServiceInstance.{i}.
export const Description_ServiceInstance = {
    path: "Device.UPnP.Description.ServiceInstance.{i}.",
    schema: {
        "ParentDevice": dm_type.STRING,
        "ServiceId": dm_type.STRING,
        "ServiceDiscovery": dm_type.STRING,
        "ServiceType": dm_type.STRING,
        "SCPDURL": dm_type.STRING,
        "ControlURL": dm_type.STRING,
        "EventSubURL": dm_type.STRING
    },
    defaults: {
        "ParentDevice": "",
        "ServiceId": "",
        "ServiceDiscovery": "",
        "ServiceType": "",
        "SCPDURL": "",
        "ControlURL": "",
        "EventSubURL": ""
    }
};

// Schema for Device.UPnP.Description.DeviceInstance.{i}.
export const Description_DeviceInstance = {
    path: "Device.UPnP.Description.DeviceInstance.{i}.",
    schema: {
        "UDN": dm_type.STRING,
        "ParentDevice": dm_type.STRING,
        "DiscoveryDevice": dm_type.STRING,
        "DeviceType": dm_type.STRING,
        "FriendlyName": dm_type.STRING,
        "DeviceCategory": dm_type.STRING,
        "Manufacturer": dm_type.STRING,
        "ManufacturerOUI": dm_type.STRING,
        "ManufacturerURL": dm_type.STRING,
        "ModelDescription": dm_type.STRING,
        "ModelName": dm_type.STRING,
        "ModelNumber": dm_type.STRING,
        "ModelURL": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "UPC": dm_type.STRING,
        "PresentationURL": dm_type.STRING
    },
    defaults: {
        "UDN": "",
        "ParentDevice": "",
        "DiscoveryDevice": "",
        "DeviceType": "",
        "FriendlyName": "",
        "DeviceCategory": "",
        "Manufacturer": "",
        "ManufacturerOUI": "",
        "ManufacturerURL": "",
        "ModelDescription": "",
        "ModelName": "",
        "ModelNumber": "",
        "ModelURL": "",
        "SerialNumber": "",
        "UPC": "",
        "PresentationURL": ""
    }
};

// Schema for Device.UPnP.Device.Capabilities.
export const Device_Capabilities = {
    path: "Device.UPnP.Device.Capabilities.",
    schema: {
        "UPnPArchitecture": dm_type.UINT,
        "UPnPArchitectureMinorVer": dm_type.UINT,
        "UPnPMediaServer": dm_type.UINT,
        "UPnPMediaRenderer": dm_type.UINT,
        "UPnPWLANAccessPoint": dm_type.UINT,
        "UPnPBasicDevice": dm_type.UINT,
        "UPnPQoSDevice": dm_type.UINT,
        "UPnPQoSPolicyHolder": dm_type.UINT,
        "UPnPIGD": dm_type.UINT,
        "UPnPDMBasicMgmt": dm_type.UINT,
        "UPnPDMConfigurationMgmt": dm_type.UINT,
        "UPnPDMSoftwareMgmt": dm_type.UINT
    },
    defaults: {
        "UPnPArchitecture": "0",
        "UPnPArchitectureMinorVer": "0",
        "UPnPMediaServer": "0",
        "UPnPMediaRenderer": "0",
        "UPnPWLANAccessPoint": "0",
        "UPnPBasicDevice": "0",
        "UPnPQoSDevice": "0",
        "UPnPQoSPolicyHolder": "0",
        "UPnPIGD": "0",
        "UPnPDMBasicMgmt": "0",
        "UPnPDMConfigurationMgmt": "0",
        "UPnPDMSoftwareMgmt": "0"
    }
};

// Schema for Device.UPnP.Device.
export const Device = {
    path: "Device.UPnP.Device.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPMediaServer": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPMediaRenderer": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPWLANAccessPoint": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPQoSDevice": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPQoSPolicyHolder": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPIGD": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPDMBasicMgmt": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPDMConfigurationMgmt": dm_type.BOOL | dm_type.WRITABLE,
        "UPnPDMSoftwareMgmt": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {}
};

// Schema for Device.UPnP.Discovery.Device.{i}.
export const Discovery_Device = {
    path: "Device.UPnP.Discovery.Device.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "UUID": dm_type.STRING,
        "USN": dm_type.STRING,
        "LeaseTime": dm_type.UINT,
        "Location": dm_type.STRING,
        "Server": dm_type.STRING,
        "Host": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Status": "",
        "UUID": "",
        "USN": "",
        "LeaseTime": "0",
        "Location": "",
        "Server": "",
        "Host": ""
    }
};

// Schema for Device.UPnP.Discovery.Service.{i}.
export const Discovery_Service = {
    path: "Device.UPnP.Discovery.Service.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "USN": dm_type.STRING,
        "LeaseTime": dm_type.UINT,
        "Location": dm_type.STRING,
        "Server": dm_type.STRING,
        "Host": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME,
        "ParentDevice": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "USN": "",
        "LeaseTime": "0",
        "Location": "",
        "Server": "",
        "Host": "",
        "ParentDevice": ""
    }
};

// Schema for Device.UPnP.Discovery.RootDevice.{i}.
export const Discovery_RootDevice = {
    path: "Device.UPnP.Discovery.RootDevice.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "UUID": dm_type.STRING,
        "USN": dm_type.STRING,
        "LeaseTime": dm_type.UINT,
        "Location": dm_type.STRING,
        "Server": dm_type.STRING,
        "Host": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Status": "",
        "UUID": "",
        "USN": "",
        "LeaseTime": "0",
        "Location": "",
        "Server": "",
        "Host": ""
    }
};
