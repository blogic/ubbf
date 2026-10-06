'use strict';

// Auto-generated schema definitions for ATM domain
// Generated from TR-181 specifications

// Schema for Device.ATM.
export const ATM = {
    path: "Device.ATM.",
    schema: {
        "LinkNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LinkNumberOfEntries": "0"
    }
};

// Schema for Device.ATM.Link.{i}.
export const Link = {
    path: "Device.ATM.Link.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "LinkType": dm_type.STRING | dm_type.WRITABLE,
        "AutoConfig": dm_type.BOOL,
        "DestinationAddress": dm_type.STRING | dm_type.WRITABLE,
        "Encapsulation": dm_type.STRING | dm_type.WRITABLE,
        "FCSPreserved": dm_type.BOOL | dm_type.WRITABLE,
        "VCSearchList": dm_type.STRING | dm_type.WRITABLE,
        "AAL": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "LinkType": "",
        "DestinationAddress": "",
        "Encapsulation": "",
        "VCSearchList": "",
        "AAL": ""
    }
};

// Schema for Device.ATM.Link.{i}.QoS.
export const Link_QoS = {
    path: "Device.ATM.Link.{i}.QoS.",
    schema: {
        "QoSClass": dm_type.STRING | dm_type.WRITABLE,
        "PeakCellRate": dm_type.UINT | dm_type.WRITABLE,
        "MaximumBurstSize": dm_type.UINT | dm_type.WRITABLE,
        "SustainableCellRate": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "QoSClass": "",
        "PeakCellRate": "0",
        "MaximumBurstSize": "0",
        "SustainableCellRate": "0"
    }
};

// Schema for Device.ATM.Link.{i}.Stats.
export const Link_Stats = {
    path: "Device.ATM.Link.{i}.Stats.",
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
        "TransmittedBlocks": dm_type.UINT,
        "ReceivedBlocks": dm_type.UINT,
        "CRCErrors": dm_type.UINT,
        "HECErrors": dm_type.UINT
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
        "TransmittedBlocks": "0",
        "ReceivedBlocks": "0",
        "CRCErrors": "0",
        "HECErrors": "0"
    }
};
