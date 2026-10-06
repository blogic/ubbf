'use strict';

// Auto-generated schema definitions for ZigBee domain
// Generated from TR-181 specifications

// Schema for Device.ZigBee.Interface.{i}.
export const Interface = {
    path: "Device.ZigBee.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.UINT,
        "IEEEAddress": dm_type.STRING,
        "NetworkAddress": dm_type.STRING,
        "ZDOReference": dm_type.STRING,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "IEEEAddress": "",
        "NetworkAddress": "",
        "ZDOReference": "",
        "AssociatedDeviceNumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.NodeDescriptor.
export const ZDO_NodeDescriptor = {
    path: "Device.ZigBee.ZDO.{i}.NodeDescriptor.",
    schema: {
        "LogicalType": dm_type.STRING,
        "ComplexDescriptorSupported": dm_type.BOOL,
        "UserDescriptorSupported": dm_type.BOOL,
        "FrequencyBand": dm_type.STRING,
        "MACCapability": dm_type.STRING,
        "ManufactureCode": dm_type.UINT,
        "MaximumBufferSize": dm_type.UINT,
        "MaximumIncomingTransferSize": dm_type.UINT,
        "MaximumOutgoingTransferSize": dm_type.UINT,
        "ServerMask": dm_type.STRING,
        "DescriptorCapability": dm_type.STRING
    },
    defaults: {
        "LogicalType": "",
        "FrequencyBand": "",
        "MACCapability": "",
        "ManufactureCode": "0",
        "MaximumBufferSize": "0",
        "MaximumIncomingTransferSize": "0",
        "MaximumOutgoingTransferSize": "0",
        "ServerMask": "",
        "DescriptorCapability": ""
    }
};

// Schema for Device.ZigBee.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.ZigBee.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "IEEEAddress": dm_type.STRING,
        "NetworkAddress": dm_type.STRING,
        "Active": dm_type.BOOL,
        "ZDOReference": dm_type.STRING
    },
    defaults: {
        "IEEEAddress": "",
        "NetworkAddress": "",
        "ZDOReference": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.Network.
export const ZDO_Network = {
    path: "Device.ZigBee.ZDO.{i}.Network.",
    schema: {
        "NeighborNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "NeighborNumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.ZigBee.Interface.{i}.Stats.",
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
        "UnknownPacketsReceived": dm_type.STRING
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
        "UnknownPacketsReceived": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.PowerDescriptor.
export const ZDO_PowerDescriptor = {
    path: "Device.ZigBee.ZDO.{i}.PowerDescriptor.",
    schema: {
        "CurrentPowerMode": dm_type.STRING,
        "AvailablePowerSource": dm_type.STRING,
        "CurrentPowerSource": dm_type.STRING,
        "CurrentPowerSourceLevel": dm_type.STRING
    },
    defaults: {
        "CurrentPowerMode": "",
        "AvailablePowerSource": "",
        "CurrentPowerSource": "",
        "CurrentPowerSourceLevel": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.UserDescriptor.
export const ZDO_UserDescriptor = {
    path: "Device.ZigBee.ZDO.{i}.UserDescriptor.",
    schema: {
        "DescriptorAvailable": dm_type.BOOL,
        "Description": dm_type.STRING
    },
    defaults: {
        "Description": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.ComplexDescriptor.
export const ZDO_ComplexDescriptor = {
    path: "Device.ZigBee.ZDO.{i}.ComplexDescriptor.",
    schema: {
        "DescriptorAvailable": dm_type.BOOL,
        "Language": dm_type.STRING,
        "CharacterSet": dm_type.STRING,
        "ManufacturerName": dm_type.STRING,
        "ModelName": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "DeviceURL": dm_type.STRING,
        "Icon": dm_type.HEXBIN,
        "IconURL": dm_type.STRING
    },
    defaults: {
        "Language": "",
        "CharacterSet": "",
        "ManufacturerName": "",
        "ModelName": "",
        "SerialNumber": "",
        "DeviceURL": "",
        "IconURL": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.NodeManager.
export const ZDO_NodeManager = {
    path: "Device.ZigBee.ZDO.{i}.NodeManager.",
    schema: {
        "RoutingTableNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "RoutingTableNumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.
export const ZDO = {
    path: "Device.ZigBee.ZDO.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "IEEEAddress": dm_type.STRING,
        "NetworkAddress": dm_type.STRING,
        "BindingTableNumberOfEntries": dm_type.UINT,
        "GroupNumberOfEntries": dm_type.UINT,
        "ApplicationEndpointNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "IEEEAddress": "",
        "NetworkAddress": "",
        "BindingTableNumberOfEntries": "0",
        "GroupNumberOfEntries": "0",
        "ApplicationEndpointNumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.ApplicationEndpoint.{i}.
export const ZDO_ApplicationEndpoint = {
    path: "Device.ZigBee.ZDO.{i}.ApplicationEndpoint.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "EndpointId": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "EndpointId": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.Group.{i}.
export const ZDO_Group = {
    path: "Device.ZigBee.ZDO.{i}.Group.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "GroupId": dm_type.STRING | dm_type.WRITABLE,
        "EndpointList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "GroupId": "",
        "EndpointList": ""
    }
};

// Schema for Device.ZigBee.Discovery.AreaNetwork.{i}.
export const Discovery_AreaNetwork = {
    path: "Device.ZigBee.Discovery.AreaNetwork.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "LastUpdate": dm_type.DATETIME,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Coordinator": dm_type.STRING | dm_type.WRITABLE,
        "ZDOReference": dm_type.STRING,
        "ZDOList": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Coordinator": "",
        "ZDOReference": "",
        "ZDOList": ""
    }
};

// Schema for Device.ZigBee.Discovery.
export const Discovery = {
    path: "Device.ZigBee.Discovery.",
    schema: {
        "AreaNetworkNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "AreaNetworkNumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.Binding.{i}.
export const ZDO_Binding = {
    path: "Device.ZigBee.ZDO.{i}.Binding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "SourceEndpoint": dm_type.UINT | dm_type.WRITABLE,
        "SourceAddress": dm_type.STRING | dm_type.WRITABLE,
        "ClusterId": dm_type.UINT | dm_type.WRITABLE,
        "DestinationAddressMode": dm_type.STRING | dm_type.WRITABLE,
        "DestinationEndpoint": dm_type.UINT | dm_type.WRITABLE,
        "IEEEDestinationAddress": dm_type.STRING | dm_type.WRITABLE,
        "GroupDestinationAddress": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "SourceEndpoint": "0",
        "SourceAddress": "",
        "ClusterId": "0",
        "DestinationAddressMode": "",
        "DestinationEndpoint": "0",
        "IEEEDestinationAddress": "",
        "GroupDestinationAddress": ""
    }
};

// Schema for Device.ZigBee.ZDO.{i}.NodeManager.RoutingTable.{i}.
export const NodeManager_RoutingTable = {
    path: "Device.ZigBee.ZDO.{i}.NodeManager.RoutingTable.{i}.",
    schema: {
        "DestinationAddress": dm_type.STRING,
        "NextHopAddress": dm_type.STRING,
        "Status": dm_type.STRING,
        "MemoryConstrained": dm_type.BOOL,
        "ManyToOne": dm_type.BOOL,
        "RouteRecordRequired": dm_type.BOOL
    },
    defaults: {
        "DestinationAddress": "",
        "NextHopAddress": "",
        "Status": ""
    }
};

// Schema for Device.ZigBee.
export const ZigBee = {
    path: "Device.ZigBee.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT,
        "ZDONumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0",
        "ZDONumberOfEntries": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.ApplicationEndpoint.{i}.SimpleDescriptor.
export const ApplicationEndpoint_SimpleDescriptor = {
    path: "Device.ZigBee.ZDO.{i}.ApplicationEndpoint.{i}.SimpleDescriptor.",
    schema: {
        "ProfileId": dm_type.UINT | dm_type.WRITABLE,
        "DeviceId": dm_type.UINT,
        "DeviceVersion": dm_type.UINT,
        "InputClusterList": dm_type.UINT | dm_type.WRITABLE,
        "OutputClusterList": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "ProfileId": "0",
        "DeviceId": "0",
        "DeviceVersion": "0",
        "InputClusterList": "0",
        "OutputClusterList": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.Security.
export const ZDO_Security = {
    path: "Device.ZigBee.ZDO.{i}.Security.",
    schema: {
        "TrustCenterAddress": dm_type.STRING,
        "SecurityLevel": dm_type.STRING,
        "TimeOutPeriod": dm_type.UINT
    },
    defaults: {
        "TrustCenterAddress": "",
        "SecurityLevel": "",
        "TimeOutPeriod": "0"
    }
};

// Schema for Device.ZigBee.ZDO.{i}.Network.Neighbor.{i}.
export const Network_Neighbor = {
    path: "Device.ZigBee.ZDO.{i}.Network.Neighbor.{i}.",
    schema: {
        "Neighbor": dm_type.STRING,
        "LQI": dm_type.UINT,
        "Relationship": dm_type.STRING,
        "PermitJoin": dm_type.STRING,
        "Depth": dm_type.UINT
    },
    defaults: {
        "Neighbor": "",
        "LQI": "0",
        "Relationship": "",
        "PermitJoin": "",
        "Depth": "0"
    }
};
