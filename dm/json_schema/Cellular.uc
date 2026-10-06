'use strict';

// Auto-generated schema definitions for Cellular domain
// Generated from TR-181 specifications

// Schema for Device.Cellular.Interface.{i}.SMS.Incoming.
export const SMS_Incoming = {
    path: "Device.Cellular.Interface.{i}.SMS.Incoming.",
    schema: {
        "StorageRef": dm_type.STRING | dm_type.WRITABLE,
        "CapacityLimit": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "StorageRef": "",
        "CapacityLimit": "0"
    }
};

// Schema for Device.Cellular.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.Cellular.Interface.{i}.Stats.",
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

// Schema for Device.Cellular.Interface.{i}.USIM.
export const Interface_USIM = {
    path: "Device.Cellular.Interface.{i}.USIM.",
    schema: {
        "Status": dm_type.STRING,
        "IMSI": dm_type.STRING,
        "ICCID": dm_type.STRING,
        "MSISDN": dm_type.STRING,
        "PINCheck": dm_type.STRING | dm_type.WRITABLE,
        "PIN": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "IMSI": "",
        "ICCID": "",
        "MSISDN": "",
        "PINCheck": "",
        "PIN": ""
    }
};

// Schema for Device.Cellular.
export const Cellular = {
    path: "Device.Cellular.",
    schema: {
        "RoamingEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "RoamingStatus": dm_type.STRING,
        "InterfaceNumberOfEntries": dm_type.UINT,
        "AccessPointNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "RoamingStatus": "",
        "InterfaceNumberOfEntries": "0",
        "AccessPointNumberOfEntries": "0"
    }
};

// Schema for Device.Cellular.Interface.{i}.
export const Interface = {
    path: "Device.Cellular.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "IMEI": dm_type.STRING,
        "SupportedAccessTechnologies": dm_type.STRING,
        "PreferredAccessTechnology": dm_type.STRING | dm_type.WRITABLE,
        "CurrentAccessTechnology": dm_type.STRING,
        "AvailableNetworks": dm_type.STRING,
        "NetworkRequested": dm_type.STRING | dm_type.WRITABLE,
        "NetworkInUse": dm_type.STRING,
        "RSSI": dm_type.INT,
        "RSRP": dm_type.INT,
        "RSRQ": dm_type.INT,
        "UpstreamMaxBitRate": dm_type.UINT,
        "DownstreamMaxBitRate": dm_type.UINT,
        "SIMReferenceList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "IMEI": "",
        "SupportedAccessTechnologies": "",
        "PreferredAccessTechnology": "Auto",
        "CurrentAccessTechnology": "",
        "AvailableNetworks": "",
        "NetworkRequested": "",
        "NetworkInUse": "",
        "RSSI": "0",
        "RSRP": "0",
        "RSRQ": "0",
        "UpstreamMaxBitRate": "0",
        "DownstreamMaxBitRate": "0",
        "SIMReferenceList": ""
    }
};

// Schema for Device.Cellular.Interface.{i}.SMS.Storage.{i}.
export const SMS_Storage = {
    path: "Device.Cellular.Interface.{i}.SMS.Storage.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Location": dm_type.STRING | dm_type.WRITABLE,
        "Capacity": dm_type.UINT,
        "StorageAvailable": dm_type.BOOL,
        "AvailableCapacity": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Location": "",
        "Capacity": "0",
        "AvailableCapacity": "0"
    }
};

// Schema for Device.Cellular.Interface.{i}.SMS.Outgoing.
export const SMS_Outgoing = {
    path: "Device.Cellular.Interface.{i}.SMS.Outgoing.",
    schema: {
        "StorageRef": dm_type.STRING | dm_type.WRITABLE,
        "CapacityLimit": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "StorageRef": "",
        "CapacityLimit": "0"
    }
};

// Schema for Device.Cellular.Interface.{i}.SMS.
export const Interface_SMS = {
    path: "Device.Cellular.Interface.{i}.SMS.",
    schema: {
        "StorageNumberOfEntries": dm_type.UINT,
        "MessageNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "StorageNumberOfEntries": "0",
        "MessageNumberOfEntries": "0"
    }
};

// Schema for Device.Cellular.Interface.{i}.SMS.Message.{i}.
export const SMS_Message = {
    path: "Device.Cellular.Interface.{i}.SMS.Message.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Sender": dm_type.STRING,
        "Receiver": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "Text": dm_type.STRING,
        "StorageRef": dm_type.STRING,
        "Status": dm_type.STRING,
        "Type": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Sender": "",
        "Receiver": "",
        "Text": "",
        "StorageRef": "",
        "Status": "",
        "Type": ""
    }
};

// Schema for Device.Cellular.AccessPoint.{i}.
export const AccessPoint = {
    path: "Device.Cellular.AccessPoint.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "APN": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "Proxy": dm_type.STRING | dm_type.WRITABLE,
        "ProxyPort": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "APN": "",
        "Username": "",
        "Password": "",
        "Proxy": "",
        "ProxyPort": "0",
        "Interface": "",
        "IPVersion": "-1",
        "Type": ""
    }
};
