'use strict';

// Auto-generated schema definitions for Channels domain
// Generated from TR-181 specifications

// Schema for Channels.
export const Channels = {
    path: "Channels.",
    schema: {
        "TimeStamp": dm_type.DATETIME
    },
    defaults: {}
};

// Schema for Channels.Channel.{i}.
export const Channel = {
    path: "Channels.Channel.{i}.",
    schema: {
        "DestinationMACAddress": dm_type.STRING,
        "SNR": dm_type.UINT
    },
    defaults: {
        "DestinationMACAddress": "",
        "SNR": "0"
    }
};
