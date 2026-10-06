'use strict';

// Auto-generated schema definitions for USB domain
// Generated from TR-181 specifications

// Schema for Device.USB.USBHosts.
export const USBHosts = {
    path: "Device.USB.USBHosts.",
    schema: {
        "HostNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "HostNumberOfEntries": "0"
    }
};

// Schema for Device.USB.USBHosts.Host.{i}.
export const Host = {
    path: "Device.USB.USBHosts.Host.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING,
        "Type": dm_type.STRING,
        "PowerManagementEnable": dm_type.BOOL | dm_type.WRITABLE,
        "USBVersion": dm_type.STRING,
        "DeviceNumberOfEntries": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Type": "",
        "USBVersion": ""
    }
};

// Schema for Device.USB.Port.{i}.
export const Port = {
    path: "Device.USB.Port.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Standard": dm_type.STRING,
        "Type": dm_type.STRING,
        "Receptacle": dm_type.STRING,
        "Rate": dm_type.STRING,
        "Power": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Standard": "",
        "Type": "",
        "Receptacle": "",
        "Rate": "",
        "Power": ""
    }
};

// Schema for Device.USB.USBHosts.Host.{i}.Device.{i}.
export const Host_Device = {
    path: "Device.USB.USBHosts.Host.{i}.Device.{i}.",
    schema: {
        "DeviceNumber": dm_type.UINT,
        "USBVersion": dm_type.STRING,
        "DeviceClass": dm_type.HEXBIN,
        "DeviceSubClass": dm_type.HEXBIN,
        "DeviceVersion": dm_type.UINT,
        "DeviceProtocol": dm_type.HEXBIN,
        "ProductID": dm_type.UINT,
        "VendorID": dm_type.UINT,
        "Manufacturer": dm_type.STRING,
        "ProductClass": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "Port": dm_type.UINT,
        "USBPort": dm_type.STRING,
        "Rate": dm_type.STRING,
        "Parent": dm_type.STRING,
        "MaxChildren": dm_type.UINT,
        "IsSuspended": dm_type.BOOL,
        "IsSelfPowered": dm_type.BOOL,
        "ConfigurationNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DeviceNumber": "0",
        "USBVersion": "",
        "DeviceVersion": "0",
        "ProductID": "0",
        "VendorID": "0",
        "Manufacturer": "",
        "ProductClass": "",
        "SerialNumber": "",
        "Port": "0",
        "USBPort": "",
        "Rate": "",
        "Parent": "",
        "MaxChildren": "0",
        "ConfigurationNumberOfEntries": "0"
    }
};

// Schema for Device.USB.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.USB.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "UnicastPacketsSent": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "MulticastPacketsSent": dm_type.STRING,
        "UnicastPacketsReceived": dm_type.STRING,
        "MulticastPacketsReceived": dm_type.STRING,
        "BroadcastPacketsSent": dm_type.STRING,
        "BroadcastPacketsReceived": dm_type.STRING,
        "UnknownProtoPacketsReceived": dm_type.STRING,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "UnicastPacketsSent": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "MulticastPacketsSent": "",
        "UnicastPacketsReceived": "",
        "MulticastPacketsReceived": "",
        "BroadcastPacketsSent": "",
        "BroadcastPacketsReceived": "",
        "UnknownProtoPacketsReceived": ""
    }
};

// Schema for Device.USB.
export const USB = {
    path: "Device.USB.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT,
        "PortNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0",
        "PortNumberOfEntries": "0"
    }
};

// Schema for Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface.{i}.
export const Configuration_Interface = {
    path: "Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface.{i}.",
    schema: {
        "InterfaceNumber": dm_type.UINT,
        "InterfaceClass": dm_type.HEXBIN,
        "InterfaceSubClass": dm_type.HEXBIN,
        "InterfaceProtocol": dm_type.HEXBIN
    },
    defaults: {
        "InterfaceNumber": "0"
    }
};

// Schema for Device.USB.Interface.{i}.
export const Interface = {
    path: "Device.USB.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.UINT,
        "MACAddress": dm_type.STRING,
        "Port": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "MACAddress": "",
        "Port": ""
    }
};

// Schema for Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.
export const Device_Configuration = {
    path: "Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.",
    schema: {
        "ConfigurationNumber": dm_type.UINT,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ConfigurationNumber": "0",
        "InterfaceNumberOfEntries": "0"
    }
};
