'use strict';

// Auto-generated schema definitions for Firewall domain
// Generated from TR-181 specifications

// Schema for Device.Firewall.Log.{i}.Filter.
export const Log_Filter = {
    path: "Device.Firewall.Log.{i}.Filter.",
    schema: {
        "Policy": dm_type.STRING | dm_type.WRITABLE,
        "SourceInterface": dm_type.STRING | dm_type.WRITABLE,
        "DestinationInterface": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Policy": "All",
        "SourceInterface": "",
        "DestinationInterface": ""
    },
    constraints: {
        "Policy": { enum: [ "All", "Denied", "Allowed" ] },
        "SourceInterface": { max_length: 256 },
        "DestinationInterface": { max_length: 256 }
    }
};

// Schema for Device.Firewall.Chain.{i}.
export const Chain = {
    path: "Device.Firewall.Chain.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Creator": dm_type.STRING,
        "RuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Name": "",
        "Creator": "ACS",
        "RuleNumberOfEntries": "0"
    },
    constraints: {
        "Name": { max_length: 64 }
    }
};

// Schema for Device.Firewall.Pinhole.{i}.
export const Pinhole = {
    path: "Device.Firewall.Pinhole.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Origin": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "LeaseDuration": dm_type.UINT | dm_type.WRITABLE,
        "RemainingLeaseTime": dm_type.UINT,
        "SourcePort": dm_type.INT | dm_type.WRITABLE,
        "SourcePortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "DestPort": dm_type.INT | dm_type.WRITABLE,
        "DestPortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "Protocol": dm_type.INT | dm_type.WRITABLE,
        "SourcePrefixes": dm_type.STRING | dm_type.WRITABLE,
        "DestIP": dm_type.STRING | dm_type.WRITABLE,
        "DestMACAddress": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleRef": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Origin": "Controller",
        "Description": "",
        "Interface": "",
        "LeaseDuration": "0",
        "RemainingLeaseTime": "0",
        "SourcePort": "-1",
        "SourcePortRangeMax": "-1",
        "DestPort": "-1",
        "DestPortRangeMax": "-1",
        "IPVersion": "-1",
        "Protocol": "-1",
        "SourcePrefixes": "",
        "DestIP": "",
        "DestMACAddress": "",
        "ScheduleRef": "",
        "Log": "false",
        "LogRef": ""
    },
    constraints: {
        "Description": { max_length: 256 },
        "Interface": { max_length: 256 },
        "SourcePort": { min: -1, max: 65535 },
        "SourcePortRangeMax": { min: -1, max: 65535 },
        "DestPort": { min: -1, max: 65535 },
        "DestPortRangeMax": { min: -1, max: 65535 },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
        "Protocol": { list: true, min: -1, max: 255 },
        "SourcePrefixes": { list: true, max_length: 49 },
        "DestIP": { max_length: 45 },
        "DestMACAddress": { max_length: 17 },
        "ScheduleRef": { list: true },
        "LogRef": { list: true }
    }
};

// Schema for Device.Firewall.Policy.{i}.
export const Policy = {
    path: "Device.Firewall.Policy.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Chain": dm_type.STRING | dm_type.WRITABLE,
        "TargetChain": dm_type.STRING | dm_type.WRITABLE,
        "SourceInterface": dm_type.STRING | dm_type.WRITABLE,
        "DestinationInterface": dm_type.STRING | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "ReverseChain": dm_type.STRING | dm_type.WRITABLE,
        "ReverseTargetChain": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Chain": "",
        "TargetChain": "Drop",
        "SourceInterface": "",
        "DestinationInterface": "",
        "IPVersion": "-1",
        "ReverseChain": "",
        "ReverseTargetChain": "Drop",
        "Log": "false",
        "LogRef": ""
    },
    constraints: {
        "TargetChain": { enum: [ "Drop", "Accept", "Reject", "Chain" ] },
        "SourceInterface": { max_length: 256 },
        "DestinationInterface": { max_length: 256 },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
        "ReverseTargetChain": { enum: [ "Drop", "Accept", "Reject", "Chain" ] },
        "LogRef": { list: true }
    }
};

// Schema for Device.Firewall.Level.{i}.
export const Level = {
    path: "Device.Firewall.Level.{i}.",
    schema: {
        "Alias": dm_type.STRING | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Policies": dm_type.STRING | dm_type.WRITABLE,
        "Chain": dm_type.STRING,
        "PortMappingEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "DefaultPolicy": dm_type.STRING | dm_type.WRITABLE,
        "DefaultLogPolicy": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Description": "",
        "Order": "",
        "Policies": "",
        "Chain": "",
        "PortMappingEnabled": "true",
        "DefaultPolicy": "Drop",
        "DefaultLogPolicy": "false"
    },
    constraints: {
        "Alias": { max_length: 64 },
        "Name": { max_length: 64 },
        "Description": { max_length: 256 },
        "Order": { min: 1 },
        "Policies": { list: true },
        "DefaultPolicy": { enum: [ "Drop", "Accept", "Reject" ] }
    }
};

// Schema for Device.Firewall.Set.{i}.
export const Set = {
    path: "Device.Firewall.Set.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "RuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Origin": "Controller",
        "Name": "",
        "Type": "IPAddresses",
        "IPVersion": "-1",
        "RuleNumberOfEntries": "0"
    },
    constraints: {
        "Name": { max_length: 31 },
        "Type": { enum: [ "IPAddresses", "Ports", "MACAddresses" ] },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] }
    }
};

// Schema for Device.Firewall.InterfaceSetting.{i}.
export const InterfaceSetting = {
    path: "Device.Firewall.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "IPv4SpoofingProtection": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6SpoofingProtection": dm_type.BOOL | dm_type.WRITABLE,
        "IPv4AcceptICMPEchoRequest": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6AcceptICMPEchoRequest": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6PassThroughICMPEchoRequest": dm_type.BOOL | dm_type.WRITABLE,
        "StealthMode": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "IPv4SpoofingProtection": "true",
        "IPv6SpoofingProtection": "true",
        "IPv4AcceptICMPEchoRequest": "true",
        "IPv6AcceptICMPEchoRequest": "true",
        "IPv6PassThroughICMPEchoRequest": "false",
        "StealthMode": "false"
    },
    constraints: {
        "Interface": { max_length: 256 }
    }
};

// Schema for Device.Firewall.ConnectionTracking.SIP.
export const ConnectionTracking_SIP = {
    path: "Device.Firewall.ConnectionTracking.SIP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Ports": dm_type.INT | dm_type.WRITABLE,
        "DirectMedia": dm_type.BOOL | dm_type.WRITABLE,
        "DirectSignaling": dm_type.BOOL | dm_type.WRITABLE,
        "ExternalMedia": dm_type.BOOL | dm_type.WRITABLE,
        "TimeOut": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Ports": "0",
        "DirectMedia": "true",
        "DirectSignaling": "true",
        "ExternalMedia": "false",
        "TimeOut": "0"
    },
    constraints: {
        "Ports": { list: true, min: 0, max: 65535 }
    }
};

// Schema for Device.Firewall.ConnectionTracking.FTP.
export const ConnectionTracking_FTP = {
    path: "Device.Firewall.ConnectionTracking.FTP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Ports": dm_type.INT | dm_type.WRITABLE,
        "Loose": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Ports": "0",
        "Loose": "false"
    },
    constraints: {
        "Ports": { list: true, min: 0, max: 65535 }
    }
};

// Schema for Device.Firewall.Chain.{i}.Rule.{i}.
export const Chain_Rule = {
    path: "Device.Firewall.Chain.{i}.Rule.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Target": dm_type.STRING | dm_type.WRITABLE,
        "TargetChain": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE,
        "CreationDate": dm_type.DATETIME,
        "ExpiryDate": dm_type.DATETIME | dm_type.WRITABLE,
        "SourceInterface": dm_type.STRING | dm_type.WRITABLE,
        "SourceInterfaceExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceAllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        "DestInterface": dm_type.STRING | dm_type.WRITABLE,
        "DestInterfaceExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestAllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "DestIP": dm_type.STRING | dm_type.WRITABLE,
        "DestMask": dm_type.STRING | dm_type.WRITABLE,
        "DestIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMatchSet": dm_type.STRING | dm_type.WRITABLE,
        "DestMatchSetExclude": dm_type.STRING | dm_type.WRITABLE,
        "SourceIP": dm_type.STRING | dm_type.WRITABLE,
        "SourceMask": dm_type.STRING | dm_type.WRITABLE,
        "SourceIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMatchSet": dm_type.STRING | dm_type.WRITABLE,
        "SourceMatchSetExclude": dm_type.STRING | dm_type.WRITABLE,
        "Protocol": dm_type.INT | dm_type.WRITABLE,
        "ProtocolExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestPort": dm_type.INT | dm_type.WRITABLE,
        "DestPortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "DestPortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourcePort": dm_type.INT | dm_type.WRITABLE,
        "SourcePortRangeMax": dm_type.INT | dm_type.WRITABLE,
        "SourcePortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DSCP": dm_type.INT | dm_type.WRITABLE,
        "DSCPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "ConnectionState": dm_type.STRING | dm_type.WRITABLE,
        "SourceMAC": dm_type.STRING | dm_type.WRITABLE,
        "SourceMACExclude": dm_type.BOOL | dm_type.WRITABLE,
        "FloodLimit": dm_type.INT | dm_type.WRITABLE,
        "BurstLimit": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Order": "",
        "Alias": "",
        "Description": "",
        "Target": "Drop",
        "TargetChain": "",
        "Log": "false",
        "LogRef": "",
        "CreationDate": "0001-01-01T00:00:00Z",
        "ExpiryDate": "9999-12-31T23:59:59Z",
        "SourceInterface": "",
        "SourceInterfaceExclude": "false",
        "SourceAllInterfaces": "false",
        "DestInterface": "",
        "DestInterfaceExclude": "false",
        "DestAllInterfaces": "false",
        "IPVersion": "-1",
        "DestIP": "",
        "DestMask": "",
        "DestIPExclude": "false",
        "DestMatchSet": "",
        "DestMatchSetExclude": "",
        "SourceIP": "",
        "SourceMask": "",
        "SourceIPExclude": "false",
        "SourceMatchSet": "",
        "SourceMatchSetExclude": "",
        "Protocol": "-1",
        "ProtocolExclude": "false",
        "DestPort": "-1",
        "DestPortRangeMax": "-1",
        "DestPortExclude": "false",
        "SourcePort": "-1",
        "SourcePortRangeMax": "-1",
        "SourcePortExclude": "false",
        "DSCP": "-1",
        "DSCPExclude": "false",
        "ConnectionState": "",
        "SourceMAC": "",
        "SourceMACExclude": "false",
        "FloodLimit": "-1",
        "BurstLimit": "-1"
    },
    since: {
        "FloodLimit": "2.20",
        "BurstLimit": "2.20"
    },
    constraints: {
        "Order": { min: 1 },
        "Description": { max_length: 256 },
        "Target": { enum: [ "Drop", "Accept", "Reject", "Return", "TargetChain" ] },
        "LogRef": { list: true },
        "SourceInterface": { max_length: 256 },
        "DestInterface": { max_length: 256 },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
        "DestIP": { max_length: 45 },
        "DestMask": { max_length: 49 },
        "SourceIP": { max_length: 45 },
        "SourceMask": { max_length: 49 },
        "Protocol": { min: -1, max: 255 },
        "DestPort": { min: -1, max: 65535 },
        "DestPortRangeMax": { min: -1, max: 65535 },
        "SourcePort": { min: -1, max: 65535 },
        "SourcePortRangeMax": { min: -1, max: 65535 },
        "DSCP": { min: -1, max: 63 },
        "ConnectionState": { list: true, enum: [ "INVALID", "NEW", "RELATED", "ESTABLISHED" ] },
        "SourceMAC": { max_length: 17 },
        "FloodLimit": { min: -1, max: 65535 },
        "BurstLimit": { min: -1, max: 65535 }
    }
};

// Schema for Device.Firewall.ConnectionTracking.IRC.
export const ConnectionTracking_IRC = {
    path: "Device.Firewall.ConnectionTracking.IRC.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Ports": dm_type.INT | dm_type.WRITABLE,
        "MAXDCCChannels": dm_type.UINT | dm_type.WRITABLE,
        "DCCTimeout": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Ports": "0",
        "MAXDCCChannels": "0",
        "DCCTimeout": "0"
    },
    constraints: {
        "Ports": { list: true, min: 0, max: 65535 }
    }
};

// Schema for Device.Firewall.
export const Firewall = {
    path: "Device.Firewall.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Config": dm_type.STRING | dm_type.WRITABLE,
        "AdvancedLevel": dm_type.STRING | dm_type.WRITABLE,
        "PolicyLevel": dm_type.STRING | dm_type.WRITABLE,
        // "Type": dm_type.STRING,
        // "Version": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "LevelNumberOfEntries": dm_type.UINT,
        "ChainNumberOfEntries": dm_type.UINT,
        "DMZNumberOfEntries": dm_type.UINT,
        "ServiceNumberOfEntries": dm_type.UINT,
        "PinholeNumberOfEntries": dm_type.UINT,
        "PolicyNumberOfEntries": dm_type.UINT,
        "InterfaceSettingNumberOfEntries": dm_type.UINT,
        "SetNumberOfEntries": dm_type.UINT,
        "X_UBBF_RespondToPing": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Config": "",
        "AdvancedLevel": "",
        "PolicyLevel": "",
        "LevelNumberOfEntries": "0",
        "ChainNumberOfEntries": "0",
        "DMZNumberOfEntries": "0",
        "ServiceNumberOfEntries": "0",
        "PinholeNumberOfEntries": "0",
        "PolicyNumberOfEntries": "0",
        "InterfaceSettingNumberOfEntries": "0",
        "SetNumberOfEntries": "0",
        "X_UBBF_RespondToPing": "true"
    },
    constraints: {
        "Config": { enum: [ "High", "Low", "Off", "Advanced", "Policy" ] }
    }
};

// Schema for Device.Firewall.Service.{i}.
export const Service = {
    path: "Device.Firewall.Service.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "DestPort": dm_type.INT | dm_type.WRITABLE,
        "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "Protocol": dm_type.INT | dm_type.WRITABLE,
        "ICMPType": dm_type.INT | dm_type.WRITABLE,
        "SourcePrefixes": dm_type.STRING | dm_type.WRITABLE,
        "Action": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Interface": "",
        "DestPort": "-1",
        "IPVersion": "-1",
        "Protocol": "-1",
        "ICMPType": "-1",
        "SourcePrefixes": "",
        "Action": "Accept",
        "Log": "false",
        "LogRef": ""
    },
    constraints: {
        "Interface": { max_length: 256 },
        "DestPort": { list: true, min: -1, max: 65535 },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
        "Protocol": { list: true, min: -1, max: 255 },
        "ICMPType": { min: -1, max: 255 },
        "SourcePrefixes": { list: true, max_length: 49 },
        "Action": { enum: [ "Drop", "Accept", "Reject" ] },
        "LogRef": { list: true }
    }
};

// Schema for Device.Firewall.Log.{i}.
export const Log = {
    path: "Device.Firewall.Log.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Severity": dm_type.STRING | dm_type.WRITABLE,
        "Prefix": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Description": "",
        "Severity": "Debug",
        "Prefix": ""
    },
    constraints: {
        "Description": { max_length: 256 },
        "Severity": { enum: [ "Emergency", "Alert", "Critical", "Error", "Warning", "Notice", "Debug" ] }
    }
};

// Schema for Device.Firewall.ConnectionTracking.TFTP.
export const ConnectionTracking_TFTP = {
    path: "Device.Firewall.ConnectionTracking.TFTP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Ports": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Ports": "0"
    },
    constraints: {
        "Ports": { list: true, min: 0, max: 65535 }
    }
};

// Schema for Device.Firewall.DMZ.{i}.
export const DMZ = {
    path: "Device.Firewall.DMZ.{i}.",
    schema: {
        "Alias": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Origin": dm_type.STRING | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        // "LeaseDuration": dm_type.UINT | dm_type.WRITABLE,
        // "RemainingLeaseTime": dm_type.UINT,
        "DestIP": dm_type.STRING | dm_type.WRITABLE,
        "SourcePrefix": dm_type.STRING | dm_type.WRITABLE,
        // "Log": dm_type.BOOL | dm_type.WRITABLE,
        // "LogRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Origin": "Controller",
        "Description": "",
        "Interface": "",
        "DestIP": "",
        "SourcePrefix": ""
    },
    constraints: {
        "Alias": { max_length: 64 },
        "Origin": { enum: [ "User", "System", "Controller" ] },
        "Description": { max_length: 256 },
        "Interface": { max_length: 256 },
        "DestIP": { max_length: 15 },
        "SourcePrefix": { max_length: 18 }
    }
};

// Schema for Device.Firewall.ConnectionTracking.PPTP.
export const ConnectionTracking_PPTP = {
    path: "Device.Firewall.ConnectionTracking.PPTP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false"
    }
};

// Schema for Device.Firewall.ConnectionTracking.H323.
export const ConnectionTracking_H323 = {
    path: "Device.Firewall.ConnectionTracking.H323.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "RegistrationRequestTTL": dm_type.UINT | dm_type.WRITABLE,
        "GKRoutedOnly": dm_type.BOOL | dm_type.WRITABLE,
        "CallForwardFilter": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "RegistrationRequestTTL": "0",
        "GKRoutedOnly": "false",
        "CallForwardFilter": "false"
    }
};

// Vendor sub-object for Device.Firewall.X_UBBF_DoSProtection.
// Broad DoS protection and IPv4 attack protection with five ACS-writable
// booleans backed by fw4 defaults, fw4 rules, and an iifname-scoped
// nftables include hooked into the global input chain so the rate-limit and malformed-TCP drops fire
// before fw4's ct-state-established accept. Fragmentation is covered
// by the kernel's nf_defrag_ipv4 reassembly: an explicit fragment-drop
// knob cannot be hooked early enough via fw4 to be useful, so it is
// not exposed.
export const X_UBBF_DoSProtection = {
    path: "Device.Firewall.X_UBBF_DoSProtection.",
    schema: {
        "SynFloodProtection": dm_type.BOOL | dm_type.WRITABLE,
        "DropInvalidPackets": dm_type.BOOL | dm_type.WRITABLE,
        "IcmpRateLimit": dm_type.BOOL | dm_type.WRITABLE,
        "DropMulticastWAN": dm_type.BOOL | dm_type.WRITABLE,
        "DropMalformedTCP": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "SynFloodProtection": "true",
        "DropInvalidPackets": "true",
        "IcmpRateLimit": "true",
        "DropMulticastWAN": "true",
        "DropMalformedTCP": "true"
    }
};

// Schema for Device.Firewall.Set.{i}.Rule.{i}.
export const Set_Rule = {
    path: "Device.Firewall.Set.{i}.Rule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Exclude": dm_type.BOOL | dm_type.WRITABLE,
        "IPAddressList": dm_type.STRING | dm_type.WRITABLE,
        "MACAddressList": dm_type.STRING | dm_type.WRITABLE,
        "PortList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Exclude": "false",
        "IPAddressList": "",
        "MACAddressList": "",
        "PortList": ""
    },
    constraints: {
        "IPAddressList": { list: true, max_length: 45 },
        "MACAddressList": { list: true, max_length: 17 },
        "PortList": { list: true }
    }
};
