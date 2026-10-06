'use strict';

// Auto-generated schema definitions for DynamicDNS domain
// Generated from TR-181 specifications

// Schema for Device.DynamicDNS.Server.{i}.
export const Server = {
    path: "Device.DynamicDNS.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "ServiceName": dm_type.STRING | dm_type.WRITABLE,
        "ServerAddress": dm_type.STRING | dm_type.WRITABLE,
        "ServerPort": dm_type.UINT | dm_type.WRITABLE,
        "SupportedProtocols": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "CheckInterval": dm_type.UINT | dm_type.WRITABLE,
        "RetryInterval": dm_type.UINT | dm_type.WRITABLE,
        "MaxRetries": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Name": "",
        "Alias": "",
        "ServiceName": "",
        "ServerAddress": "",
        "ServerPort": "0",
        "SupportedProtocols": "",
        "Protocol": "",
        "CheckInterval": "0",
        "RetryInterval": "0",
        "MaxRetries": "0"
    }
};

// Schema for Device.DynamicDNS.
export const DynamicDNS = {
    path: "Device.DynamicDNS.",
    schema: {
        "ClientNumberOfEntries": dm_type.UINT,
        "ServerNumberOfEntries": dm_type.UINT,
        "SupportedServices": dm_type.STRING
    },
    defaults: {
        "ClientNumberOfEntries": "0",
        "ServerNumberOfEntries": "0",
        "SupportedServices": ""
    }
};

// Schema for Device.DynamicDNS.Client.{i}.Hostname.{i}.
export const Client_Hostname = {
    path: "Device.DynamicDNS.Client.{i}.Hostname.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Status": "",
        "Name": ""
    }
};

// Schema for Device.DynamicDNS.Client.{i}.
export const Client = {
    path: "Device.DynamicDNS.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "LastError": dm_type.STRING,
        "Server": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "HostnameNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "LastError": "",
        "Server": "",
        "Interface": "",
        "Username": "",
        "Password": "",
        "HostnameNumberOfEntries": "0"
    }
};
