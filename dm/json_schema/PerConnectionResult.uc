'use strict';

// Auto-generated schema definitions for PerConnectionResult domain
// Generated from TR-181 specifications

// Schema for PerConnectionResult.{i}.
export const PerConnectionResult = {
    path: "PerConnectionResult.{i}.",
    schema: {
        "ROMTime": dm_type.DATETIME,
        "BOMTime": dm_type.DATETIME,
        "EOMTime": dm_type.DATETIME,
        "TestBytesSent": dm_type.STRING,
        "TotalBytesReceived": dm_type.STRING,
        "TotalBytesSent": dm_type.STRING,
        "TCPOpenRequestTime": dm_type.DATETIME,
        "TCPOpenResponseTime": dm_type.DATETIME
    },
    defaults: {
        "TestBytesSent": "",
        "TotalBytesReceived": "",
        "TotalBytesSent": ""
    }
};
