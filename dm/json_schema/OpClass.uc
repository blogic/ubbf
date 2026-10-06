'use strict';

// Auto-generated schema definitions for OpClass domain
// Generated from TR-181 specifications

// Schema for OpClass.{i}.
export const OpClass = {
    path: "OpClass.{i}.",
    schema: {
        "OperatingClass": dm_type.UINT
    },
    defaults: {
        "OperatingClass": "0"
    }
};

// Schema for OpClass.{i}.Channel.{i}.
export const Channel = {
    path: "OpClass.{i}.Channel.{i}.",
    schema: {
        "Channel": dm_type.UINT
    },
    defaults: {
        "Channel": "0"
    }
};
