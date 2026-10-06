'use strict';

// Auto-generated schema definitions for DSL domain
// Generated from TR-181 specifications

// Schema for Device.DSL.Line.{i}.Stats.CurrentDay.
export const Stats_CurrentDay = {
    path: "Device.DSL.Line.{i}.Stats.CurrentDay.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0"
    }
};

// Schema for Device.DSL.Line.{i}.TestParams.
export const Line_TestParams = {
    path: "Device.DSL.Line.{i}.TestParams.",
    schema: {
        "HLOGGds": dm_type.UINT,
        "HLOGGus": dm_type.UINT,
        "HLOGpsds": dm_type.STRING,
        "HLOGpsus": dm_type.STRING,
        "HLOGMTds": dm_type.UINT,
        "HLOGMTus": dm_type.UINT,
        "QLNGds": dm_type.UINT,
        "QLNGus": dm_type.UINT,
        "QLNpsds": dm_type.INT,
        "QLNpsus": dm_type.STRING,
        "QLNMTds": dm_type.UINT,
        "QLNMTus": dm_type.UINT,
        "SNRGds": dm_type.UINT,
        "SNRGus": dm_type.UINT,
        "SNRpsds": dm_type.INT,
        "SNRpsus": dm_type.STRING,
        "SNRMTds": dm_type.UINT,
        "SNRMTus": dm_type.UINT,
        "LATNds": dm_type.STRING,
        "LATNus": dm_type.STRING,
        "SATNds": dm_type.STRING,
        "SATNus": dm_type.STRING
    },
    defaults: {
        "HLOGGds": "0",
        "HLOGGus": "0",
        "HLOGpsds": "",
        "HLOGpsus": "",
        "HLOGMTds": "0",
        "HLOGMTus": "0",
        "QLNGds": "0",
        "QLNGus": "0",
        "QLNpsds": "0",
        "QLNpsus": "",
        "QLNMTds": "0",
        "QLNMTus": "0",
        "SNRGds": "0",
        "SNRGus": "0",
        "SNRpsds": "0",
        "SNRpsus": "",
        "SNRMTds": "0",
        "SNRMTus": "0",
        "LATNds": "",
        "LATNus": "",
        "SATNds": "",
        "SATNus": ""
    }
};

// Schema for Device.DSL.BondingGroup.{i}.Ethernet.Stats.
export const Ethernet_Stats = {
    path: "Device.DSL.BondingGroup.{i}.Ethernet.Stats.",
    schema: {
        "PAFErrors": dm_type.UINT,
        "PAFSmallFragments": dm_type.UINT,
        "PAFLargeFragments": dm_type.UINT,
        "PAFBadFragments": dm_type.UINT,
        "PAFLostFragments": dm_type.UINT,
        "PAFLateFragments": dm_type.UINT,
        "PAFLostStarts": dm_type.UINT,
        "PAFLostEnds": dm_type.UINT,
        "PAFOverflows": dm_type.UINT,
        "PauseFramesSent": dm_type.UINT,
        "CRCErrorsReceived": dm_type.UINT,
        "AlignmentErrorsReceived": dm_type.UINT,
        "ShortPacketsReceived": dm_type.UINT,
        "LongPacketsReceived": dm_type.UINT,
        "OverflowErrorsReceived": dm_type.UINT,
        "FramesDropped": dm_type.UINT
    },
    defaults: {
        "PAFErrors": "0",
        "PAFSmallFragments": "0",
        "PAFLargeFragments": "0",
        "PAFBadFragments": "0",
        "PAFLostFragments": "0",
        "PAFLateFragments": "0",
        "PAFLostStarts": "0",
        "PAFLostEnds": "0",
        "PAFOverflows": "0",
        "PauseFramesSent": "0",
        "CRCErrorsReceived": "0",
        "AlignmentErrorsReceived": "0",
        "ShortPacketsReceived": "0",
        "LongPacketsReceived": "0",
        "OverflowErrorsReceived": "0",
        "FramesDropped": "0"
    }
};

// Schema for Device.DSL.Channel.{i}.Stats.QuarterHour.
export const Stats_QuarterHour = {
    path: "Device.DSL.Channel.{i}.Stats.QuarterHour.",
    schema: {
        "XTURFECErrors": dm_type.UINT,
        "XTUCFECErrors": dm_type.UINT,
        "XTURHECErrors": dm_type.UINT,
        "XTUCHECErrors": dm_type.UINT,
        "XTURCRCErrors": dm_type.UINT,
        "XTUCCRCErrors": dm_type.UINT
    },
    defaults: {
        "XTURFECErrors": "0",
        "XTUCFECErrors": "0",
        "XTURHECErrors": "0",
        "XTUCHECErrors": "0",
        "XTURCRCErrors": "0",
        "XTUCCRCErrors": "0"
    }
};

// Schema for Device.DSL.Line.{i}.Stats.Total.
export const Stats_Total = {
    path: "Device.DSL.Line.{i}.Stats.Total.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0"
    }
};

// Schema for Device.DSL.Channel.{i}.Stats.Showtime.
export const Stats_Showtime = {
    path: "Device.DSL.Channel.{i}.Stats.Showtime.",
    schema: {
        "XTURFECErrors": dm_type.UINT,
        "XTUCFECErrors": dm_type.UINT,
        "XTURHECErrors": dm_type.UINT,
        "XTUCHECErrors": dm_type.UINT,
        "XTURCRCErrors": dm_type.UINT,
        "XTUCCRCErrors": dm_type.UINT
    },
    defaults: {
        "XTURFECErrors": "0",
        "XTUCFECErrors": "0",
        "XTURHECErrors": "0",
        "XTUCHECErrors": "0",
        "XTURCRCErrors": "0",
        "XTUCCRCErrors": "0"
    }
};

// Schema for Device.DSL.Line.{i}.DataGathering.
export const Line_DataGathering = {
    path: "Device.DSL.Line.{i}.DataGathering.",
    schema: {
        "LoggingDepthR": dm_type.UINT,
        "ActLoggingDepthReportingR": dm_type.UINT,
        "EventTraceBufferR": dm_type.STRING
    },
    defaults: {
        "LoggingDepthR": "0",
        "ActLoggingDepthReportingR": "0",
        "EventTraceBufferR": ""
    }
};

// Schema for Device.DSL.BondingGroup.{i}.BondedChannel.{i}.
export const BondingGroup_BondedChannel = {
    path: "Device.DSL.BondingGroup.{i}.BondedChannel.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Channel": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Channel": ""
    }
};

// Schema for Device.DSL.Line.{i}.Stats.
export const Line_Stats = {
    path: "Device.DSL.Line.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "TotalStart": dm_type.UINT,
        "ShowtimeStart": dm_type.UINT,
        "LastShowtimeStart": dm_type.UINT,
        "CurrentDayStart": dm_type.UINT,
        "QuarterHourStart": dm_type.UINT
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "TotalStart": "0",
        "ShowtimeStart": "0",
        "LastShowtimeStart": "0",
        "CurrentDayStart": "0",
        "QuarterHourStart": "0"
    }
};

// Schema for Device.DSL.Line.{i}.
export const Line = {
    path: "Device.DSL.Line.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "EnableDataGathering": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "FirmwareVersion": dm_type.STRING,
        "LinkStatus": dm_type.STRING,
        "StandardsSupported": dm_type.STRING,
        "XTSE": dm_type.HEXBIN,
        "StandardUsed": dm_type.STRING,
        "XTSUsed": dm_type.HEXBIN,
        "LineEncoding": dm_type.STRING,
        "AllowedProfiles": dm_type.STRING,
        "CurrentProfile": dm_type.STRING,
        "PowerManagementState": dm_type.STRING,
        "SuccessFailureCause": dm_type.UINT,
        "UPBOKLER": dm_type.UINT,
        "UPBOKLEPb": dm_type.UINT,
        "UPBOKLERPb": dm_type.UINT,
        "RXTHRSHds": dm_type.INT,
        "ACTRAMODEds": dm_type.UINT,
        "ACTRAMODEus": dm_type.UINT,
        "ACTINPROCds": dm_type.UINT,
        "ACTINPROCus": dm_type.UINT,
        "SNRMROCds": dm_type.UINT,
        "SNRMROCus": dm_type.UINT,
        "LastStateTransmittedDownstream": dm_type.UINT,
        "LastStateTransmittedUpstream": dm_type.UINT,
        "UPBOKLE": dm_type.UINT,
        "MREFPSDds": dm_type.BASE64,
        "MREFPSDus": dm_type.BASE64,
        "LIMITMASK": dm_type.UINT,
        "US0MASK": dm_type.UINT,
        "TRELLISds": dm_type.INT,
        "TRELLISus": dm_type.INT,
        "ACTSNRMODEds": dm_type.UINT,
        "ACTSNRMODEus": dm_type.UINT,
        "VirtualNoisePSDds": dm_type.BASE64,
        "VirtualNoisePSDus": dm_type.BASE64,
        "ACTUALCE": dm_type.UINT,
        "LineNumber": dm_type.INT,
        "UpstreamMaxBitRate": dm_type.UINT,
        "DownstreamMaxBitRate": dm_type.UINT,
        "UpstreamNoiseMargin": dm_type.INT,
        "DownstreamNoiseMargin": dm_type.INT,
        "SNRMpbus": dm_type.STRING,
        "SNRMpbds": dm_type.STRING,
        "INMIATOds": dm_type.UINT,
        "INMIATSds": dm_type.UINT,
        "INMCCds": dm_type.UINT,
        "INMINPEQMODEds": dm_type.UINT,
        "UpstreamAttenuation": dm_type.INT,
        "DownstreamAttenuation": dm_type.INT,
        "UpstreamPower": dm_type.INT,
        "DownstreamPower": dm_type.INT,
        "XTURVersion": dm_type.STRING,
        "XTURSerial": dm_type.STRING,
        "XTURVendor": dm_type.HEXBIN,
        "XTURVendorSpecific": dm_type.HEXBIN,
        "XTURCountry": dm_type.HEXBIN,
        "XTURSystemVendor": dm_type.HEXBIN,
        "XTURSystemVendorSpecific": dm_type.HEXBIN,
        "XTURSystemCountry": dm_type.HEXBIN,
        "XTURANSIStd": dm_type.UINT,
        "XTURANSIRev": dm_type.UINT,
        "XTUCVersion": dm_type.HEXBIN,
        "XTUCSerial": dm_type.STRING,
        "XTUCVendor": dm_type.HEXBIN,
        "XTUCVendorSpecific": dm_type.HEXBIN,
        "XTUCCountry": dm_type.HEXBIN,
        "XTUCSystemVendor": dm_type.HEXBIN,
        "XTUCSystemVendorSpecific": dm_type.HEXBIN,
        "XTUCSystemCountry": dm_type.HEXBIN,
        "XTUCANSIStd": dm_type.UINT,
        "XTUCANSIRev": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "FirmwareVersion": "",
        "LinkStatus": "",
        "StandardsSupported": "",
        "StandardUsed": "",
        "LineEncoding": "",
        "AllowedProfiles": "",
        "CurrentProfile": "",
        "PowerManagementState": "",
        "SuccessFailureCause": "0",
        "UPBOKLER": "0",
        "UPBOKLEPb": "0",
        "UPBOKLERPb": "0",
        "RXTHRSHds": "0",
        "ACTRAMODEds": "0",
        "ACTRAMODEus": "0",
        "ACTINPROCds": "0",
        "ACTINPROCus": "0",
        "SNRMROCds": "0",
        "SNRMROCus": "0",
        "LastStateTransmittedDownstream": "0",
        "LastStateTransmittedUpstream": "0",
        "UPBOKLE": "0",
        "LIMITMASK": "0",
        "US0MASK": "0",
        "TRELLISds": "0",
        "TRELLISus": "0",
        "ACTSNRMODEds": "0",
        "ACTSNRMODEus": "0",
        "ACTUALCE": "0",
        "LineNumber": "0",
        "UpstreamMaxBitRate": "0",
        "DownstreamMaxBitRate": "0",
        "UpstreamNoiseMargin": "0",
        "DownstreamNoiseMargin": "0",
        "SNRMpbus": "",
        "SNRMpbds": "",
        "INMIATOds": "0",
        "INMIATSds": "0",
        "INMCCds": "0",
        "INMINPEQMODEds": "0",
        "UpstreamAttenuation": "0",
        "DownstreamAttenuation": "0",
        "UpstreamPower": "0",
        "DownstreamPower": "0",
        "XTURVersion": "",
        "XTURSerial": "",
        "XTURANSIStd": "0",
        "XTURANSIRev": "0",
        "XTUCSerial": "",
        "XTUCANSIStd": "0",
        "XTUCANSIRev": "0"
    }
};

// Schema for Device.DSL.Channel.{i}.Stats.
export const Channel_Stats = {
    path: "Device.DSL.Channel.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "TotalStart": dm_type.UINT,
        "ShowtimeStart": dm_type.UINT,
        "LastShowtimeStart": dm_type.UINT,
        "CurrentDayStart": dm_type.UINT,
        "QuarterHourStart": dm_type.UINT
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "TotalStart": "0",
        "ShowtimeStart": "0",
        "LastShowtimeStart": "0",
        "CurrentDayStart": "0",
        "QuarterHourStart": "0"
    }
};

// Schema for Device.DSL.Channel.{i}.
export const Channel = {
    path: "Device.DSL.Channel.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "LinkEncapsulationSupported": dm_type.STRING,
        "LinkEncapsulationUsed": dm_type.STRING,
        "LPATH": dm_type.UINT,
        "INTLVDEPTH": dm_type.UINT,
        "INTLVBLOCK": dm_type.INT,
        "ActualInterleavingDelay": dm_type.UINT,
        "ACTINP": dm_type.INT,
        "INPREPORT": dm_type.BOOL,
        "NFEC": dm_type.INT,
        "RFEC": dm_type.INT,
        "LSYMB": dm_type.INT,
        "UpstreamCurrRate": dm_type.UINT,
        "DownstreamCurrRate": dm_type.UINT,
        "ACTNDR": dm_type.UINT,
        "ACTINPREIN": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "LinkEncapsulationSupported": "",
        "LinkEncapsulationUsed": "",
        "LPATH": "0",
        "INTLVDEPTH": "0",
        "INTLVBLOCK": "0",
        "ActualInterleavingDelay": "0",
        "ACTINP": "0",
        "NFEC": "0",
        "RFEC": "0",
        "LSYMB": "0",
        "UpstreamCurrRate": "0",
        "DownstreamCurrRate": "0",
        "ACTNDR": "0",
        "ACTINPREIN": "0"
    }
};

// Schema for Device.DSL.Channel.{i}.Stats.LastShowtime.
export const Stats_LastShowtime = {
    path: "Device.DSL.Channel.{i}.Stats.LastShowtime.",
    schema: {
        "XTURFECErrors": dm_type.UINT,
        "XTUCFECErrors": dm_type.UINT,
        "XTURHECErrors": dm_type.UINT,
        "XTUCHECErrors": dm_type.UINT,
        "XTURCRCErrors": dm_type.UINT,
        "XTUCCRCErrors": dm_type.UINT
    },
    defaults: {
        "XTURFECErrors": "0",
        "XTUCFECErrors": "0",
        "XTURHECErrors": "0",
        "XTUCHECErrors": "0",
        "XTURCRCErrors": "0",
        "XTUCCRCErrors": "0"
    }
};

// Schema for Device.DSL.
export const DSL = {
    path: "Device.DSL.",
    schema: {
        "LineNumberOfEntries": dm_type.UINT,
        "ChannelNumberOfEntries": dm_type.UINT,
        "BondingGroupNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LineNumberOfEntries": "0",
        "ChannelNumberOfEntries": "0",
        "BondingGroupNumberOfEntries": "0"
    }
};

// Schema for Device.DSL.BondingGroup.{i}.
export const BondingGroup = {
    path: "Device.DSL.BondingGroup.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "GroupStatus": dm_type.STRING,
        "GroupID": dm_type.UINT,
        "BondSchemesSupported": dm_type.STRING,
        "BondScheme": dm_type.STRING,
        "GroupCapacity": dm_type.UINT,
        "RunningTime": dm_type.UINT,
        "TargetUpRate": dm_type.UINT,
        "TargetDownRate": dm_type.UINT,
        "ThreshLowUpRate": dm_type.UINT,
        "ThreshLowDownRate": dm_type.UINT,
        "UpstreamDifferentialDelayTolerance": dm_type.UINT,
        "DownstreamDifferentialDelayTolerance": dm_type.UINT,
        "BondedChannelNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "GroupStatus": "",
        "GroupID": "0",
        "BondSchemesSupported": "",
        "BondScheme": "",
        "GroupCapacity": "0",
        "RunningTime": "0",
        "TargetUpRate": "0",
        "TargetDownRate": "0",
        "ThreshLowUpRate": "0",
        "ThreshLowDownRate": "0",
        "UpstreamDifferentialDelayTolerance": "0",
        "DownstreamDifferentialDelayTolerance": "0",
        "BondedChannelNumberOfEntries": "0"
    }
};

// Schema for Device.DSL.BondingGroup.{i}.Stats.
export const BondingGroup_Stats = {
    path: "Device.DSL.BondingGroup.{i}.Stats.",
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
        "TotalStart": dm_type.UINT,
        "CurrentDayStart": dm_type.UINT,
        "QuarterHourStart": dm_type.UINT
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
        "TotalStart": "0",
        "CurrentDayStart": "0",
        "QuarterHourStart": "0"
    }
};
