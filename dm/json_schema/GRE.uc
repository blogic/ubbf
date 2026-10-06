'use strict';

// Auto-generated schema definitions for GRE domain
// Generated from TR-181 specifications

// Schema for Device.GRE.
export const GRE = {
    path: "Device.GRE.",
    schema: {
        "TunnelNumberOfEntries": dm_type.UINT,
        "FilterNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "TunnelNumberOfEntries": "0",
        "FilterNumberOfEntries": "0"
    }
};

// Schema for Device.GRE.Tunnel.{i}.Interface.{i}.
export const Tunnel_Interface = {
    path: "Device.GRE.Tunnel.{i}.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "ProtocolIdOverride": dm_type.UINT | dm_type.WRITABLE,
        "UseChecksum": dm_type.BOOL | dm_type.WRITABLE,
        "KeyIdentifierGenerationPolicy": dm_type.STRING | dm_type.WRITABLE,
        "KeyIdentifier": dm_type.UINT | dm_type.WRITABLE,
        "UseSequenceNumber": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "ProtocolIdOverride": "0",
        "UseChecksum": "false",
        "KeyIdentifierGenerationPolicy": "Disabled",
        "KeyIdentifier": "0",
        "UseSequenceNumber": "false"
    }
};

// Schema for Device.GRE.Tunnel.{i}.
export const Tunnel = {
    path: "Device.GRE.Tunnel.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "RemoteEndpoints": dm_type.STRING | dm_type.WRITABLE,
        "KeepAlivePolicy": dm_type.STRING | dm_type.WRITABLE,
        "KeepAliveTimeout": dm_type.UINT | dm_type.WRITABLE,
        "KeepAliveThreshold": dm_type.UINT | dm_type.WRITABLE,
        "DeliveryHeaderProtocol": dm_type.STRING | dm_type.WRITABLE,
        "DefaultDSCPMark": dm_type.UINT | dm_type.WRITABLE,
        "ConnectedRemoteEndpoint": dm_type.STRING,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "RemoteEndpoints": "",
        "KeepAlivePolicy": "None",
        "KeepAliveTimeout": "10",
        "KeepAliveThreshold": "3",
        "DeliveryHeaderProtocol": "",
        "DefaultDSCPMark": "0",
        "ConnectedRemoteEndpoint": "",
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.GRE.Tunnel.{i}.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.GRE.Tunnel.{i}.Interface.{i}.Stats.",
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
        "UnknownProtoPacketsReceived": dm_type.STRING,
        "DiscardChecksumReceived": dm_type.STRING,
        "DiscardSequenceNumberReceived": dm_type.STRING
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
        "UnknownProtoPacketsReceived": "",
        "DiscardChecksumReceived": "",
        "DiscardSequenceNumberReceived": ""
    }
};

// Schema for Device.GRE.Filter.{i}.
export const Filter = {
    path: "Device.GRE.Filter.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        "VLANIDCheck": dm_type.INT | dm_type.WRITABLE,
        "VLANIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DSCPMarkPolicy": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Order": "",
        "Alias": "",
        "Interface": "",
        "AllInterfaces": "false",
        "VLANIDCheck": "-1",
        "VLANIDExclude": "false",
        "DSCPMarkPolicy": "0"
    }
};

// Schema for Device.GRE.Tunnel.{i}.Stats.
export const Tunnel_Stats = {
    path: "Device.GRE.Tunnel.{i}.Stats.",
    schema: {
        "KeepAliveSent": dm_type.STRING,
        "KeepAliveReceived": dm_type.STRING,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING
    },
    defaults: {
        "KeepAliveSent": "",
        "KeepAliveReceived": "",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": ""
    }
};
