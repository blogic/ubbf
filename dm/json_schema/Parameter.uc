'use strict';

// Auto-generated schema definitions for Parameter domain
// Generated from TR-181 specifications

// Schema for Parameter.{i}.
export const Parameter = {
    path: "Parameter.{i}.",
    schema: {
        "Reference": dm_type.STRING,
        "Values": dm_type.STRING,
        "SampleSeconds": dm_type.UINT,
        "SuspectData": dm_type.UINT,
        "Failures": dm_type.UINT
    },
    defaults: {
        "Reference": "",
        "Values": "",
        "SampleSeconds": "0",
        "SuspectData": "0",
        "Failures": "0"
    }
};
