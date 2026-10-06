'use strict';

// Auto-generated schema definitions for Nodes domain
// Generated from TR-181 specifications

// Schema for Nodes.Node.{i}.
export const Node = {
    path: "Nodes.Node.{i}.",
    schema: {
        "DestinationMACAddress": dm_type.STRING,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "UnicastPacketsSent": dm_type.STRING,
        "UnicastPacketsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "MulticastPacketsSent": dm_type.STRING,
        "MulticastPacketsReceived": dm_type.STRING,
        "BroadcastPacketsSent": dm_type.STRING,
        "BroadcastPacketsReceived": dm_type.STRING,
        "UnknownProtoPacketsReceived": dm_type.STRING,
        "MgmtBytesSent": dm_type.STRING,
        "MgmtBytesReceived": dm_type.STRING,
        "MgmtPacketsSent": dm_type.STRING,
        "MgmtPacketsReceived": dm_type.STRING,
        "BlocksSent": dm_type.STRING,
        "BlocksReceived": dm_type.STRING,
        "BlocksResent": dm_type.STRING,
        "BlocksErrorsReceived": dm_type.STRING
    },
    defaults: {
        "DestinationMACAddress": "",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "UnicastPacketsSent": "",
        "UnicastPacketsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "MulticastPacketsSent": "",
        "MulticastPacketsReceived": "",
        "BroadcastPacketsSent": "",
        "BroadcastPacketsReceived": "",
        "UnknownProtoPacketsReceived": "",
        "MgmtBytesSent": "",
        "MgmtBytesReceived": "",
        "MgmtPacketsSent": "",
        "MgmtPacketsReceived": "",
        "BlocksSent": "",
        "BlocksReceived": "",
        "BlocksResent": "",
        "BlocksErrorsReceived": ""
    }
};

// Schema for Nodes.
export const Nodes = {
    path: "Nodes.",
    schema: {
        "CurrentStart": dm_type.DATETIME,
        "CurrentEnd": dm_type.DATETIME
    },
    defaults: {}
};
