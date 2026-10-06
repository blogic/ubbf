'use strict';

// Auto-generated schema definitions for BASAPM domain
// Generated from TR-181 specifications

// Schema for Device.BASAPM.MeasurementEndpoint.{i}.ISPDevice.
export const MeasurementEndpoint_ISPDevice = {
    path: "Device.BASAPM.MeasurementEndpoint.{i}.ISPDevice.",
    schema: {
        "ReferencePoint": dm_type.STRING | dm_type.WRITABLE,
        "GeographicalLocation": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ReferencePoint": "",
        "GeographicalLocation": ""
    }
};

// Schema for Device.BASAPM.MeasurementEndpoint.{i}.CustomerDevice.
export const MeasurementEndpoint_CustomerDevice = {
    path: "Device.BASAPM.MeasurementEndpoint.{i}.CustomerDevice.",
    schema: {
        "EquipmentIdentifier": dm_type.STRING | dm_type.WRITABLE,
        "CustomerIdentifier": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "EquipmentIdentifier": "",
        "CustomerIdentifier": ""
    }
};

// Schema for Device.BASAPM.
export const BASAPM = {
    path: "Device.BASAPM.",
    schema: {
        "MeasurementEndpointNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MeasurementEndpointNumberOfEntries": "0"
    }
};

// Schema for Device.BASAPM.MeasurementEndpoint.{i}.
export const MeasurementEndpoint = {
    path: "Device.BASAPM.MeasurementEndpoint.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MeasurementAgent": dm_type.STRING | dm_type.WRITABLE,
        "DeviceOwnership": dm_type.STRING | dm_type.WRITABLE,
        "OperationalDomain": dm_type.STRING | dm_type.WRITABLE,
        "InternetDomain": dm_type.STRING | dm_type.WRITABLE,
        "UseMeasurementEndpointInReports": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "MeasurementAgent": "",
        "DeviceOwnership": "",
        "OperationalDomain": "",
        "InternetDomain": ""
    }
};
