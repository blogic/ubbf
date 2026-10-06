'use strict';

// Auto-generated schema definitions for Bridging domain
// Generated from TR-181 specifications

// Schema for Device.Bridging.Bridge.{i}.Port.{i}.PriorityCodePoint.
export const Port_PriorityCodePoint = {
    path: "Device.Bridging.Bridge.{i}.Port.{i}.PriorityCodePoint.",
    schema: {
        "PCPSelection": dm_type.UINT | dm_type.WRITABLE,
        "UseDEI": dm_type.BOOL | dm_type.WRITABLE,
        "RequireDropEncoding": dm_type.BOOL | dm_type.WRITABLE,
        "PCPEncoding": dm_type.STRING | dm_type.WRITABLE,
        "PCPDecoding": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "PCPSelection": "1",
        "UseDEI": "false",
        "RequireDropEncoding": "false",
        "PCPEncoding": "",
        "PCPDecoding": ""
    }
};

// Schema for Device.Bridging.Bridge.{i}.Port.{i}.Stats.
export const Port_Stats = {
    path: "Device.Bridging.Bridge.{i}.Port.{i}.Stats.",
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

// Schema for Device.Bridging.Bridge.{i}.STP.
export const Bridge_STP = {
    path: "Device.Bridging.Bridge.{i}.STP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "BridgePriority": dm_type.UINT | dm_type.WRITABLE,
        "HelloTime": dm_type.UINT | dm_type.WRITABLE,
        "MaxAge": dm_type.UINT | dm_type.WRITABLE,
        "ForwardingDelay": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Protocol": "",
        "BridgePriority": "32768",
        "HelloTime": "200",
        "MaxAge": "2000",
        "ForwardingDelay": "15"
    }
};

// Schema for Device.Bridging.Bridge.{i}.Port.{i}.
export const Bridge_Port = {
    path: "Device.Bridging.Bridge.{i}.Port.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        // "Status": dm_type.STRING,
        // "Alias": dm_type.STRING,
        // "Name": dm_type.STRING,
        // "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        // "ManagementPort": dm_type.BOOL | dm_type.WRITABLE,
        // "Type": dm_type.STRING | dm_type.WRITABLE,
        // "DefaultUserPriority": dm_type.UINT | dm_type.WRITABLE,
        // "PriorityRegeneration": dm_type.UINT | dm_type.WRITABLE,
        "PortState": dm_type.STRING,
        "PVID": dm_type.INT | dm_type.WRITABLE,
        // "TPID": dm_type.UINT | dm_type.WRITABLE,
        "AcceptableFrameTypes": dm_type.STRING | dm_type.WRITABLE,
        // "IngressFiltering": dm_type.BOOL | dm_type.WRITABLE,
        // "ServiceAccessPrioritySelection": dm_type.BOOL | dm_type.WRITABLE,
        // "ServiceAccessPriorityTranslation": dm_type.UINT | dm_type.WRITABLE,
        // "PriorityTagging": dm_type.BOOL | dm_type.WRITABLE,
        // "PathCost": dm_type.UINT | dm_type.WRITABLE,
        // "Priority": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "ManagementPort": "false",
        "Type": "",
        "DefaultUserPriority": "0",
        "PriorityRegeneration": "[0,1,2,3,4,5,6,7]",
        "PortState": "Disabled",
        "PVID": "1",
        "TPID": "33024",
        "AcceptableFrameTypes": "AdmitAll",
        "IngressFiltering": "false",
        "ServiceAccessPrioritySelection": "false",
        "ServiceAccessPriorityTranslation": "[0,1,2,3,4,5,6,7]",
        "PriorityTagging": "false",
        "PathCost": "0",
        "Priority": "128"
    }
};

// Schema for Device.Bridging.
export const Bridging = {
    path: "Device.Bridging.",
    schema: {
        "MaxBridgeEntries": dm_type.UINT,
        "MaxDBridgeEntries": dm_type.UINT,
        "MaxQBridgeEntries": dm_type.UINT,
        "MaxVLANEntries": dm_type.UINT,
        "MaxProviderBridgeEntries": dm_type.UINT,
        "ProviderBridgeNumberOfEntries": dm_type.UINT,
        "MaxFilterEntries": dm_type.UINT,
        "BridgeNumberOfEntries": dm_type.UINT,
        "FilterNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MaxBridgeEntries": "0",
        "MaxDBridgeEntries": "0",
        "MaxQBridgeEntries": "0",
        "MaxVLANEntries": "0",
        "MaxProviderBridgeEntries": "0",
        "ProviderBridgeNumberOfEntries": "0",
        "MaxFilterEntries": "0",
        "BridgeNumberOfEntries": "0",
        "FilterNumberOfEntries": "0"
    }
};

// Schema for Device.Bridging.ProviderBridge.{i}.
export const ProviderBridge = {
    path: "Device.Bridging.ProviderBridge.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "SVLANcomponent": dm_type.STRING | dm_type.WRITABLE,
        "CVLANcomponents": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Type": "",
        "SVLANcomponent": "",
        "CVLANcomponents": "[]"
    }
};

// Schema for Device.Bridging.Bridge.{i}.VLAN.{i}.
export const Bridge_VLAN = {
    path: "Device.Bridging.Bridge.{i}.VLAN.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "VLANID": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Name": "",
        "VLANID": "0"
    }
};

// Schema for Device.Bridging.Bridge.{i}.VLANPort.{i}.
export const Bridge_VLANPort = {
    path: "Device.Bridging.Bridge.{i}.VLANPort.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "VLAN": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.STRING | dm_type.WRITABLE,
        "Untagged": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "VLAN": "",
        "Port": ""
    }
};

// Schema for Device.Bridging.Bridge.{i}.
export const Bridge = {
    path: "Device.Bridging.Bridge.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        // "Name": dm_type.STRING,
        "Standard": dm_type.STRING | dm_type.WRITABLE,
        // "AgingTime": dm_type.UINT | dm_type.WRITABLE,
        "PortNumberOfEntries": dm_type.UINT,
        // "VLANNumberOfEntries": dm_type.UINT,
        // "VLANPortNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Name": "",
        "Standard": "",
        "AgingTime": "300",
        "PortNumberOfEntries": "0",
        "VLANNumberOfEntries": "0",
        "VLANPortNumberOfEntries": "0"
    }
};

// Schema for Device.Bridging.Filter.{i}.
export const Filter = {
    path: "Device.Bridging.Filter.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Status": dm_type.STRING,
        "Bridge": dm_type.STRING | dm_type.WRITABLE,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "DHCPType": dm_type.STRING | dm_type.WRITABLE,
        "VLANIDFilter": dm_type.UINT | dm_type.WRITABLE,
        "EthertypeFilterList": dm_type.UINT | dm_type.WRITABLE,
        "EthertypeFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMACAddressFilterList": dm_type.STRING | dm_type.WRITABLE,
        "SourceMACAddressFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMACAddressFilterList": dm_type.STRING | dm_type.WRITABLE,
        "DestMACAddressFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMACFromVendorClassIDFilter": dm_type.STRING | dm_type.WRITABLE,
        "SourceMACFromVendorClassIDFilterv6": dm_type.HEXBIN | dm_type.WRITABLE,
        "SourceMACFromVendorClassIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMACFromVendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "DestMACFromVendorClassIDFilter": dm_type.STRING | dm_type.WRITABLE,
        "DestMACFromVendorClassIDFilterv6": dm_type.HEXBIN | dm_type.WRITABLE,
        "DestMACFromVendorClassIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMACFromVendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "SourceMACFromClientIDFilter": dm_type.HEXBIN | dm_type.WRITABLE,
        "SourceMACFromClientIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMACFromClientIDFilter": dm_type.HEXBIN | dm_type.WRITABLE,
        "DestMACFromClientIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMACFromUserClassIDFilter": dm_type.HEXBIN | dm_type.WRITABLE,
        "SourceMACFromUserClassIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMACFromUserClassIDFilter": dm_type.HEXBIN | dm_type.WRITABLE,
        "DestMACFromUserClassIDFilterExclude": dm_type.BOOL | dm_type.WRITABLE,
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
        "SourcePortExclude": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Status": "Disabled",
        "Bridge": "",
        "Order": "",
        "Interface": "",
        "DHCPType": "DHCPv4",
        "VLANIDFilter": "0",
        "EthertypeFilterList": "[]",
        "EthertypeFilterExclude": "true",
        "SourceMACAddressFilterList": "[]",
        "SourceMACAddressFilterExclude": "true",
        "DestMACAddressFilterList": "[]",
        "DestMACAddressFilterExclude": "true",
        "SourceMACFromVendorClassIDFilter": "",
        "SourceMACFromVendorClassIDFilterv6": "",
        "SourceMACFromVendorClassIDFilterExclude": "true",
        "SourceMACFromVendorClassIDMode": "Exact",
        "DestMACFromVendorClassIDFilter": "",
        "DestMACFromVendorClassIDFilterv6": "",
        "DestMACFromVendorClassIDFilterExclude": "true",
        "DestMACFromVendorClassIDMode": "Exact",
        "SourceMACFromClientIDFilter": "",
        "SourceMACFromClientIDFilterExclude": "true",
        "DestMACFromClientIDFilter": "",
        "DestMACFromClientIDFilterExclude": "true",
        "SourceMACFromUserClassIDFilter": "",
        "SourceMACFromUserClassIDFilterExclude": "true",
        "DestMACFromUserClassIDFilter": "",
        "DestMACFromUserClassIDFilterExclude": "true",
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
        "SourcePortExclude": "false"
    }
};
