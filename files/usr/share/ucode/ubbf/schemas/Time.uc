'use strict';

// Auto-generated schema definitions for Time domain
// Generated from TR-181 specifications

// Schema for Device.Time.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.Time.Client.{i}.Stats.",
    schema: {
	"PacketsSent": dm_type.UINT,
	"PacketsSentFailed": dm_type.UINT,
	"PacketsReceived": dm_type.UINT,
	"PacketsDropped": dm_type.UINT
    },
    defaults: {
	"PacketsSent": "4294967295",
	"PacketsSentFailed": "4294967295",
	"PacketsReceived": "4294967295",
	"PacketsDropped": "4294967295"
    }
};

// Schema for Device.Time.Server.{i}.Stats.
export const Server_Stats = {
    path: "Device.Time.Server.{i}.Stats.",
    schema: {
	"PacketsSent": dm_type.UINT,
	"PacketsSentFailed": dm_type.UINT,
	"PacketsReceived": dm_type.UINT,
	"PacketsDropped": dm_type.UINT
    },
    defaults: {
	"PacketsSent": "4294967295",
	"PacketsSentFailed": "4294967295",
	"PacketsReceived": "4294967295",
	"PacketsDropped": "4294967295"
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
    },
    constraints: {
        "NTSPort": { min: 1, max: 65535 }
    }
};

// Schema for Device.Time.Client.{i}.
export const Client = {
    path: "Device.Time.Client.{i}.",
    schema: {
	"Enable": dm_type.BOOL | dm_type.WRITABLE,
	"Status": dm_type.STRING,
	"Alias": dm_type.STRING,
//	"Mode": dm_type.STRING | dm_type.WRITABLE,
//	"Port": dm_type.UINT | dm_type.WRITABLE,
//	"IPVersion": dm_type.INT | dm_type.WRITABLE,
//	"ServerInUse": dm_type.STRING,
//	"Version": dm_type.UINT | dm_type.WRITABLE,
	"Servers": dm_type.STRING | dm_type.WRITABLE,
//	"ResolveAddresses": dm_type.BOOL | dm_type.WRITABLE,
//	"ResolveMaxAddresses": dm_type.UINT | dm_type.WRITABLE,
//	"Peer": dm_type.BOOL | dm_type.WRITABLE,
//	"MinPoll": dm_type.UINT | dm_type.WRITABLE,
//	"MaxPoll": dm_type.UINT | dm_type.WRITABLE,
//	"IBurst": dm_type.BOOL | dm_type.WRITABLE,
//	"Burst": dm_type.UINT | dm_type.WRITABLE,
//	"Interface": dm_type.STRING | dm_type.WRITABLE,
//	"BindType": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
	"Status": "",
	"Alias": "",
	"Servers": ""
    },
    constraints: {
        "Servers": { list: true }
    }
};

// Schema for Device.Time.
export const Time = {
    path: "Device.Time.",
    schema: {
	"Enable": dm_type.BOOL | dm_type.WRITABLE,
	"Status": dm_type.STRING,
	"CurrentLocalTime": dm_type.DATETIME,
	"LocalTimeZone": dm_type.STRING | dm_type.WRITABLE,
	"ClientNumberOfEntries": dm_type.UINT,
	"ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
	"Status": "",
	"LocalTimeZone": "",
	"ClientNumberOfEntries": "0",
	"ServerNumberOfEntries": "0"
    },
    constraints: {
        "LocalTimeZone": { max_length: 256 }
    }
};

// Schema for Device.Time.Server.{i}.
export const Server = {
    path: "Device.Time.Server.{i}.",
    schema: {
	"Enable": dm_type.BOOL | dm_type.WRITABLE,
	"Status": dm_type.STRING,
	"Alias": dm_type.STRING,
//	"Mode": dm_type.STRING | dm_type.WRITABLE,
//	"Version": dm_type.UINT | dm_type.WRITABLE,
//	"Port": dm_type.UINT | dm_type.WRITABLE,
	"Interface": dm_type.STRING | dm_type.WRITABLE,
//	"BindType": dm_type.STRING | dm_type.WRITABLE,
//	"MinPoll": dm_type.UINT | dm_type.WRITABLE,
//	"MaxPoll": dm_type.UINT | dm_type.WRITABLE,
//	"TTL": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
	"Status": "",
	"Alias": "",
	"Interface": ""
    },
    constraints: {
        "Interface": { max_length: 256 }
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
	"NTSNTPServer": ""
    },
    constraints: {
        "NTSNTPServer": { list: true }
    }
};
