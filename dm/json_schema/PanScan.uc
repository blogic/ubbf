'use strict';

// Auto-generated schema definitions for PanScan domain
// Generated from TR-181 specifications

// Schema for PanScan.{i}.
export const PanScan = {
    path: "PanScan.{i}.",
    schema: {
        "PanID": dm_type.HEXBIN,
        "MACAddress": dm_type.STRING,
        "Channel": dm_type.UINT,
        "RSSI": dm_type.INT,
        "LQI": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "Channel": "0",
        "RSSI": "0",
        "LQI": ""
    }
};
