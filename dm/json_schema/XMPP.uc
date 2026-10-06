'use strict';

// Auto-generated schema definitions for XMPP domain
// Generated from TR-181 specifications

// Schema for Device.XMPP.Connection.{i}.Server.{i}.
export const Connection_Server = {
    path: "Device.XMPP.Connection.{i}.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Priority": dm_type.UINT | dm_type.WRITABLE,
        "Weight": dm_type.LONG | dm_type.WRITABLE,
        "ServerAddress": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Priority": "0",
        "Weight": "0",
        "ServerAddress": "",
        "Port": "5222"
    }
};

// Schema for Device.XMPP.
export const XMPP = {
    path: "Device.XMPP.",
    schema: {
        "ConnectionNumberOfEntries": dm_type.UINT,
        "SupportedServerConnectAlgorithms": dm_type.STRING
    },
    defaults: {
        "ConnectionNumberOfEntries": "0",
        "SupportedServerConnectAlgorithms": ""
    }
};

// Schema for Device.XMPP.Connection.{i}.Stats.
export const Connection_Stats = {
    path: "Device.XMPP.Connection.{i}.Stats.",
    schema: {
        "ReceivedMessages": dm_type.UINT,
        "TransmittedMessages": dm_type.UINT,
        "ReceivedErrorMessages": dm_type.UINT,
        "TransmittedErrorMessages": dm_type.UINT
    },
    defaults: {
        "ReceivedMessages": "0",
        "TransmittedMessages": "0",
        "ReceivedErrorMessages": "0",
        "TransmittedErrorMessages": "0"
    }
};

// Schema for Device.XMPP.Connection.{i}.
export const Connection = {
    path: "Device.XMPP.Connection.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "Domain": dm_type.STRING | dm_type.WRITABLE,
        "Resource": dm_type.STRING | dm_type.WRITABLE,
        "JabberID": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastChangeDate": dm_type.DATETIME,
        "ServerConnectAlgorithm": dm_type.STRING | dm_type.WRITABLE,
        "KeepAliveInterval": dm_type.LONG | dm_type.WRITABLE,
        "ServerConnectAttempts": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryInitialInterval": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "ServerRetryMaxInterval": dm_type.UINT | dm_type.WRITABLE,
        "UseTLS": dm_type.BOOL | dm_type.WRITABLE,
        "TLSEstablished": dm_type.BOOL,
        "ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Username": "",
        "Password": "",
        "Domain": "",
        "Resource": "",
        "JabberID": "",
        "Status": "",
        "ServerConnectAlgorithm": "DNS-SRV",
        "KeepAliveInterval": "-1",
        "ServerConnectAttempts": "16",
        "ServerRetryInitialInterval": "60",
        "ServerRetryIntervalMultiplier": "2000",
        "ServerRetryMaxInterval": "30720",
        "UseTLS": "false",
        "ServerNumberOfEntries": "0"
    }
};
