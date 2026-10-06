'use strict';

// Auto-generated schema definitions for BulkData domain
// Generated from TR-181 specifications

// Schema for Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}.
export const HTTP_RequestURIParameter = {
    path: "Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}.",
    schema: {
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Reference": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Name": "",
        "Reference": ""
    }
};

// Schema for Device.BulkData.Profile.{i}.JSONEncoding.
export const Profile_JSONEncoding = {
    path: "Device.BulkData.Profile.{i}.JSONEncoding.",
    schema: {
        "ReportFormat": dm_type.STRING | dm_type.WRITABLE,
        "ReportTimestamp": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ReportFormat": "ObjectHierarchy",
        "ReportTimestamp": "Unix-Epoch"
    }
};

// Schema for Device.BulkData.Profile.{i}.MQTT.
export const Profile_MQTT = {
    path: "Device.BulkData.Profile.{i}.MQTT.",
    schema: {
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "PublishTopic": dm_type.STRING | dm_type.WRITABLE,
        "PublishQoS": dm_type.UINT | dm_type.WRITABLE,
        "PublishRetain": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Reference": "",
        "PublishTopic": "",
        "PublishQoS": "0",
        "PublishRetain": "false"
    }
};

// Schema for Device.BulkData.Profile.{i}.HTTP.
export const Profile_HTTP = {
    path: "Device.BulkData.Profile.{i}.HTTP.",
    schema: {
        "URL": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "CompressionsSupported": dm_type.STRING,
        "Compression": dm_type.STRING | dm_type.WRITABLE,
        "MethodsSupported": dm_type.STRING,
        "Method": dm_type.STRING | dm_type.WRITABLE,
        "UseDateHeader": dm_type.BOOL | dm_type.WRITABLE,
        "RetryEnable": dm_type.BOOL | dm_type.WRITABLE,
        "RetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "RetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "RequestURIParameterNumberOfEntries": dm_type.UINT,
        "PersistAcrossReboot": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "URL": "",
        "Username": "",
        "Password": "",
        "CompressionsSupported": "",
        "Compression": "None",
        "MethodsSupported": "",
        "Method": "POST",
        "UseDateHeader": "true",
        "RetryEnable": "false",
        "RetryMinimumWaitInterval": "5",
        "RetryIntervalMultiplier": "2000",
        "RequestURIParameterNumberOfEntries": "0",
        "PersistAcrossReboot": "false"
    },
    constraints: {
        "Password": { secured: true }
    }
};

// Schema for Device.BulkData.Profile.{i}.
export const Profile = {
    path: "Device.BulkData.Profile.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Controller": dm_type.STRING,
        "NumberOfRetainedFailedReports": dm_type.INT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "EncodingType": dm_type.STRING | dm_type.WRITABLE,
        "ReportingInterval": dm_type.UINT | dm_type.WRITABLE,
        "TimeReference": dm_type.DATETIME | dm_type.WRITABLE,
        "ParameterNumberOfEntries": dm_type.UINT,
        "StreamingHost": dm_type.STRING | dm_type.WRITABLE,
        "StreamingPort": dm_type.UINT | dm_type.WRITABLE,
        "StreamingSessionID": dm_type.UINT | dm_type.WRITABLE,
        "FileTransferURL": dm_type.STRING | dm_type.WRITABLE,
        "FileTransferUsername": dm_type.STRING | dm_type.WRITABLE,
        "FileTransferPassword": dm_type.STRING | dm_type.WRITABLE,
        "ControlFileFormat": dm_type.STRING | dm_type.WRITABLE,
        "Push!": {
            type: 'event',
            input: ['Data']
        }
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Name": "",
        "Controller": "",
        "NumberOfRetainedFailedReports": "0",
        "Protocol": "",
        "EncodingType": "",
        "ReportingInterval": "86400",
        "TimeReference": "0001-01-01T00:00:00Z",
        "ParameterNumberOfEntries": "0",
        "StreamingHost": "",
        "StreamingPort": "4737",
        "StreamingSessionID": "0",
        "FileTransferURL": "",
        "FileTransferUsername": "",
        "FileTransferPassword": "",
        "ControlFileFormat": ""
    },
    constraints: {
        "FileTransferPassword": { secured: true }
    }
};

// Schema for Device.BulkData.Profile.{i}.Parameter.{i}.
export const Profile_Parameter = {
    path: "Device.BulkData.Profile.{i}.Parameter.{i}.",
    schema: {
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "Exclude": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Name": "",
        "Reference": "",
        "Exclude": "false"
    }
};

// Schema for Device.BulkData.Profile.{i}.CSVEncoding.
export const Profile_CSVEncoding = {
    path: "Device.BulkData.Profile.{i}.CSVEncoding.",
    schema: {
        "FieldSeparator": dm_type.STRING | dm_type.WRITABLE,
        "RowSeparator": dm_type.STRING | dm_type.WRITABLE,
        "EscapeCharacter": dm_type.STRING | dm_type.WRITABLE,
        "ReportFormat": dm_type.STRING | dm_type.WRITABLE,
        "RowTimestamp": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "FieldSeparator": ",",
        "RowSeparator": " ",
        "EscapeCharacter": "\"",
        "ReportFormat": "ParameterPerColumn",
        "RowTimestamp": "Unix-Epoch"
    }
};

// Schema for Device.BulkData.
export const BulkData = {
    path: "Device.BulkData.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "MinReportingInterval": dm_type.UINT,
        "Protocols": dm_type.STRING,
        "EncodingTypes": dm_type.STRING,
        "ParameterWildCardSupported": dm_type.BOOL,
        "MaxNumberOfProfiles": dm_type.INT,
        "MaxNumberOfParameterReferences": dm_type.INT,
        "ProfileNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "",
        "MinReportingInterval": "0",
        "Protocols": "",
        "EncodingTypes": "",
        "ParameterWildCardSupported": "false",
        "MaxNumberOfProfiles": "0",
        "MaxNumberOfParameterReferences": "0",
        "ProfileNumberOfEntries": "0"
    }
};
