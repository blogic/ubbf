'use strict';

// Auto-generated schema definitions for SPRule domain
// Generated from TR-181 specifications

// Schema for SPRule.{i}.
export const SPRule = {
    path: "SPRule.{i}.",
    schema: {
        "ID": dm_type.UINT,
        "Precedence": dm_type.UINT,
        "Output": dm_type.UINT,
        "AlwaysMatch": dm_type.BOOL
    },
    defaults: {
        "ID": "0",
        "Precedence": "0",
        "Output": "0"
    }
};
