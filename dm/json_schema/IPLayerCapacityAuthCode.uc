'use strict';

// Auto-generated schema definitions for IPLayerCapacityAuthCode domain
// Generated from TR-181 specifications

// Schema for IPLayerCapacityAuthCode.{i}.
export const IPLayerCapacityAuthCode = {
    path: "IPLayerCapacityAuthCode.{i}.",
    schema: {
        "AuthenticationKey": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "AuthenticationKey": ""
    }
};
