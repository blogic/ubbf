'use strict';

// Auto-generated schema definitions for AutoRestart domain
// Generated from TR-181 specifications

// Schema for AutoRestart.
export const AutoRestart = {
    path: "AutoRestart.",
    schema: {
        "Enable": dm_type.BOOL,
        "RetryMinimumWaitInterval": dm_type.UINT,
        "RetryMaximumWaitInterval": dm_type.UINT,
        "RetryIntervalMultiplier": dm_type.UINT,
        "MaximumRetryCount": dm_type.UINT,
        "ResetPeriod": dm_type.UINT
    },
    defaults: {
        "RetryMinimumWaitInterval": "0",
        "RetryMaximumWaitInterval": "0",
        "RetryIntervalMultiplier": "0",
        "MaximumRetryCount": "10",
        "ResetPeriod": "0"
    }
};
