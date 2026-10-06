'use strict';

// Auto-generated schema definitions for STOMP domain
// Generated from TR-181 specifications

// Schema for Device.STOMP.Connection.{i}.
export const Connection = {
    path: "Device.STOMP.Connection.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "LastChangeDate": dm_type.DATETIME,
        "Host": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "VirtualHost": dm_type.STRING | dm_type.WRITABLE,
        "EnableHeartbeats": dm_type.BOOL | dm_type.WRITABLE,
        "OutgoingHeartbeat": dm_type.UINT | dm_type.WRITABLE,
        "IncomingHeartbeat": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryInitialInterval": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryMaxInterval": dm_type.UINT | dm_type.WRITABLE,
        "IsEncrypted": dm_type.BOOL,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Status": "",
        "Host": "",
        "Port": "61613",
        "Username": "",
        "Password": "",
        "VirtualHost": "",
        "EnableHeartbeats": "false",
        "OutgoingHeartbeat": "0",
        "IncomingHeartbeat": "0",
        "ServerRetryInitialInterval": "60",
        "ServerRetryIntervalMultiplier": "2000",
        "ServerRetryMaxInterval": "30720",
        "EnableEncryption": "true"
    }
};

// Schema for Device.STOMP.
export const STOMP = {
    path: "Device.STOMP.",
    schema: {
        "ConnectionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ConnectionNumberOfEntries": "0"
    }
};
