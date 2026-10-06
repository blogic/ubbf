'use strict';

// Auto-generated schema definitions for TimeWindow domain
// Generated from TR-181 specifications

// Schema for TimeWindow.{i}.
export const TimeWindow = {
    path: "TimeWindow.{i}.",
    schema: {
        "Start": dm_type.UINT,
        "End": dm_type.UINT,
        "Mode": dm_type.STRING,
        "UserMessage": dm_type.STRING,
        "MaxRetries": dm_type.INT
    },
    defaults: {
        "Start": "0",
        "End": "0",
        "Mode": "",
        "UserMessage": "",
        "MaxRetries": "0"
    }
};
