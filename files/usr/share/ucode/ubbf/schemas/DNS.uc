'use strict';

// Auto-generated schema definitions for DNS domain
// Generated from TR-181 specifications

// Schema for Device.DNS.Zone.{i}.
export const Zone = {
    path: "Device.DNS.Zone.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "HostNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Origin": "System",
        "Interface": "",
        "HostNumberOfEntries": "0"
    },
    constraints: {
        "Name": { max_length: 128 },
        "Interface": { max_length: 256 }
    }
};

// Schema for Device.DNS.Relay.
export const Relay = {
    path: "Device.DNS.Relay.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ConfigNumberOfEntries": dm_type.UINT,
        "ForwardNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ConfigNumberOfEntries": "0",
        "ForwardNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.RebindProtection.
// IPExceptions is not modelled: dnsmasq exempts only domains and all of
// 127.0.0.0/8 from rebind protection, never a given address or prefix.
export const RebindProtection = {
    path: "Device.DNS.RebindProtection.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "DomainExceptions": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "DomainExceptions": ""
    },
    constraints: {
        "DomainExceptions": { list: true }
    }
};

// Schema for Device.DNS.Client.Server.{i}.
export const Client_Server = {
    path: "Device.DNS.Client.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "DNSServer": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "DNSServer": "",
        "Interface": "",
        "Type": "Static"
    },
    constraints: {
        "DNSServer": { max_length: 45 },
        "Interface": { max_length: 256 }
    }
};

// Schema for Device.DNS.Client.
export const Client = {
    path: "Device.DNS.Client.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ServerNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Relay.Config.{i}.
export const Relay_Config = {
    path: "Device.DNS.Relay.Config.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Forwarders": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "CacheSize": dm_type.UINT,
        "CacheMinTTL": dm_type.UINT,
        "CacheMaxTTL": dm_type.UINT,
        "X_UBBF_CacheEntries": dm_type.UINT | dm_type.WRITABLE,
        "X_UBBF_CacheMinTTL": dm_type.UINT | dm_type.WRITABLE,
        "X_UBBF_CacheMaxTTL": dm_type.UINT | dm_type.WRITABLE,
        "FlushCache()": { type: 'sync', input: [] }
    },
    defaults: {
        "Alias": "",
        "Forwarders": "",
        "Interface": "",
        "CacheSize": "0",
        "CacheMinTTL": "0",
        "CacheMaxTTL": "86400",
        "X_UBBF_CacheEntries": "150",
        "X_UBBF_CacheMinTTL": "0",
        "X_UBBF_CacheMaxTTL": "86400"
    },
    constraints: {
        "Forwarders": { list: true, max_length: 256 },
        "Interface": { max_length: 256 }
    }
};

// Schema for Device.DNS.
export const DNS = {
    path: "Device.DNS.",
    schema: {
        "SupportedRecordTypes": dm_type.STRING,
        "ZoneNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupportedRecordTypes": "",
        "ZoneNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Relay.Forwarding.{i}.
export const Relay_Forwarding = {
    path: "Device.DNS.Relay.Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "DNSServer": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "DNSServer": "",
        "Interface": "",
        "Type": "Static"
    },
    constraints: {
        "DNSServer": { max_length: 45 },
        "Interface": { max_length: 256 }
    }
};

// Schema for Device.DNS.Zone.{i}.Host.{i}.
export const Zone_Host = {
    path: "Device.DNS.Zone.{i}.Host.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Host": dm_type.STRING | dm_type.WRITABLE,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Origin": "System",
        "Host": ""
    },
    constraints: {
        "Name": { list: true, max_length: 128 },
        "Host": { max_length: 256 }
    }
};

// Schema for Device.DNS.Diagnostics.
export const Diagnostics = {
    path: "Device.DNS.Diagnostics.",
    schema: {
        'NSLookupDiagnostics()': {
            type: 'async',
            input: [
                'HostName',
                'DNSServer',
                'Interface',
                'NumberOfRepetitions',
                'Timeout'
            ],
            output: [
                'Status',
                'SuccessCount',
                'Result.{i}.Status',
                'Result.{i}.AnswerType',
                'Result.{i}.HostNameReturned',
                'Result.{i}.IPAddresses',
                'Result.{i}.DNSServerIP',
                'Result.{i}.ResponseTime'
            ]
        }
    },
    defaults: {}
};

// Schema for Device.DNS.Diagnostics.NSLookupDiagnostics.
export const NSLookupDiagnostics = {
    path: "Device.DNS.Diagnostics.NSLookupDiagnostics.",
    schema: {
        "DiagnosticsState": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "HostName": dm_type.STRING | dm_type.WRITABLE,
        "DNSServer": dm_type.STRING | dm_type.WRITABLE,
        "NumberOfRepetitions": dm_type.UINT | dm_type.WRITABLE,
        "Timeout": dm_type.UINT | dm_type.WRITABLE,
        "SuccessCount": dm_type.UINT,
        "ResultNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DiagnosticsState": "None",
        "Interface": "",
        "HostName": "",
        "DNSServer": "",
        "NumberOfRepetitions": "1",
        "Timeout": "5000",
        "SuccessCount": "0",
        "ResultNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Diagnostics.NSLookupDiagnostics.Result.{i}.
export const NSLookupResult = {
    path: "Device.DNS.Diagnostics.NSLookupDiagnostics.Result.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "AnswerType": dm_type.STRING,
        "HostNameReturned": dm_type.STRING,
        "IPAddresses": dm_type.STRING,
        "DNSServerIP": dm_type.STRING,
        "ResponseTime": dm_type.UINT
    },
    defaults: {}
};
