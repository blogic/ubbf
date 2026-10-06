'use strict';

// Auto-generated schema definitions for DisassociationLinkStats domain
// Generated from TR-181 specifications

// Schema for DisassociationLinkStats.{i}.
export const DisassociationLinkStats = {
    path: "DisassociationLinkStats.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": ""
    }
};
