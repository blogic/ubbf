'use strict';

// Auto-generated schema definitions for SSIDtoVIDMapping domain
// Generated from TR-181 specifications

// Schema for SSIDtoVIDMapping.{i}.
export const SSIDtoVIDMapping = {
    path: "SSIDtoVIDMapping.{i}.",
    schema: {
        "SSID": dm_type.STRING,
        "VID": dm_type.UINT
    },
    defaults: {
        "SSID": "",
        "VID": "0"
    }
};
