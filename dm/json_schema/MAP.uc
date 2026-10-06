'use strict';

// Auto-generated schema definitions for MAP domain
// Generated from TR-181 specifications

// Schema for Device.MAP.Domain.{i}.
export const Domain = {
    path: "Device.MAP.Domain.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "TransportMode": dm_type.STRING | dm_type.WRITABLE,
        "WANInterface": dm_type.STRING | dm_type.WRITABLE,
        "IPv6Prefix": dm_type.STRING | dm_type.WRITABLE,
        "BRIPv6Prefix": dm_type.STRING | dm_type.WRITABLE,
        "DSCPMarkPolicy": dm_type.INT | dm_type.WRITABLE,
        "PSIDOffset": dm_type.UINT | dm_type.WRITABLE,
        "PSIDLength": dm_type.UINT | dm_type.WRITABLE,
        "PSID": dm_type.UINT | dm_type.WRITABLE,
        "IncludeSystemPorts": dm_type.BOOL | dm_type.WRITABLE,
        "RuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "",
        "Alias": "",
        "TransportMode": "Translation",
        "WANInterface": "",
        "IPv6Prefix": "",
        "BRIPv6Prefix": "",
        "DSCPMarkPolicy": "0",
        "PSIDOffset": "6",
        "PSIDLength": "0",
        "PSID": "0",
        "IncludeSystemPorts": "false",
        "RuleNumberOfEntries": "0"
    }
};

// Schema for Device.MAP.Domain.{i}.Rule.{i}.
export const Domain_Rule = {
    path: "Device.MAP.Domain.{i}.Rule.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "IPv6Prefix": dm_type.STRING | dm_type.WRITABLE,
        "IPv4Prefix": dm_type.STRING | dm_type.WRITABLE,
        "EABitsLength": dm_type.UINT | dm_type.WRITABLE,
        "IsFMR": dm_type.BOOL | dm_type.WRITABLE,
        "PSIDOffset": dm_type.UINT | dm_type.WRITABLE,
        "PSIDLength": dm_type.UINT | dm_type.WRITABLE,
        "PSID": dm_type.UINT | dm_type.WRITABLE,
        "IncludeSystemPorts": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Origin": "Static",
        "IPv6Prefix": "/0",
        "IPv4Prefix": "/0",
        "EABitsLength": "0",
        "IsFMR": "false",
        "PSIDOffset": "6",
        "PSIDLength": "0",
        "PSID": "0",
        "IncludeSystemPorts": "false"
    }
};

// Schema for Device.MAP.
export const MAP = {
    path: "Device.MAP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "DomainNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DomainNumberOfEntries": "0"
    }
};

// Schema for Device.MAP.Domain.{i}.Interface.Stats.
export const Interface_Stats = {
    path: "Device.MAP.Domain.{i}.Interface.Stats.",
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
        "UnknownProtoPacketsReceived": dm_type.STRING
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

// Schema for Device.MAP.Domain.{i}.Interface.
export const Domain_Interface = {
    path: "Device.MAP.Domain.{i}.Interface.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]"
    }
};
