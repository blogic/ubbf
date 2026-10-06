'use strict';

// Auto-generated schema definitions for Ethernet domain
// Generated from TR-181 specifications

// Schema for Device.Ethernet.
export const Ethernet = {
    path: "Device.Ethernet.",
    schema: {
        "WoLSupported": dm_type.BOOL,
        "FlowControlSupported": dm_type.BOOL,
        "InterfaceNumberOfEntries": dm_type.UINT,
        "LinkNumberOfEntries": dm_type.UINT,
        "VLANTerminationNumberOfEntries": dm_type.UINT,
        "LAGNumberOfEntries": dm_type.UINT,
        "RMONStatsNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "WoLSupported": "false",
        "FlowControlSupported": "false",
        "InterfaceNumberOfEntries": "0",
        "LinkNumberOfEntries": "0",
        "VLANTerminationNumberOfEntries": "0",
        "LAGNumberOfEntries": "0",
        "RMONStatsNumberOfEntries": "0"
    }
};

// Schema for Device.Ethernet.LAG.{i}.
export const LAG = {
    path: "Device.Ethernet.LAG.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MACAddress": ""
    },
    constraints: {
        "LowerLayers": { list: true, list_max_length: 1024 },
        "MACAddress": { max_length: 17 }
    }
};

// Schema for Device.Ethernet.RMONStats.{i}.
export const RMONStats = {
    path: "Device.Ethernet.RMONStats.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "VLANID": dm_type.UINT | dm_type.WRITABLE,
        "Queue": dm_type.STRING | dm_type.WRITABLE,
        "AllQueues": dm_type.BOOL | dm_type.WRITABLE,
        "DropEvents": dm_type.UINT,
        "Bytes": dm_type.ULONG,
        "Packets": dm_type.ULONG,
        "BroadcastPackets": dm_type.ULONG,
        "MulticastPackets": dm_type.ULONG,
        "CRCErroredPackets": dm_type.UINT,
        "UndersizePackets": dm_type.UINT,
        "OversizePackets": dm_type.UINT,
        "Packets64Bytes": dm_type.ULONG,
        "Packets65to127Bytes": dm_type.ULONG,
        "Packets128to255Bytes": dm_type.ULONG,
        "Packets256to511Bytes": dm_type.ULONG,
        "Packets512to1023Bytes": dm_type.ULONG,
        "Packets1024to1518Bytes": dm_type.ULONG
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Name": "",
        "Interface": "",
        "VLANID": "0",
        "Queue": "",
        "AllQueues": "false",
        "DropEvents": "0",
        "Bytes": "0",
        "Packets": "0",
        "BroadcastPackets": "0",
        "MulticastPackets": "0",
        "CRCErroredPackets": "0",
        "UndersizePackets": "0",
        "OversizePackets": "0",
        "Packets64Bytes": "0",
        "Packets65to127Bytes": "0",
        "Packets128to255Bytes": "0",
        "Packets256to511Bytes": "0",
        "Packets512to1023Bytes": "0",
        "Packets1024to1518Bytes": "0"
    },
    constraints: {
        "VLANID": { min: 0, max: 4094 }
    }
};

// Schema for Device.Ethernet.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.Ethernet.Interface.{i}.Stats.",
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
        "Collisions": dm_type.ULONG,
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
        "UnknownProtoPacketsReceived": "4294967295",
        "Collisions": "18446744073709551615"
    }
};

// Schema for Device.Ethernet.LAG.{i}.Stats.
export const LAG_Stats = {
    path: "Device.Ethernet.LAG.{i}.Stats.",
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
        "UnknownProtoPacketsReceived": dm_type.UINT
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

// Schema for Device.Ethernet.Link.{i}.
export const Link = {
    path: "Device.Ethernet.Link.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MTU": dm_type.UINT | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING | dm_type.WRITABLE,
        "PriorityTagging": dm_type.BOOL | dm_type.WRITABLE,
        "FlowControl": dm_type.BOOL | dm_type.WRITABLE,
        "NoARP": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "Description": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MTU": "0",
        "MACAddress": "",
        "PriorityTagging": "false",
        "FlowControl": "false",
        "NoARP": "false"
    },
    since: {
        "Description": "2.21"
    },
    constraints: {
        "Description": { max_length: 256 },
        "LowerLayers": { list: true, list_max_length: 1024 },
        "MACAddress": { max_length: 17 }
    }
};

// Schema for Device.Ethernet.Link.{i}.Stats.
export const Link_Stats = {
    path: "Device.Ethernet.Link.{i}.Stats.",
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
        "PausePacketsSent": dm_type.ULONG,
        "PausePacketsReceived": dm_type.ULONG,
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
        "UnknownProtoPacketsReceived": "4294967295",
        "PausePacketsSent": "18446744073709551615",
        "PausePacketsReceived": "18446744073709551615"
    }
};

// Schema for Device.Ethernet.Interface.{i}.
export const Interface = {
    path: "Device.Ethernet.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.INT | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING,
        "CurrentBitRate": dm_type.UINT,
        "CurrentDuplexMode": dm_type.STRING,
        "DuplexMode": dm_type.STRING | dm_type.WRITABLE,
        "SupportedLinkModes": dm_type.STRING,
        "AdvertisedLinkModes": dm_type.STRING | dm_type.WRITABLE,
        "LinkPartnerAdvertisedLinkModes": dm_type.STRING,
        "EEECapability": dm_type.BOOL,
        "EEEEnable": dm_type.BOOL | dm_type.WRITABLE,
        "MDIX": dm_type.STRING | dm_type.WRITABLE,
        "CurrentMDIX": dm_type.STRING
    },
    defaults: {
        "Enable": "true",
        "Status": "",
        "Alias": "",
        "Name": "",
        "Description": "",
        "LastChange": "0",
        "LowerLayers": "",
        "Upstream": "false",
        "MaxBitRate": "-1",
        "MACAddress": "",
        "CurrentBitRate": "0",
        "CurrentDuplexMode": "Auto",
        "DuplexMode": "Auto",
        "SupportedLinkModes": "",
        "AdvertisedLinkModes": "",
        "LinkPartnerAdvertisedLinkModes": "",
        "EEECapability": "true",
        "EEEEnable": "false",
        "MDIX": "Auto",
        "CurrentMDIX": "Unknown"
    },
    since: {
        "Description": "2.21"
    },
    constraints: {
        "Description": { max_length: 256 },
        "LowerLayers": { list: true, list_max_length: 1024 },
        "MaxBitRate": { min: -1 },
        "DuplexMode": { enum: [ "Half", "Full", "Auto" ] },
        "AdvertisedLinkModes": { list: true },
        "MDIX": { enum: [ "Auto", "On", "Off" ] }
    },
    addable: false
};

// Schema for Device.Ethernet.VLANTermination.{i}.
export const VLANTermination = {
    path: "Device.Ethernet.VLANTermination.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "VLANID": dm_type.UINT | dm_type.WRITABLE,
        "VLANPriority": dm_type.INT | dm_type.WRITABLE,
        "TPID": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "Description": "",
        "LastChange": "0",
        "LowerLayers": "",
        "VLANID": "0",
        "VLANPriority": "0",
        "TPID": "33024"
    },
    since: {
        "Description": "2.21"
    },
    constraints: {
        "Description": { max_length: 256 },
        "LowerLayers": { list: true, list_max_length: 1024 },
        "VLANID": { min: 1, max: 4094 },
        "VLANPriority": { min: -1, max: 7 }
    }
};

// Schema for Device.Ethernet.VLANTermination.{i}.Stats.
export const VLANTermination_Stats = {
    path: "Device.Ethernet.VLANTermination.{i}.Stats.",
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
