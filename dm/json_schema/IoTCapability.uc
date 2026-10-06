'use strict';

// Auto-generated schema definitions for IoTCapability domain
// Generated from TR-181 specifications

// Schema for Device.IoTCapability.{i}.LevelControl.
export const LevelControl = {
    path: "Device.IoTCapability.{i}.LevelControl.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.STRING | dm_type.WRITABLE,
        "Unit": dm_type.STRING,
        "MinValue": dm_type.STRING,
        "MaxValue": dm_type.STRING,
        "StepValue": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Type": "",
        "Description": "",
        "Unit": ""
    }
};

// Schema for Device.IoTCapability.{i}.BlobSensor.
export const BlobSensor = {
    path: "Device.IoTCapability.{i}.BlobSensor.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "LastContactTime": dm_type.DATETIME,
        "Value": dm_type.BASE64
    },
    defaults: {
        "Type": "",
        "Description": ""
    }
};

// Schema for Device.IoTCapability.{i}.BinaryControl.
export const BinaryControl = {
    path: "Device.IoTCapability.{i}.BinaryControl.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Type": "",
        "Description": ""
    }
};

// Schema for Device.IoTCapability.{i}.EnumControl.
export const EnumControl = {
    path: "Device.IoTCapability.{i}.EnumControl.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.STRING | dm_type.WRITABLE,
        "ValidValues": dm_type.STRING
    },
    defaults: {
        "Type": "",
        "Description": "",
        "Value": "",
        "ValidValues": ""
    }
};

// Schema for Device.IoTCapability.{i}.MultiLevelSensor.
export const MultiLevelSensor = {
    path: "Device.IoTCapability.{i}.MultiLevelSensor.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Values": dm_type.STRING,
        "ValueNames": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "LastContactTime": dm_type.DATETIME,
        "Unit": dm_type.STRING
    },
    defaults: {
        "Type": "",
        "Description": "",
        "ValueNames": "",
        "Unit": ""
    }
};

// Schema for Device.IoTCapability.{i}.
export const IoTCapability = {
    path: "Device.IoTCapability.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Class": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Class": ""
    }
};

// Schema for Device.IoTCapability.{i}.LevelSensor.
export const LevelSensor = {
    path: "Device.IoTCapability.{i}.LevelSensor.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "LastContactTime": dm_type.DATETIME,
        "Unit": dm_type.STRING,
        "LowLevel": dm_type.BOOL,
        "LowLevelThreshold": dm_type.STRING | dm_type.WRITABLE,
        "HighLevel": dm_type.BOOL,
        "HighLevelThreshold": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Type": "",
        "Description": "",
        "Unit": ""
    }
};

// Schema for Device.IoTCapability.{i}.BinarySensor.
export const BinarySensor = {
    path: "Device.IoTCapability.{i}.BinarySensor.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.BOOL,
        "LastChange": dm_type.DATETIME,
        "LastContactTime": dm_type.DATETIME,
        "Sensitivity": dm_type.UINT | dm_type.WRITABLE,
        "HoldTime": dm_type.UINT | dm_type.WRITABLE,
        "RestTime": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Type": "",
        "Description": "",
        "Sensitivity": "0",
        "HoldTime": "0",
        "RestTime": "0"
    }
};

// Schema for Device.IoTCapability.{i}.EnumSensor.
export const EnumSensor = {
    path: "Device.IoTCapability.{i}.EnumSensor.",
    schema: {
        "Type": dm_type.STRING,
        "Description": dm_type.STRING,
        "Value": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "LastContactTime": dm_type.DATETIME,
        "ValidValues": dm_type.STRING
    },
    defaults: {
        "Type": "",
        "Description": "",
        "Value": "",
        "ValidValues": ""
    }
};
