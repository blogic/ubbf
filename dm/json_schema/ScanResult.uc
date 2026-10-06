'use strict';

// Auto-generated schema definitions for ScanResult domain
// Generated from TR-181 specifications

// Schema for ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS.{i}.
export const ChannelScan_NeighborBSS = {
    path: "ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "SSID": dm_type.STRING,
        "SignalStrength": dm_type.UINT,
        "ChannelBandwidth": dm_type.STRING,
        "ChannelUtilization": dm_type.UINT,
        "StationCount": dm_type.UINT,
        "MLDMACAddress": dm_type.STRING,
        "ReportingBSSID": dm_type.STRING,
        "MultiBSSID": dm_type.BOOL,
        "BSSLoadElementPresent": dm_type.BOOL,
        "BSSColor": dm_type.UINT,
        "SecurityModeEnabled": dm_type.STRING,
        "EncryptionMode": dm_type.STRING,
        "SupportedStandards": dm_type.STRING,
        "OperatingStandards": dm_type.STRING,
        "BasicDataTransferRates": dm_type.STRING,
        "SupportedDataTransferRates": dm_type.STRING,
        "SupportedNSS": dm_type.UINT,
        "DTIMPeriod": dm_type.UINT,
        "BeaconPeriod": dm_type.UINT
    },
    defaults: {
        "BSSID": "",
        "SSID": "",
        "SignalStrength": "0",
        "ChannelBandwidth": "",
        "ChannelUtilization": "0",
        "StationCount": "0",
        "MLDMACAddress": "",
        "ReportingBSSID": "",
        "BSSColor": "0",
        "SecurityModeEnabled": "",
        "EncryptionMode": "",
        "SupportedStandards": "",
        "OperatingStandards": "",
        "BasicDataTransferRates": "",
        "SupportedDataTransferRates": "",
        "SupportedNSS": "0",
        "DTIMPeriod": "0",
        "BeaconPeriod": "0"
    }
};

// Schema for ScanResult.{i}.
export const ScanResult = {
    path: "ScanResult.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "AggregateScanDuration": dm_type.UINT,
        "ScanType": dm_type.BOOL
    },
    defaults: {
        "AggregateScanDuration": "0"
    }
};

// Schema for ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.
export const OpClassScan_ChannelScan = {
    path: "ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.",
    schema: {
        "Channel": dm_type.UINT,
        "TimeStamp": dm_type.DATETIME,
        "Utilization": dm_type.UINT,
        "Noise": dm_type.UINT,
        "ScanStatus": dm_type.STRING
    },
    defaults: {
        "Channel": "0",
        "Utilization": "0",
        "Noise": "0",
        "ScanStatus": ""
    }
};

// Schema for ScanResult.{i}.OpClassScan.{i}.
export const OpClassScan = {
    path: "ScanResult.{i}.OpClassScan.{i}.",
    schema: {
        "OperatingClass": dm_type.UINT
    },
    defaults: {
        "OperatingClass": "0"
    }
};
