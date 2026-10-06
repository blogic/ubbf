'use strict';

// Auto-generated schema definitions for Class domain
// Generated from TR-181 specifications

// Schema for Class.{i}.
export const Class = {
    path: "Class.{i}.",
    schema: {
        "OpClass": dm_type.UINT
    },
    defaults: {
        "OpClass": "0"
    }
};

// Schema for Class.{i}.Channel.{i}.
export const Channel = {
    path: "Class.{i}.Channel.{i}.",
    schema: {
        "Channel": dm_type.UINT,
        "Preference": dm_type.UINT
    },
    defaults: {
        "Channel": "0",
        "Preference": "0"
    }
};
