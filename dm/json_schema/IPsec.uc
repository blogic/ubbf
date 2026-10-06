'use strict';

// Auto-generated schema definitions for IPsec domain
// Generated from TR-181 specifications

// Schema for Device.IPsec.IKEv2SA.{i}.
export const IKEv2SA = {
    path: "Device.IPsec.IKEv2SA.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Tunnel": dm_type.STRING,
        "LocalAddress": dm_type.STRING,
        "RemoteAddress": dm_type.STRING,
        "EncryptionAlgorithm": dm_type.STRING,
        "EncryptionKeyLength": dm_type.UINT,
        "PseudoRandomFunction": dm_type.STRING,
        "IntegrityAlgorithm": dm_type.STRING,
        "DiffieHellmanGroupTransform": dm_type.STRING,
        "CreationTime": dm_type.DATETIME,
        "NATDetected": dm_type.STRING,
        "ReceivedCPAttrNumberOfEntries": dm_type.UINT,
        "ChildSANumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Tunnel": "",
        "LocalAddress": "",
        "RemoteAddress": "",
        "EncryptionAlgorithm": "",
        "EncryptionKeyLength": "0",
        "PseudoRandomFunction": "",
        "IntegrityAlgorithm": "",
        "DiffieHellmanGroupTransform": "",
        "NATDetected": "",
        "ReceivedCPAttrNumberOfEntries": "0",
        "ChildSANumberOfEntries": "0"
    }
};

// Schema for Device.IPsec.Stats.
export const Stats = {
    path: "Device.IPsec.Stats.",
    schema: {
        "NegotiationFailures": dm_type.STRING,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "UnknownSPIErrors": dm_type.STRING,
        "DecryptionErrors": dm_type.STRING,
        "IntegrityErrors": dm_type.STRING,
        "ReplayErrors": dm_type.STRING,
        "PolicyErrors": dm_type.STRING,
        "OtherReceiveErrors": dm_type.STRING
    },
    defaults: {
        "NegotiationFailures": "",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "UnknownSPIErrors": "",
        "DecryptionErrors": "",
        "IntegrityErrors": "",
        "ReplayErrors": "",
        "PolicyErrors": "",
        "OtherReceiveErrors": ""
    }
};

// Schema for Device.IPsec.IKEv2SA.{i}.Stats.
export const IKEv2SA_Stats = {
    path: "Device.IPsec.IKEv2SA.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "DecryptionErrors": dm_type.STRING,
        "IntegrityErrors": dm_type.STRING,
        "OtherReceiveErrors": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "DecryptionErrors": "",
        "IntegrityErrors": "",
        "OtherReceiveErrors": ""
    }
};

// Schema for Device.IPsec.IKEv2SA.{i}.ChildSA.{i}.Stats.
export const ChildSA_Stats = {
    path: "Device.IPsec.IKEv2SA.{i}.ChildSA.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "DecryptionErrors": dm_type.STRING,
        "IntegrityErrors": dm_type.STRING,
        "ReplayErrors": dm_type.STRING,
        "PolicyErrors": dm_type.STRING,
        "OtherReceiveErrors": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "DecryptionErrors": "",
        "IntegrityErrors": "",
        "ReplayErrors": "",
        "PolicyErrors": "",
        "OtherReceiveErrors": ""
    }
};

// Schema for Device.IPsec.Profile.{i}.
export const Profile = {
    path: "Device.IPsec.Profile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "MaxChildSAs": dm_type.UINT | dm_type.WRITABLE,
        "RemoteEndpoints": dm_type.STRING | dm_type.WRITABLE,
        "ForwardingPolicy": dm_type.UINT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2AuthenticationMethod": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2AllowedEncryptionAlgorithms": dm_type.STRING | dm_type.WRITABLE,
        "ESPAllowedEncryptionAlgorithms": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2AllowedPseudoRandomFunctions": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2AllowedIntegrityAlgorithms": dm_type.STRING | dm_type.WRITABLE,
        "AHAllowedIntegrityAlgorithms": dm_type.STRING | dm_type.WRITABLE,
        "ESPAllowedIntegrityAlgorithms": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2AllowedDiffieHellmanGroupTransforms": dm_type.STRING | dm_type.WRITABLE,
        "IKEv2DeadPeerDetectionTimeout": dm_type.UINT | dm_type.WRITABLE,
        "IKEv2NATTKeepaliveTimeout": dm_type.UINT | dm_type.WRITABLE,
        "AntiReplayWindowSize": dm_type.UINT | dm_type.WRITABLE,
        "DoNotFragment": dm_type.STRING | dm_type.WRITABLE,
        "DSCPMarkPolicy": dm_type.INT | dm_type.WRITABLE,
        "IKEv2SATrafficLimit": dm_type.ULONG | dm_type.WRITABLE,
        "IKEv2SATimeLimit": dm_type.UINT | dm_type.WRITABLE,
        "IKEv2SAExpiryAction": dm_type.STRING | dm_type.WRITABLE,
        "ChildSATrafficLimit": dm_type.ULONG | dm_type.WRITABLE,
        "ChildSATimeLimit": dm_type.UINT | dm_type.WRITABLE,
        "ChildSAExpiryAction": dm_type.STRING | dm_type.WRITABLE,
        "SentCPAttrNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "MaxChildSAs": "0",
        "RemoteEndpoints": "",
        "ForwardingPolicy": "0",
        "Protocol": "ESP",
        "IKEv2AuthenticationMethod": "",
        "IKEv2AllowedEncryptionAlgorithms": "",
        "ESPAllowedEncryptionAlgorithms": "",
        "IKEv2AllowedPseudoRandomFunctions": "",
        "IKEv2AllowedIntegrityAlgorithms": "",
        "AHAllowedIntegrityAlgorithms": "[]",
        "ESPAllowedIntegrityAlgorithms": "[]",
        "IKEv2AllowedDiffieHellmanGroupTransforms": "",
        "IKEv2DeadPeerDetectionTimeout": "0",
        "IKEv2NATTKeepaliveTimeout": "0",
        "AntiReplayWindowSize": "0",
        "DoNotFragment": "",
        "DSCPMarkPolicy": "0",
        "IKEv2SATrafficLimit": "0",
        "IKEv2SATimeLimit": "0",
        "IKEv2SAExpiryAction": "",
        "ChildSATrafficLimit": "0",
        "ChildSATimeLimit": "0",
        "ChildSAExpiryAction": "",
        "SentCPAttrNumberOfEntries": "0"
    }
};

// Schema for Device.IPsec.Filter.{i}.
export const Filter = {
    path: "Device.IPsec.Filter.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        "DestIP": dm_type.STRING | dm_type.WRITABLE,
        "DestMask": dm_type.STRING | dm_type.WRITABLE,
        "DestIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceIP": dm_type.STRING | dm_type.WRITABLE,
        "SourceMask": dm_type.STRING | dm_type.WRITABLE,
        "SourceIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "Protocol": dm_type.INT | dm_type.WRITABLE,
        "ProtocolExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestPort": dm_type.INT | dm_type.WRITABLE,
        "DestPortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "DestPortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourcePort": dm_type.INT | dm_type.WRITABLE,
        "SourcePortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "SourcePortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "ProcessingChoice": dm_type.STRING | dm_type.WRITABLE,
        "Profile": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Order": "",
        "Alias": "",
        "Interface": "",
        "AllInterfaces": "false",
        "DestIP": "",
        "DestMask": "",
        "DestIPExclude": "false",
        "SourceIP": "",
        "SourceMask": "",
        "SourceIPExclude": "false",
        "Protocol": "-1",
        "ProtocolExclude": "false",
        "DestPort": "-1",
        "DestPortRangeMax": "-1",
        "DestPortExclude": "false",
        "SourcePort": "-1",
        "SourcePortRangeMax": "-1",
        "SourcePortExclude": "false",
        "ProcessingChoice": "Bypass",
        "Profile": ""
    }
};

// Schema for Device.IPsec.
export const IPsec = {
    path: "Device.IPsec.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "AHSupported": dm_type.BOOL,
        "IKEv2SupportedEncryptionAlgorithms": dm_type.STRING,
        "ESPSupportedEncryptionAlgorithms": dm_type.STRING,
        "IKEv2SupportedPseudoRandomFunctions": dm_type.STRING,
        "SupportedIntegrityAlgorithms": dm_type.STRING,
        "SupportedDiffieHellmanGroupTransforms": dm_type.STRING,
        "MaxFilterEntries": dm_type.UINT,
        "MaxProfileEntries": dm_type.UINT,
        "FilterNumberOfEntries": dm_type.UINT,
        "ProfileNumberOfEntries": dm_type.UINT,
        "TunnelNumberOfEntries": dm_type.UINT,
        "IKEv2SANumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "IKEv2SupportedEncryptionAlgorithms": "",
        "ESPSupportedEncryptionAlgorithms": "",
        "IKEv2SupportedPseudoRandomFunctions": "",
        "SupportedIntegrityAlgorithms": "",
        "SupportedDiffieHellmanGroupTransforms": "",
        "MaxFilterEntries": "0",
        "MaxProfileEntries": "0",
        "FilterNumberOfEntries": "0",
        "ProfileNumberOfEntries": "0",
        "TunnelNumberOfEntries": "0",
        "IKEv2SANumberOfEntries": "0"
    }
};

// Schema for Device.IPsec.IKEv2SA.{i}.ReceivedCPAttr.{i}.
export const IKEv2SA_ReceivedCPAttr = {
    path: "Device.IPsec.IKEv2SA.{i}.ReceivedCPAttr.{i}.",
    schema: {
        "Type": dm_type.UINT,
        "Value": dm_type.HEXBIN
    },
    defaults: {
        "Type": "0"
    }
};

// Schema for Device.IPsec.Profile.{i}.SentCPAttr.{i}.
export const Profile_SentCPAttr = {
    path: "Device.IPsec.Profile.{i}.SentCPAttr.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Type": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Type": "0"
    }
};

// Schema for Device.IPsec.Tunnel.{i}.
export const Tunnel = {
    path: "Device.IPsec.Tunnel.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "TunnelInterface": dm_type.STRING,
        "TunneledInterface": dm_type.STRING,
        "Filters": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "TunnelInterface": "",
        "TunneledInterface": "",
        "Filters": ""
    }
};

// Schema for Device.IPsec.IKEv2SA.{i}.ChildSA.{i}.
export const IKEv2SA_ChildSA = {
    path: "Device.IPsec.IKEv2SA.{i}.ChildSA.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "InboundSPI": dm_type.UINT,
        "OutboundSPI": dm_type.UINT,
        "CreationTime": dm_type.DATETIME
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "InboundSPI": "0",
        "OutboundSPI": "0"
    }
};

// Schema for Device.IPsec.Tunnel.{i}.Stats.
export const Tunnel_Stats = {
    path: "Device.IPsec.Tunnel.{i}.Stats.",
    schema: {
        "DecryptionErrors": dm_type.STRING,
        "IntegrityErrors": dm_type.STRING,
        "ReplayErrors": dm_type.STRING,
        "PolicyErrors": dm_type.STRING,
        "OtherReceiveErrors": dm_type.STRING
    },
    defaults: {
        "DecryptionErrors": "",
        "IntegrityErrors": "",
        "ReplayErrors": "",
        "PolicyErrors": "",
        "OtherReceiveErrors": ""
    }
};
