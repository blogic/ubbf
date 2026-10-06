'use strict';

// Auto-generated schema definitions for InterfaceStack domain
// Generated from TR-181 specifications

// Schema for Device.InterfaceStack.{i}.
export const InterfaceStack = {
    path: "Device.InterfaceStack.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "HigherLayer": dm_type.STRING,
        "LowerLayer": dm_type.STRING,
        "HigherAlias": dm_type.STRING,
        "LowerAlias": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "HigherLayer": "",
        "LowerLayer": "",
        "HigherAlias": "",
        "LowerAlias": ""
    }
};
