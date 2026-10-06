'use strict';

// Auto-generated schema definitions for IEEE1905 domain
// Generated from TR-181 specifications

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.VendorProperties.{i}.
export const IEEE1905Device_VendorProperties = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.VendorProperties.{i}.",
    schema: {
        "MessageType": dm_type.HEXBIN,
        "OUI": dm_type.STRING,
        "Information": dm_type.HEXBIN
    },
    defaults: {
        "OUI": ""
    }
};

// Schema for Device.IEEE1905.AL.ForwardingTable.ForwardingRule.{i}.
export const ForwardingTable_ForwardingRule = {
    path: "Device.IEEE1905.AL.ForwardingTable.ForwardingRule.{i}.",
    schema: {
        "InterfaceList": dm_type.STRING | dm_type.WRITABLE,
        "MACDestinationAddress": dm_type.STRING | dm_type.WRITABLE,
        "MACDestinationAddressFlag": dm_type.BOOL | dm_type.WRITABLE,
        "MACSourceAddress": dm_type.STRING | dm_type.WRITABLE,
        "MACSourceAddressFlag": dm_type.BOOL | dm_type.WRITABLE,
        "EtherType": dm_type.UINT | dm_type.WRITABLE,
        "EtherTypeFlag": dm_type.BOOL | dm_type.WRITABLE,
        "Vid": dm_type.UINT | dm_type.WRITABLE,
        "VidFlag": dm_type.BOOL | dm_type.WRITABLE,
        "PCP": dm_type.UINT | dm_type.WRITABLE,
        "PCPFlag": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "InterfaceList": "[]",
        "MACDestinationAddress": "",
        "MACDestinationAddressFlag": "false",
        "MACSourceAddress": "",
        "MACSourceAddressFlag": "false",
        "EtherType": "0",
        "EtherTypeFlag": "false",
        "Vid": "0",
        "VidFlag": "false",
        "PCP": "0",
        "PCPFlag": "false"
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.Link.{i}.Metric.
export const Link_Metric = {
    path: "Device.IEEE1905.AL.Interface.{i}.Link.{i}.Metric.",
    schema: {
        "IEEE802dot1Bridge": dm_type.BOOL,
        "PacketErrors": dm_type.STRING,
        "PacketErrorsReceived": dm_type.STRING,
        "TransmittedPackets": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "MACThroughputCapacity": dm_type.UINT,
        "LinkAvailability": dm_type.UINT,
        "PHYRate": dm_type.UINT,
        "RSSI": dm_type.UINT
    },
    defaults: {
        "PacketErrors": "",
        "PacketErrorsReceived": "",
        "TransmittedPackets": "",
        "PacketsReceived": "",
        "MACThroughputCapacity": "0",
        "LinkAvailability": "0",
        "PHYRate": "0",
        "RSSI": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.NonIEEE1905Neighbor.{i}.
export const IEEE1905Device_NonIEEE1905Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.NonIEEE1905Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborInterfaceId": dm_type.STRING
    },
    defaults: {
        "LocalInterface": "",
        "NeighborInterfaceId": ""
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.VendorProperties.{i}.
export const Interface_VendorProperties = {
    path: "Device.IEEE1905.AL.Interface.{i}.VendorProperties.{i}.",
    schema: {
        "OUI": dm_type.STRING,
        "Information": dm_type.HEXBIN
    },
    defaults: {
        "OUI": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv4Address.{i}.
export const IEEE1905Device_IPv4Address = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv4Address.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "IPv4Address": dm_type.STRING,
        "IPv4AddressType": dm_type.STRING,
        "DHCPServer": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "IPv4Address": "",
        "IPv4AddressType": "",
        "DHCPServer": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.BridgingTuple.{i}.
export const IEEE1905Device_BridgingTuple = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.BridgingTuple.{i}.",
    schema: {
        "InterfaceList": dm_type.STRING
    },
    defaults: {
        "InterfaceList": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv6Address.{i}.
export const IEEE1905Device_IPv6Address = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv6Address.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "IPv6Address": dm_type.STRING,
        "IPv6AddressType": dm_type.STRING,
        "IPv6AddressOrigin": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "IPv6Address": "",
        "IPv6AddressType": "",
        "IPv6AddressOrigin": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.
export const AL_NetworkTopology = {
    path: "Device.IEEE1905.AL.NetworkTopology.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "MaxChangeLogEntries": dm_type.UINT | dm_type.WRITABLE,
        "LastChange": dm_type.STRING,
        "IEEE1905DeviceNumberOfEntries": dm_type.UINT,
        "ChangeLogNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "MaxChangeLogEntries": "0",
        "LastChange": "",
        "IEEE1905DeviceNumberOfEntries": "0",
        "ChangeLogNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.Link.{i}.
export const Interface_Link = {
    path: "Device.IEEE1905.AL.Interface.{i}.Link.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "IEEE1905Id": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING
    },
    defaults: {
        "InterfaceId": "",
        "IEEE1905Id": "",
        "MediaType": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.Interface.{i}.
export const IEEE1905Device_Interface = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.Interface.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "PowerState": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING,
        "NetworkMembership": dm_type.STRING,
        "Role": dm_type.STRING,
        "APChannelBand": dm_type.HEXBIN,
        "FrequencyIndex1": dm_type.HEXBIN,
        "FrequencyIndex2": dm_type.HEXBIN
    },
    defaults: {
        "InterfaceId": "",
        "MediaType": "",
        "PowerState": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": "",
        "NetworkMembership": "",
        "Role": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.ChangeLog.{i}.
export const NetworkTopology_ChangeLog = {
    path: "Device.IEEE1905.AL.NetworkTopology.ChangeLog.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "EventType": dm_type.STRING,
        "ReporterDeviceId": dm_type.STRING,
        "ReporterInterfaceId": dm_type.STRING,
        "NeighborType": dm_type.STRING,
        "NeighborId": dm_type.STRING
    },
    defaults: {
        "EventType": "",
        "ReporterDeviceId": "",
        "ReporterInterfaceId": "",
        "NeighborType": "",
        "NeighborId": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.Metric.{i}.
export const IEEE1905Neighbor_Metric = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.Metric.{i}.",
    schema: {
        "NeighborMACAddress": dm_type.STRING,
        "IEEE802dot1Bridge": dm_type.BOOL,
        "PacketErrors": dm_type.STRING,
        "PacketErrorsReceived": dm_type.STRING,
        "TransmittedPackets": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "MACThroughputCapacity": dm_type.UINT,
        "LinkAvailability": dm_type.UINT,
        "PHYRate": dm_type.UINT,
        "RSSI": dm_type.UINT
    },
    defaults: {
        "NeighborMACAddress": "",
        "PacketErrors": "",
        "PacketErrorsReceived": "",
        "TransmittedPackets": "",
        "PacketsReceived": "",
        "MACThroughputCapacity": "0",
        "LinkAvailability": "0",
        "PHYRate": "0",
        "RSSI": "0"
    }
};

// Schema for Device.IEEE1905.AL.ForwardingTable.
export const AL_ForwardingTable = {
    path: "Device.IEEE1905.AL.ForwardingTable.",
    schema: {
        "SetForwardingEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "ForwardingRuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ForwardingRuleNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.
export const NetworkTopology_IEEE1905Device = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.",
    schema: {
        "IEEE1905Id": dm_type.STRING,
        "Version": dm_type.STRING,
        "RegistrarFreqBand": dm_type.STRING,
        "FriendlyName": dm_type.STRING,
        "ManufacturerName": dm_type.STRING,
        "ManufacturerModel": dm_type.STRING,
        "ControlURL": dm_type.STRING,
        "AssocWiFiNetworkDeviceRef": dm_type.STRING,
        "VendorPropertiesNumberOfEntries": dm_type.UINT,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT,
        "InterfaceNumberOfEntries": dm_type.UINT,
        "NonIEEE1905NeighborNumberOfEntries": dm_type.UINT,
        "IEEE1905NeighborNumberOfEntries": dm_type.UINT,
        "L2NeighborNumberOfEntries": dm_type.UINT,
        "BridgingTupleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "IEEE1905Id": "",
        "Version": "",
        "RegistrarFreqBand": "",
        "FriendlyName": "",
        "ManufacturerName": "",
        "ManufacturerModel": "",
        "ControlURL": "",
        "AssocWiFiNetworkDeviceRef": "",
        "VendorPropertiesNumberOfEntries": "0",
        "IPv4AddressNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0",
        "InterfaceNumberOfEntries": "0",
        "NonIEEE1905NeighborNumberOfEntries": "0",
        "IEEE1905NeighborNumberOfEntries": "0",
        "L2NeighborNumberOfEntries": "0",
        "BridgingTupleNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.
export const IEEE1905Device_IEEE1905Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborDeviceId": dm_type.STRING,
        "MetricNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LocalInterface": "",
        "NeighborDeviceId": "",
        "MetricNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.Security.
export const AL_Security = {
    path: "Device.IEEE1905.AL.Security.",
    schema: {
        "SetupMethod": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "SetupMethod": "",
        "Password": ""
    }
};

// Schema for Device.IEEE1905.AL.NetworkingRegistrar.
export const AL_NetworkingRegistrar = {
    path: "Device.IEEE1905.AL.NetworkingRegistrar.",
    schema: {
        "Registrar2dot4": dm_type.STRING,
        "Registrar5": dm_type.STRING,
        "Registrar60": dm_type.STRING
    },
    defaults: {
        "Registrar2dot4": "",
        "Registrar5": "",
        "Registrar60": ""
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.
export const AL_Interface = {
    path: "Device.IEEE1905.AL.Interface.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "InterfaceStackReference": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING,
        "SetIntfPowerStateEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "PowerState": dm_type.STRING | dm_type.WRITABLE,
        "VendorPropertiesNumberOfEntries": dm_type.UINT,
        "LinkNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceId": "",
        "Status": "",
        "LastChange": "0",
        "LowerLayers": "",
        "InterfaceStackReference": "",
        "MediaType": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": "",
        "PowerState": "",
        "VendorPropertiesNumberOfEntries": "0",
        "LinkNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.
export const IEEE1905 = {
    path: "Device.IEEE1905.",
    schema: {
        "Version": dm_type.STRING
    },
    defaults: {
        "Version": ""
    }
};

// Schema for Device.IEEE1905.AL.
export const AL = {
    path: "Device.IEEE1905.AL.",
    schema: {
        "IEEE1905Id": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "RegistrarFreqBand": dm_type.STRING,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "IEEE1905Id": "",
        "Status": "",
        "LastChange": "0",
        "LowerLayers": "",
        "RegistrarFreqBand": "",
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.L2Neighbor.{i}.
export const IEEE1905Device_L2Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.L2Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborInterfaceId": dm_type.STRING,
        "BehindInterfaceIds": dm_type.STRING
    },
    defaults: {
        "LocalInterface": "",
        "NeighborInterfaceId": "",
        "BehindInterfaceIds": ""
    }
};
