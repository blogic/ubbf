'use strict';

// Auto-generated schema definitions for MoCA domain
// Generated from TR-181 specifications

// Schema for Device.MoCA.Interface.{i}.QoS.FlowStats.{i}.
export const QoS_FlowStats = {
    path: "Device.MoCA.Interface.{i}.QoS.FlowStats.{i}.",
    schema: {
        "FlowID": dm_type.STRING,
        "PacketDA": dm_type.STRING,
        "MaxRate": dm_type.UINT,
        "MaxBurstSize": dm_type.UINT,
        "LeaseTime": dm_type.UINT,
        "Tag": dm_type.UINT,
        "LeaseTimeLeft": dm_type.UINT,
        "FlowPackets": dm_type.STRING,
        "IngressGuid": dm_type.STRING,
        "EgressGuid": dm_type.STRING,
        "MaximumLatency": dm_type.UINT,
        "ShortTermAvgRatio": dm_type.UINT,
        "FlowPer": dm_type.UINT,
        "IngressClassify": dm_type.STRING,
        "VlanTag": dm_type.UINT,
        "DscpMoca": dm_type.UINT,
        "Dfid": dm_type.UINT
    },
    defaults: {
        "FlowID": "",
        "PacketDA": "",
        "MaxRate": "0",
        "MaxBurstSize": "0",
        "LeaseTime": "0",
        "Tag": "0",
        "LeaseTimeLeft": "0",
        "FlowPackets": "",
        "IngressGuid": "",
        "EgressGuid": "",
        "MaximumLatency": "0",
        "ShortTermAvgRatio": "0",
        "FlowPer": "0",
        "IngressClassify": "",
        "VlanTag": "0",
        "DscpMoca": "0",
        "Dfid": "0"
    }
};

// Schema for Device.MoCA.Interface.{i}.Sapm.{i}.
export const Interface_Sapm = {
    path: "Device.MoCA.Interface.{i}.Sapm.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Profile": dm_type.UINT | dm_type.WRITABLE,
        "Frequency": dm_type.UINT | dm_type.WRITABLE,
        "AggrRxPwrLevelThreshold": dm_type.UINT | dm_type.WRITABLE,
        "PhyMargin": dm_type.UINT | dm_type.WRITABLE,
        "Status": dm_type.STRING
    },
    defaults: {
        "Enable": "true",
        "Profile": "0",
        "Frequency": "0",
        "AggrRxPwrLevelThreshold": "0",
        "PhyMargin": "0",
        "Status": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.Bridge.{i}.
export const Interface_Bridge = {
    path: "Device.MoCA.Interface.{i}.Bridge.{i}.",
    schema: {
        "NodeIndex": dm_type.STRING,
        "MACAddresses": dm_type.STRING
    },
    defaults: {
        "NodeIndex": "",
        "MACAddresses": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.MoCA.Interface.{i}.Stats.",
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
        "RxCorrectedErrors": dm_type.STRING
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
        "RxCorrectedErrors": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.
export const Interface = {
    path: "Device.MoCA.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.UINT,
        "AccessControlNumberOfEntries": dm_type.UINT,
        "RlapmNumberOfEntries": dm_type.UINT,
        "SapmNumberOfEntries": dm_type.UINT,
        "MeshNumberOfEntries": dm_type.UINT,
        "BridgeNumberOfEntries": dm_type.UINT,
        "MeshScModNumberOfEntries": dm_type.UINT,
        "MACAddress": dm_type.STRING,
        "FirmwareVersion": dm_type.STRING,
        "MaxIngressBW": dm_type.STRING,
        "MaxEgressBW": dm_type.STRING,
        "HighestVersion": dm_type.STRING,
        "CurrentVersion": dm_type.STRING,
        "NetworkCoordinator": dm_type.STRING,
        "NodeID": dm_type.STRING,
        "MaxNodes": dm_type.BOOL,
        "NumNodes": dm_type.UINT,
        "PreferredNC": dm_type.BOOL | dm_type.WRITABLE,
        "BackupNC": dm_type.STRING,
        "PrivacyEnabledSetting": dm_type.BOOL | dm_type.WRITABLE,
        "PrivacyEnabled": dm_type.BOOL,
        "AccessControlEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PhyThreshold": dm_type.STRING | dm_type.WRITABLE,
        "PhyThresholdTrapEnable": dm_type.BOOL | dm_type.WRITABLE,
        "StatusChangeEnable": dm_type.BOOL | dm_type.WRITABLE,
        "NumNodesChangeEnable": dm_type.BOOL | dm_type.WRITABLE,
        "TpcTargetRateNper": dm_type.STRING | dm_type.WRITABLE,
        "Band": dm_type.STRING | dm_type.WRITABLE,
        "LastOperFreqUpdateEnable": dm_type.BOOL | dm_type.WRITABLE,
        "FreqCapabilityMask": dm_type.STRING,
        "FreqCurrentMaskSetting": dm_type.STRING | dm_type.WRITABLE,
        "FreqCurrentMask": dm_type.STRING,
        "CurrentOperFreq": dm_type.UINT,
        "LastOperFreq": dm_type.UINT | dm_type.WRITABLE,
        "TpcEnable": dm_type.BOOL | dm_type.WRITABLE,
        "KeyPassphrase": dm_type.STRING | dm_type.WRITABLE,
        "PerMode": dm_type.UINT | dm_type.WRITABLE,
        "TurboModeEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PolicingEnable": dm_type.BOOL | dm_type.WRITABLE,
        "TlpMin": dm_type.UINT | dm_type.WRITABLE,
        "TlpMax": dm_type.UINT | dm_type.WRITABLE,
        "RlapmEnable": dm_type.BOOL | dm_type.WRITABLE,
        "RlapmProfileSelect": dm_type.UINT | dm_type.WRITABLE,
        "SapmEnable": dm_type.BOOL | dm_type.WRITABLE,
        "SapmProfileSelect": dm_type.UINT | dm_type.WRITABLE,
        "PowerStateRequest": dm_type.STRING | dm_type.WRITABLE,
        "SeqNumMr": dm_type.UINT | dm_type.WRITABLE,
        "PowerStateTrapEnable": dm_type.BOOL | dm_type.WRITABLE,
        "LmoTrapEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PrimaryOffset": dm_type.INT | dm_type.WRITABLE,
        "SecondaryOffset": dm_type.INT | dm_type.WRITABLE,
        "BeaconPowerDistributed": dm_type.INT | dm_type.WRITABLE,
        "BeaconPowerLocal": dm_type.INT | dm_type.WRITABLE,
        "BeaconPowerMePie": dm_type.HEXBIN | dm_type.WRITABLE,
        "BeaconPowerMePieSend": dm_type.BOOL | dm_type.WRITABLE,
        "BeaconPowerNetConfig": dm_type.BOOL | dm_type.WRITABLE,
        "EnhancedPassword": dm_type.STRING | dm_type.WRITABLE,
        "FirstOffset": dm_type.INT | dm_type.WRITABLE,
        "HandoffToLowerVersionEnable": dm_type.BOOL | dm_type.WRITABLE,
        "MgntEntityNetIePayloadRespTimeout": dm_type.UINT | dm_type.WRITABLE,
        "MgntEntityNetIePayloadTx": dm_type.HEXBIN | dm_type.WRITABLE,
        "MpsPrivacyDown": dm_type.BOOL | dm_type.WRITABLE,
        "MpsPrivacyReceive": dm_type.BOOL | dm_type.WRITABLE,
        "MpsReset": dm_type.BOOL | dm_type.WRITABLE,
        "MpsTriggered": dm_type.BOOL | dm_type.WRITABLE,
        "MpsUnpairedTime": dm_type.UINT | dm_type.WRITABLE,
        "MpsWalkTime": dm_type.UINT | dm_type.WRITABLE,
        "NetworkJoin": dm_type.BOOL | dm_type.WRITABLE,
        "NetworkNameAdmissionRule": dm_type.STRING | dm_type.WRITABLE,
        "NetworkNameNcNn": dm_type.STRING | dm_type.WRITABLE,
        "NumChannels": dm_type.UINT | dm_type.WRITABLE,
        "Per25Mode": dm_type.UINT | dm_type.WRITABLE,
        "PrivacySupported": dm_type.STRING | dm_type.WRITABLE,
        "TrafficPermissionEthertype": dm_type.HEXBIN | dm_type.WRITABLE,
        "TrafficPermissionLink": dm_type.HEXBIN | dm_type.WRITABLE,
        "ConnectedNodesChangeTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "MgntEntityNetwIePayloadRecTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "MpsTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "NcPrivSupportedRecTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "NetworkNameRecTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "NodeDropTrapEn": dm_type.BOOL | dm_type.WRITABLE,
        "TxPowerLimit": dm_type.STRING | dm_type.WRITABLE,
        "PowerCntlPhyTarget": dm_type.STRING | dm_type.WRITABLE,
        "BeaconPowerLimit": dm_type.STRING | dm_type.WRITABLE,
        "NetworkTabooMask": dm_type.STRING,
        "NodeTabooMask": dm_type.STRING,
        "SupportedBands": dm_type.STRING,
        "TxBcastRate": dm_type.STRING,
        "TxBcastPowerReduction": dm_type.STRING,
        "QAM256Capable": dm_type.BOOL,
        "PacketAggregationCapability": dm_type.UINT,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT,
        "PasswordHash": dm_type.HEXBIN,
        "AggregationSize": dm_type.UINT,
        "AeNumber": dm_type.UINT,
        "SupportedIngressPqosFlows": dm_type.UINT,
        "SupportedEgressPqosFlows": dm_type.UINT,
        "PowerStateCap": dm_type.STRING,
        "AvbSupport": dm_type.BOOL,
        "ResetCount": dm_type.STRING,
        "LinkDownCount": dm_type.STRING,
        "LmoNodeID": dm_type.STRING,
        "NetworkState": dm_type.STRING,
        "PrimaryChannelOffset": dm_type.INT,
        "SecondaryChannelOffset": dm_type.INT,
        "ResetReason": dm_type.STRING,
        "NcVersion": dm_type.STRING,
        "LinkState": dm_type.HEXBIN,
        "ConnectedNodesInfo": dm_type.HEXBIN,
        "MgntEntityNetIePayloadRx": dm_type.HEXBIN,
        "Moca25PhyCapable": dm_type.BOOL,
        "MpsInitScanPayload": dm_type.HEXBIN,
        "MpsState": dm_type.BOOL,
        "NetworkNamePayload": dm_type.HEXBIN,
        "PrivacyNc": dm_type.STRING,
        "PowerStateResp": dm_type.BOOL,
        "PowerStateStatus": dm_type.STRING,
        "ConnectedNodesDropReason": dm_type.HEXBIN
    },
    defaults: {
        "Enable": "true",
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "AccessControlNumberOfEntries": "0",
        "RlapmNumberOfEntries": "0",
        "SapmNumberOfEntries": "0",
        "MeshNumberOfEntries": "0",
        "BridgeNumberOfEntries": "0",
        "MeshScModNumberOfEntries": "0",
        "MACAddress": "",
        "FirmwareVersion": "",
        "MaxIngressBW": "",
        "MaxEgressBW": "",
        "HighestVersion": "",
        "CurrentVersion": "",
        "NetworkCoordinator": "",
        "NodeID": "",
        "NumNodes": "0",
        "PreferredNC": "false",
        "BackupNC": "",
        "PrivacyEnabledSetting": "false",
        "AccessControlEnable": "false",
        "PhyThreshold": "123",
        "PhyThresholdTrapEnable": "false",
        "StatusChangeEnable": "false",
        "NumNodesChangeEnable": "false",
        "TpcTargetRateNper": "",
        "Band": "",
        "FreqCapabilityMask": "",
        "FreqCurrentMaskSetting": "",
        "FreqCurrentMask": "",
        "CurrentOperFreq": "0",
        "LastOperFreq": "0",
        "TpcEnable": "true",
        "KeyPassphrase": "",
        "PerMode": "0",
        "TurboModeEnable": "false",
        "PolicingEnable": "false",
        "TlpMin": "0",
        "TlpMax": "0",
        "RlapmProfileSelect": "0",
        "SapmProfileSelect": "0",
        "PowerStateRequest": "m0Active",
        "SeqNumMr": "0",
        "PowerStateTrapEnable": "false",
        "LmoTrapEnable": "false",
        "PrimaryOffset": "0",
        "SecondaryOffset": "0",
        "BeaconPowerDistributed": "0",
        "BeaconPowerLocal": "0",
        "EnhancedPassword": "",
        "FirstOffset": "0",
        "HandoffToLowerVersionEnable": "false",
        "MgntEntityNetIePayloadRespTimeout": "1000",
        "MpsPrivacyDown": "false",
        "MpsPrivacyReceive": "true",
        "MpsUnpairedTime": "300",
        "MpsWalkTime": "120",
        "NetworkNameAdmissionRule": "none",
        "NetworkNameNcNn": "",
        "NumChannels": "5",
        "Per25Mode": "0",
        "PrivacySupported": "[moca1Privacy,moca20Privacy,moca2EnhancedPrivacy]",
        "TrafficPermissionEthertype": "888E",
        "ConnectedNodesChangeTrapEn": "false",
        "MgntEntityNetwIePayloadRecTrapEn": "false",
        "MpsTrapEn": "false",
        "NcPrivSupportedRecTrapEn": "false",
        "NetworkNameRecTrapEn": "false",
        "NodeDropTrapEn": "false",
        "TxPowerLimit": "0",
        "PowerCntlPhyTarget": "630",
        "BeaconPowerLimit": "0",
        "NetworkTabooMask": "",
        "NodeTabooMask": "",
        "SupportedBands": "",
        "TxBcastRate": "",
        "TxBcastPowerReduction": "",
        "PacketAggregationCapability": "0",
        "AssociatedDeviceNumberOfEntries": "0",
        "AggregationSize": "0",
        "AeNumber": "0",
        "SupportedIngressPqosFlows": "0",
        "SupportedEgressPqosFlows": "0",
        "PowerStateCap": "",
        "ResetCount": "",
        "LinkDownCount": "",
        "LmoNodeID": "",
        "NetworkState": "",
        "PrimaryChannelOffset": "0",
        "SecondaryChannelOffset": "0",
        "ResetReason": "",
        "NcVersion": "",
        "PrivacyNc": "",
        "PowerStateStatus": ""
    }
};

// Schema for Device.MoCA.
export const MoCA = {
    path: "Device.MoCA.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.MoCA.Interface.{i}.AccessControl.{i}.
export const Interface_AccessControl = {
    path: "Device.MoCA.Interface.{i}.AccessControl.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "MACAddress": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.MoCA.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "NodeID": dm_type.STRING,
        "PreferredNC": dm_type.BOOL,
        "HighestVersion": dm_type.STRING,
        "PHYTxRate": dm_type.UINT,
        "PHYRxRate": dm_type.UINT,
        "TxPowerControlReduction": dm_type.STRING,
        "RxPowerLevel": dm_type.UINT,
        "TxBcastRate": dm_type.STRING,
        "RxBcastPowerLevel": dm_type.STRING,
        "TxPackets": dm_type.STRING,
        "TxDrops": dm_type.STRING,
        "RxPackets": dm_type.STRING,
        "RxCorrected": dm_type.STRING,
        "RxErroredAndMissedPackets": dm_type.STRING,
        "BondingCapable": dm_type.BOOL,
        "QAM256Capable": dm_type.BOOL,
        "PacketAggregationCapability": dm_type.UINT,
        "RxSNR": dm_type.STRING,
        "Active": dm_type.BOOL,
        "SupportedIngressPqosFlows": dm_type.UINT,
        "SupportedEgressPqosFlows": dm_type.UINT,
        "AggregationSize": dm_type.UINT,
        "AeNumber": dm_type.UINT,
        "PowerState": dm_type.STRING,
        "PowerStateCapability": dm_type.STRING,
        "PDelay": dm_type.INT,
        "EnhancedPrivacyCapable": dm_type.BOOL,
        "LinkType": dm_type.STRING,
        "Moca25PhyCapable": dm_type.BOOL,
        "RxPwrList": dm_type.STRING,
        "RxSNRList": dm_type.STRING,
        "TxPwrList": dm_type.STRING,
        "TxPwrReductionList": dm_type.STRING,
        "EgressNodeNumFlows": dm_type.UINT,
        "IngressNodeNumFlows": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "NodeID": "",
        "PreferredNC": "false",
        "HighestVersion": "",
        "PHYTxRate": "0",
        "PHYRxRate": "0",
        "TxPowerControlReduction": "",
        "RxPowerLevel": "0",
        "TxBcastRate": "",
        "RxBcastPowerLevel": "",
        "TxPackets": "",
        "TxDrops": "",
        "RxPackets": "",
        "RxCorrected": "",
        "RxErroredAndMissedPackets": "",
        "PacketAggregationCapability": "0",
        "RxSNR": "",
        "SupportedIngressPqosFlows": "0",
        "SupportedEgressPqosFlows": "0",
        "AggregationSize": "0",
        "AeNumber": "0",
        "PowerState": "",
        "PowerStateCapability": "",
        "PDelay": "0",
        "LinkType": "",
        "RxPwrList": "",
        "RxSNRList": "",
        "TxPwrList": "",
        "TxPwrReductionList": "",
        "EgressNodeNumFlows": "0",
        "IngressNodeNumFlows": "0"
    }
};

// Schema for Device.MoCA.Interface.{i}.MeshScMod.{i}.
export const Interface_MeshScMod = {
    path: "Device.MoCA.Interface.{i}.MeshScMod.{i}.",
    schema: {
        "TxNodeIndex": dm_type.STRING,
        "RxNodeIndex": dm_type.STRING,
        "ChannelIndex": dm_type.STRING,
        "Mod": dm_type.STRING,
        "Nper": dm_type.STRING,
        "Vlper": dm_type.STRING,
        "ModM25": dm_type.STRING
    },
    defaults: {
        "TxNodeIndex": "",
        "RxNodeIndex": "",
        "ChannelIndex": "",
        "Mod": "",
        "Nper": "",
        "Vlper": "",
        "ModM25": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.Mesh.{i}.
export const Interface_Mesh = {
    path: "Device.MoCA.Interface.{i}.Mesh.{i}.",
    schema: {
        "TxNodeIndex": dm_type.STRING,
        "RxNodeIndex": dm_type.STRING,
        "TxRate": dm_type.STRING,
        "TxRateNper": dm_type.STRING,
        "TxRateVlper": dm_type.STRING,
        "LinkType": dm_type.STRING,
        "Power": dm_type.HEXBIN,
        "PowerReduction": dm_type.HEXBIN,
        "RxSNR": dm_type.HEXBIN
    },
    defaults: {
        "TxNodeIndex": "",
        "RxNodeIndex": "",
        "TxRate": "",
        "TxRateNper": "",
        "TxRateVlper": "",
        "LinkType": ""
    }
};

// Schema for Device.MoCA.Interface.{i}.QoS.
export const Interface_QoS = {
    path: "Device.MoCA.Interface.{i}.QoS.",
    schema: {
        "EgressNumFlows": dm_type.UINT,
        "IngressNumFlows": dm_type.UINT,
        "FlowStatsNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "EgressNumFlows": "0",
        "IngressNumFlows": "0",
        "FlowStatsNumberOfEntries": "0"
    }
};

// Schema for Device.MoCA.Interface.{i}.Reset.
export const Interface_Reset = {
    path: "Device.MoCA.Interface.{i}.Reset.",
    schema: {
        "NodeMask": dm_type.HEXBIN | dm_type.WRITABLE,
        "StartTime": dm_type.UINT | dm_type.WRITABLE,
        "StatusTrapEnable": dm_type.BOOL | dm_type.WRITABLE,
        "NetworkTrapEnable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "StartTime": "0"
    }
};

// Schema for Device.MoCA.Interface.{i}.Rlapm.{i}.
export const Interface_Rlapm = {
    path: "Device.MoCA.Interface.{i}.Rlapm.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Profile": dm_type.UINT | dm_type.WRITABLE,
        "Frequency": dm_type.UINT | dm_type.WRITABLE,
        "GlobalAggrRxPwrLevel": dm_type.UINT | dm_type.WRITABLE,
        "PhyMargin": dm_type.UINT | dm_type.WRITABLE,
        "Status": dm_type.STRING
    },
    defaults: {
        "Enable": "true",
        "Profile": "0",
        "Frequency": "0",
        "GlobalAggrRxPwrLevel": "0",
        "PhyMargin": "0",
        "Status": ""
    }
};
