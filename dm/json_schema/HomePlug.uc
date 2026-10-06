'use strict';

// Auto-generated schema definitions for HomePlug domain
// Generated from TR-181 specifications

// Schema for Device.HomePlug.Interface.{i}.
export const Interface = {
    path: "Device.HomePlug.Interface.{i}.",
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
        "LogicalNetwork": dm_type.STRING | dm_type.WRITABLE,
        "Version": dm_type.STRING,
        "FirmwareVersion": dm_type.STRING,
        "ForceCCo": dm_type.BOOL | dm_type.WRITABLE,
        "NetworkPassword": dm_type.STRING | dm_type.WRITABLE,
        "OtherNetworksPresent": dm_type.STRING,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "MACAddress": "",
        "LogicalNetwork": "",
        "Version": "",
        "FirmwareVersion": "",
        "ForceCCo": "false",
        "NetworkPassword": "",
        "OtherNetworksPresent": "",
        "AssociatedDeviceNumberOfEntries": "0"
    }
};

// Schema for Device.HomePlug.
export const HomePlug = {
    path: "Device.HomePlug.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.HomePlug.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.HomePlug.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "TxPhyRate": dm_type.UINT,
        "RxPhyRate": dm_type.UINT,
        "SNRPerTone": dm_type.UINT,
        "AvgAttenuation": dm_type.UINT,
        "EndStationMACs": dm_type.STRING,
        "Active": dm_type.BOOL
    },
    defaults: {
        "MACAddress": "",
        "TxPhyRate": "0",
        "RxPhyRate": "0",
        "SNRPerTone": "0",
        "AvgAttenuation": "0",
        "EndStationMACs": ""
    }
};

// Schema for Device.HomePlug.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.HomePlug.Interface.{i}.Stats.",
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
        "MPDUTxAck": dm_type.ULONG,
        "MPDUTxCol": dm_type.ULONG,
        "MPDUTxFailed": dm_type.ULONG,
        "MPDURxAck": dm_type.ULONG,
        "MPDURxFailed": dm_type.ULONG
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
        "MPDUTxAck": "0",
        "MPDUTxCol": "0",
        "MPDUTxFailed": "0",
        "MPDURxAck": "0",
        "MPDURxFailed": "0"
    }
};
