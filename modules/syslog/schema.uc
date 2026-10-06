'use strict';

// Auto-generated schema definitions for Syslog domain
// Generated from TR-181 specifications

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.Syslog.
schemas.Syslog = {
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

// Schema for Device.Syslog.Source.{i}.UnixDomainSocket.
schemas.Source_UnixDomainSocket = {
    path: "Device.Syslog.Source.{i}.UnixDomainSocket.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Path": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Path": ""
    },
    constraints: {
        "Path": { max_length: 2048 }
    }
};

// Schema for Device.Syslog.Source.{i}.Network.
schemas.Source_Network = {
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
    },
    constraints: {
        "Interface": { max_length: 256 },
        "Port": { min: 1, max: 65535 },
        "Protocol": { enum: [ "TCP", "UDP", "TLS" ] }
    }
};

// Schema for Device.Syslog.Action.{i}.LogRemote.
schemas.Action_LogRemote = {
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
        "Protocol": "UDP",
        "Port": "514",
        "Certificate": "",
        "CABundle": "",
        "PeerVerify": "false"
    },
    constraints: {
        "Protocol": { enum: [ "TCP", "UDP", "TLS" ] },
        "Port": { min: 1, max: 65535 }
    }
};

// Schema for Device.Syslog.Action.{i}.
schemas.Action = {
    path: "Device.Syslog.Action.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "SourceRef": dm_type.STRING | dm_type.WRITABLE,
        "FilterRef": dm_type.STRING | dm_type.WRITABLE,
        "TemplateRef": dm_type.STRING | dm_type.WRITABLE,
        "StructuredData": dm_type.BOOL | dm_type.WRITABLE,
        "LogEvent!": {
            type: 'event',
            input: [ 'LogLine' ]
        }
    },
    defaults: {
        "Alias": "",
        "SourceRef": "",
        "FilterRef": "",
        "TemplateRef": "",
        "StructuredData": "false"
    },
    constraints: {
        "SourceRef": { list: true, max_length: 256 },
        "FilterRef": { list: true, max_length: 256 },
        "TemplateRef": { max_length: 256 }
    }
};

// Schema for Device.Syslog.Template.{i}.
schemas.Template = {
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
schemas.Action_LogFile = {
    path: "Device.Syslog.Action.{i}.LogFile.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "VendorLogFileRef": dm_type.STRING,
        "FilePath": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "VendorLogFileRef": "",
        "FilePath": ""
    },
    constraints: {
        "FilePath": { max_length: 2048 }
    }
};

// Schema for Device.Syslog.Filter.{i}.
schemas.Filter = {
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
        "FacilityLevel": "All",
        "Severity": "All",
        "SeverityCompare": "EqualOrHigher",
        "SeverityCompareAction": "Log",
        "PatternMatch": ""
    },
    constraints: {
        "FacilityLevel": { list: true, enum: [ "Kern", "User", "Mail", "Daemon", "Auth", "Syslog", "LPR", "News", "UUCP", "Cron", "AuthPriv", "FTP", "NTP", "Audit", "Console", "Cron2", "Local0", "Local1", "Local2", "Local3", "Local4", "Local5", "Local6", "Local7", "All" ] },
        "Severity": { enum: [ "Emergency", "Alert", "Critical", "Error", "Warning", "Notice", "Info", "Debug", "All", "None" ] },
        "SeverityCompare": { enum: [ "Equal", "EqualOrHigher" ] },
        "SeverityCompareAction": { enum: [ "Log", "Block", "Stop" ] }
    }
};

// Schema for Device.Syslog.Source.{i}.
schemas.Source = {
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
    },
    constraints: {
        "Severity": { enum: [ "Emergency", "Alert", "Critical", "Error", "Warning", "Notice", "Info", "Debug", "All", "None" ] },
        "FacilityLevel": { enum: [ "Kern", "User", "Mail", "Daemon", "Auth", "Syslog", "LPR", "News", "UUCP", "Cron", "AuthPriv", "FTP", "NTP", "Audit", "Console", "Cron2", "Local0", "Local1", "Local2", "Local3", "Local4", "Local5", "Local6", "Local7", "All" ] }
    }
};
