'use strict';

// Auto-generated schema definitions for BulkData domain
// Generated from TR-181 specifications
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}.
schemas.HTTP_RequestURIParameter = {
    path: "Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}.",
    schema: {
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Reference": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Name": "",
        "Reference": ""
    },
    constraints: {
        "Name": { max_length: 64 },
        "Reference": { max_length: 256 }
    }
};

// Schema for Device.BulkData.Profile.{i}.JSONEncoding.
schemas.Profile_JSONEncoding = {
    path: "Device.BulkData.Profile.{i}.JSONEncoding.",
    schema: {
        "ReportFormat": dm_type.STRING | dm_type.WRITABLE,
        "ReportTimestamp": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ReportFormat": "ObjectHierarchy",
        "ReportTimestamp": "Unix-Epoch"
    },
    constraints: {
        "ReportFormat": { enum: [ "ObjectHierarchy", "NameValuePair" ] },
        "ReportTimestamp": { enum: [ "Unix-Epoch", "ISO-8601", "None" ] }
    }
};

// Schema for Device.BulkData.Profile.{i}.MQTT.
schemas.Profile_MQTT = {
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
    },
    constraints: {
        "PublishTopic": { max_length: 65535 },
        "PublishQoS": { min: 0, max: 2 }
    }
};

// Schema for Device.BulkData.Profile.{i}.HTTP.
schemas.Profile_HTTP = {
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
        "URL": { max_length: 2048 },
        "Username": { max_length: 256 },
        "Password": { secured: true, max_length: 256 },
        "RetryMinimumWaitInterval": { min: 1, max: 65535 },
        "RetryIntervalMultiplier": { min: 1000, max: 65535 }
    }
};

// Schema for Device.BulkData.Profile.{i}.
schemas.Profile = {
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
        "ParameterNumberOfEntries": "0"
    },
    constraints: {
        "Name": { max_length: 255 },
        "NumberOfRetainedFailedReports": { min: -1 },
        "ReportingInterval": { min: 1 }
    }
};

// Schema for Device.BulkData.Profile.{i}.Parameter.{i}.
schemas.Profile_Parameter = {
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
    },
    constraints: {
        "Name": { max_length: 64 },
        "Reference": { max_length: 256 }
    }
};

// Schema for Device.BulkData.Profile.{i}.CSVEncoding.
schemas.Profile_CSVEncoding = {
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
        "RowSeparator": "\n",
        "EscapeCharacter": "\"",
        "ReportFormat": "ParameterPerColumn",
        "RowTimestamp": "Unix-Epoch"
    },
    constraints: {
        "ReportFormat": { enum: [ "ParameterPerRow", "ParameterPerColumn" ] },
        "RowTimestamp": { enum: [ "Unix-Epoch", "ISO-8601", "None" ] }
    }
};

// Schema for Device.BulkData.
schemas.BulkData = {
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
