'use strict';

// Auto-generated schema definitions for QMDescriptor domain
// Generated from TR-181 specifications

// Schema for QMDescriptor.{i}.
export const QMDescriptor = {
    path: "QMDescriptor.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "ClientMAC": dm_type.STRING,
        "DescriptorElement": dm_type.HEXBIN
    },
    defaults: {
        "BSSID": "",
        "ClientMAC": ""
    }
};
