'use strict';

// Auto-generated schema definitions for PPP domain
// Generated from TR-181 specifications

// Schema for Device.PPP.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.PPP.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "UnicastPacketsSent": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "MulticastPacketsSent": dm_type.STRING,
        "UnicastPacketsReceived": dm_type.STRING,
        "MulticastPacketsReceived": dm_type.STRING,
        "BroadcastPacketsSent": dm_type.STRING,
        "BroadcastPacketsReceived": dm_type.STRING,
        "UnknownProtoPacketsReceived": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "UnicastPacketsSent": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "MulticastPacketsSent": "",
        "UnicastPacketsReceived": "",
        "MulticastPacketsReceived": "",
        "BroadcastPacketsSent": "",
        "BroadcastPacketsReceived": "",
        "UnknownProtoPacketsReceived": ""
    }
};

// Schema for Device.PPP.Interface.{i}.IPv6CP.
export const Interface_IPv6CP = {
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
export const PPP = {
    path: "Device.PPP.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT,
        "SupportedNCPs": dm_type.STRING
    },
    defaults: {
        "InterfaceNumberOfEntries": "0",
        "SupportedNCPs": ""
    }
};

// Schema for Device.PPP.Interface.{i}.IPCP.
export const Interface_IPCP = {
    path: "Device.PPP.Interface.{i}.IPCP.",
    schema: {
        "LocalIPAddress": dm_type.STRING,
        "RemoteIPAddress": dm_type.STRING,
        "DNSServers": dm_type.STRING,
        "PassthroughEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PassthroughDHCPPool": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "LocalIPAddress": "",
        "RemoteIPAddress": "",
        "DNSServers": "[]",
        "PassthroughEnable": "false",
        "PassthroughDHCPPool": ""
    }
};

// Schema for Device.PPP.Interface.{i}.PPPoE.
export const Interface_PPPoE = {
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
    }
};

// Schema for Device.PPP.Interface.{i}.
export const Interface = {
    path: "Device.PPP.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "ConnectionStatus": dm_type.STRING,
        "LastConnectionError": dm_type.STRING,
        "AutoDisconnectTime": dm_type.UINT | dm_type.WRITABLE,
        "IdleDisconnectTime": dm_type.UINT | dm_type.WRITABLE,
        "WarnDisconnectDelay": dm_type.UINT | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "EncryptionProtocol": dm_type.STRING,
        "CompressionProtocol": dm_type.STRING,
        "AuthenticationProtocol": dm_type.STRING,
        "MaxMRUSize": dm_type.UINT | dm_type.WRITABLE,
        "CurrentMRUSize": dm_type.UINT,
        "ConnectionTrigger": dm_type.STRING | dm_type.WRITABLE,
        "LCPEcho": dm_type.UINT | dm_type.WRITABLE,
        "LCPEchoRetry": dm_type.UINT | dm_type.WRITABLE,
        "LCPEchoAdaptive": dm_type.BOOL | dm_type.WRITABLE,
        "IPCPEnable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6CPEnable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "ConnectionStatus": "",
        "LastConnectionError": "",
        "AutoDisconnectTime": "0",
        "IdleDisconnectTime": "0",
        "WarnDisconnectDelay": "0",
        "Username": "",
        "Password": "",
        "EncryptionProtocol": "",
        "CompressionProtocol": "",
        "AuthenticationProtocol": "",
        "MaxMRUSize": "1500",
        "CurrentMRUSize": "0",
        "ConnectionTrigger": "",
        "LCPEcho": "0",
        "LCPEchoRetry": "0",
        "LCPEchoAdaptive": "true"
    }
};
