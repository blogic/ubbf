'use strict';

// Auto-generated schema definitions for Thread domain
// Generated from TR-181 specifications

// Schema for Device.Thread.MLE.{i}.AssociatedNode.{i}.Route.{i}.
export const AssociatedNode_Route = {
    path: "Device.Thread.MLE.{i}.AssociatedNode.{i}.Route.{i}.",
    schema: {
        "ID": dm_type.UINT,
        "PathCost": dm_type.UINT,
        "LQIn": dm_type.STRING,
        "LQOut": dm_type.STRING
    },
    defaults: {
        "ID": "0",
        "PathCost": "0",
        "LQIn": "",
        "LQOut": ""
    }
};

// Schema for Device.Thread.MLE.{i}.Dataset.{i}.
export const MLE_Dataset = {
    path: "Device.Thread.MLE.{i}.Dataset.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "DelayTimer": dm_type.UINT,
        "Channel": dm_type.UINT,
        "NetworkName": dm_type.STRING,
        "PanID": dm_type.HEXBIN,
        "ExtendedPanID": dm_type.HEXBIN,
        "MeshLocalPrefix": dm_type.STRING,
        "ChannelMask": dm_type.HEXBIN,
        "PSKc": dm_type.HEXBIN,
        "NetworkKey": dm_type.HEXBIN
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "DelayTimer": "0",
        "Channel": "0",
        "NetworkName": "",
        "MeshLocalPrefix": ""
    }
};

// Schema for Device.Thread.MLE.{i}.
export const MLE = {
    path: "Device.Thread.MLE.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "SupportedStandards": dm_type.STRING,
        "OperatingStandard": dm_type.STRING,
        "DatasetNumberOfEntries": dm_type.UINT,
        "AssociatedNodeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "SupportedStandards": "",
        "OperatingStandard": "",
        "DatasetNumberOfEntries": "0",
        "AssociatedNodeNumberOfEntries": "0"
    }
};

// Schema for Device.Thread.MLE.{i}.Stats.
export const MLE_Stats = {
    path: "Device.Thread.MLE.{i}.Stats.",
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

// Schema for Device.Thread.MLE.{i}.AssociatedNode.{i}.IPv6Address.{i}.
export const AssociatedNode_IPv6Address = {
    path: "Device.Thread.MLE.{i}.AssociatedNode.{i}.IPv6Address.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Type": dm_type.STRING,
        "IPAddress": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Type": "",
        "IPAddress": ""
    }
};

// Schema for Device.Thread.
export const Thread = {
    path: "Device.Thread.",
    schema: {
        "BorderRouterNumberOfEntries": dm_type.UINT,
        "RadioNumberOfEntries": dm_type.UINT,
        "MLENumberOfEntries": dm_type.UINT,
        "NodeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "BorderRouterNumberOfEntries": "0",
        "RadioNumberOfEntries": "0",
        "MLENumberOfEntries": "0",
        "NodeNumberOfEntries": "0"
    }
};

// Schema for Device.Thread.Radio.{i}.
export const Radio = {
    path: "Device.Thread.Radio.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MaxBitRate": dm_type.UINT,
        "Upstream": dm_type.BOOL,
        "TransmitPowerSupported": dm_type.INT,
        "TransmitPower": dm_type.INT | dm_type.WRITABLE,
        "HardwareVersion": dm_type.STRING,
        "FirmwareVersion": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "TransmitPowerSupported": "0",
        "TransmitPower": "0",
        "HardwareVersion": "",
        "FirmwareVersion": ""
    }
};

// Schema for Device.Thread.Radio.{i}.Stats.
export const Radio_Stats = {
    path: "Device.Thread.Radio.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": ""
    }
};

// Schema for Device.Thread.Node.{i}.
export const Node = {
    path: "Device.Thread.Node.{i}.",
    schema: {
        "ExtendedMAC": dm_type.HEXBIN,
        "Connected": dm_type.BOOL | dm_type.WRITABLE,
        "MLEReference": dm_type.STRING
    },
    defaults: {
        "MLEReference": ""
    }
};

// Schema for Device.Thread.MLE.{i}.AssociatedNode.{i}.
export const MLE_AssociatedNode = {
    path: "Device.Thread.MLE.{i}.AssociatedNode.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "LastContactTime": dm_type.DATETIME,
        "ExtendedMAC": dm_type.HEXBIN,
        "Rloc16": dm_type.UINT,
        "RoutingRole": dm_type.STRING,
        "Mode": dm_type.STRING,
        "RouteNumberOfEntries": dm_type.UINT,
        "NeighborNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Rloc16": "0",
        "RoutingRole": "",
        "Mode": "",
        "RouteNumberOfEntries": "0",
        "NeighborNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0"
    }
};

// Schema for Device.Thread.BorderRouter.{i}.
export const BorderRouter = {
    path: "Device.Thread.BorderRouter.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "BorderAgentID": dm_type.HEXBIN,
        "MLEReference": dm_type.STRING | dm_type.WRITABLE,
        "RoutingRef": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "MLEReference": "",
        "RoutingRef": ""
    }
};

// Schema for Device.Thread.MLE.{i}.AssociatedNode.{i}.Neighbor.{i}.
export const AssociatedNode_Neighbor = {
    path: "Device.Thread.MLE.{i}.AssociatedNode.{i}.Neighbor.{i}.",
    schema: {
        "NodeReference": dm_type.STRING,
        "AvgRSSI": dm_type.UINT
    },
    defaults: {
        "NodeReference": "",
        "AvgRSSI": "0"
    }
};

// Schema for Device.Thread.MLE.{i}.LeaderData.
export const MLE_LeaderData = {
    path: "Device.Thread.MLE.{i}.LeaderData.",
    schema: {
        "DataVersion": dm_type.UINT,
        "LeaderRouterID": dm_type.UINT,
        "PartitionID": dm_type.UINT,
        "StableDataVersion": dm_type.UINT,
        "Weighting": dm_type.UINT
    },
    defaults: {
        "DataVersion": "0",
        "LeaderRouterID": "0",
        "PartitionID": "0",
        "StableDataVersion": "0",
        "Weighting": "0"
    }
};

// Schema for Device.Thread.MLE.{i}.Dataset.{i}.SecurityPolicy.
export const Dataset_SecurityPolicy = {
    path: "Device.Thread.MLE.{i}.Dataset.{i}.SecurityPolicy.",
    schema: {
        "RotationTime": dm_type.UINT,
        "Flags": dm_type.STRING
    },
    defaults: {
        "RotationTime": "0",
        "Flags": ""
    }
};
