'use strict';

// Schema for Device.QoS.Classification.{i}.
export const Classification = {
    path: "Device.QoS.Classification.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        // "Status": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        // "DHCPType": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        // "IPVersion": dm_type.INT | dm_type.WRITABLE,
        "DestIP": dm_type.STRING | dm_type.WRITABLE,
        "DestMask": dm_type.STRING | dm_type.WRITABLE,
        // "DestIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceIP": dm_type.STRING | dm_type.WRITABLE,
        "SourceMask": dm_type.STRING | dm_type.WRITABLE,
        // "SourceIPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "Protocol": dm_type.INT | dm_type.WRITABLE,
        // "ProtocolExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestPort": dm_type.INT | dm_type.WRITABLE,
        "DestPortRangeMax": dm_type.INT | dm_type.WRITABLE,
        // "DestPortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourcePort": dm_type.INT | dm_type.WRITABLE,
        "SourcePortRangeMax": dm_type.INT | dm_type.WRITABLE,
        // "SourcePortExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceMACAddress": dm_type.STRING | dm_type.WRITABLE,
        // "SourceMACMask": dm_type.STRING | dm_type.WRITABLE,
        // "SourceMACExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestMACAddress": dm_type.STRING | dm_type.WRITABLE,
        // "DestMACMask": dm_type.STRING | dm_type.WRITABLE,
        // "DestMACExclude": dm_type.BOOL | dm_type.WRITABLE,
        "Ethertype": dm_type.INT | dm_type.WRITABLE,
        // "EthertypeExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "SSAP": dm_type.INT | dm_type.WRITABLE,
        // "SSAPExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "DSAP": dm_type.INT | dm_type.WRITABLE,
        // "DSAPExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "LLCControl": dm_type.INT | dm_type.WRITABLE,
        // "LLCControlExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "SNAPOUI": dm_type.INT | dm_type.WRITABLE,
        // "SNAPOUIExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceVendorClassID": dm_type.STRING | dm_type.WRITABLE,
        // "SourceVendorClassIDv6": dm_type.HEXBIN | dm_type.WRITABLE,
        // "SourceVendorClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "SourceVendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "DestVendorClassID": dm_type.STRING | dm_type.WRITABLE,
        // "DestVendorClassIDv6": dm_type.HEXBIN | dm_type.WRITABLE,
        // "DestVendorClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "DestVendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "SourceClientID": dm_type.HEXBIN | dm_type.WRITABLE,
        // "SourceClientIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestClientID": dm_type.HEXBIN | dm_type.WRITABLE,
        // "DestClientIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceUserClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        // "SourceUserClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DestUserClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        // "DestUserClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "SourceVendorSpecificInfo": dm_type.HEXBIN | dm_type.WRITABLE,
        // "SourceVendorSpecificInfoExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "SourceVendorSpecificInfoEnterprise": dm_type.UINT | dm_type.WRITABLE,
        // "SourceVendorSpecificInfoSubOption": dm_type.INT | dm_type.WRITABLE,
        // "DestVendorSpecificInfo": dm_type.HEXBIN | dm_type.WRITABLE,
        // "DestVendorSpecificInfoExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "DestVendorSpecificInfoEnterprise": dm_type.UINT | dm_type.WRITABLE,
        // "DestVendorSpecificInfoSubOption": dm_type.INT | dm_type.WRITABLE,
        // "TCPACK": dm_type.BOOL | dm_type.WRITABLE,
        // "TCPACKExclude": dm_type.BOOL | dm_type.WRITABLE,
        "IPLengthMin": dm_type.UINT | dm_type.WRITABLE,
        "IPLengthMax": dm_type.UINT | dm_type.WRITABLE,
        // "IPLengthExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DSCPCheck": dm_type.INT | dm_type.WRITABLE,
        // "DSCPExclude": dm_type.BOOL | dm_type.WRITABLE,
        "DSCPMark": dm_type.INT | dm_type.WRITABLE,
        "EthernetPriorityCheck": dm_type.INT | dm_type.WRITABLE,
        // "EthernetPriorityExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "EthernetPriorityMark": dm_type.INT | dm_type.WRITABLE,
        // "InnerEthernetPriorityCheck": dm_type.INT | dm_type.WRITABLE,
        // "InnerEthernetPriorityExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "InnerEthernetPriorityMark": dm_type.INT | dm_type.WRITABLE,
        // "EthernetDEICheck": dm_type.INT | dm_type.WRITABLE,
        // "EthernetDEIExclude": dm_type.BOOL | dm_type.WRITABLE,
        "VLANIDCheck": dm_type.INT | dm_type.WRITABLE,
        // "VLANIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        // "OutOfBandInfo": dm_type.INT | dm_type.WRITABLE,
        "ForwardingPolicy": dm_type.UINT | dm_type.WRITABLE,
        "TrafficClass": dm_type.INT | dm_type.WRITABLE,
        "Policer": dm_type.STRING | dm_type.WRITABLE
        // "App": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Order": "",
        "Alias": "",
        "Interface": "",
        "AllInterfaces": "false",
        "DestIP": "",
        "DestMask": "",
        "SourceIP": "",
        "SourceMask": "",
        "Protocol": "-1",
        "DestPort": "-1",
        "DestPortRangeMax": "-1",
        "SourcePort": "-1",
        "SourcePortRangeMax": "-1",
        "SourceMACAddress": "",
        "DestMACAddress": "",
        "Ethertype": "-1",
        "SourceVendorClassID": "",
        "DestVendorClassID": "",
        "SourceClientID": "",
        "DestClientID": "",
        "SourceUserClassID": "",
        "DestUserClassID": "",
        "IPLengthMin": "0",
        "IPLengthMax": "0",
        "DSCPCheck": "-1",
        "DSCPMark": "-1",
        "EthernetPriorityCheck": "-1",
        "VLANIDCheck": "-1",
        "ForwardingPolicy": "0",
        "TrafficClass": "-1",
        "Policer": ""
    }
};

// Schema for Device.QoS.
export const QoS = {
    path: "Device.QoS.",
    schema: {
        "MaxClassificationEntries": dm_type.UINT,
        "ClassificationNumberOfEntries": dm_type.UINT,
        // "MaxAppEntries": dm_type.UINT,
        // "AppNumberOfEntries": dm_type.UINT,
        // "MaxFlowEntries": dm_type.UINT,
        // "FlowNumberOfEntries": dm_type.UINT,
        "MaxPolicerEntries": dm_type.UINT,
        "PolicerNumberOfEntries": dm_type.UINT,
        "MaxQueueEntries": dm_type.UINT,
        "QueueNumberOfEntries": dm_type.UINT,
        "QueueStatsNumberOfEntries": dm_type.UINT,
        "MaxShaperEntries": dm_type.UINT,
        "ShaperNumberOfEntries": dm_type.UINT
        // "MaxSchedulerEntries": dm_type.UINT,
        // "SchedulerNumberOfEntries": dm_type.UINT,
        // "DefaultForwardingPolicy": dm_type.UINT | dm_type.WRITABLE,
        // "DefaultTrafficClass": dm_type.UINT | dm_type.WRITABLE,
        // "DefaultPolicer": dm_type.STRING | dm_type.WRITABLE,
        // "DefaultQueue": dm_type.STRING | dm_type.WRITABLE,
        // "DefaultDSCPMark": dm_type.INT | dm_type.WRITABLE,
        // "DefaultEthernetPriorityMark": dm_type.INT | dm_type.WRITABLE,
        // "DefaultInnerEthernetPriorityMark": dm_type.INT | dm_type.WRITABLE,
        // "AvailableAppList": dm_type.STRING
    },
    defaults: {
        "MaxClassificationEntries": "0",
        "ClassificationNumberOfEntries": "0",
        "MaxPolicerEntries": "0",
        "PolicerNumberOfEntries": "0",
        "MaxQueueEntries": "0",
        "QueueNumberOfEntries": "0",
        "QueueStatsNumberOfEntries": "0",
        "MaxShaperEntries": "0",
        "ShaperNumberOfEntries": "0"
    }
};

// Schema for Device.QoS.Policer.{i}.
export const Policer = {
    path: "Device.QoS.Policer.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "CommittedRate": dm_type.ULONG | dm_type.WRITABLE,
        "CommittedBurstSize": dm_type.UINT | dm_type.WRITABLE,
        "ExcessBurstSize": dm_type.UINT | dm_type.WRITABLE,
        "PeakRate": dm_type.ULONG | dm_type.WRITABLE,
        "PeakBurstSize": dm_type.UINT | dm_type.WRITABLE,
        "MeterType": dm_type.STRING | dm_type.WRITABLE,
        "PossibleMeterTypes": dm_type.STRING
        // "ConformingAction": dm_type.STRING | dm_type.WRITABLE,
        // "PartialConformingAction": dm_type.STRING | dm_type.WRITABLE,
        // "NonConformingAction": dm_type.STRING | dm_type.WRITABLE,
        // "TotalCountedPackets": dm_type.UINT,
        // "TotalCountedBytes": dm_type.UINT,
        // "ConformingCountedPackets": dm_type.UINT,
        // "ConformingCountedBytes": dm_type.UINT,
        // "PartiallyConformingCountedPackets": dm_type.UINT,
        // "PartiallyConformingCountedBytes": dm_type.UINT,
        // "NonConformingCountedPackets": dm_type.UINT,
        // "NonConformingCountedBytes": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "CommittedRate": "0",
        "CommittedBurstSize": "0",
        "ExcessBurstSize": "0",
        "PeakRate": "0",
        "PeakBurstSize": "0",
        "MeterType": "SimpleTokenBucket",
        "PossibleMeterTypes": ""
    }
};

// Schema for Device.QoS.Shaper.{i}.
export const Shaper = {
    path: "Device.QoS.Shaper.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        // "Children": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "ShapingRate": dm_type.LONG | dm_type.WRITABLE,
        "ShapingBurstSize": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "ShapingRate": "-1",
        "ShapingBurstSize": "0"
    }
};

// Schema for Device.QoS.Queue.{i}.
export const Queue = {
    path: "Device.QoS.Queue.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        // "Children": dm_type.STRING | dm_type.WRITABLE,
        "TrafficClasses": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        // "AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        // "HardwareAssisted": dm_type.BOOL,
        // "BufferLength": dm_type.UINT,
        "Weight": dm_type.UINT | dm_type.WRITABLE,
        "Precedence": dm_type.UINT | dm_type.WRITABLE,
        // "REDThreshold": dm_type.UINT | dm_type.WRITABLE,
        // "REDPercentage": dm_type.UINT | dm_type.WRITABLE,
        // "DropAlgorithm": dm_type.STRING | dm_type.WRITABLE,
        "SchedulerAlgorithm": dm_type.STRING | dm_type.WRITABLE,
        "ShapingRate": dm_type.LONG | dm_type.WRITABLE,
        // "CurrentShapingRate": dm_type.LONG,
        // "AssuredRate": dm_type.LONG | dm_type.WRITABLE,
        // "CurrentAssuredRate": dm_type.LONG,
        "ShapingBurstSize": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "TrafficClasses": "[]",
        "Interface": "",
        "Weight": "0",
        "Precedence": "1",
        "SchedulerAlgorithm": "SP",
        "ShapingRate": "-1",
        "ShapingBurstSize": "0"
    }
};

// Schema for Device.QoS.QueueStats.{i}.
export const QueueStats = {
    path: "Device.QoS.QueueStats.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Queue": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "OutputPackets": dm_type.UINT,
        "OutputBytes": dm_type.UINT,
        "DroppedPackets": dm_type.UINT,
        "DroppedBytes": dm_type.UINT
        // "QueueOccupancyPackets": dm_type.UINT,
        // "QueueOccupancyPercentage": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Queue": "",
        "Interface": "",
        "OutputPackets": "0",
        "OutputBytes": "0",
        "DroppedPackets": "0",
        "DroppedBytes": "0"
    }
};
