'use strict';

// Auto-generated schema definitions for Time domain
// Generated from TR-181 specifications

// Schema for Device.Time.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.Time.Client.{i}.Stats.",
    schema: {
        "PacketsSent": dm_type.STRING,
        "PacketsSentFailed": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "PacketsDropped": dm_type.STRING
    },
    defaults: {
        "PacketsSent": "",
        "PacketsSentFailed": "",
        "PacketsReceived": "",
        "PacketsDropped": ""
    }
};

// Schema for Device.Time.Server.{i}.Stats.
export const Server_Stats = {
    path: "Device.Time.Server.{i}.Stats.",
    schema: {
        "PacketsSent": dm_type.STRING,
        "PacketsSentFailed": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "PacketsDropped": dm_type.STRING
    },
    defaults: {
        "PacketsSent": "",
        "PacketsSentFailed": "",
        "PacketsReceived": "",
        "PacketsDropped": ""
    }
};

// Schema for Device.Time.Client.{i}.Authentication.
export const Client_Authentication = {
    path: "Device.Time.Client.{i}.Authentication.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "NTSPort": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Certificate": "",
        "NTSPort": "4460"
    }
};

// Schema for Device.Time.Client.{i}.
export const Client = {
    path: "Device.Time.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Mode": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "ServerInUse": dm_type.STRING,
        "Version": dm_type.UINT | dm_type.WRITABLE,
        "Servers": dm_type.STRING | dm_type.WRITABLE,
        "ResolveAddresses": dm_type.BOOL | dm_type.WRITABLE,
        "ResolveMaxAddresses": dm_type.UINT | dm_type.WRITABLE,
        "Peer": dm_type.BOOL | dm_type.WRITABLE,
        "MinPoll": dm_type.UINT | dm_type.WRITABLE,
        "MaxPoll": dm_type.UINT | dm_type.WRITABLE,
        "IBurst": dm_type.BOOL | dm_type.WRITABLE,
        "Burst": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "BindType": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Mode": "",
        "Port": "123",
        "IPVersion": "-1",
        "ServerInUse": "",
        "Version": "4",
        "Servers": "[]",
        "ResolveAddresses": "false",
        "ResolveMaxAddresses": "6",
        "MinPoll": "6",
        "MaxPoll": "10",
        "Burst": "8",
        "Interface": "",
        "BindType": ""
    }
};

// Schema for Device.Time.
export const Time = {
    path: "Device.Time.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "NTPServer1": dm_type.STRING | dm_type.WRITABLE,
        "NTPServer2": dm_type.STRING | dm_type.WRITABLE,
        "NTPServer3": dm_type.STRING | dm_type.WRITABLE,
        // "NTPServer4": dm_type.STRING | dm_type.WRITABLE,
        // "NTPServer5": dm_type.STRING | dm_type.WRITABLE,
        "CurrentLocalTime": dm_type.DATETIME,
        "LocalTimeZone": dm_type.STRING | dm_type.WRITABLE,
        // "ClientNumberOfEntries": dm_type.UINT,
        // "ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "NTPServer1": "",
        "NTPServer2": "",
        "NTPServer3": "",
        "NTPServer4": "",
        "NTPServer5": "",
        "LocalTimeZone": "",
        "ClientNumberOfEntries": "0",
        "ServerNumberOfEntries": "0"
    }
};

// Schema for Device.Time.Server.{i}.
export const Server = {
    path: "Device.Time.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Mode": dm_type.STRING | dm_type.WRITABLE,
        "Version": dm_type.UINT | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "BindType": dm_type.STRING | dm_type.WRITABLE,
        "MinPoll": dm_type.UINT | dm_type.WRITABLE,
        "MaxPoll": dm_type.UINT | dm_type.WRITABLE,
        "TTL": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Mode": "",
        "Version": "4",
        "Port": "123",
        "Interface": "",
        "BindType": "",
        "MinPoll": "6",
        "MaxPoll": "10",
        "TTL": "255"
    }
};

// Schema for Device.Time.Server.{i}.Authentication.
export const Server_Authentication = {
    path: "Device.Time.Server.{i}.Authentication.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "NTSNTPServer": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Certificate": "",
        "NTSNTPServer": "[]"
    }
};
