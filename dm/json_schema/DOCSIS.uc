'use strict';

// Auto-generated schema definitions for DOCSIS domain
// Generated from TR-181 specifications

// Schema for Device.DOCSIS.SpectrumAnalysis.Result.{i}.
export const SpectrumAnalysis_Result = {
    path: "Device.DOCSIS.SpectrumAnalysis.Result.{i}.",
    schema: {
        "Frequency": dm_type.INT,
        "AmplitudeData": dm_type.STRING,
        "TotalSegmentPower": dm_type.STRING
    },
    defaults: {
        "Frequency": "0",
        "AmplitudeData": ""
    }
};

// Schema for Device.DOCSIS.DownstreamChannel.{i}.
export const DownstreamChannel = {
    path: "Device.DOCSIS.DownstreamChannel.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "ID": dm_type.UINT,
        "Frequency": dm_type.INT,
        "Width": dm_type.INT,
        "Modulation": dm_type.STRING,
        "Interleave": dm_type.STRING,
        "Power": dm_type.STRING,
        "Annex": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "ID": "0",
        "Frequency": "0",
        "Width": "0",
        "Modulation": "",
        "Interleave": "",
        "Power": "",
        "Annex": ""
    }
};

// Schema for Device.DOCSIS.Upstream.{i}.
export const Upstream = {
    path: "Device.DOCSIS.Upstream.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MaxBitRate": dm_type.INT | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "CurrentBitRate": dm_type.UINT,
        "UpstreamChannelList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "CurrentBitRate": "0",
        "UpstreamChannelList": ""
    }
};

// Schema for Device.DOCSIS.DownstreamChannel.{i}.SignalQuality.
export const DownstreamChannel_SignalQuality = {
    path: "Device.DOCSIS.DownstreamChannel.{i}.SignalQuality.",
    schema: {
        "SignalNoise": dm_type.STRING,
        "Microreflections": dm_type.INT,
        "EqualizationData": dm_type.STRING,
        "ExtUnerroreds": dm_type.STRING,
        "ExtCorrecteds": dm_type.STRING,
        "ExtUncorrectables": dm_type.STRING
    },
    defaults: {
        "Microreflections": "0",
        "EqualizationData": "",
        "ExtUnerroreds": "",
        "ExtCorrecteds": "",
        "ExtUncorrectables": ""
    }
};

// Schema for Device.DOCSIS.Upstream.{i}.Stats.
export const Upstream_Stats = {
    path: "Device.DOCSIS.Upstream.{i}.Stats.",
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

// Schema for Device.DOCSIS.Downstream.{i}.Stats.
export const Downstream_Stats = {
    path: "Device.DOCSIS.Downstream.{i}.Stats.",
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

// Schema for Device.DOCSIS.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.DOCSIS.Interface.{i}.Stats.",
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

// Schema for Device.DOCSIS.
export const DOCSIS = {
    path: "Device.DOCSIS.",
    schema: {
        "CapabilitiesReq": dm_type.STRING,
        "CapabilitiesRsp": dm_type.STRING,
        "DownstreamChannelNumberOfEntries": dm_type.UINT,
        "UpstreamChannelNumberOfEntries": dm_type.UINT,
        "DownstreamNumberOfEntries": dm_type.UINT,
        "UpstreamNumberOfEntries": dm_type.UINT,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CapabilitiesReq": "",
        "CapabilitiesRsp": "",
        "DownstreamChannelNumberOfEntries": "0",
        "UpstreamChannelNumberOfEntries": "0",
        "DownstreamNumberOfEntries": "0",
        "UpstreamNumberOfEntries": "0",
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.DOCSIS.UpstreamChannel.{i}.Status.
export const UpstreamChannel_Status = {
    path: "Device.DOCSIS.UpstreamChannel.{i}.Status.",
    schema: {
        "TxPower": dm_type.STRING,
        "T3Timeouts": dm_type.STRING,
        "T4Timeouts": dm_type.STRING,
        "RangingAborteds": dm_type.STRING,
        "ModulationType": dm_type.STRING,
        "EqData": dm_type.STRING,
        "T3Exceededs": dm_type.STRING,
        "IsMuted": dm_type.BOOL,
        "RangingStatus": dm_type.STRING
    },
    defaults: {
        "T3Timeouts": "",
        "T4Timeouts": "",
        "RangingAborteds": "",
        "ModulationType": "",
        "EqData": "",
        "T3Exceededs": "",
        "RangingStatus": ""
    }
};

// Schema for Device.DOCSIS.Interface.{i}.ConnectivityStatus.
export const Interface_ConnectivityStatus = {
    path: "Device.DOCSIS.Interface.{i}.ConnectivityStatus.",
    schema: {
        "Value": dm_type.STRING,
        "StatusCode": dm_type.STRING,
        "Resets": dm_type.STRING,
        "LostSyncs": dm_type.STRING,
        "InvalidMaps": dm_type.STRING,
        "InvalidUcds": dm_type.STRING,
        "InvalidRangingRsps": dm_type.STRING,
        "InvalidRegRsps": dm_type.STRING,
        "T1Timeouts": dm_type.STRING,
        "T2Timeouts": dm_type.STRING
    },
    defaults: {
        "Value": "",
        "StatusCode": "",
        "Resets": "",
        "LostSyncs": "",
        "InvalidMaps": "",
        "InvalidUcds": "",
        "InvalidRangingRsps": "",
        "InvalidRegRsps": "",
        "T1Timeouts": "",
        "T2Timeouts": ""
    }
};

// Schema for Device.DOCSIS.SpectrumAnalysis.
export const SpectrumAnalysis = {
    path: "Device.DOCSIS.SpectrumAnalysis.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InactivityTimeout": dm_type.INT | dm_type.WRITABLE,
        "FirstSegmentCenterFrequency": dm_type.UINT | dm_type.WRITABLE,
        "LastSegmentCenterFrequency": dm_type.UINT | dm_type.WRITABLE,
        "SegmentFrequencySpan": dm_type.UINT | dm_type.WRITABLE,
        "NumBinsPerSegment": dm_type.UINT | dm_type.WRITABLE,
        "EquivalentNoiseBandwidth": dm_type.UINT | dm_type.WRITABLE,
        "WindowFunction": dm_type.STRING | dm_type.WRITABLE,
        "NumberOfAverages": dm_type.UINT | dm_type.WRITABLE,
        "ResultNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "InactivityTimeout": "300",
        "FirstSegmentCenterFrequency": "93000000",
        "LastSegmentCenterFrequency": "993000000",
        "SegmentFrequencySpan": "7500000",
        "NumBinsPerSegment": "256",
        "EquivalentNoiseBandwidth": "150",
        "WindowFunction": "",
        "NumberOfAverages": "1",
        "ResultNumberOfEntries": "0"
    }
};

// Schema for Device.DOCSIS.Interface.{i}.
export const Interface = {
    path: "Device.DOCSIS.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MACAddress": dm_type.STRING,
        "CMTSAddress": dm_type.STRING,
        "Capabilities": dm_type.STRING,
        "FirmwareVersion": dm_type.STRING,
        "DOCSISVersion": dm_type.STRING,
        "MdCfgIpProvMode": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MACAddress": "",
        "CMTSAddress": "",
        "Capabilities": "",
        "FirmwareVersion": "",
        "DOCSISVersion": "",
        "MdCfgIpProvMode": ""
    }
};

// Schema for Device.DOCSIS.Downstream.{i}.
export const Downstream = {
    path: "Device.DOCSIS.Downstream.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MaxBitRate": dm_type.INT | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "CurrentBitRate": dm_type.UINT,
        "DownstreamChannelList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "CurrentBitRate": "0",
        "DownstreamChannelList": ""
    }
};

// Schema for Device.DOCSIS.UpstreamChannel.{i}.
export const UpstreamChannel = {
    path: "Device.DOCSIS.UpstreamChannel.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "ID": dm_type.INT,
        "Frequency": dm_type.INT,
        "Width": dm_type.INT,
        "SlotSize": dm_type.UINT,
        "TxTimingOffset": dm_type.UINT,
        "RangingBackoffStart": dm_type.INT,
        "RangingBackoffEnd": dm_type.INT,
        "TxBackoffStart": dm_type.INT,
        "TxBackoffEnd": dm_type.INT
    },
    defaults: {
        "Alias": "",
        "ID": "0",
        "Frequency": "0",
        "Width": "0",
        "SlotSize": "0",
        "TxTimingOffset": "0",
        "RangingBackoffStart": "0",
        "RangingBackoffEnd": "0",
        "TxBackoffStart": "0",
        "TxBackoffEnd": "0"
    }
};

// Schema for Device.DOCSIS.DownstreamChannel.{i}.SignalQualityExt.
export const DownstreamChannel_SignalQualityExt = {
    path: "Device.DOCSIS.DownstreamChannel.{i}.SignalQualityExt.",
    schema: {
        "RxMER": dm_type.STRING,
        "RxMerSamples": dm_type.UINT,
        "FbeNormalizationCoefficient": dm_type.INT
    },
    defaults: {
        "RxMerSamples": "0",
        "FbeNormalizationCoefficient": "0"
    }
};
