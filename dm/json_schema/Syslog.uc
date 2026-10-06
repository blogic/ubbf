'use strict';

// Auto-generated schema definitions for Syslog domain
// Generated from TR-181 specifications

// Schema for Device.Syslog.
export const Syslog = {
    path: "Device.Syslog.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "FilterNumberOfEntries": dm_type.UINT,
        "SourceNumberOfEntries": dm_type.UINT,
        "TemplateNumberOfEntries": dm_type.UINT,
        "ActionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "FilterNumberOfEntries": "0",
        "SourceNumberOfEntries": "0",
        "TemplateNumberOfEntries": "0",
        "ActionNumberOfEntries": "0"
    }
};

// Schema for Device.Syslog.Source.{i}.Network.
export const Source_Network = {
    path: "Device.Syslog.Source.{i}.Network.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE,
        "PeerVerify": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Interface": "",
        "Port": "1099",
        "Protocol": "UDP",
        "Certificate": "",
        "CABundle": "",
        "PeerVerify": "false"
    }
};

// Schema for Device.Syslog.Action.{i}.LogRemote.
export const Action_LogRemote = {
    path: "Device.Syslog.Action.{i}.LogRemote.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Address": dm_type.STRING | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE,
        "PeerVerify": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Address": "",
        "Protocol": "",
        "Port": "514",
        "Certificate": "",
        "CABundle": "",
        "PeerVerify": "false"
    }
};

// Schema for Device.Syslog.Action.{i}.
export const Action = {
    path: "Device.Syslog.Action.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "SourceRef": dm_type.STRING | dm_type.WRITABLE,
        "FilterRef": dm_type.STRING | dm_type.WRITABLE,
        "TemplateRef": dm_type.STRING | dm_type.WRITABLE,
        "StructuredData": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "SourceRef": "[]",
        "FilterRef": "[]",
        "TemplateRef": "",
        "StructuredData": "false"
    }
};

// Schema for Device.Syslog.Template.{i}.
export const Template = {
    path: "Device.Syslog.Template.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Expression": dm_type.STRING | dm_type.WRITABLE,
        "EscapeMessage": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Expression": "",
        "EscapeMessage": "false"
    }
};

// Schema for Device.Syslog.Action.{i}.LogFile.
export const Action_LogFile = {
    path: "Device.Syslog.Action.{i}.LogFile.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "VendorLogFileRef": dm_type.STRING,
        "FilePath": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "VendorLogFileRef": "",
        "FilePath": ""
    }
};

// Schema for Device.Syslog.Filter.{i}.
export const Filter = {
    path: "Device.Syslog.Filter.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "FacilityLevel": dm_type.STRING | dm_type.WRITABLE,
        "Severity": dm_type.STRING | dm_type.WRITABLE,
        "SeverityCompare": dm_type.STRING | dm_type.WRITABLE,
        "SeverityCompareAction": dm_type.STRING | dm_type.WRITABLE,
        "PatternMatch": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "FacilityLevel": "[All]",
        "Severity": "All",
        "SeverityCompare": "EqualOrHigher",
        "SeverityCompareAction": "Log",
        "PatternMatch": ""
    }
};

// Schema for Device.Syslog.Source.{i}.
export const Source = {
    path: "Device.Syslog.Source.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "KernelMessages": dm_type.BOOL | dm_type.WRITABLE,
        "SystemMessages": dm_type.BOOL | dm_type.WRITABLE,
        "Severity": dm_type.STRING | dm_type.WRITABLE,
        "FacilityLevel": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "KernelMessages": "true",
        "SystemMessages": "true",
        "Severity": "All",
        "FacilityLevel": "All"
    }
};
