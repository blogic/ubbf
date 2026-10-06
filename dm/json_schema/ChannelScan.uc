'use strict';

// Auto-generated schema definitions for ChannelScan domain
// Generated from TR-181 specifications

// Schema for ChannelScan.{i}.
export const ChannelScan = {
    path: "ChannelScan.{i}.",
    schema: {
        "Channel": dm_type.UINT,
        "RSSI": dm_type.INT
    },
    defaults: {
        "Channel": "0",
        "RSSI": "0"
    }
};
