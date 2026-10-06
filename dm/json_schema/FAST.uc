'use strict';

// Auto-generated schema definitions for FAST domain
// Generated from TR-181 specifications

// Schema for Device.FAST.Line.{i}.Stats.
export const Line_Stats = {
    path: "Device.FAST.Line.{i}.Stats.",
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

// Schema for Device.FAST.
export const FAST = {
    path: "Device.FAST.",
    schema: {
        "LineNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LineNumberOfEntries": "0"
    }
};

// Schema for Device.FAST.Line.{i}.Stats.CurrentDay.
export const Stats_CurrentDay = {
    path: "Device.FAST.Line.{i}.Stats.CurrentDay.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT,
        "LOSS": dm_type.UINT,
        "LORS": dm_type.UINT,
        "UAS": dm_type.UINT,
        "RTXUC": dm_type.UINT,
        "RTXTX": dm_type.UINT,
        "SuccessBSW": dm_type.UINT,
        "SuccessSRA": dm_type.UINT,
        "SuccessFRA": dm_type.UINT,
        "SuccessRPA": dm_type.UINT,
        "SuccessTIGA": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0",
        "LOSS": "0",
        "LORS": "0",
        "UAS": "0",
        "RTXUC": "0",
        "RTXTX": "0",
        "SuccessBSW": "0",
        "SuccessSRA": "0",
        "SuccessFRA": "0",
        "SuccessRPA": "0",
        "SuccessTIGA": "0"
    }
};

// Schema for Device.FAST.Line.{i}.Stats.QuarterHour.
export const Stats_QuarterHour = {
    path: "Device.FAST.Line.{i}.Stats.QuarterHour.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT,
        "LOSS": dm_type.UINT,
        "LORS": dm_type.UINT,
        "UAS": dm_type.UINT,
        "RTXUC": dm_type.UINT,
        "RTXTX": dm_type.UINT,
        "SuccessBSW": dm_type.UINT,
        "SuccessSRA": dm_type.UINT,
        "SuccessFRA": dm_type.UINT,
        "SuccessRPA": dm_type.UINT,
        "SuccessTIGA": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0",
        "LOSS": "0",
        "LORS": "0",
        "UAS": "0",
        "RTXUC": "0",
        "RTXTX": "0",
        "SuccessBSW": "0",
        "SuccessSRA": "0",
        "SuccessFRA": "0",
        "SuccessRPA": "0",
        "SuccessTIGA": "0"
    }
};

// Schema for Device.FAST.Line.{i}.Stats.Total.
export const Stats_Total = {
    path: "Device.FAST.Line.{i}.Stats.Total.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT,
        "LOSS": dm_type.UINT,
        "LORS": dm_type.UINT,
        "UAS": dm_type.UINT,
        "RTXUC": dm_type.UINT,
        "RTXTX": dm_type.UINT,
        "SuccessBSW": dm_type.UINT,
        "SuccessSRA": dm_type.UINT,
        "SuccessFRA": dm_type.UINT,
        "SuccessRPA": dm_type.UINT,
        "SuccessTIGA": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0",
        "LOSS": "0",
        "LORS": "0",
        "UAS": "0",
        "RTXUC": "0",
        "RTXTX": "0",
        "SuccessBSW": "0",
        "SuccessSRA": "0",
        "SuccessFRA": "0",
        "SuccessRPA": "0",
        "SuccessTIGA": "0"
    }
};

// Schema for Device.FAST.Line.{i}.Stats.LastShowtime.
export const Stats_LastShowtime = {
    path: "Device.FAST.Line.{i}.Stats.LastShowtime.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT,
        "LOSS": dm_type.UINT,
        "LORS": dm_type.UINT,
        "UAS": dm_type.UINT,
        "RTXUC": dm_type.UINT,
        "RTXTX": dm_type.UINT,
        "SuccessBSW": dm_type.UINT,
        "SuccessSRA": dm_type.UINT,
        "SuccessFRA": dm_type.UINT,
        "SuccessRPA": dm_type.UINT,
        "SuccessTIGA": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0",
        "LOSS": "0",
        "LORS": "0",
        "UAS": "0",
        "RTXUC": "0",
        "RTXTX": "0",
        "SuccessBSW": "0",
        "SuccessSRA": "0",
        "SuccessFRA": "0",
        "SuccessRPA": "0",
        "SuccessTIGA": "0"
    }
};

// Schema for Device.FAST.Line.{i}.TestParams.
export const Line_TestParams = {
    path: "Device.FAST.Line.{i}.TestParams.",
    schema: {
        "SNRGds": dm_type.UINT,
        "SNRGus": dm_type.UINT,
        "SNRpsds": dm_type.INT,
        "SNRpsus": dm_type.STRING,
        "SNRMTds": dm_type.UINT,
        "SNRMTus": dm_type.UINT,
        "ACTINP": dm_type.UINT,
        "NFEC": dm_type.UINT,
        "RFEC": dm_type.INT,
        "UpstreamCurrRate": dm_type.UINT,
        "DownstreamCurrRate": dm_type.UINT,
        "ACTINPREIN": dm_type.UINT
    },
    defaults: {
        "SNRGds": "0",
        "SNRGus": "0",
        "SNRpsds": "0",
        "SNRpsus": "",
        "SNRMTds": "0",
        "SNRMTus": "0",
        "ACTINP": "0",
        "NFEC": "0",
        "RFEC": "0",
        "UpstreamCurrRate": "0",
        "DownstreamCurrRate": "0",
        "ACTINPREIN": "0"
    }
};

// Schema for Device.FAST.Line.{i}.Stats.Showtime.
export const Stats_Showtime = {
    path: "Device.FAST.Line.{i}.Stats.Showtime.",
    schema: {
        "ErroredSecs": dm_type.UINT,
        "SeverelyErroredSecs": dm_type.UINT,
        "LOSS": dm_type.UINT,
        "LORS": dm_type.UINT,
        "UAS": dm_type.UINT,
        "RTXUC": dm_type.UINT,
        "RTXTX": dm_type.UINT,
        "SuccessBSW": dm_type.UINT,
        "SuccessSRA": dm_type.UINT,
        "SuccessFRA": dm_type.UINT,
        "SuccessRPA": dm_type.UINT,
        "SuccessTIGA": dm_type.UINT
    },
    defaults: {
        "ErroredSecs": "0",
        "SeverelyErroredSecs": "0",
        "LOSS": "0",
        "LORS": "0",
        "UAS": "0",
        "RTXUC": "0",
        "RTXTX": "0",
        "SuccessBSW": "0",
        "SuccessSRA": "0",
        "SuccessFRA": "0",
        "SuccessRPA": "0",
        "SuccessTIGA": "0"
    }
};

// Schema for Device.FAST.Line.{i}.
export const Line = {
    path: "Device.FAST.Line.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "FirmwareVersion": dm_type.STRING,
        "LinkStatus": dm_type.STRING,
        "AllowedProfiles": dm_type.STRING,
        "CurrentProfile": dm_type.STRING,
        "PowerManagementState": dm_type.STRING,
        "SuccessFailureCause": dm_type.UINT,
        "UPBOKLER": dm_type.UINT,
        "LastTransmittedDownstreamSignal": dm_type.UINT,
        "LastTransmittedUpstreamSignal": dm_type.UINT,
        "UPBOKLE": dm_type.UINT,
        "LineNumber": dm_type.INT,
        "UpstreamMaxBitRate": dm_type.UINT,
        "DownstreamMaxBitRate": dm_type.UINT,
        "UpstreamNoiseMargin": dm_type.INT,
        "DownstreamNoiseMargin": dm_type.INT,
        "UpstreamAttenuation": dm_type.INT,
        "DownstreamAttenuation": dm_type.INT,
        "UpstreamPower": dm_type.INT,
        "DownstreamPower": dm_type.INT,
        "SNRMRMCds": dm_type.INT,
        "SNRMRMCus": dm_type.INT,
        "BITSRMCpsds": dm_type.INT,
        "BITSRMCpsus": dm_type.INT,
        "FEXTCANCELds": dm_type.BOOL,
        "FEXTCANCELus": dm_type.BOOL,
        "ETRds": dm_type.UINT,
        "ETRus": dm_type.UINT,
        "ATTETRds": dm_type.UINT,
        "ATTETRus": dm_type.UINT,
        "MINEFTR": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "FirmwareVersion": "",
        "LinkStatus": "",
        "AllowedProfiles": "",
        "CurrentProfile": "",
        "PowerManagementState": "",
        "SuccessFailureCause": "0",
        "UPBOKLER": "0",
        "LastTransmittedDownstreamSignal": "0",
        "LastTransmittedUpstreamSignal": "0",
        "UPBOKLE": "0",
        "LineNumber": "0",
        "UpstreamMaxBitRate": "0",
        "DownstreamMaxBitRate": "0",
        "UpstreamNoiseMargin": "0",
        "DownstreamNoiseMargin": "0",
        "UpstreamAttenuation": "0",
        "DownstreamAttenuation": "0",
        "UpstreamPower": "0",
        "DownstreamPower": "0",
        "SNRMRMCds": "0",
        "SNRMRMCus": "0",
        "BITSRMCpsds": "0",
        "BITSRMCpsus": "0",
        "ETRds": "0",
        "ETRus": "0",
        "ATTETRds": "0",
        "ATTETRus": "0",
        "MINEFTR": "0"
    }
};
