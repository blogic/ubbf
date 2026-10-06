'use strict';

// Auto-generated schema definitions for ChangeSet domain
// Generated from TR-181 specifications

// Schema for ChangeSet.{i}.
export const ChangeSet = {
    path: "ChangeSet.{i}.",
    schema: {
        "ObjectPath": dm_type.STRING
    },
    defaults: {
        "ObjectPath": ""
    }
};

// Schema for ChangeSet.{i}.Parameter.{i}.
export const Parameter = {
    path: "ChangeSet.{i}.Parameter.{i}.",
    schema: {
        "Name": dm_type.STRING,
        "Value": dm_type.STRING,
        "OldValue": dm_type.STRING,
        "ChangeTime": dm_type.DATETIME
    },
    defaults: {
        "Name": "",
        "Value": "",
        "OldValue": ""
    }
};
