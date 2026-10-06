'use strict';

// Auto-generated schema definitions for IP domain
// Generated from TR-181 specifications

// Schema for Device.IP.Diagnostics.IPLayerCapacityAuthCode.{i}.
export const Diagnostics_IPLayerCapacityAuthCode = {
    path: "Device.IP.Diagnostics.IPLayerCapacityAuthCode.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "AuthenticationKey": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "AuthenticationKey": ""
    },
    constraints: {
        "AuthenticationKey": { secured: true }
    }
};

// Schema for Device.IP.Diagnostics.UDPEchoConfig.
export const Diagnostics_UDPEchoConfig = {
    path: "Device.IP.Diagnostics.UDPEchoConfig.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "SourceIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "UDPPort": dm_type.UINT | dm_type.WRITABLE,
        "EchoPlusEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "EchoPlusSupported": dm_type.BOOL,
        "PacketsReceived": dm_type.UINT,
        "PacketsResponded": dm_type.UINT,
        "BytesReceived": dm_type.UINT,
        "BytesResponded": dm_type.UINT,
        "TimeFirstPacketReceived": dm_type.DATETIME,
        "TimeLastPacketReceived": dm_type.DATETIME
    },
    defaults: {
        "Interface": "",
        "SourceIPAddress": "",
        "UDPPort": "0",
        "PacketsReceived": "0",
        "PacketsResponded": "0",
        "BytesReceived": "0",
        "BytesResponded": "0"
    }
};

// Schema for Device.IP.Interface.{i}.IPv4Address.{i}.
export const Interface_IPv4Address = {
    path: "Device.IP.Interface.{i}.IPv4Address.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "IPAddress": dm_type.STRING | dm_type.WRITABLE,
        "SubnetMask": dm_type.STRING | dm_type.WRITABLE,
        "AddressingType": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "IPAddress": "",
        "SubnetMask": "",
        "AddressingType": "Static"
    }
};

// Schema for Device.IP.ActivePort.{i}.
export const ActivePort = {
    path: "Device.IP.ActivePort.{i}.",
    schema: {
        "LocalIPAddress": dm_type.STRING,
        "LocalPort": dm_type.UINT,
        "RemoteIPAddress": dm_type.STRING,
        "RemotePort": dm_type.UINT,
        "Status": dm_type.STRING
    },
    defaults: {
        "LocalIPAddress": "",
        "LocalPort": "0",
        "RemoteIPAddress": "",
        "RemotePort": "0",
        "Status": ""
    }
};

// Schema for Device.IP.Interface.{i}.IPv6Prefix.{i}.
export const Interface_IPv6Prefix = {
    path: "Device.IP.Interface.{i}.IPv6Prefix.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "PrefixStatus": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Prefix": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "StaticType": dm_type.STRING | dm_type.WRITABLE,
        "ParentPrefix": dm_type.STRING | dm_type.WRITABLE,
        "ChildPrefixBits": dm_type.STRING | dm_type.WRITABLE,
        "OnLink": dm_type.BOOL | dm_type.WRITABLE,
        "Autonomous": dm_type.BOOL | dm_type.WRITABLE,
        "PreferredLifetime": dm_type.DATETIME | dm_type.WRITABLE,
        "ValidLifetime": dm_type.DATETIME | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "PrefixStatus": "Invalid",
        "Alias": "",
        "Prefix": "",
        "Origin": "Static",
        "StaticType": "Static",
        "ParentPrefix": "",
        "ChildPrefixBits": "",
        "OnLink": "false",
        "Autonomous": "false",
        "PreferredLifetime": "9999-12-31T23:59:59Z",
        "ValidLifetime": "9999-12-31T23:59:59Z"
    }
};

// Schema for Device.IP.Diagnostics.
export const Diagnostics = {
    path: "Device.IP.Diagnostics.",
    schema: {
        "IPv4PingSupported": dm_type.BOOL,
        "IPv6PingSupported": dm_type.BOOL,
        "IPv4TraceRouteSupported": dm_type.BOOL,
        "IPv6TraceRouteSupported": dm_type.BOOL,
        "IPv4DownloadDiagnosticsSupported": dm_type.BOOL,
        "IPv6DownloadDiagnosticsSupported": dm_type.BOOL,
        "IPv4UploadDiagnosticsSupported": dm_type.BOOL,
        "IPv6UploadDiagnosticsSupported": dm_type.BOOL,
        "IPv4UDPEchoDiagnosticsSupported": dm_type.BOOL,
        "IPv6UDPEchoDiagnosticsSupported": dm_type.BOOL,
        "IPLayerCapacitySupported": dm_type.BOOL,
        "IPv4ServerSelectionDiagnosticsSupported": dm_type.BOOL,
        "IPv6ServerSelectionDiagnosticsSupported": dm_type.BOOL,
        "DownloadTransports": dm_type.STRING,
        "DownloadDiagnosticMaxConnections": dm_type.UINT,
        "DownloadDiagnosticsMaxIncrementalResult": dm_type.UINT,
        "UploadTransports": dm_type.STRING,
        "UploadDiagnosticsMaxConnections": dm_type.UINT,
        "UploadDiagnosticsMaxIncrementalResult": dm_type.UINT,
        "UDPEchoDiagnosticsMaxResults": dm_type.UINT,
        "IPLayerMaxConnections": dm_type.UINT,
        "IPLayerMaxIncrementalResult": dm_type.UINT,
        "IPLayerCapSupportedSoftwareVersion": dm_type.STRING,
        "IPLayerCapSupportedControlProtocolVersion": dm_type.STRING,
        "IPLayerCapSupportedMetrics": dm_type.STRING,
        "IPLayerCapacityAuthCodeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DownloadTransports": "",
        "DownloadDiagnosticMaxConnections": "0",
        "DownloadDiagnosticsMaxIncrementalResult": "0",
        "UploadTransports": "",
        "UploadDiagnosticsMaxConnections": "0",
        "UploadDiagnosticsMaxIncrementalResult": "0",
        "UDPEchoDiagnosticsMaxResults": "0",
        "IPLayerMaxConnections": "0",
        "IPLayerMaxIncrementalResult": "0",
        "IPLayerCapSupportedSoftwareVersion": "",
        "IPLayerCapSupportedControlProtocolVersion": "",
        "IPLayerCapSupportedMetrics": "",
        "IPLayerCapacityAuthCodeNumberOfEntries": "0"
    }
};

// Schema for Device.IP.Interface.{i}.IPv6Address.{i}.
export const Interface_IPv6Address = {
    path: "Device.IP.Interface.{i}.IPv6Address.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "IPAddressStatus": dm_type.STRING,
        "Alias": dm_type.STRING,
        "IPAddress": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Prefix": dm_type.STRING | dm_type.WRITABLE,
        "PreferredLifetime": dm_type.DATETIME | dm_type.WRITABLE,
        "ValidLifetime": dm_type.DATETIME | dm_type.WRITABLE,
        "Anycast": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "IPAddressStatus": "Invalid",
        "Alias": "",
        "IPAddress": "",
        "Origin": "Static",
        "Prefix": "",
        "PreferredLifetime": "9999-12-31T23:59:59Z",
        "ValidLifetime": "9999-12-31T23:59:59Z",
        "Anycast": "false"
    }
};

// Schema for Device.IP.Interface.{i}.TWAMPReflector.{i}.
export const Interface_TWAMPReflector = {
    path: "Device.IP.Interface.{i}.TWAMPReflector.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "MaximumTTL": dm_type.UINT | dm_type.WRITABLE,
        "IPAllowedList": dm_type.STRING | dm_type.WRITABLE,
        "PortAllowedList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Port": "862",
        "MaximumTTL": "1",
        "IPAllowedList": "",
        "PortAllowedList": ""
    }
};

// Schema for Device.IP.
export const IP = {
    path: "Device.IP.",
    schema: {
        "IPv4Capable": dm_type.BOOL,
        "IPv4Enable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv4Status": dm_type.STRING,
        "IPv6Capable": dm_type.BOOL,
        "IPv6Enable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6Status": dm_type.STRING,
        "ULAPrefix": dm_type.STRING | dm_type.WRITABLE,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "IPv4Capable": "true",
        "IPv4Enable": "true",
        "IPv4Status": "Enabled",
        "IPv6Capable": "true",
        "IPv6Enable": "true",
        "IPv6Status": "Enabled",
        "ULAPrefix": "",
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.IP.Interface.{i}.
export const Interface = {
    path: "Device.IP.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv4Enable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ULAEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxMTUSize": dm_type.UINT | dm_type.WRITABLE,
        "Type": dm_type.STRING,
        "Loopback": dm_type.BOOL,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT,
        "IPv6PrefixNumberOfEntries": dm_type.UINT,
        "X_UBBF_CarrierLossDelay": dm_type.UINT | dm_type.WRITABLE,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "IPv4Enable": "true",
        "IPv6Enable": "true",
        "ULAEnable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "Upstream": "false",
        "MaxMTUSize": "0",
        "Type": "Normal",
        "Loopback": "false",
        "IPv4AddressNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0",
        "IPv6PrefixNumberOfEntries": "0",
        "X_UBBF_CarrierLossDelay": "0"
    },
    constraints: {
        // 0 leaves the MTU to the lower layer (ip.uc emits no mtu), which
        // TR-181's 64-65535 range has no value for.
        "MaxMTUSize": { min: null, max: null, ranges: [ [ 0, 0 ], [ 64, 65535 ] ] }
    }
};

// Schema for Device.IP.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.IP.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.ULONG,
        "BytesReceived": dm_type.ULONG,
        "PacketsSent": dm_type.ULONG,
        "PacketsReceived": dm_type.ULONG,
        "ErrorsSent": dm_type.UINT,
        "ErrorsReceived": dm_type.UINT,
        "UnicastPacketsSent": dm_type.ULONG,
        "UnicastPacketsReceived": dm_type.ULONG,
        "DiscardPacketsSent": dm_type.UINT,
        "DiscardPacketsReceived": dm_type.UINT,
        "MulticastPacketsSent": dm_type.ULONG,
        "MulticastPacketsReceived": dm_type.ULONG,
        "BroadcastPacketsSent": dm_type.ULONG,
        "BroadcastPacketsReceived": dm_type.ULONG,
        "UnknownProtoPacketsReceived": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "BytesSent": "0",
        "BytesReceived": "0",
        "PacketsSent": "0",
        "PacketsReceived": "0",
        "ErrorsSent": "0",
        "ErrorsReceived": "0",
        "UnicastPacketsSent": "0",
        "UnicastPacketsReceived": "0",
        "DiscardPacketsSent": "0",
        "DiscardPacketsReceived": "0",
        "MulticastPacketsSent": "0",
        "MulticastPacketsReceived": "0",
        "BroadcastPacketsSent": "0",
        "BroadcastPacketsReceived": "0",
        "UnknownProtoPacketsReceived": "0"
    }
};
