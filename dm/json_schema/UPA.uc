'use strict';

// Auto-generated schema definitions for UPA domain
// Generated from TR-181 specifications

// Schema for Device.UPA.Interface.{i}.BridgeFor.{i}.
export const Interface_BridgeFor = {
    path: "Device.UPA.Interface.{i}.BridgeFor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "Port": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "MACAddress": "",
        "Port": "0"
    }
};

// Schema for Device.UPA.Interface.{i}.
export const Interface = {
    path: "Device.UPA.Interface.{i}.",
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
        "NodeType": dm_type.STRING | dm_type.WRITABLE,
        "LogicalNetwork": dm_type.STRING | dm_type.WRITABLE,
        "EncryptionMethod": dm_type.STRING | dm_type.WRITABLE,
        "EncryptionKey": dm_type.STRING | dm_type.WRITABLE,
        "PowerBackoffEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "PowerBackoffMechanismActive": dm_type.BOOL,
        "EstApplicationThroughput": dm_type.UINT,
        "ActiveNotchEnable": dm_type.BOOL | dm_type.WRITABLE,
        "ActiveNotchNumberOfEntries": dm_type.UINT,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT,
        "BridgeForNumberOfEntries": dm_type.UINT
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
        "NodeType": "",
        "LogicalNetwork": "",
        "EncryptionMethod": "",
        "EncryptionKey": "",
        "EstApplicationThroughput": "0",
        "ActiveNotchNumberOfEntries": "0",
        "AssociatedDeviceNumberOfEntries": "0",
        "BridgeForNumberOfEntries": "0"
    }
};

// Schema for Device.UPA.Interface.{i}.ActiveNotch.{i}.
export const Interface_ActiveNotch = {
    path: "Device.UPA.Interface.{i}.ActiveNotch.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "StartFreq": dm_type.UINT | dm_type.WRITABLE,
        "StopFreq": dm_type.UINT | dm_type.WRITABLE,
        "Depth": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "StartFreq": "0",
        "StopFreq": "0",
        "Depth": "0"
    }
};

// Schema for Device.UPA.
export const UPA = {
    path: "Device.UPA.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.UPA.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.UPA.Interface.{i}.Stats.",
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

// Schema for Device.UPA.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.UPA.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "Port": dm_type.UINT,
        "LogicalNetwork": dm_type.STRING,
        "PhyTxThroughput": dm_type.UINT,
        "PhyRxThroughput": dm_type.UINT,
        "RealPhyRxThroughput": dm_type.UINT,
        "EstimatedPLR": dm_type.UINT,
        "MeanEstimatedAtt": dm_type.UINT,
        "SmartRouteIntermediatePLCMAC": dm_type.STRING,
        "DirectRoute": dm_type.BOOL,
        "Active": dm_type.BOOL
    },
    defaults: {
        "MACAddress": "",
        "Port": "0",
        "LogicalNetwork": "",
        "PhyTxThroughput": "0",
        "PhyRxThroughput": "0",
        "RealPhyRxThroughput": "0",
        "EstimatedPLR": "0",
        "MeanEstimatedAtt": "0",
        "SmartRouteIntermediatePLCMAC": ""
    }
};
