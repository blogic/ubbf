'use strict';

// Auto-generated schema definitions for Ghn domain
// Generated from TR-181 specifications

// Schema for Device.Ghn.Interface.{i}.
export const Interface = {
    path: "Device.Ghn.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.UINT,
        "MACAddress": dm_type.STRING,
        "FirmwareVersion": dm_type.STRING,
        "ConnectionType": dm_type.STRING,
        "MaxTransmitRate": dm_type.UINT,
        "TargetDomainNames": dm_type.STRING | dm_type.WRITABLE,
        "DomainName": dm_type.STRING,
        "DomainNameIdentifier": dm_type.UINT,
        "DomainId": dm_type.UINT,
        "DeviceId": dm_type.UINT,
        "NodeTypeDMCapable": dm_type.BOOL,
        "DMRequested": dm_type.BOOL | dm_type.WRITABLE,
        "IsDM": dm_type.BOOL,
        "NodeTypeSCCapable": dm_type.BOOL,
        "SCRequested": dm_type.BOOL | dm_type.WRITABLE,
        "IsSC": dm_type.BOOL,
        "StandardVersions": dm_type.STRING,
        "MaxBandPlan": dm_type.UINT,
        "MediumType": dm_type.STRING,
        "TAIFG": dm_type.UINT,
        "NotchedAmateurRadioBands": dm_type.HEXBIN | dm_type.WRITABLE,
        "PHYThroughputDiagnosticsEnable": dm_type.UINT | dm_type.WRITABLE,
        "PerformanceMonitoringDiagnosticsEnable": dm_type.UINT | dm_type.WRITABLE,
        "SMMaskedBandNumberOfEntries": dm_type.UINT,
        "NodeTypeDMConfig": dm_type.BOOL | dm_type.WRITABLE,
        "NodeTypeDMStatus": dm_type.BOOL,
        "NodeTypeSCStatus": dm_type.BOOL,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT,
        "PSM": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "MACAddress": "",
        "FirmwareVersion": "",
        "ConnectionType": "",
        "MaxTransmitRate": "0",
        "TargetDomainNames": "",
        "DomainName": "",
        "DomainNameIdentifier": "0",
        "DomainId": "0",
        "DeviceId": "0",
        "StandardVersions": "",
        "MaxBandPlan": "0",
        "MediumType": "",
        "TAIFG": "0",
        "PHYThroughputDiagnosticsEnable": "0",
        "PerformanceMonitoringDiagnosticsEnable": "0",
        "SMMaskedBandNumberOfEntries": "0",
        "AssociatedDeviceNumberOfEntries": "0",
        "PSM": ""
    }
};

// Schema for Device.Ghn.Interface.{i}.DMInfo.
export const Interface_DMInfo = {
    path: "Device.Ghn.Interface.{i}.DMInfo.",
    schema: {
        "DomainName": dm_type.HEXBIN | dm_type.WRITABLE,
        "DomainNameIdentifier": dm_type.HEXBIN,
        "DomainId": dm_type.UINT,
        "MACCycleDuration": dm_type.UINT | dm_type.WRITABLE,
        "SCDeviceId": dm_type.UINT | dm_type.WRITABLE,
        "SCMACAddress": dm_type.STRING | dm_type.WRITABLE,
        "ReregistrationTimePeriod": dm_type.UINT | dm_type.WRITABLE,
        "TopologyPeriodicInterval": dm_type.UINT | dm_type.WRITABLE,
        "MinSupportedBandplan": dm_type.UINT | dm_type.WRITABLE,
        "MaxSupportedBandplan": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "DomainId": "0",
        "MACCycleDuration": "0",
        "SCDeviceId": "0",
        "SCMACAddress": "",
        "ReregistrationTimePeriod": "0",
        "TopologyPeriodicInterval": "0",
        "MinSupportedBandplan": "0",
        "MaxSupportedBandplan": "0"
    }
};

// Schema for Device.Ghn.Interface.{i}.AssociatedDevice.{i}.
export const Interface_AssociatedDevice = {
    path: "Device.Ghn.Interface.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "DeviceId": dm_type.UINT,
        "TxPhyRate": dm_type.UINT,
        "RxPhyRate": dm_type.UINT,
        "Active": dm_type.BOOL
    },
    defaults: {
        "MACAddress": "",
        "DeviceId": "0",
        "TxPhyRate": "0",
        "RxPhyRate": "0"
    }
};

// Schema for Device.Ghn.Interface.{i}.SCInfo.
export const Interface_SCInfo = {
    path: "Device.Ghn.Interface.{i}.SCInfo.",
    schema: {
        "ModesSupported": dm_type.STRING,
        "ModeEnabled": dm_type.STRING | dm_type.WRITABLE,
        "MICSize": dm_type.STRING | dm_type.WRITABLE,
        "Location": dm_type.BOOL
    },
    defaults: {
        "ModesSupported": "",
        "ModeEnabled": "",
        "MICSize": ""
    }
};

// Schema for Device.Ghn.
export const Ghn = {
    path: "Device.Ghn.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.Ghn.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.Ghn.Interface.{i}.Stats.",
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
        "MgmtBytesSent": dm_type.STRING,
        "MgmtBytesReceived": dm_type.STRING,
        "MgmtPacketsSent": dm_type.STRING,
        "MgmtPacketsReceived": dm_type.STRING,
        "BlocksSent": dm_type.STRING,
        "BlocksReceived": dm_type.STRING,
        "BlocksResent": dm_type.STRING,
        "BlocksErrorsReceived": dm_type.STRING
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
        "MgmtBytesSent": "",
        "MgmtBytesReceived": "",
        "MgmtPacketsSent": "",
        "MgmtPacketsReceived": "",
        "BlocksSent": "",
        "BlocksReceived": "",
        "BlocksResent": "",
        "BlocksErrorsReceived": ""
    }
};

// Schema for Device.Ghn.Interface.{i}.SMMaskedBand.{i}.
export const Interface_SMMaskedBand = {
    path: "Device.Ghn.Interface.{i}.SMMaskedBand.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "BandNumber": dm_type.UINT | dm_type.WRITABLE,
        "StartSubCarrier": dm_type.UINT | dm_type.WRITABLE,
        "StopSubCarrier": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "BandNumber": "0",
        "StartSubCarrier": "0",
        "StopSubCarrier": "0"
    }
};
