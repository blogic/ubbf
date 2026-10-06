'use strict';

// Auto-generated schema definitions for ApplicationData domain
// Generated from TR-181 specifications

// Schema for ApplicationData.{i}.
export const ApplicationData = {
    path: "ApplicationData.{i}.",
    schema: {
        "Name": dm_type.STRING,
        "Capacity": dm_type.UINT,
        "Encrypted": dm_type.BOOL,
        "Retain": dm_type.STRING,
        "AccessPath": dm_type.STRING
    },
    defaults: {
        "Name": "",
        "Capacity": "0",
        "Encrypted": "true",
        "Retain": "",
        "AccessPath": ""
    }
};
