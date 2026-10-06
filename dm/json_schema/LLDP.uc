'use strict';

// Auto-generated schema definitions for LLDP domain
// Generated from TR-181 specifications

// Schema for Device.LLDP.Discovery.Device.{i}.Port.{i}.LinkInformation.
export const Port_LinkInformation = {
    path: "Device.LLDP.Discovery.Device.{i}.Port.{i}.LinkInformation.",
    schema: {
        "InterfaceType": dm_type.UINT,
        "MACForwardingTable": dm_type.STRING
    },
    defaults: {
        "InterfaceType": "0",
        "MACForwardingTable": ""
    }
};

// Schema for Device.LLDP.Discovery.Device.{i}.DeviceInformation.
export const Device_DeviceInformation = {
    path: "Device.LLDP.Discovery.Device.{i}.DeviceInformation.",
    schema: {
        "DeviceCategory": dm_type.STRING,
        "ManufacturerOUI": dm_type.STRING,
        "ModelName": dm_type.STRING,
        "ModelNumber": dm_type.STRING,
        "VendorSpecificNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DeviceCategory": "",
        "ManufacturerOUI": "",
        "ModelName": "",
        "ModelNumber": "",
        "VendorSpecificNumberOfEntries": "0"
    }
};

// Schema for Device.LLDP.Discovery.Device.{i}.DeviceInformation.VendorSpecific.{i}.
export const DeviceInformation_VendorSpecific = {
    path: "Device.LLDP.Discovery.Device.{i}.DeviceInformation.VendorSpecific.{i}.",
    schema: {
        "OrganizationCode": dm_type.STRING,
        "InformationType": dm_type.UINT,
        "Information": dm_type.STRING
    },
    defaults: {
        "OrganizationCode": "",
        "InformationType": "0",
        "Information": ""
    }
};

// Schema for Device.LLDP.Discovery.Device.{i}.
export const Discovery_Device = {
    path: "Device.LLDP.Discovery.Device.{i}.",
    schema: {
        "Interface": dm_type.STRING,
        "ChassisIDSubtype": dm_type.UINT,
        "ChassisID": dm_type.STRING,
        "Host": dm_type.STRING,
        "PortNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Interface": "",
        "ChassisIDSubtype": "0",
        "ChassisID": "",
        "Host": "",
        "PortNumberOfEntries": "0"
    }
};

// Schema for Device.LLDP.Discovery.Device.{i}.Port.{i}.
export const Device_Port = {
    path: "Device.LLDP.Discovery.Device.{i}.Port.{i}.",
    schema: {
        "PortIDSubtype": dm_type.UINT,
        "PortID": dm_type.STRING,
        "TTL": dm_type.UINT,
        "PortDescription": dm_type.STRING,
        "MACAddressList": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "PortIDSubtype": "0",
        "PortID": "",
        "TTL": "0",
        "PortDescription": "",
        "MACAddressList": ""
    }
};
