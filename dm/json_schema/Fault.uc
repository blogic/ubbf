'use strict';

// Auto-generated schema definitions for Fault domain
// Generated from TR-181 specifications

// Schema for Fault.
export const Fault = {
    path: "Fault.",
    schema: {
        "FaultCode": dm_type.UINT,
        "FaultString": dm_type.STRING
    },
    defaults: {
        "FaultCode": "0",
        "FaultString": ""
    }
};
