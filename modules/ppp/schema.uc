'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.PPP.Interface.{i}.Stats.
schemas.Interface_Stats = {
    path: "Device.PPP.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.ULONG,
        "BytesReceived": dm_type.ULONG,
        "PacketsSent": dm_type.ULONG,
        "PacketsReceived": dm_type.ULONG,
        "ErrorsSent": dm_type.UINT,
        "ErrorsReceived": dm_type.UINT,
        "UnicastPacketsSent": dm_type.ULONG,
        "DiscardPacketsSent": dm_type.UINT,
        "DiscardPacketsReceived": dm_type.UINT,
        "MulticastPacketsSent": dm_type.ULONG,
        "UnicastPacketsReceived": dm_type.ULONG,
        "MulticastPacketsReceived": dm_type.ULONG,
        "BroadcastPacketsSent": dm_type.ULONG,
        "BroadcastPacketsReceived": dm_type.ULONG,
        "UnknownProtoPacketsReceived": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "BytesSent": "18446744073709551615",
        "BytesReceived": "18446744073709551615",
        "PacketsSent": "18446744073709551615",
        "PacketsReceived": "18446744073709551615",
        "ErrorsSent": "4294967295",
        "ErrorsReceived": "4294967295",
        "UnicastPacketsSent": "18446744073709551615",
        "DiscardPacketsSent": "4294967295",
        "DiscardPacketsReceived": "4294967295",
        "MulticastPacketsSent": "18446744073709551615",
        "UnicastPacketsReceived": "18446744073709551615",
        "MulticastPacketsReceived": "18446744073709551615",
        "BroadcastPacketsSent": "18446744073709551615",
        "BroadcastPacketsReceived": "18446744073709551615",
        "UnknownProtoPacketsReceived": "4294967295"
    }
};

// Schema for Device.PPP.Interface.{i}.IPv6CP.
schemas.Interface_IPv6CP = {
    path: "Device.PPP.Interface.{i}.IPv6CP.",
    schema: {
        "LocalInterfaceIdentifier": dm_type.STRING,
        "RemoteInterfaceIdentifier": dm_type.STRING
    },
    defaults: {
        "LocalInterfaceIdentifier": "",
        "RemoteInterfaceIdentifier": ""
    }
};

// Schema for Device.PPP.
schemas.PPP = {
    path: "Device.PPP.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT,
        "SupportedNCPs": dm_type.STRING
    },
    defaults: {
        "InterfaceNumberOfEntries": "0",
        "SupportedNCPs": "IPCP,IPv6CP"
    }
};

// Schema for Device.PPP.Interface.{i}.IPCP.
schemas.Interface_IPCP = {
    path: "Device.PPP.Interface.{i}.IPCP.",
    schema: {
        "LocalIPAddress": dm_type.STRING,
        "RemoteIPAddress": dm_type.STRING,
        "DNSServers": dm_type.STRING
        // "PassthroughEnable": dm_type.BOOL | dm_type.WRITABLE,
        // "PassthroughDHCPPool": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "LocalIPAddress": "",
        "RemoteIPAddress": "",
        "DNSServers": ""
    }
};

// Schema for Device.PPP.Interface.{i}.PPPoE.
schemas.Interface_PPPoE = {
    path: "Device.PPP.Interface.{i}.PPPoE.",
    schema: {
        "SessionID": dm_type.UINT,
        "ACName": dm_type.STRING | dm_type.WRITABLE,
        "ServiceName": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "SessionID": "0",
        "ACName": "",
        "ServiceName": ""
    },
    constraints: {
        "ACName": { max_length: 256 },
        "ServiceName": { max_length: 256 }
    }
};

// Schema for Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.
// LANInterface holds an explicit TR-181 reference to the one LAN port that
// relays PPPoE discovery/session frames: Device.Ethernet.Interface.{i} or
// a port of a bridge that is not its management port. Empty or
// unresolvable -> no daemon runs, no passthrough traffic.
schemas.Interface_PPPoE_X_UBBF_Passthrough = {
    path: "Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MaxSessions": dm_type.UINT | dm_type.WRITABLE,
        "LANInterface": dm_type.STRING | dm_type.WRITABLE,
        "SessionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "MaxSessions": "16",
        "LANInterface": "",
        "SessionNumberOfEntries": "0"
    }
};

// Schema for Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.Session.{i}.
schemas.Interface_PPPoE_X_UBBF_Passthrough_Session = {
    path: "Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.Session.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "ClientMACAddress": dm_type.STRING,
        "SessionID": dm_type.UINT,
        "StartTime": dm_type.DATETIME,
        "LastActivityTime": dm_type.DATETIME
    },
    defaults: {
        "Alias": "",
        "ClientMACAddress": "",
        "SessionID": "0",
        "StartTime": "0001-01-01T00:00:00Z",
        "LastActivityTime": "0001-01-01T00:00:00Z"
    }
};

// Schema for Device.PPP.Interface.{i}.
schemas.Interface = {
    path: "Device.PPP.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "ConnectionStatus": dm_type.STRING,
        "LastConnectionError": dm_type.STRING,
        "AutoDisconnectTime": dm_type.UINT | dm_type.WRITABLE,
        "IdleDisconnectTime": dm_type.UINT | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        // "EncryptionProtocol": dm_type.STRING,
        // "CompressionProtocol": dm_type.STRING,
        // "AuthenticationProtocol": dm_type.STRING,
        "MaxMRUSize": dm_type.UINT | dm_type.WRITABLE,
        "CurrentMRUSize": dm_type.UINT,
        "ConnectionTrigger": dm_type.STRING | dm_type.WRITABLE,
        "LCPEcho": dm_type.UINT | dm_type.WRITABLE,
        "LCPEchoRetry": dm_type.UINT | dm_type.WRITABLE,
        "LCPEchoAdaptive": dm_type.BOOL | dm_type.WRITABLE,
        "IPCPEnable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6CPEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "Description": "",
        "LastChange": "0",
        "LowerLayers": "",
        "ConnectionStatus": "",
        "LastConnectionError": "",
        "AutoDisconnectTime": "0",
        "IdleDisconnectTime": "0",
        "Username": "",
        "Password": "",
        "MaxMRUSize": "1492",
        "CurrentMRUSize": "0",
        "ConnectionTrigger": "",
        "LCPEcho": "1",
        "LCPEchoRetry": "5",
        "LCPEchoAdaptive": "true",
        "IPCPEnable": "true",
        "IPv6CPEnable": "true"
    },
    since: {
        "Description": "2.21"
    },
    constraints: {
        "Description": { max_length: 256 },
        "LowerLayers": { list: true, list_max_length: 1024 },
        "Username": { max_length: 64 },
        "Password": { secured: true, max_length: 64 },
        "MaxMRUSize": { min: 64, max: 65535 },
        "ConnectionTrigger": { enum: [ "OnDemand", "AlwaysOn", "Manual" ] }
    }
};
