'use strict';

// Auto-generated schema definitions for USB domain
// Generated from TR-181 specifications
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.USB.USBHosts.
schemas.USBHosts = {
    path: "Device.USB.USBHosts.",
    schema: {
        "HostNumberOfEntries": dm_type.UINT,
        "AllowedDeviceNumberOfEntries": dm_type.UINT,
        "AllowAllDevices": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "HostNumberOfEntries": "0",
        "AllowedDeviceNumberOfEntries": "0",
        "AllowAllDevices": "true"
    },
    since: {
        "AllowedDeviceNumberOfEntries": "2.20",
        "AllowAllDevices": "2.20"
    }
};

// Schema for Device.USB.USBHosts.AllowedDevice.{i}.
schemas.AllowedDevice = {
    path: "Device.USB.USBHosts.AllowedDevice.{i}.",
    schema: {
        "Alias": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "DeviceClass": dm_type.STRING | dm_type.WRITABLE,
        "DeviceSubClass": dm_type.STRING | dm_type.WRITABLE,
        "DeviceProtocol": dm_type.STRING | dm_type.WRITABLE,
        "ProductID": dm_type.STRING | dm_type.WRITABLE,
        "VendorID": dm_type.STRING | dm_type.WRITABLE,
        "Interfaces": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Description": "",
        "DeviceClass": "",
        "DeviceSubClass": "",
        "DeviceProtocol": "",
        "ProductID": "",
        "VendorID": "",
        "Interfaces": ""
    },
    constraints: {
        "Alias": { max_length: 64 },
        "Description": { max_length: 64 },
        "Interfaces": { list: true }
    }
};

// Schema for Device.USB.USBHosts.Host.{i}.
schemas.Host = {
    path: "Device.USB.USBHosts.Host.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL,
        "Name": dm_type.STRING,
        "Type": dm_type.STRING,
        "PowerManagementEnable": dm_type.BOOL,
        "USBVersion": dm_type.STRING,
        "DeviceNumberOfEntries": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Type": "",
        "USBVersion": ""
    },
    addable: false
};

// Schema for Device.USB.Port.{i}.
schemas.Port = {
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
    },
    addable: false
};

// Schema for Device.USB.USBHosts.Host.{i}.Device.{i}.
schemas.Host_Device = {
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
        "ConfigurationNumberOfEntries": dm_type.UINT,
        "DeviceState": dm_type.STRING,
        "IsAllowed": dm_type.BOOL
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
        "ConfigurationNumberOfEntries": "0",
        "DeviceState": "",
        "IsAllowed": "true"
    },
    since: {
        "DeviceState": "2.20",
        "IsAllowed": "2.20"
    },
    addable: false
};

// Schema for Device.USB.Interface.{i}.Stats.
schemas.Interface_Stats = {
    path: "Device.USB.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.ULONG,
        "BytesReceived": dm_type.ULONG,
        "PacketsSent": dm_type.ULONG,
        "PacketsReceived": dm_type.ULONG,
        "ErrorsSent": dm_type.UINT,
        "ErrorsReceived": dm_type.UINT,
        "UnicastPacketsSent": dm_type.ULONG,
        "DiscardPacketsSent": dm_type.UINT,
        "DiscardPacketsReceived": dm_type.UINT,
        "MulticastPacketsSent": dm_type.ULONG,
        "UnicastPacketsReceived": dm_type.ULONG,
        "MulticastPacketsReceived": dm_type.ULONG,
        "BroadcastPacketsSent": dm_type.ULONG,
        "BroadcastPacketsReceived": dm_type.ULONG,
        "UnknownProtoPacketsReceived": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "BytesSent": "18446744073709551615",
        "BytesReceived": "18446744073709551615",
        "PacketsSent": "18446744073709551615",
        "PacketsReceived": "18446744073709551615",
        "ErrorsSent": "4294967295",
        "ErrorsReceived": "4294967295",
        "UnicastPacketsSent": "18446744073709551615",
        "DiscardPacketsSent": "4294967295",
        "DiscardPacketsReceived": "4294967295",
        "MulticastPacketsSent": "18446744073709551615",
        "UnicastPacketsReceived": "18446744073709551615",
        "MulticastPacketsReceived": "18446744073709551615",
        "BroadcastPacketsSent": "18446744073709551615",
        "BroadcastPacketsReceived": "18446744073709551615",
        "UnknownProtoPacketsReceived": "4294967295"
    }
};

// Schema for Device.USB.
schemas.USB = {
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
schemas.Configuration_Interface = {
    path: "Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.Interface.{i}.",
    schema: {
        "InterfaceNumber": dm_type.UINT,
        "InterfaceClass": dm_type.HEXBIN,
        "InterfaceSubClass": dm_type.HEXBIN,
        "InterfaceProtocol": dm_type.HEXBIN
    },
    defaults: {
        "InterfaceNumber": "0"
    },
    addable: false
};

// Schema for Device.USB.Interface.{i}.
schemas.Interface = {
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
    },
    constraints: {
        "LowerLayers": { list: true, list_max_length: 1024 }
    },
    addable: false
};

// Schema for Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.
schemas.Device_Configuration = {
    path: "Device.USB.USBHosts.Host.{i}.Device.{i}.Configuration.{i}.",
    schema: {
        "ConfigurationNumber": dm_type.UINT,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ConfigurationNumber": "0",
        "InterfaceNumberOfEntries": "0"
    },
    addable: false
};
