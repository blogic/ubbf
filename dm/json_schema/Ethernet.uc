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
        "LowerLayers": "[]",
        "MACAddress": ""
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
    }
};

// Schema for Device.Ethernet.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.Ethernet.Interface.{i}.Stats.",
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
        "Collisions": dm_type.STRING
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
        "UnknownProtoPacketsReceived": "",
        "Collisions": ""
    }
};

// Schema for Device.Ethernet.LAG.{i}.Stats.
export const LAG_Stats = {
    path: "Device.Ethernet.LAG.{i}.Stats.",
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

// Schema for Device.Ethernet.Link.{i}.
export const Link = {
    path: "Device.Ethernet.Link.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
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
        "LastChange": "0",
        "LowerLayers": "[]",
        "MTU": "0",
        "MACAddress": "",
        "PriorityTagging": "false",
        "FlowControl": "false",
        "NoARP": "false"
    }
};

// Schema for Device.Ethernet.Link.{i}.Stats.
export const Link_Stats = {
    path: "Device.Ethernet.Link.{i}.Stats.",
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
        "PausePacketsSent": dm_type.STRING,
        "PausePacketsReceived": dm_type.STRING
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
        "UnknownProtoPacketsReceived": "",
        "PausePacketsSent": "",
        "PausePacketsReceived": ""
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
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.INT | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING,
        "SupportedLinkModes": dm_type.UINT,
        "AdvertisedLinkModes": dm_type.UINT | dm_type.WRITABLE,
        "LinkPartnerAdvertisedLinkModes": dm_type.UINT,
        "CurrentBitRate": dm_type.UINT,
        "DuplexMode": dm_type.STRING | dm_type.WRITABLE,
        "CurrentDuplexMode": dm_type.STRING,
        "EEECapability": dm_type.BOOL,
        "EEEEnable": dm_type.BOOL | dm_type.WRITABLE,
        "EEEStatus": dm_type.STRING,
        "EDPDCapability": dm_type.BOOL,
        "EDPDEnable": dm_type.BOOL | dm_type.WRITABLE,
        "EDPDStatus": dm_type.STRING,
        "MDIX": dm_type.STRING | dm_type.WRITABLE,
        "CurrentMDIX": dm_type.STRING,
        "SFPReferenceList": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "MACAddress": "",
        "SupportedLinkModes": "0",
        "AdvertisedLinkModes": "0",
        "LinkPartnerAdvertisedLinkModes": "0",
        "CurrentBitRate": "0",
        "DuplexMode": "",
        "CurrentDuplexMode": "",
        "EEEStatus": "",
        "EDPDStatus": "",
        "MDIX": "Auto",
        "CurrentMDIX": "",
        "SFPReferenceList": ""
    }
};

// Schema for Device.Ethernet.VLANTermination.{i}.
export const VLANTermination = {
    path: "Device.Ethernet.VLANTermination.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
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
        "LastChange": "0",
        "LowerLayers": "[]",
        "VLANID": "0",
        "VLANPriority": "0",
        "TPID": "33024"
    }
};

// Schema for Device.Ethernet.VLANTermination.{i}.Stats.
export const VLANTermination_Stats = {
    path: "Device.Ethernet.VLANTermination.{i}.Stats.",
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
