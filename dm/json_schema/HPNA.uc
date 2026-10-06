'use strict';

// Auto-generated schema definitions for HPNA domain
// Generated from TR-181 specifications

// Schema for Device.HPNA.Interface.{i}.QoS.FlowSpec.{i}.
export const QoS_FlowSpec = {
    path: "Device.HPNA.Interface.{i}.QoS.FlowSpec.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "TrafficClasses": dm_type.UINT | dm_type.WRITABLE,
        "FlowType": dm_type.STRING | dm_type.WRITABLE,
        "Priority": dm_type.UINT | dm_type.WRITABLE,
        "Latency": dm_type.UINT | dm_type.WRITABLE,
        "Jitter": dm_type.UINT | dm_type.WRITABLE,
        "PacketSize": dm_type.UINT | dm_type.WRITABLE,
        "MinRate": dm_type.UINT | dm_type.WRITABLE,
        "AvgRate": dm_type.UINT | dm_type.WRITABLE,
        "MaxRate": dm_type.UINT | dm_type.WRITABLE,
        "PER": dm_type.UINT | dm_type.WRITABLE,
        "Timeout": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "TrafficClasses": "[]",
        "FlowType": "BE",
        "Priority": "0",
        "Latency": "0",
        "Jitter": "0",
        "PacketSize": "0",
        "MinRate": "0",
        "AvgRate": "0",
        "MaxRate": "0",
        "PER": "0",
        "Timeout": "0"
    }
};

// Schema for Device.HPNA.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.HPNA.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "NodeID": dm_type.UINT,
        "IsMaster": dm_type.BOOL,
        "Synced": dm_type.BOOL,
        "TotalSyncTime": dm_type.UINT,
        "MaxBitRate": dm_type.UINT,
        "PHYDiagnosticsEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Active": dm_type.BOOL
    },
    defaults: {
        "MACAddress": "",
        "NodeID": "0",
        "TotalSyncTime": "0",
        "MaxBitRate": "0"
    }
};

// Schema for Device.HPNA.Interface.{i}.QoS.
export const Interface_QoS = {
    path: "Device.HPNA.Interface.{i}.QoS.",
    schema: {
        "FlowSpecNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "FlowSpecNumberOfEntries": "0"
    }
};

// Schema for Device.HPNA.Interface.{i}.
export const Interface = {
    path: "Device.HPNA.Interface.{i}.",
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
        "FirmwareVersion": dm_type.STRING,
        "NodeID": dm_type.UINT,
        "IsMaster": dm_type.BOOL,
        "Synced": dm_type.BOOL,
        "TotalSyncTime": dm_type.UINT,
        "NetworkUtilization": dm_type.UINT,
        "PossibleConnectionTypes": dm_type.STRING,
        "ConnectionType": dm_type.STRING | dm_type.WRITABLE,
        "PossibleSpectralModes": dm_type.STRING,
        "SpectralMode": dm_type.STRING | dm_type.WRITABLE,
        "MTU": dm_type.UINT | dm_type.WRITABLE,
        "NoiseMargin": dm_type.UINT | dm_type.WRITABLE,
        "DefaultNonLARQPER": dm_type.UINT | dm_type.WRITABLE,
        "LARQEnable": dm_type.BOOL | dm_type.WRITABLE,
        "MinMulticastRate": dm_type.UINT | dm_type.WRITABLE,
        "NegMulticastRate": dm_type.UINT,
        "MasterSelectionMode": dm_type.STRING | dm_type.WRITABLE,
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
        "FirmwareVersion": "",
        "NodeID": "0",
        "TotalSyncTime": "0",
        "NetworkUtilization": "0",
        "PossibleConnectionTypes": "",
        "ConnectionType": "",
        "PossibleSpectralModes": "",
        "SpectralMode": "",
        "MTU": "0",
        "NoiseMargin": "0",
        "DefaultNonLARQPER": "0",
        "MinMulticastRate": "0",
        "NegMulticastRate": "0",
        "MasterSelectionMode": "",
        "AssociatedDeviceNumberOfEntries": "0"
    }
};

// Schema for Device.HPNA.
export const HPNA = {
    path: "Device.HPNA.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.HPNA.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.HPNA.Interface.{i}.Stats.",
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
