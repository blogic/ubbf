'use strict';

// Auto-generated schema definitions for USPServices domain
// Generated from TR-181 specifications

// Schema for Device.USPServices.USPService.{i}.
export const USPService = {
    path: "Device.USPServices.USPService.{i}.",
    schema: {
        "EndpointID": dm_type.STRING,
        "Protocol": dm_type.STRING,
        "DataModelPaths": dm_type.STRING,
        "DeploymentUnitRef": dm_type.STRING,
        "ExecutionUnitRef": dm_type.STRING,
        "HasController": dm_type.BOOL
    },
    defaults: {
        "EndpointID": "",
        "Protocol": "",
        "DataModelPaths": "",
        "DeploymentUnitRef": "",
        "ExecutionUnitRef": ""
    }
};

// Schema for Device.USPServices.
export const USPServices = {
    path: "Device.USPServices.",
    schema: {
        "TrustNumberOfEntries": dm_type.UINT,
        "USPServiceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "TrustNumberOfEntries": "0",
        "USPServiceNumberOfEntries": "0"
    }
};

// Schema for Device.USPServices.Trust.{i}.
export const Trust = {
    path: "Device.USPServices.Trust.{i}.",
    schema: {
        "EndpointID": dm_type.STRING | dm_type.WRITABLE,
        "TargetPaths": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "EndpointID": "",
        "TargetPaths": ""
    }
};
