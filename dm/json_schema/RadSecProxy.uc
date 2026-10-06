'use strict';

// Auto-generated schema definitions for RadSecProxy domain
// Generated from TR-181 specifications

// Schema for Device.RadSecProxy.Server.{i}.
export const Server = {
    path: "Device.RadSecProxy.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Address": dm_type.STRING | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Secret": dm_type.STRING | dm_type.WRITABLE,
        "TLS": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Address": "",
        "Protocol": "",
        "Port": "0",
        "Secret": "",
        "TLS": ""
    }
};

// Schema for Device.RadSecProxy.Client.{i}.
export const Client = {
    path: "Device.RadSecProxy.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Address": dm_type.STRING | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Secret": dm_type.STRING | dm_type.WRITABLE,
        "TLS": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Address": "",
        "Protocol": "",
        "Secret": "",
        "TLS": ""
    }
};

// Schema for Device.RadSecProxy.TLS.{i}.
export const TLS = {
    path: "Device.RadSecProxy.TLS.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE,
        "TLSVersion": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Certificate": "",
        "CABundle": "",
        "TLSVersion": ""
    }
};

// Schema for Device.RadSecProxy.Realm.{i}.
export const Realm = {
    path: "Device.RadSecProxy.Realm.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Pattern": dm_type.STRING | dm_type.WRITABLE,
        "Server": dm_type.STRING | dm_type.WRITABLE,
        "AccountingServer": dm_type.STRING | dm_type.WRITABLE,
        "AccountingResponse": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Pattern": "",
        "Server": "",
        "AccountingServer": "",
        "AccountingResponse": "false"
    }
};

// Schema for Device.RadSecProxy.
export const RadSecProxy = {
    path: "Device.RadSecProxy.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ListenConfigNumberOfEntries": dm_type.UINT,
        "SourceConfigNumberOfEntries": dm_type.UINT,
        "ClientNumberOfEntries": dm_type.UINT,
        "RealmNumberOfEntries": dm_type.UINT,
        "ServerNumberOfEntries": dm_type.UINT,
        "TLSNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ListenConfigNumberOfEntries": "0",
        "SourceConfigNumberOfEntries": "0",
        "ClientNumberOfEntries": "0",
        "RealmNumberOfEntries": "0",
        "ServerNumberOfEntries": "0",
        "TLSNumberOfEntries": "0"
    }
};

// Schema for Device.RadSecProxy.ListenConfig.{i}.
export const ListenConfig = {
    path: "Device.RadSecProxy.ListenConfig.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Protocol": "",
        "Interface": "",
        "Port": "0"
    }
};

// Schema for Device.RadSecProxy.SourceConfig.{i}.
export const SourceConfig = {
    path: "Device.RadSecProxy.SourceConfig.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Protocol": "",
        "Interface": "",
        "Port": "0"
    }
};
