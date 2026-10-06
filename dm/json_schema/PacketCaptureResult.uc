'use strict';

// Auto-generated schema definitions for PacketCaptureResult domain
// Generated from TR-181 specifications

// Schema for PacketCaptureResult.{i}.
export const PacketCaptureResult = {
    path: "PacketCaptureResult.{i}.",
    schema: {
        "FileLocation": dm_type.STRING,
        "StartTime": dm_type.DATETIME,
        "EndTime": dm_type.DATETIME,
        "Count": dm_type.UINT
    },
    defaults: {
        "FileLocation": "",
        "Count": "0"
    }
};
