'use strict';

// Auto-generated schema definitions for WiFi domain
// Generated from TR-181 specifications

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.
export const STA_MultiAPSTA = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.",
    schema: {
        "AssociationTime": dm_type.DATETIME,
        "Noise": dm_type.UINT,
        "SteeringHistoryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Noise": "0",
        "SteeringHistoryNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.
export const Device_Radio = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.",
    schema: {
        "ID": dm_type.BASE64,
        "Enabled": dm_type.BOOL,
        "Noise": dm_type.UINT,
        "Utilization": dm_type.UINT,
        "Transmit": dm_type.UINT,
        "ReceiveSelf": dm_type.UINT,
        "ReceiveOther": dm_type.UINT,
        "TrafficSeparationCombinedFronthaul": dm_type.BOOL,
        "TrafficSeparationCombinedBackhaul": dm_type.BOOL,
        "SteeringPolicy": dm_type.UINT | dm_type.WRITABLE,
        "ChannelUtilizationThreshold": dm_type.UINT | dm_type.WRITABLE,
        "RCPISteeringThreshold": dm_type.UINT | dm_type.WRITABLE,
        "STAReportingRCPIThreshold": dm_type.UINT | dm_type.WRITABLE,
        "STAReportingRCPIHysteresisMarginOverride": dm_type.UINT | dm_type.WRITABLE,
        "ChannelUtilizationReportingThreshold": dm_type.UINT | dm_type.WRITABLE,
        "AssociatedSTATrafficStatsInclusionPolicy": dm_type.BOOL | dm_type.WRITABLE,
        "AssociatedSTALinkMetricsInclusionPolicy": dm_type.BOOL | dm_type.WRITABLE,
        "ChipsetVendor": dm_type.STRING,
        "APMetricsWiFi6": dm_type.BOOL | dm_type.WRITABLE,
        "MaxBSS": dm_type.UINT,
        "CurrentOperatingClassProfileNumberOfEntries": dm_type.UINT,
        "UnassociatedSTANumberOfEntries": dm_type.UINT,
        "BSSNumberOfEntries": dm_type.UINT,
        "ScanResultNumberOfEntries": dm_type.UINT,
        "DisAllowedOpClassChannelsNumberOfEntries": dm_type.UINT,
        "OpClassPreferenceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Noise": "0",
        "Utilization": "0",
        "Transmit": "0",
        "ReceiveSelf": "0",
        "ReceiveOther": "0",
        "SteeringPolicy": "0",
        "ChannelUtilizationThreshold": "0",
        "RCPISteeringThreshold": "0",
        "STAReportingRCPIThreshold": "0",
        "STAReportingRCPIHysteresisMarginOverride": "0",
        "ChannelUtilizationReportingThreshold": "0",
        "ChipsetVendor": "",
        "MaxBSS": "0",
        "CurrentOperatingClassProfileNumberOfEntries": "0",
        "UnassociatedSTANumberOfEntries": "0",
        "BSSNumberOfEntries": "0",
        "ScanResultNumberOfEntries": "0",
        "DisAllowedOpClassChannelsNumberOfEntries": "0",
        "OpClassPreferenceNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.
export const ScanResult_OpClassScan = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.",
    schema: {
        "OperatingClass": dm_type.UINT,
        "ChannelScanNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "OperatingClass": "0",
        "ChannelScanNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringSummaryStats.
export const MultiAPSTA_SteeringSummaryStats = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringSummaryStats.",
    schema: {
        "NoCandidateAPFailures": dm_type.STRING,
        "BlacklistAttempts": dm_type.STRING,
        "BlacklistSuccesses": dm_type.STRING,
        "BlacklistFailures": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMSuccesses": dm_type.STRING,
        "BTMFailures": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING,
        "LastSteerTime": dm_type.UINT
    },
    defaults: {
        "NoCandidateAPFailures": "",
        "BlacklistAttempts": "",
        "BlacklistSuccesses": "",
        "BlacklistFailures": "",
        "BTMAttempts": "",
        "BTMSuccesses": "",
        "BTMFailures": "",
        "BTMQueryResponses": "",
        "LastSteerTime": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.
export const BSS_STA = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "HTCapabilities": dm_type.BASE64,
        "VHTCapabilities": dm_type.BASE64,
        "HECapabilities": dm_type.BASE64,
        "ClientCapabilities": dm_type.BASE64,
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "UtilizationReceive": dm_type.ULONG,
        "UtilizationTransmit": dm_type.ULONG,
        "EstMACDataRateDownlink": dm_type.UINT,
        "EstMACDataRateUplink": dm_type.UINT,
        "SignalStrength": dm_type.UINT,
        "LastConnectTime": dm_type.UINT,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "RetransCount": dm_type.STRING,
        "MeasurementReport": dm_type.BASE64,
        "NumberOfMeasureReports": dm_type.UINT,
        "IPV4Address": dm_type.STRING,
        "IPV6Address": dm_type.STRING,
        "Hostname": dm_type.STRING,
        "CellularDataPreference": dm_type.STRING | dm_type.WRITABLE,
        "ReAssociationDelay": dm_type.UINT | dm_type.WRITABLE,
        "SleepMode": dm_type.STRING,
        "SecurityAssociation": dm_type.STRING,
        "PairwiseAKM": dm_type.HEXBIN,
        "PairwiseCipher": dm_type.HEXBIN,
        "RSNCapabilities": dm_type.UINT,
        "TIDQueueSizesNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "UtilizationReceive": "0",
        "UtilizationTransmit": "0",
        "EstMACDataRateDownlink": "0",
        "EstMACDataRateUplink": "0",
        "SignalStrength": "0",
        "LastConnectTime": "0",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "RetransCount": "",
        "NumberOfMeasureReports": "0",
        "IPV4Address": "",
        "IPV6Address": "",
        "Hostname": "",
        "CellularDataPreference": "",
        "ReAssociationDelay": "0",
        "SleepMode": "",
        "SecurityAssociation": "",
        "RSNCapabilities": "0",
        "TIDQueueSizesNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.AffiliatedAP.{i}.
export const APMLD_AffiliatedAP = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.AffiliatedAP.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "LinkID": dm_type.UINT,
        "RUID": dm_type.BASE64,
        "DisabledSubChannels": dm_type.UINT,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "UnicastBytesSent": dm_type.STRING,
        "UnicastBytesReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "MulticastBytesSent": dm_type.STRING,
        "MulticastBytesReceived": dm_type.STRING,
        "BroadcastBytesSent": dm_type.STRING,
        "BroadcastBytesReceived": dm_type.STRING,
        "EstServiceParametersBE": dm_type.BASE64,
        "EstServiceParametersBK": dm_type.BASE64,
        "EstServiceParametersVI": dm_type.BASE64,
        "EstServiceParametersVO": dm_type.BASE64
    },
    defaults: {
        "BSSID": "",
        "LinkID": "0",
        "DisabledSubChannels": "0",
        "PacketsSent": "",
        "PacketsReceived": "",
        "UnicastBytesSent": "",
        "UnicastBytesReceived": "",
        "ErrorsSent": "",
        "MulticastBytesSent": "",
        "MulticastBytesReceived": "",
        "BroadcastBytesSent": "",
        "BroadcastBytesReceived": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels.{i}.
export const CACMethod_OpClassChannels = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "ChannelList": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "ChannelList": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels.{i}.
export const Device_AnticipatedChannels = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "ChannelList": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "ChannelList": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.STABlock.{i}.
export const Network_STABlock = {
    path: "Device.WiFi.DataElements.Network.STABlock.{i}.",
    schema: {
        "BlockedSTA": dm_type.STRING | dm_type.WRITABLE,
        "BSSID": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "BlockedSTA": "",
        "BSSID": "",
        "ScheduleNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.
export const AP_AssociatedDevice = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "OperatingStandard": dm_type.STRING,
        "Active": dm_type.BOOL,
        "AssociationTime": dm_type.DATETIME,
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "SignalStrength": dm_type.UINT,
        "Noise": dm_type.UINT,
        "SteeringHistoryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "OperatingStandard": "",
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "SignalStrength": "0",
        "Noise": "0",
        "SteeringHistoryNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.Interworking.
export const AccessPoint_Interworking = {
    path: "Device.WiFi.AccessPoint.{i}.Interworking.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "AccessNetworkType": dm_type.STRING | dm_type.WRITABLE,
        "InternetAvailable": dm_type.BOOL | dm_type.WRITABLE,
        "ASRA": dm_type.BOOL | dm_type.WRITABLE,
        "VenueGroup": dm_type.STRING | dm_type.WRITABLE,
        "VenueType": dm_type.STRING | dm_type.WRITABLE,
        "HESSID": dm_type.STRING | dm_type.WRITABLE,
        "EmergencyServiceReachable": dm_type.BOOL | dm_type.WRITABLE,
        "UnauthenticatedEmergencyServiceAvailable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "AccessNetworkType": "",
        "VenueGroup": "",
        "VenueType": "",
        "HESSID": ""
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.
export const MultiAP_APDevice = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "Manufacturer": dm_type.STRING,
        "ManufacturerOUI": dm_type.STRING,
        "ProductClass": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "SoftwareVersion": dm_type.STRING,
        "LastContactTime": dm_type.DATETIME,
        "AssocIEEE1905DeviceRef": dm_type.STRING,
        "BackhaulLinkType": dm_type.STRING,
        "BackhaulMACAddress": dm_type.STRING,
        "BackhaulBytesSent": dm_type.STRING,
        "BackhaulBytesReceived": dm_type.STRING,
        "BackhaulLinkUtilization": dm_type.UINT,
        "BackhaulSignalStrength": dm_type.UINT,
        "RadarDetections": dm_type.UINT,
        "DFSEnable": dm_type.BOOL | dm_type.WRITABLE,
        "RadioNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "Manufacturer": "",
        "ManufacturerOUI": "",
        "ProductClass": "",
        "SerialNumber": "",
        "SoftwareVersion": "",
        "AssocIEEE1905DeviceRef": "",
        "BackhaulLinkType": "",
        "BackhaulMACAddress": "",
        "BackhaulBytesSent": "",
        "BackhaulBytesReceived": "",
        "BackhaulLinkUtilization": "0",
        "BackhaulSignalStrength": "0",
        "RadarDetections": "0",
        "RadioNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.HaLowCapabilities.
export const STA_HaLowCapabilities = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.HaLowCapabilities.",
    schema: {
        "BW4MHz": dm_type.BOOL,
        "BW8MHz": dm_type.BOOL,
        "BW16MHz": dm_type.BOOL,
        "S1GLong": dm_type.BOOL,
        "BW1MHzShortGI": dm_type.BOOL,
        "BW2MHzShortGI": dm_type.BOOL,
        "BW4MHzShortGI": dm_type.BOOL,
        "BW8MHzShortGI": dm_type.BOOL,
        "BW16MHzShortGI": dm_type.BOOL,
        "AMSDU": dm_type.BOOL,
        "AMPDU": dm_type.BOOL,
        "FlowControl": dm_type.BOOL,
        "CentralizedAuthenticationControl": dm_type.BOOL,
        "DistributedAuthenticationControl": dm_type.BOOL,
        "MaxMPDULen": dm_type.STRING,
        "NonTIMMode": dm_type.BOOL,
        "DynamicAID": dm_type.BOOL,
        "GroupAID": dm_type.BOOL,
        "BATSupport": dm_type.BOOL,
        "RAWOperation": dm_type.BOOL,
        "PageSlicing": dm_type.BOOL,
        "PV1Frame": dm_type.BOOL,
        "TxMCSNSS": dm_type.UINT,
        "RxMCSNSS": dm_type.UINT,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "MUBeamformee": dm_type.BOOL,
        "TravelingPilot": dm_type.BOOL,
        "TWTGrouping": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "IsSensorDevice": dm_type.BOOL
    },
    defaults: {
        "MaxMPDULen": "",
        "TxMCSNSS": "0",
        "RxMCSNSS": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.Stats.
export const Backhaul_Stats = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "LinkUtilization": dm_type.UINT,
        "SignalStrength": dm_type.UINT,
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "TimeStamp": dm_type.DATETIME
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "LinkUtilization": "0",
        "SignalStrength": "0",
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0"
    }
};

// Schema for Device.WiFi.Radio.{i}.Stats.
export const Radio_Stats = {
    path: "Device.WiFi.Radio.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "CtsReceived": dm_type.STRING,
        "NoCtsReceived": dm_type.STRING,
        "FrameHeaderError": dm_type.STRING,
        "GoodPLCPReceived": dm_type.STRING,
        "DPacketOtherMACReceived": dm_type.STRING,
        "MPacketOtherMACReceived": dm_type.STRING,
        "CPacketOtherMACReceived": dm_type.STRING,
        "CtsOtherMACReceived": dm_type.STRING,
        "RtsOtherMACReceived": dm_type.STRING,
        "PLCPErrorCount": dm_type.UINT,
        "FCSErrorCount": dm_type.UINT,
        "InvalidMACCount": dm_type.UINT,
        "PacketsOtherReceived": dm_type.UINT,
        "Noise": dm_type.INT,
        "TotalChannelChangeCount": dm_type.UINT,
        "ManualChannelChangeCount": dm_type.UINT,
        "AutoStartupChannelChangeCount": dm_type.UINT,
        "AutoUserChannelChangeCount": dm_type.UINT,
        "AutoRefreshChannelChangeCount": dm_type.UINT,
        "AutoDynamicChannelChangeCount": dm_type.UINT,
        "AutoDFSChannelChangeCount": dm_type.UINT
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
        "CtsReceived": "",
        "NoCtsReceived": "",
        "FrameHeaderError": "",
        "GoodPLCPReceived": "",
        "DPacketOtherMACReceived": "",
        "MPacketOtherMACReceived": "",
        "CPacketOtherMACReceived": "",
        "CtsOtherMACReceived": "",
        "RtsOtherMACReceived": "",
        "PLCPErrorCount": "0",
        "FCSErrorCount": "0",
        "InvalidMACCount": "0",
        "PacketsOtherReceived": "0",
        "Noise": "0",
        "TotalChannelChangeCount": "0",
        "ManualChannelChangeCount": "0",
        "AutoStartupChannelChangeCount": "0",
        "AutoUserChannelChangeCount": "0",
        "AutoRefreshChannelChangeCount": "0",
        "AutoDynamicChannelChangeCount": "0",
        "AutoDFSChannelChangeCount": "0"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.AC.{i}.
export const EndPoint_AC = {
    path: "Device.WiFi.EndPoint.{i}.AC.{i}.",
    schema: {
        "AccessCategory": dm_type.STRING,
        "Alias": dm_type.STRING,
        "AIFSN": dm_type.UINT | dm_type.WRITABLE,
        "ECWMin": dm_type.UINT | dm_type.WRITABLE,
        "ECWMax": dm_type.UINT | dm_type.WRITABLE,
        "TxOpMax": dm_type.UINT | dm_type.WRITABLE,
        "AckPolicy": dm_type.BOOL | dm_type.WRITABLE,
        "OutQLenHistogramIntervals": dm_type.STRING | dm_type.WRITABLE,
        "OutQLenHistogramSampleInterval": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "AccessCategory": "",
        "Alias": "",
        "AIFSN": "0",
        "ECWMin": "0",
        "ECWMax": "0",
        "TxOpMax": "0",
        "OutQLenHistogramIntervals": "",
        "OutQLenHistogramSampleInterval": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.QMDescriptor.{i}.
export const BSS_QMDescriptor = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.QMDescriptor.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "ClientMAC": dm_type.STRING,
        "DescriptorElement": dm_type.HEXBIN
    },
    defaults: {
        "BSSID": "",
        "ClientMAC": ""
    }
};

// Schema for Device.WiFi.SSID.{i}.
export const SSID = {
    path: "Device.WiFi.SSID.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "BSSID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "SSID": dm_type.STRING | dm_type.WRITABLE,
        "MLDUnit": dm_type.INT | dm_type.WRITABLE,
        "ATFEnable": dm_type.BOOL | dm_type.WRITABLE,
        "FlushATFTable": dm_type.BOOL | dm_type.WRITABLE,
        "SetATF": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Down",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "[]",
        "BSSID": "",
        "MACAddress": "",
        "SSID": "",
        "MLDUnit": "-1",
        "SetATF": "0"
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.Stats.
export const AssociatedDevice_Stats = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "RetransCount": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "RetransCount": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Default8021Q.{i}.
export const Device_Default8021Q = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Default8021Q.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "PrimaryVID": dm_type.UINT | dm_type.WRITABLE,
        "DefaultPCP": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "PrimaryVID": "0",
        "DefaultPCP": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.HaLowCapabilities.
export const Capabilities_HaLowCapabilities = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.HaLowCapabilities.",
    schema: {
        "BW4MHz": dm_type.BOOL,
        "BW8MHz": dm_type.BOOL,
        "BW16MHz": dm_type.BOOL,
        "S1GLong": dm_type.BOOL,
        "BW1MHzShortGI": dm_type.BOOL,
        "BW2MHzShortGI": dm_type.BOOL,
        "BW4MHzShortGI": dm_type.BOOL,
        "BW8MHzShortGI": dm_type.BOOL,
        "BW16MHzShortGI": dm_type.BOOL,
        "AMSDU": dm_type.BOOL,
        "AMPDU": dm_type.BOOL,
        "FlowControl": dm_type.BOOL,
        "CentralizedAuthenticationControl": dm_type.BOOL,
        "DistributedAuthenticationControl": dm_type.BOOL,
        "MaxMPDULen": dm_type.STRING,
        "NonTIMMode": dm_type.BOOL,
        "DynamicAID": dm_type.BOOL,
        "GroupAID": dm_type.BOOL,
        "BATSupport": dm_type.BOOL,
        "RAWOperation": dm_type.BOOL,
        "PageSlicing": dm_type.BOOL,
        "PV1Frame": dm_type.BOOL,
        "TxMCSNSS": dm_type.UINT,
        "RxMCSNSS": dm_type.UINT,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "MUBeamformee": dm_type.BOOL,
        "TravelingPilot": dm_type.BOOL,
        "TWTGrouping": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "AcceptSensorDevices": dm_type.BOOL,
        "AcceptNonSensorDevices": dm_type.BOOL
    },
    defaults: {
        "MaxMPDULen": "",
        "TxMCSNSS": "0",
        "RxMCSNSS": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.AssociatedDevice.{i}.
export const AccessPoint_AssociatedDevice = {
    path: "Device.WiFi.AccessPoint.{i}.AssociatedDevice.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "Type": dm_type.STRING,
        "SetStaATF": dm_type.UINT | dm_type.WRITABLE,
        "OperatingStandard": dm_type.STRING,
        "AuthenticationState": dm_type.BOOL,
        "LastDataDownlinkRate": dm_type.UINT,
        "MaxSupportedDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "MaxSupportedDataUplinkRate": dm_type.UINT,
        "AssociationTime": dm_type.DATETIME,
        "SignalStrength": dm_type.INT,
        "Noise": dm_type.INT,
        "SNR": dm_type.UINT,
        "Retransmissions": dm_type.UINT,
        "Active": dm_type.BOOL,
        "MaxSupportedBandwidth": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "Type": "",
        "SetStaATF": "0",
        "OperatingStandard": "",
        "LastDataDownlinkRate": "0",
        "MaxSupportedDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "MaxSupportedDataUplinkRate": "0",
        "SignalStrength": "0",
        "Noise": "0",
        "SNR": "0",
        "Retransmissions": "0",
        "MaxSupportedBandwidth": ""
    }
};

// Schema for Device.WiFi.DataElements.DisassociationEvent.
export const DataElements_DisassociationEvent = {
    path: "Device.WiFi.DataElements.DisassociationEvent.",
    schema: {
        "DisassociationEventDataNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "DisassociationEventDataNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.Security.
export const AccessPoint_Security = {
    path: "Device.WiFi.AccessPoint.{i}.Security.",
    schema: {
        "ModesSupported": dm_type.STRING,
        "ModeEnabled": dm_type.STRING | dm_type.WRITABLE,
        "EncryptionMode": dm_type.STRING | dm_type.WRITABLE,
        "WEPKey": dm_type.HEXBIN | dm_type.WRITABLE,
        "PreSharedKey": dm_type.HEXBIN | dm_type.WRITABLE,
        "KeyPassphrase": dm_type.STRING | dm_type.WRITABLE,
        "RekeyingInterval": dm_type.UINT | dm_type.WRITABLE,
        "SAEPassphrase": dm_type.STRING | dm_type.WRITABLE,
        "RadiusServerIPAddr": dm_type.STRING | dm_type.WRITABLE,
        "SecondaryRadiusServerIPAddr": dm_type.STRING | dm_type.WRITABLE,
        "RadiusServerPort": dm_type.UINT | dm_type.WRITABLE,
        "SecondaryRadiusServerPort": dm_type.UINT | dm_type.WRITABLE,
        "RadiusSecret": dm_type.STRING | dm_type.WRITABLE,
        "SecondaryRadiusSecret": dm_type.STRING | dm_type.WRITABLE,
        "MFPConfig": dm_type.STRING | dm_type.WRITABLE,
        "SPPAMSDU": dm_type.STRING | dm_type.WRITABLE,
        "TransitionDisableIndication": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "ModesSupported": "",
        "ModeEnabled": "",
        "EncryptionMode": "",
        "KeyPassphrase": "",
        "RekeyingInterval": "3600",
        "SAEPassphrase": "",
        "RadiusServerIPAddr": "",
        "SecondaryRadiusServerIPAddr": "",
        "RadiusServerPort": "1812",
        "SecondaryRadiusServerPort": "1812",
        "RadiusSecret": "",
        "SecondaryRadiusSecret": "",
        "MFPConfig": "Disabled",
        "SPPAMSDU": "",
        "TransitionDisableIndication": "true"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringHistory.{i}.
export const MultiAPSTA_SteeringHistory = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringHistory.{i}.",
    schema: {
        "Time": dm_type.DATETIME,
        "APOrigin": dm_type.STRING,
        "TriggerEvent": dm_type.STRING,
        "SteeringApproach": dm_type.STRING,
        "APDestination": dm_type.STRING,
        "SteeringDuration": dm_type.UINT
    },
    defaults: {
        "APOrigin": "",
        "TriggerEvent": "",
        "SteeringApproach": "",
        "APDestination": "",
        "SteeringDuration": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMFrontHaul.{i}.
export const Capabilities_AKMFrontHaul = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMFrontHaul.{i}.",
    schema: {
        "OUI": dm_type.BASE64,
        "Type": dm_type.UINT
    },
    defaults: {
        "Type": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.DisAllowedOpClassChannels.{i}.
export const Radio_DisAllowedOpClassChannels = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.DisAllowedOpClassChannels.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "OpClass": dm_type.UINT | dm_type.WRITABLE,
        "ChannelList": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "OpClass": "0",
        "ChannelList": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.
export const MultiAPDevice_Backhaul = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.",
    schema: {
        "LinkType": dm_type.STRING,
        "BackhaulMACAddress": dm_type.STRING,
        "BackhaulDeviceID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "CurrentOperatingClassProfileNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LinkType": "",
        "BackhaulMACAddress": "",
        "BackhaulDeviceID": "",
        "MACAddress": "",
        "CurrentOperatingClassProfileNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLMRFreqSeparation.{i}.
export const WiFi7bSTARole_EMLMRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLMRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.SpatialReuse.
export const Radio_SpatialReuse = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.SpatialReuse.",
    schema: {
        "PartialBSSColor": dm_type.UINT,
        "BSSColor": dm_type.UINT,
        "HESIGASpatialReuseValue15Allowed": dm_type.BOOL,
        "SRGInformationValid": dm_type.BOOL,
        "NonSRGOffsetValid": dm_type.BOOL,
        "PSRDisallowed": dm_type.BOOL,
        "NonSRGOBSSPDMaxOffset": dm_type.UINT,
        "SRGOBSSPDMinOffset": dm_type.UINT,
        "SRGOBSSPDMaxOffset": dm_type.UINT,
        "SRGBSSColorBitmap": dm_type.HEXBIN,
        "SRGPartialBSSIDBitmap": dm_type.HEXBIN,
        "NeighborBSSColorInUseBitmap": dm_type.HEXBIN
    },
    defaults: {
        "PartialBSSColor": "0",
        "BSSColor": "0",
        "NonSRGOBSSPDMaxOffset": "0",
        "SRGOBSSPDMinOffset": "0",
        "SRGOBSSPDMaxOffset": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels.{i}.
export const ScanCapability_OpClassChannels = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "ChannelList": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "ChannelList": "0"
    }
};

// Schema for Device.WiFi.
export const WiFi = {
    path: "Device.WiFi.",
    schema: {
        "RadioNumberOfEntries": dm_type.UINT,
        "SSIDNumberOfEntries": dm_type.UINT,
        "AccessPointNumberOfEntries": dm_type.UINT,
        "EndPointNumberOfEntries": dm_type.UINT,
        "ResetCounter": dm_type.STRING,
        "ResetCause": dm_type.STRING
    },
    defaults: {
        "RadioNumberOfEntries": "0",
        "SSIDNumberOfEntries": "0",
        "AccessPointNumberOfEntries": "0",
        "EndPointNumberOfEntries": "0",
        "ResetCounter": "",
        "ResetCause": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLMRFreqSeparation.{i}.
export const WiFi7APRole_EMLMRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLMRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.
export const AccessPoint = {
    path: "Device.WiFi.AccessPoint.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "SSIDReference": dm_type.STRING | dm_type.WRITABLE,
        "SSIDAdvertisementEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "RetryLimit": dm_type.UINT | dm_type.WRITABLE,
        "WMMCapability": dm_type.BOOL,
        "UAPSDCapability": dm_type.BOOL,
        "WMMEnable": dm_type.BOOL | dm_type.WRITABLE,
        "UAPSDEnable": dm_type.BOOL | dm_type.WRITABLE,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT,
        "MaxAssociatedDevices": dm_type.UINT | dm_type.WRITABLE,
        "IsolationEnable": dm_type.BOOL | dm_type.WRITABLE,
        "MACAddressControlEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "AllowedMACAddress": dm_type.STRING | dm_type.WRITABLE,
        "MaxAllowedAssociations": dm_type.UINT | dm_type.WRITABLE,
        "CpeOperationMode": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "SSIDReference": "",
        "RetryLimit": "0",
        "AssociatedDeviceNumberOfEntries": "0",
        "MaxAssociatedDevices": "0",
        "AllowedMACAddress": "",
        "MaxAllowedAssociations": "0",
        "CpeOperationMode": "Router"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.Security.
export const EndPoint_Security = {
    path: "Device.WiFi.EndPoint.{i}.Security.",
    schema: {
        "ModesSupported": dm_type.STRING
    },
    defaults: {
        "ModesSupported": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.
export const Radio_Capabilities = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.",
    schema: {
        "HTCapabilities": dm_type.BASE64,
        "VHTCapabilities": dm_type.BASE64,
        "HECapabilities": dm_type.BASE64,
        "MSCSCapability": dm_type.BOOL,
        "SCSCapability": dm_type.BOOL,
        "QoSMapCapability": dm_type.BOOL,
        "DSCPPolicyCapability": dm_type.BOOL,
        "SCSTrafficDescriptionCapability": dm_type.BOOL,
        "CapableOperatingClassProfileNumberOfEntries": dm_type.UINT,
        "AKMFrontHaulNumberOfEntries": dm_type.UINT,
        "AKMBackhaulNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CapableOperatingClassProfileNumberOfEntries": "0",
        "AKMFrontHaulNumberOfEntries": "0",
        "AKMBackhaulNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.SSID.{i}.
export const Network_SSID = {
    path: "Device.WiFi.DataElements.Network.SSID.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "SSID": dm_type.STRING,
        "Band": dm_type.STRING,
        "Enable": dm_type.BOOL,
        "AKMsAllowed": dm_type.STRING,
        "SuiteSelector": dm_type.HEXBIN,
        "AdvertisementEnabled": dm_type.BOOL,
        "MFPConfig": dm_type.STRING,
        "MobilityDomain": dm_type.STRING,
        "HaulType": dm_type.STRING,
        "Type": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "SSID": "",
        "Band": "",
        "AKMsAllowed": "",
        "MFPConfig": "",
        "MobilityDomain": "",
        "HaulType": "",
        "Type": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.SetQoSManagementInput.
export const BSS_SetQoSManagementInput = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.SetQoSManagementInput.",
    schema: {
        "QosMapEnable": dm_type.BOOL,
        "MSCSEnable": dm_type.BOOL,
        "SCSEnable": dm_type.BOOL,
        "DSCPPolicyEnable": dm_type.BOOL,
        "SCSTrafficDescriptionEnable": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.STRFreqSeparation.{i}.
export const WiFi7bSTARole_STRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.STRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.STRFreqSeparation.{i}.
export const WiFi7APRole_STRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.STRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.SteeringHistory.{i}.
export const AssociatedDevice_SteeringHistory = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.SteeringHistory.{i}.",
    schema: {
        "Time": dm_type.DATETIME,
        "APOrigin": dm_type.STRING,
        "TriggerEvent": dm_type.STRING,
        "SteeringApproach": dm_type.STRING,
        "APDestination": dm_type.STRING,
        "SteeringDuration": dm_type.UINT
    },
    defaults: {
        "APOrigin": "",
        "TriggerEvent": "",
        "SteeringApproach": "",
        "APDestination": "",
        "SteeringDuration": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACAvailableChannel.{i}.
export const CACStatus_CACAvailableChannel = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACAvailableChannel.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT,
        "Minutes": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "Channel": "0",
        "Minutes": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMBackhaul.{i}.
export const Capabilities_AKMBackhaul = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMBackhaul.{i}.",
    schema: {
        "OUI": dm_type.BASE64,
        "Type": dm_type.UINT
    },
    defaults: {
        "Type": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.TIDQueueSizes.{i}.
export const STA_TIDQueueSizes = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.TIDQueueSizes.{i}.",
    schema: {
        "TID": dm_type.UINT,
        "Size": dm_type.UINT
    },
    defaults: {
        "TID": "0",
        "Size": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.ANQP.
export const AccessPoint_ANQP = {
    path: "Device.WiFi.AccessPoint.{i}.ANQP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "IPv4AddressAvailability": dm_type.STRING | dm_type.WRITABLE,
        "IPv6AddressAvailability": dm_type.STRING | dm_type.WRITABLE,
        "VenueName": dm_type.STRING | dm_type.WRITABLE,
        "RoamingConsortiumOIs": dm_type.STRING | dm_type.WRITABLE,
        "NAIRealms": dm_type.STRING | dm_type.WRITABLE,
        "Domains": dm_type.STRING | dm_type.WRITABLE,
        "AdviceOfCharges": dm_type.STRING | dm_type.WRITABLE,
        "NetworkAuthTypes": dm_type.STRING | dm_type.WRITABLE,
        "Cellular3GPPNetworkInfo": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "IPv4AddressAvailability": "",
        "IPv6AddressAvailability": "",
        "VenueName": "",
        "RoamingConsortiumOIs": "",
        "NAIRealms": "",
        "Domains": "",
        "AdviceOfCharges": "",
        "NetworkAuthTypes": "",
        "Cellular3GPPNetworkInfo": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUStats.
export const BSS_MUStats = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUStats.",
    schema: {
        "DLTotalPPDUCount": dm_type.STRING,
        "DLHEPPDUCount": dm_type.STRING,
        "DLMUPPDUCount": dm_type.STRING,
        "DLOFDMAPPDUCount": dm_type.STRING,
        "DLMUMIMOPPDUCount": dm_type.STRING,
        "DLOFDMAMUMIMOPPDUCount": dm_type.STRING,
        "ULTotalPPDUCount": dm_type.STRING,
        "ULHEPPDUCount": dm_type.STRING,
        "ULMUPPDUCount": dm_type.STRING,
        "ULOFDMAPPDUCount": dm_type.STRING,
        "ULMUMIMOPPDUCount": dm_type.STRING,
        "ULOFDMAMUMIMOPPDUCount": dm_type.STRING,
        "DLRU26PPDUCount": dm_type.STRING,
        "DLRU52PPDUCount": dm_type.STRING,
        "DLRU106PPDUCount": dm_type.STRING,
        "DLRU242PPDUCount": dm_type.STRING,
        "DLRU484PPDUCount": dm_type.STRING,
        "DLRU996PPDUCount": dm_type.STRING,
        "DLRU1992PPDUCount": dm_type.STRING,
        "ULRU26PPDUCount": dm_type.STRING,
        "ULRU52PPDUCount": dm_type.STRING,
        "ULRU106PPDUCount": dm_type.STRING,
        "ULRU242PPDUCount": dm_type.STRING,
        "ULRU484PPDUCount": dm_type.STRING,
        "ULRU996PPDUCount": dm_type.STRING,
        "ULRU1992PPDUCount": dm_type.STRING
    },
    defaults: {
        "DLTotalPPDUCount": "",
        "DLHEPPDUCount": "",
        "DLMUPPDUCount": "",
        "DLOFDMAPPDUCount": "",
        "DLMUMIMOPPDUCount": "",
        "DLOFDMAMUMIMOPPDUCount": "",
        "ULTotalPPDUCount": "",
        "ULHEPPDUCount": "",
        "ULMUPPDUCount": "",
        "ULOFDMAPPDUCount": "",
        "ULMUMIMOPPDUCount": "",
        "ULOFDMAMUMIMOPPDUCount": "",
        "DLRU26PPDUCount": "",
        "DLRU52PPDUCount": "",
        "DLRU106PPDUCount": "",
        "DLRU242PPDUCount": "",
        "DLRU484PPDUCount": "",
        "DLRU996PPDUCount": "",
        "DLRU1992PPDUCount": "",
        "ULRU26PPDUCount": "",
        "ULRU52PPDUCount": "",
        "ULRU106PPDUCount": "",
        "ULRU242PPDUCount": "",
        "ULRU484PPDUCount": "",
        "ULRU996PPDUCount": "",
        "ULRU1992PPDUCount": ""
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.Passpoint.
export const AccessPoint_Passpoint = {
    path: "Device.WiFi.AccessPoint.{i}.Passpoint.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Version": dm_type.STRING,
        "OperatorFriendlyName": dm_type.STRING | dm_type.WRITABLE,
        "DGAFDisable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Version": "",
        "OperatorFriendlyName": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.
export const Radio_BSS = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "SSID": dm_type.STRING,
        "Enabled": dm_type.BOOL,
        "LastChange": dm_type.UINT,
        "TimeStamp": dm_type.DATETIME,
        "UnicastBytesSent": dm_type.STRING,
        "UnicastBytesReceived": dm_type.STRING,
        "MulticastBytesSent": dm_type.STRING,
        "MulticastBytesReceived": dm_type.STRING,
        "BroadcastBytesSent": dm_type.STRING,
        "BroadcastBytesReceived": dm_type.STRING,
        "ByteCounterUnits": dm_type.UINT,
        "Profile1bSTAsDisallowed": dm_type.BOOL,
        "Profile2bSTAsDisallowed": dm_type.BOOL,
        "AssociationAllowanceStatus": dm_type.UINT,
        "EstServiceParametersBE": dm_type.BASE64,
        "EstServiceParametersBK": dm_type.BASE64,
        "EstServiceParametersVI": dm_type.BASE64,
        "EstServiceParametersVO": dm_type.BASE64,
        "BackhaulUse": dm_type.BOOL,
        "FronthaulUse": dm_type.BOOL,
        "R1disallowed": dm_type.BOOL,
        "R2disallowed": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "TransmittedBSSID": dm_type.BOOL,
        "FronthaulAKMsAllowed": dm_type.STRING | dm_type.WRITABLE,
        "FronthaulSuiteSelector": dm_type.HEXBIN | dm_type.WRITABLE,
        "BackhaulAKMsAllowed": dm_type.STRING | dm_type.WRITABLE,
        "BackhaulSuiteSelector": dm_type.HEXBIN | dm_type.WRITABLE,
        "BasicDataTransmitRates": dm_type.UINT,
        "STANumberOfEntries": dm_type.UINT,
        "QMDescriptorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "BSSID": "",
        "SSID": "",
        "LastChange": "0",
        "UnicastBytesSent": "",
        "UnicastBytesReceived": "",
        "MulticastBytesSent": "",
        "MulticastBytesReceived": "",
        "BroadcastBytesSent": "",
        "BroadcastBytesReceived": "",
        "ByteCounterUnits": "0",
        "AssociationAllowanceStatus": "0",
        "FronthaulAKMsAllowed": "",
        "BackhaulAKMsAllowed": "",
        "BasicDataTransmitRates": "0",
        "STANumberOfEntries": "0",
        "QMDescriptorNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.MultiAP.SteeringSummaryStats.
export const MultiAP_SteeringSummaryStats = {
    path: "Device.WiFi.MultiAP.SteeringSummaryStats.",
    schema: {
        "NoCandidateAPFailures": dm_type.STRING,
        "BlacklistAttempts": dm_type.STRING,
        "BlacklistSuccesses": dm_type.STRING,
        "BlacklistFailures": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMSuccesses": dm_type.STRING,
        "BTMFailures": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING
    },
    defaults: {
        "NoCandidateAPFailures": "",
        "BlacklistAttempts": "",
        "BlacklistSuccesses": "",
        "BlacklistFailures": "",
        "BTMAttempts": "",
        "BTMSuccesses": "",
        "BTMFailures": "",
        "BTMQueryResponses": ""
    }
};

// Schema for Device.WiFi.EndPoint.{i}.Stats.
export const EndPoint_Stats = {
    path: "Device.WiFi.EndPoint.{i}.Stats.",
    schema: {
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "SignalStrength": dm_type.INT,
        "Retransmissions": dm_type.UINT
    },
    defaults: {
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "SignalStrength": "0",
        "Retransmissions": "0"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.Profile.{i}.Security.
export const Profile_Security = {
    path: "Device.WiFi.EndPoint.{i}.Profile.{i}.Security.",
    schema: {
        "ModeEnabled": dm_type.STRING | dm_type.WRITABLE,
        "WEPKey": dm_type.HEXBIN | dm_type.WRITABLE,
        "PreSharedKey": dm_type.HEXBIN | dm_type.WRITABLE,
        "KeyPassphrase": dm_type.STRING | dm_type.WRITABLE,
        "SAEPassphrase": dm_type.STRING | dm_type.WRITABLE,
        "MFPConfig": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ModeEnabled": "",
        "KeyPassphrase": "",
        "SAEPassphrase": "",
        "MFPConfig": "Disabled"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLSRFreqSeparation.{i}.
export const WiFi7APRole_EMLSRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLSRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.Accounting.
export const AccessPoint_Accounting = {
    path: "Device.WiFi.AccessPoint.{i}.Accounting.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ServerIPAddr": dm_type.STRING | dm_type.WRITABLE,
        "SecondaryServerIPAddr": dm_type.STRING | dm_type.WRITABLE,
        "ServerPort": dm_type.UINT | dm_type.WRITABLE,
        "SecondaryServerPort": dm_type.UINT | dm_type.WRITABLE,
        "Secret": dm_type.STRING | dm_type.WRITABLE,
        "SecondarySecret": dm_type.STRING | dm_type.WRITABLE,
        "InterimInterval": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "ServerIPAddr": "",
        "SecondaryServerIPAddr": "",
        "ServerPort": "1813",
        "SecondaryServerPort": "1813",
        "Secret": "",
        "SecondarySecret": "",
        "InterimInterval": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MultiAPSteering.
export const BSS_MultiAPSteering = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MultiAPSteering.",
    schema: {
        "BlacklistAttempts": dm_type.STRING,
        "BlacklistSuccesses": dm_type.STRING,
        "BlacklistFailures": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMSuccesses": dm_type.STRING,
        "BTMFailures": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING
    },
    defaults: {
        "BlacklistAttempts": "",
        "BlacklistSuccesses": "",
        "BlacklistFailures": "",
        "BTMAttempts": "",
        "BTMSuccesses": "",
        "BTMFailures": "",
        "BTMQueryResponses": ""
    }
};

// Schema for Device.WiFi.DataElements.DisassociationEvent.DisassociationEventData.{i}.
export const DisassociationEvent_DisassociationEventData = {
    path: "Device.WiFi.DataElements.DisassociationEvent.DisassociationEventData.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "ReasonCode": dm_type.UINT,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "RetransCount": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "UtilizationReceive": dm_type.ULONG,
        "UtilizationTransmit": dm_type.ULONG,
        "EstMACDataRateDownlink": dm_type.UINT,
        "EstMACDataRateUplink": dm_type.UINT,
        "SignalStrength": dm_type.UINT,
        "LastConnectTime": dm_type.UINT,
        "Noise": dm_type.UINT,
        "InitiatedBy": dm_type.STRING,
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT
    },
    defaults: {
        "BSSID": "",
        "MACAddress": "",
        "ReasonCode": "0",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "RetransCount": "",
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "UtilizationReceive": "0",
        "UtilizationTransmit": "0",
        "EstMACDataRateDownlink": "0",
        "EstMACDataRateUplink": "0",
        "SignalStrength": "0",
        "LastConnectTime": "0",
        "Noise": "0",
        "InitiatedBy": "",
        "OpClass": "0",
        "Channel": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.SSIDtoVIDMapping.{i}.
export const Device_SSIDtoVIDMapping = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.SSIDtoVIDMapping.{i}.",
    schema: {
        "SSID": dm_type.STRING,
        "VID": dm_type.UINT
    },
    defaults: {
        "SSID": "",
        "VID": "0"
    }
};

// Schema for Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.WiFi6Capabilities.
export const AssociationEventData_WiFi6Capabilities = {
    path: "Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.WiFi6Capabilities.",
    schema: {
        "HE160": dm_type.BOOL,
        "HE8080": dm_type.BOOL,
        "MCSNSS": dm_type.BASE64,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "Beamformee80orLess": dm_type.BOOL,
        "BeamformeeAbove80": dm_type.BOOL,
        "ULMUMIMO": dm_type.BOOL,
        "ULOFDMA": dm_type.BOOL,
        "DLOFDMA": dm_type.BOOL,
        "MaxDLMUMIMO": dm_type.UINT,
        "MaxULMUMIMO": dm_type.UINT,
        "MaxDLOFDMA": dm_type.UINT,
        "MaxULOFDMA": dm_type.UINT,
        "RTS": dm_type.BOOL,
        "MURTS": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "MUEDCA": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "SpatialReuse": dm_type.BOOL,
        "AnticipatedChannelUsage": dm_type.BOOL
    },
    defaults: {
        "MaxDLMUMIMO": "0",
        "MaxULMUMIMO": "0",
        "MaxDLOFDMA": "0",
        "MaxULOFDMA": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.WPS.
export const Device_WPS = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.WPS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING
    },
    defaults: {
        "Status": ""
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.SteeringSummaryStats.
export const AssociatedDevice_SteeringSummaryStats = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.AssociatedDevice.{i}.SteeringSummaryStats.",
    schema: {
        "NoCandidateAPFailures": dm_type.STRING,
        "BlacklistAttempts": dm_type.STRING,
        "BlacklistSuccesses": dm_type.STRING,
        "BlacklistFailures": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMSuccesses": dm_type.STRING,
        "BTMFailures": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING,
        "LastSteerTime": dm_type.UINT
    },
    defaults: {
        "NoCandidateAPFailures": "",
        "BlacklistAttempts": "",
        "BlacklistSuccesses": "",
        "BlacklistFailures": "",
        "BTMAttempts": "",
        "BTMSuccesses": "",
        "BTMFailures": "",
        "BTMQueryResponses": "",
        "LastSteerTime": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.NSTRFreqSeparation.{i}.
export const WiFi7bSTARole_NSTRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.NSTRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACNonOccupancyChannel.{i}.
export const CACStatus_CACNonOccupancyChannel = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACNonOccupancyChannel.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT,
        "Seconds": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "Channel": "0",
        "Seconds": "0"
    }
};

// Schema for Device.WiFi.Radio.{i}.
export const Radio = {
    path: "Device.WiFi.Radio.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "MaxBitRate": dm_type.UINT,
        "Upstream": dm_type.BOOL,
        "SupportedFrequencyBands": dm_type.STRING,
        "OperatingFrequencyBand": dm_type.STRING | dm_type.WRITABLE,
        "SupportedStandards": dm_type.STRING,
        "OperatingStandards": dm_type.STRING | dm_type.WRITABLE,
        "PossibleChannels": dm_type.STRING,
        "ChannelsInUse": dm_type.STRING,
        "Channel": dm_type.UINT | dm_type.WRITABLE,
        "AutoChannelSupported": dm_type.BOOL,
        "AutoChannelEnable": dm_type.BOOL | dm_type.WRITABLE,
        "AutoChannelRefreshPeriod": dm_type.UINT | dm_type.WRITABLE,
        "ChannelLastChange": dm_type.UINT,
        "ChannelLastSelectionReason": dm_type.STRING,
        "MaxSupportedSSIDs": dm_type.UINT,
        "MaxSupportedAssociations": dm_type.UINT,
        "FirmwareVersion": dm_type.STRING,
        "SupportedOperatingChannelBandwidths": dm_type.STRING,
        "OperatingChannelBandwidth": dm_type.STRING | dm_type.WRITABLE,
        "CurrentOperatingChannelBandwidth": dm_type.STRING,
        "ExtensionChannel": dm_type.STRING | dm_type.WRITABLE,
        "GuardInterval": dm_type.STRING | dm_type.WRITABLE,
        "CenterFrequencySegement0": dm_type.UINT | dm_type.WRITABLE,
        "CenterFrequencySegement1": dm_type.UINT | dm_type.WRITABLE,
        "CenterFrequencySegment0": dm_type.UINT | dm_type.WRITABLE,
        "CenterFrequencySegment1": dm_type.UINT | dm_type.WRITABLE,
        "MCS": dm_type.INT | dm_type.WRITABLE,
        "TransmitPowerSupported": dm_type.INT,
        "TransmitPower": dm_type.INT | dm_type.WRITABLE,
        "IEEE80211hSupported": dm_type.BOOL,
        "IEEE80211hEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "RegulatoryDomain": dm_type.STRING | dm_type.WRITABLE,
        "RetryLimit": dm_type.UINT | dm_type.WRITABLE,
        "CCARequest": dm_type.HEXBIN | dm_type.WRITABLE,
        "CCAReport": dm_type.HEXBIN,
        "RPIHistogramRequest": dm_type.HEXBIN | dm_type.WRITABLE,
        "RPIHistogramReport": dm_type.HEXBIN,
        "FragmentationThreshold": dm_type.UINT | dm_type.WRITABLE,
        "RTSThreshold": dm_type.UINT | dm_type.WRITABLE,
        "LongRetryLimit": dm_type.UINT | dm_type.WRITABLE,
        "BeaconPeriod": dm_type.UINT | dm_type.WRITABLE,
        "DTIMPeriod": dm_type.UINT | dm_type.WRITABLE,
        "PacketAggregationEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PreambleType": dm_type.STRING | dm_type.WRITABLE,
        "BasicDataTransmitRates": dm_type.STRING | dm_type.WRITABLE,
        "SupportedDataTransmitRates": dm_type.STRING,
        "OperationalDataTransmitRates": dm_type.STRING | dm_type.WRITABLE,
        "EnableRRM": dm_type.BOOL | dm_type.WRITABLE,
        "ManagementPacketRate": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "SupportedFrequencyBands": "",
        "OperatingFrequencyBand": "",
        "SupportedStandards": "",
        "OperatingStandards": "",
        "PossibleChannels": "",
        "ChannelsInUse": "",
        "Channel": "0",
        "AutoChannelRefreshPeriod": "0",
        "ChannelLastChange": "0",
        "ChannelLastSelectionReason": "",
        "MaxSupportedSSIDs": "0",
        "MaxSupportedAssociations": "0",
        "FirmwareVersion": "",
        "SupportedOperatingChannelBandwidths": "",
        "OperatingChannelBandwidth": "",
        "CurrentOperatingChannelBandwidth": "",
        "ExtensionChannel": "",
        "GuardInterval": "",
        "CenterFrequencySegement0": "0",
        "CenterFrequencySegement1": "0",
        "CenterFrequencySegment0": "0",
        "CenterFrequencySegment1": "0",
        "MCS": "0",
        "TransmitPowerSupported": "0",
        "TransmitPower": "0",
        "RegulatoryDomain": "",
        "RetryLimit": "0",
        "FragmentationThreshold": "0",
        "RTSThreshold": "0",
        "LongRetryLimit": "0",
        "BeaconPeriod": "0",
        "DTIMPeriod": "0",
        "PreambleType": "",
        "BasicDataTransmitRates": "",
        "SupportedDataTransmitRates": "",
        "OperationalDataTransmitRates": "",
        "ManagementPacketRate": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD.
export const Device_bSTAMLD = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD.",
    schema: {
        "MLDMACAddress": dm_type.STRING,
        "BSSID": dm_type.STRING,
        "AffiliatedbSTAList": dm_type.STRING
    },
    defaults: {
        "MLDMACAddress": "",
        "BSSID": "",
        "AffiliatedbSTAList": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.
export const Radio_ScanResult = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "AggregateScanDuration": dm_type.UINT,
        "ScanType": dm_type.BOOL,
        "OpClassScanNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "AggregateScanDuration": "0",
        "OpClassScanNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.WiFi7Capabilities.
export const STAMLD_WiFi7Capabilities = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.WiFi7Capabilities.",
    schema: {
        "EMLMRSupport": dm_type.BOOL,
        "EMLSRSupport": dm_type.BOOL,
        "STRSupport": dm_type.BOOL,
        "NSTRSupport": dm_type.BOOL,
        "TIDLinkMapNegotiation": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.
export const Radio_CACCapability = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.",
    schema: {
        "CACMethodNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CACMethodNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.AFCAvailableSpectrum.
export const Device_AFCAvailableSpectrum = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.AFCAvailableSpectrum.",
    schema: {
        "AFCAvailableSpectrumInquiryRequest": dm_type.STRING,
        "AFCAvailableSpectrumInquiryResponse": dm_type.STRING
    },
    defaults: {
        "AFCAvailableSpectrumInquiryRequest": "",
        "AFCAvailableSpectrumInquiryResponse": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.UnassociatedSTA.{i}.
export const Radio_UnassociatedSTA = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.UnassociatedSTA.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "SignalStrength": dm_type.UINT,
        "OperatingClass": dm_type.UINT,
        "Channel": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "SignalStrength": "0",
        "OperatingClass": "0",
        "Channel": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.
export const CACCapability_CACMethod = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.",
    schema: {
        "Method": dm_type.UINT,
        "NumberOfSeconds": dm_type.UINT,
        "OpClassChannelsNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Method": "0",
        "NumberOfSeconds": "0",
        "OpClassChannelsNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.ThroughputTestResult.
export const BSS_ThroughputTestResult = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.ThroughputTestResult.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "ClientMAC": dm_type.STRING,
        "VID": dm_type.UINT,
        "WMMUP": dm_type.UINT,
        "TestDuration": dm_type.UINT,
        "TestLayer": dm_type.UINT,
        "TestAlgorithm": dm_type.STRING,
        "DownlinkSpeed": dm_type.UINT,
        "UplinkSpeed": dm_type.UINT
    },
    defaults: {
        "ClientMAC": "",
        "VID": "0",
        "WMMUP": "0",
        "TestDuration": "0",
        "TestLayer": "0",
        "TestAlgorithm": "",
        "DownlinkSpeed": "0",
        "UplinkSpeed": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.
export const Device_APMLD = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.",
    schema: {
        "MLDMACAddress": dm_type.STRING,
        "TIDLinkMapNumberOfEntries": dm_type.UINT,
        "AffiliatedAPNumberOfEntries": dm_type.UINT,
        "STAMLDNumberOfEntries": dm_type.UINT,
        "LinkToOpClassMapNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MLDMACAddress": "",
        "TIDLinkMapNumberOfEntries": "0",
        "AffiliatedAPNumberOfEntries": "0",
        "STAMLDNumberOfEntries": "0",
        "LinkToOpClassMapNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.
export const Radio_AP = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.AP.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "SSID": dm_type.STRING,
        "BlacklistAttempts": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING,
        "AssociatedDeviceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "BSSID": "",
        "SSID": "",
        "BlacklistAttempts": "",
        "BTMAttempts": "",
        "BTMQueryResponses": "",
        "AssociatedDeviceNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.SSID.{i}.Stats.
export const SSID_Stats = {
    path: "Device.WiFi.SSID.{i}.Stats.",
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
        "RetransCount": dm_type.UINT,
        "FailedRetransCount": dm_type.UINT,
        "RetryCount": dm_type.UINT,
        "MultipleRetryCount": dm_type.UINT,
        "ACKFailureCount": dm_type.UINT,
        "AggregatedPacketCount": dm_type.UINT,
        "DiscardPacketsSentBufOverflow": dm_type.STRING,
        "DiscardPacketsSentNoAssoc": dm_type.STRING,
        "FragSent": dm_type.STRING,
        "SentNoAck": dm_type.STRING,
        "DupReceived": dm_type.STRING,
        "TooLongReceived": dm_type.STRING,
        "TooShortReceived": dm_type.STRING,
        "AckUcastReceived": dm_type.STRING
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
        "RetransCount": "0",
        "FailedRetransCount": "0",
        "RetryCount": "0",
        "MultipleRetryCount": "0",
        "ACKFailureCount": "0",
        "AggregatedPacketCount": "0",
        "DiscardPacketsSentBufOverflow": "",
        "DiscardPacketsSentNoAssoc": "",
        "FragSent": "",
        "SentNoAck": "",
        "DupReceived": "",
        "TooLongReceived": "",
        "TooShortReceived": "",
        "AckUcastReceived": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.CapableOperatingClassProfile.{i}.
export const Capabilities_CapableOperatingClassProfile = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.CapableOperatingClassProfile.{i}.",
    schema: {
        "Class": dm_type.UINT,
        "MaxTxPower": dm_type.INT,
        "NonOperable": dm_type.UINT,
        "NumberOfNonOperChan": dm_type.UINT
    },
    defaults: {
        "Class": "0",
        "MaxTxPower": "0",
        "NonOperable": "0",
        "NumberOfNonOperChan": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.SPRule.{i}.
export const Device_SPRule = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.SPRule.{i}.",
    schema: {
        "ID": dm_type.UINT,
        "Precedence": dm_type.UINT,
        "Output": dm_type.UINT,
        "AlwaysMatch": dm_type.BOOL
    },
    defaults: {
        "ID": "0",
        "Precedence": "0",
        "Output": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BackhaulSta.
export const Radio_BackhaulSta = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BackhaulSta.",
    schema: {
        "MACAddress": dm_type.STRING
    },
    defaults: {
        "MACAddress": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CurrentOperatingClassProfile.{i}.
export const Radio_CurrentOperatingClassProfile = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CurrentOperatingClassProfile.{i}.",
    schema: {
        "Class": dm_type.UINT,
        "Channel": dm_type.UINT,
        "TxPower": dm_type.INT,
        "TransmitPowerLimit": dm_type.INT,
        "TimeStamp": dm_type.DATETIME
    },
    defaults: {
        "Class": "0",
        "Channel": "0",
        "TxPower": "0",
        "TransmitPowerLimit": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.MultiAPSteeringSummaryStats.
export const Network_MultiAPSteeringSummaryStats = {
    path: "Device.WiFi.DataElements.Network.MultiAPSteeringSummaryStats.",
    schema: {
        "NoCandidateAPFailures": dm_type.STRING,
        "BlacklistAttempts": dm_type.STRING,
        "BlacklistSuccesses": dm_type.STRING,
        "BlacklistFailures": dm_type.STRING,
        "BTMAttempts": dm_type.STRING,
        "BTMSuccesses": dm_type.STRING,
        "BTMFailures": dm_type.STRING,
        "BTMQueryResponses": dm_type.STRING
    },
    defaults: {
        "NoCandidateAPFailures": "",
        "BlacklistAttempts": "",
        "BlacklistSuccesses": "",
        "BlacklistFailures": "",
        "BTMAttempts": "",
        "BTMSuccesses": "",
        "BTMFailures": "",
        "BTMQueryResponses": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD.bSTAMLDConfig.
export const bSTAMLD_bSTAMLDConfig = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD.bSTAMLDConfig.",
    schema: {
        "EMLMREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "EMLSREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "STREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "NSTREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "TIDLinkMapNegotiation": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {}
};

// Schema for Device.WiFi.EndPoint.{i}.WPS.
export const EndPoint_WPS = {
    path: "Device.WiFi.EndPoint.{i}.WPS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ConfigMethodsSupported": dm_type.STRING,
        "ConfigMethodsEnabled": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Version": dm_type.STRING,
        "PIN": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "ConfigMethodsSupported": "",
        "ConfigMethodsEnabled": "",
        "Status": "",
        "Version": "",
        "PIN": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.LatencyTestResult.
export const BSS_LatencyTestResult = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.LatencyTestResult.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "ClientMAC": dm_type.STRING,
        "VID": dm_type.UINT,
        "WMMUP": dm_type.UINT,
        "DataBlockSize": dm_type.UINT,
        "TestLayer": dm_type.UINT,
        "TestAlgorithm": dm_type.STRING,
        "SuccessCount": dm_type.UINT,
        "LostCount": dm_type.UINT,
        "AverageResponseTime": dm_type.UINT,
        "MinimumResponseTime": dm_type.UINT,
        "MaximumResponseTime": dm_type.UINT
    },
    defaults: {
        "ClientMAC": "",
        "VID": "0",
        "WMMUP": "0",
        "DataBlockSize": "0",
        "TestLayer": "0",
        "TestAlgorithm": "",
        "SuccessCount": "0",
        "LostCount": "0",
        "AverageResponseTime": "0",
        "MinimumResponseTime": "0",
        "MaximumResponseTime": "0"
    }
};

// Schema for Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.
export const APDevice_Radio = {
    path: "Device.WiFi.MultiAP.APDevice.{i}.Radio.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "OperatingFrequencyBand": dm_type.STRING,
        "OperatingStandards": dm_type.STRING,
        "Channel": dm_type.UINT | dm_type.WRITABLE,
        "ExtensionChannel": dm_type.STRING,
        "PossibleChannels": dm_type.STRING,
        "CurrentOperatingChannelBandwidth": dm_type.STRING,
        "MCS": dm_type.INT,
        "TransmitPower": dm_type.INT,
        "TransmitPowerLimit": dm_type.INT | dm_type.WRITABLE,
        "APNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MACAddress": "",
        "OperatingFrequencyBand": "",
        "OperatingStandards": "",
        "Channel": "0",
        "ExtensionChannel": "",
        "PossibleChannels": "",
        "CurrentOperatingChannelBandwidth": "",
        "MCS": "0",
        "TransmitPower": "0",
        "TransmitPowerLimit": "0",
        "APNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.WiFi6Capabilities.
export const STA_WiFi6Capabilities = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.WiFi6Capabilities.",
    schema: {
        "HE160": dm_type.BOOL,
        "HE8080": dm_type.BOOL,
        "MCSNSS": dm_type.BASE64,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "Beamformee80orLess": dm_type.BOOL,
        "BeamformeeAbove80": dm_type.BOOL,
        "ULMUMIMO": dm_type.BOOL,
        "ULOFDMA": dm_type.BOOL,
        "DLOFDMA": dm_type.BOOL,
        "MaxDLMUMIMO": dm_type.UINT,
        "MaxULMUMIMO": dm_type.UINT,
        "MaxDLOFDMA": dm_type.UINT,
        "MaxULOFDMA": dm_type.UINT,
        "RTS": dm_type.BOOL,
        "MURTS": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "MUEDCA": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "SpatialReuse": dm_type.BOOL,
        "AnticipatedChannelUsage": dm_type.BOOL
    },
    defaults: {
        "MaxDLMUMIMO": "0",
        "MaxULMUMIMO": "0",
        "MaxDLOFDMA": "0",
        "MaxULOFDMA": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.AffiliatedSTA.{i}.
export const STAMLD_AffiliatedSTA = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.AffiliatedSTA.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "BSSID": dm_type.STRING,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "SignalStrength": dm_type.UINT,
        "EstMACDataRateDownlink": dm_type.UINT,
        "EstMACDataRateUplink": dm_type.UINT,
        "LastDataDownlinkRate": dm_type.UINT,
        "LastDataUplinkRate": dm_type.UINT,
        "UtilizationReceive": dm_type.ULONG,
        "UtilizationTransmit": dm_type.ULONG
    },
    defaults: {
        "MACAddress": "",
        "BSSID": "",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "SignalStrength": "0",
        "EstMACDataRateDownlink": "0",
        "EstMACDataRateUplink": "0",
        "LastDataDownlinkRate": "0",
        "LastDataUplinkRate": "0",
        "UtilizationReceive": "0",
        "UtilizationTransmit": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.
export const Device_MultiAPDevice = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.",
    schema: {
        "ManufacturerOUI": dm_type.STRING,
        "LastContactTime": dm_type.DATETIME,
        "AssocIEEE1905DeviceRef": dm_type.STRING,
        "EasyMeshControllerOperationMode": dm_type.STRING,
        "EasyMeshAgentOperationMode": dm_type.STRING
    },
    defaults: {
        "ManufacturerOUI": "",
        "AssocIEEE1905DeviceRef": "",
        "EasyMeshControllerOperationMode": "",
        "EasyMeshAgentOperationMode": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.IEEE1905Security.{i}.
export const Device_IEEE1905Security = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.IEEE1905Security.{i}.",
    schema: {
        "OnboardingProtocol": dm_type.UINT,
        "IntegrityAlgorithm": dm_type.UINT,
        "EncryptionAlgorithm": dm_type.UINT
    },
    defaults: {
        "OnboardingProtocol": "0",
        "IntegrityAlgorithm": "0",
        "EncryptionAlgorithm": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.MultiAPRadio.
export const Radio_MultiAPRadio = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.MultiAPRadio.",
    schema: {
        "RadarDetections": dm_type.UINT
    },
    defaults: {
        "RadarDetections": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.ProvisionedDPP.{i}.
export const Network_ProvisionedDPP = {
    path: "Device.WiFi.DataElements.Network.ProvisionedDPP.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "DPPURI": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "DPPURI": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STATIDLinkMap.{i}.
export const STAMLD_STATIDLinkMap = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STATIDLinkMap.{i}.",
    schema: {
        "Direction": dm_type.STRING,
        "TID": dm_type.UINT,
        "BSSID": dm_type.STRING,
        "LinkID": dm_type.UINT
    },
    defaults: {
        "Direction": "",
        "TID": "0",
        "BSSID": "",
        "LinkID": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUConfig.
export const BSS_MUConfig = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUConfig.",
    schema: {
        "DLOFDMAEnable": dm_type.BOOL | dm_type.WRITABLE,
        "ULOFDMAEnable": dm_type.BOOL | dm_type.WRITABLE,
        "DLMUMIMOEnable": dm_type.BOOL | dm_type.WRITABLE,
        "ULMUMIMOEnable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {}
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.
export const Device_AnticipatedChannelUsage = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT,
        "ReferenceBSSID": dm_type.STRING,
        "EntryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "Channel": "0",
        "ReferenceBSSID": "",
        "EntryNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.FailedConnectionEvent.
export const DataElements_FailedConnectionEvent = {
    path: "Device.WiFi.DataElements.FailedConnectionEvent.",
    schema: {
        "FailedConnectionEventDataNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "FailedConnectionEventDataNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.AssociationEvent.
export const DataElements_AssociationEvent = {
    path: "Device.WiFi.DataElements.AssociationEvent.",
    schema: {
        "AssociationEventDataNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "AssociationEventDataNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.OpClassPreference.{i}.
export const Radio_OpClassPreference = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.OpClassPreference.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "ChannelList": dm_type.UINT,
        "Preference": dm_type.UINT,
        "ReasonCode": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "ChannelList": "0",
        "Preference": "0",
        "ReasonCode": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.
export const Device_CACStatus = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "CACAvailableChannelNumberOfEntries": dm_type.UINT,
        "CACNonOccupancyChannelNumberOfEntries": dm_type.UINT,
        "CACActiveChannelNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CACAvailableChannelNumberOfEntries": "0",
        "CACNonOccupancyChannelNumberOfEntries": "0",
        "CACActiveChannelNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.FailedConnectionEvent.FailedConnectionEventData.{i}.
export const FailedConnectionEvent_FailedConnectionEventData = {
    path: "Device.WiFi.DataElements.FailedConnectionEvent.FailedConnectionEventData.{i}.",
    schema: {
        "BSSID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "StatusCode": dm_type.UINT,
        "ReasonCode": dm_type.UINT,
        "TimeStamp": dm_type.DATETIME
    },
    defaults: {
        "BSSID": "",
        "MACAddress": "",
        "StatusCode": "0",
        "ReasonCode": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.
export const Network_Device = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.",
    schema: {
        "ID": dm_type.STRING,
        "MultiAPCapabilities": dm_type.BASE64,
        "CollectionInterval": dm_type.UINT,
        "ReportUnsuccessfulAssociations": dm_type.BOOL | dm_type.WRITABLE,
        "MaxReportingRate": dm_type.UINT,
        "APMetricsReportingInterval": dm_type.UINT | dm_type.WRITABLE,
        "AssociatedSTAReportingInterval": dm_type.UINT | dm_type.WRITABLE,
        "Manufacturer": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "ManufacturerModel": dm_type.STRING,
        "SoftwareVersion": dm_type.STRING,
        "ExecutionEnv": dm_type.STRING,
        "DSCPMap": dm_type.HEXBIN,
        "MaxPrioritizationRules": dm_type.UINT,
        "PrioritizationSupport": dm_type.BOOL,
        "MaxVIDs": dm_type.UINT,
        "APMetricsWiFi6": dm_type.BOOL,
        "CountryCode": dm_type.STRING,
        "LocalSteeringDisallowedSTAList": dm_type.STRING | dm_type.WRITABLE,
        "BTMSteeringDisallowedSTAList": dm_type.STRING | dm_type.WRITABLE,
        "DFSEnable": dm_type.BOOL,
        "ReportIndependentScans": dm_type.BOOL | dm_type.WRITABLE,
        "AssociatedSTAinAPMetricsWiFi6": dm_type.BOOL | dm_type.WRITABLE,
        "MaxUnsuccessfulAssociationReportingRate": dm_type.UINT | dm_type.WRITABLE,
        "STASteeringState": dm_type.BOOL,
        "CoordinatedCACAllowed": dm_type.BOOL | dm_type.WRITABLE,
        "TrafficSeparationAllowed": dm_type.BOOL,
        "ServicePrioritizationAllowed": dm_type.BOOL,
        "ControllerOperationMode": dm_type.STRING,
        "BackhaulMACAddress": dm_type.STRING,
        "BackhaulALID": dm_type.STRING,
        "BackhaulDownMACAddress": dm_type.STRING,
        "BackhaulMediaType": dm_type.STRING,
        "BackhaulPHYRate": dm_type.UINT,
        "TrafficSeparationCapability": dm_type.BOOL,
        "EasyConnectCapability": dm_type.BOOL,
        "TestCapabilities": dm_type.UINT,
        "RadioNumberOfEntries": dm_type.UINT,
        "Default8021QNumberOfEntries": dm_type.UINT,
        "SSIDtoVIDMappingNumberOfEntries": dm_type.UINT,
        "CACStatusNumberOfEntries": dm_type.UINT,
        "IEEE1905SecurityNumberOfEntries": dm_type.UINT,
        "SPRuleNumberOfEntries": dm_type.UINT,
        "AnticipatedChannelsNumberOfEntries": dm_type.UINT,
        "AnticipatedChannelUsageNumberOfEntries": dm_type.UINT,
        "MaxNumMLDs": dm_type.UINT,
        "APMLDMaxLinks": dm_type.UINT,
        "bSTAMLDMaxLinks": dm_type.UINT,
        "TIDLinkMapCapability": dm_type.STRING,
        "APMLDNumberOfEntries": dm_type.UINT,
        "BackhaulDownNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ID": "",
        "CollectionInterval": "0",
        "MaxReportingRate": "0",
        "APMetricsReportingInterval": "0",
        "AssociatedSTAReportingInterval": "0",
        "Manufacturer": "",
        "SerialNumber": "",
        "ManufacturerModel": "",
        "SoftwareVersion": "",
        "ExecutionEnv": "",
        "MaxPrioritizationRules": "0",
        "MaxVIDs": "0",
        "CountryCode": "",
        "LocalSteeringDisallowedSTAList": "",
        "BTMSteeringDisallowedSTAList": "",
        "MaxUnsuccessfulAssociationReportingRate": "0",
        "ControllerOperationMode": "",
        "BackhaulMACAddress": "",
        "BackhaulALID": "",
        "BackhaulDownMACAddress": "",
        "BackhaulMediaType": "",
        "BackhaulPHYRate": "0",
        "TestCapabilities": "0",
        "RadioNumberOfEntries": "0",
        "Default8021QNumberOfEntries": "0",
        "SSIDtoVIDMappingNumberOfEntries": "0",
        "CACStatusNumberOfEntries": "0",
        "IEEE1905SecurityNumberOfEntries": "0",
        "SPRuleNumberOfEntries": "0",
        "AnticipatedChannelsNumberOfEntries": "0",
        "AnticipatedChannelUsageNumberOfEntries": "0",
        "MaxNumMLDs": "0",
        "APMLDMaxLinks": "0",
        "bSTAMLDMaxLinks": "0",
        "TIDLinkMapCapability": "",
        "APMLDNumberOfEntries": "0",
        "BackhaulDownNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.TIDToOpClassPolicy.{i}.
export const APMLDConfig_TIDToOpClassPolicy = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.TIDToOpClassPolicy.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "TID": dm_type.UINT | dm_type.WRITABLE,
        "OpClass": dm_type.UINT | dm_type.WRITABLE,
        "Direction": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "TID": "0",
        "OpClass": "0",
        "Direction": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACActiveChannel.{i}.
export const CACStatus_CACActiveChannel = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACActiveChannel.{i}.",
    schema: {
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT,
        "Countdown": dm_type.UINT
    },
    defaults: {
        "OpClass": "0",
        "Channel": "0",
        "Countdown": "0"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.AC.{i}.Stats.
export const AC_Stats = {
    path: "Device.WiFi.EndPoint.{i}.AC.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "RetransCount": dm_type.STRING,
        "OutQLenHistogram": dm_type.STRING
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
        "RetransCount": "",
        "OutQLenHistogram": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6APRole.
export const Capabilities_WiFi6APRole = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6APRole.",
    schema: {
        "HE160": dm_type.BOOL,
        "HE8080": dm_type.BOOL,
        "MCSNSS": dm_type.BASE64,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "Beamformee80orLess": dm_type.BOOL,
        "BeamformeeAbove80": dm_type.BOOL,
        "ULMUMIMO": dm_type.BOOL,
        "ULOFDMA": dm_type.BOOL,
        "DLOFDMA": dm_type.BOOL,
        "MaxDLMUMIMO": dm_type.UINT,
        "MaxULMUMIMO": dm_type.UINT,
        "MaxDLOFDMA": dm_type.UINT,
        "MaxULOFDMA": dm_type.UINT,
        "RTS": dm_type.BOOL,
        "MURTS": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "MUEDCA": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "SpatialReuse": dm_type.BOOL,
        "AnticipatedChannelUsage": dm_type.BOOL
    },
    defaults: {
        "MaxDLMUMIMO": "0",
        "MaxULMUMIMO": "0",
        "MaxDLOFDMA": "0",
        "MaxULOFDMA": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.PreferredBackhauls.{i}.
export const Network_PreferredBackhauls = {
    path: "Device.WiFi.DataElements.Network.PreferredBackhauls.{i}.",
    schema: {
        "BackhaulMACAddress": dm_type.STRING,
        "bSTAMACAddress": dm_type.STRING
    },
    defaults: {
        "BackhaulMACAddress": "",
        "bSTAMACAddress": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.
export const APMLD_STAMLD = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.",
    schema: {
        "MLDMACAddress": dm_type.STRING,
        "Hostname": dm_type.STRING,
        "IPv4Address": dm_type.STRING,
        "IPv6Address": dm_type.STRING,
        "IsbSTA": dm_type.BOOL,
        "LastConnectTime": dm_type.UINT,
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "RetransCount": dm_type.STRING,
        "PairwiseAKM": dm_type.HEXBIN,
        "PairwiseCipher": dm_type.HEXBIN,
        "RSNCapabilities": dm_type.UINT,
        "STATIDLinkMapNumberOfEntries": dm_type.UINT,
        "AffiliatedSTANumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MLDMACAddress": "",
        "Hostname": "",
        "IPv4Address": "",
        "IPv6Address": "",
        "LastConnectTime": "0",
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "RetransCount": "",
        "RSNCapabilities": "0",
        "STATIDLinkMapNumberOfEntries": "0",
        "AffiliatedSTANumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.
export const Radio_ScanCapability = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.",
    schema: {
        "OnBootOnly": dm_type.BOOL,
        "Impact": dm_type.UINT,
        "MinimumInterval": dm_type.UINT,
        "OpClassChannelsNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Impact": "0",
        "MinimumInterval": "0",
        "OpClassChannelsNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.
export const Capabilities_WiFi7APRole = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.",
    schema: {
        "EMLMRSupport": dm_type.BOOL,
        "EMLSRSupport": dm_type.BOOL,
        "STRSupport": dm_type.BOOL,
        "NSTRSupport": dm_type.BOOL,
        "TIDLinkMapNegotiation": dm_type.BOOL,
        "EMLMRFreqSeparationNumberOfEntries": dm_type.UINT,
        "EMLSRFreqSeparationNumberOfEntries": dm_type.UINT,
        "STRFreqSeparationNumberOfEntries": dm_type.UINT,
        "NSTRFreqSeparationNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "EMLMRFreqSeparationNumberOfEntries": "0",
        "EMLSRFreqSeparationNumberOfEntries": "0",
        "STRFreqSeparationNumberOfEntries": "0",
        "NSTRFreqSeparationNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.LinkToOpClassMap.{i}.
export const APMLD_LinkToOpClassMap = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.LinkToOpClassMap.{i}.",
    schema: {
        "LinkID": dm_type.UINT,
        "OpClass": dm_type.UINT
    },
    defaults: {
        "LinkID": "0",
        "OpClass": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.AC.{i}.
export const AccessPoint_AC = {
    path: "Device.WiFi.AccessPoint.{i}.AC.{i}.",
    schema: {
        "AccessCategory": dm_type.STRING,
        "Alias": dm_type.STRING,
        "AIFSN": dm_type.UINT | dm_type.WRITABLE,
        "ECWMin": dm_type.UINT | dm_type.WRITABLE,
        "ECWMax": dm_type.UINT | dm_type.WRITABLE,
        "TxOpMax": dm_type.UINT | dm_type.WRITABLE,
        "AckPolicy": dm_type.BOOL | dm_type.WRITABLE,
        "OutQLenHistogramIntervals": dm_type.STRING | dm_type.WRITABLE,
        "OutQLenHistogramSampleInterval": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "AccessCategory": "",
        "Alias": "",
        "AIFSN": "0",
        "ECWMin": "0",
        "ECWMax": "0",
        "TxOpMax": "0",
        "OutQLenHistogramIntervals": "",
        "OutQLenHistogramSampleInterval": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.NSTRFreqSeparation.{i}.
export const WiFi7APRole_NSTRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.NSTRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.
export const OpClassScan_ChannelScan = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.",
    schema: {
        "Channel": dm_type.UINT,
        "TimeStamp": dm_type.DATETIME,
        "Utilization": dm_type.UINT,
        "Noise": dm_type.UINT,
        "ScanStatus": dm_type.STRING,
        "NeighborBSSNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Channel": "0",
        "Utilization": "0",
        "Noise": "0",
        "ScanStatus": "",
        "NeighborBSSNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.Entry.{i}.
export const AnticipatedChannelUsage_Entry = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.Entry.{i}.",
    schema: {
        "BurstStartTime": dm_type.HEXBIN,
        "BurstLength": dm_type.UINT,
        "Repetitions": dm_type.UINT,
        "BurstInterval": dm_type.UINT,
        "RUBitmask": dm_type.HEXBIN,
        "TransmitterIdentifier": dm_type.STRING,
        "PowerLevel": dm_type.INT,
        "ChannelUsageReason": dm_type.STRING
    },
    defaults: {
        "BurstLength": "0",
        "Repetitions": "0",
        "BurstInterval": "0",
        "TransmitterIdentifier": "",
        "PowerLevel": "0",
        "ChannelUsageReason": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.
export const APMLD_APMLDConfig = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.",
    schema: {
        "EMLMREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "EMLSREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "STREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "NSTREnabled": dm_type.BOOL | dm_type.WRITABLE,
        "TIDLinkMapNegotiation": dm_type.BOOL | dm_type.WRITABLE,
        "TIDToOpClassPolicyNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "TIDToOpClassPolicyNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.MultiAP.
export const MultiAP = {
    path: "Device.WiFi.MultiAP.",
    schema: {
        "APDeviceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "APDeviceNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.Profile.{i}.
export const EndPoint_Profile = {
    path: "Device.WiFi.EndPoint.{i}.Profile.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "SSID": dm_type.STRING | dm_type.WRITABLE,
        "Location": dm_type.STRING | dm_type.WRITABLE,
        "Priority": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "SSID": "",
        "Location": "",
        "Priority": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.CurrentOperatingClassProfile.{i}.
export const Backhaul_CurrentOperatingClassProfile = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.CurrentOperatingClassProfile.{i}.",
    schema: {
        "Class": dm_type.UINT,
        "Channel": dm_type.UINT,
        "TxPower": dm_type.INT,
        "TimeStamp": dm_type.DATETIME
    },
    defaults: {
        "Class": "0",
        "Channel": "0",
        "TxPower": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.WPS.
export const AccessPoint_WPS = {
    path: "Device.WiFi.AccessPoint.{i}.WPS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ConfigMethodsSupported": dm_type.STRING,
        "ConfigMethodsEnabled": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Version": dm_type.STRING,
        "PIN": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "ConfigMethodsSupported": "",
        "ConfigMethodsEnabled": "",
        "Status": "",
        "Version": "",
        "PIN": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS.{i}.
export const ChannelScan_NeighborBSS = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS.{i}.",
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
        "BSSColor": dm_type.UINT
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
        "BSSColor": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.STABlock.{i}.Schedule.{i}.
export const STABlock_Schedule = {
    path: "Device.WiFi.DataElements.Network.STABlock.{i}.Schedule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Day": dm_type.STRING | dm_type.WRITABLE,
        "StartTime": dm_type.STRING | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Day": "",
        "StartTime": "",
        "Duration": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6bSTARole.
export const Capabilities_WiFi6bSTARole = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6bSTARole.",
    schema: {
        "HE160": dm_type.BOOL,
        "HE8080": dm_type.BOOL,
        "MCSNSS": dm_type.BASE64,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "Beamformee80orLess": dm_type.BOOL,
        "BeamformeeAbove80": dm_type.BOOL,
        "ULMUMIMO": dm_type.BOOL,
        "ULOFDMA": dm_type.BOOL,
        "DLOFDMA": dm_type.BOOL,
        "MaxDLMUMIMO": dm_type.UINT,
        "MaxULMUMIMO": dm_type.UINT,
        "MaxDLOFDMA": dm_type.UINT,
        "MaxULOFDMA": dm_type.UINT,
        "RTS": dm_type.BOOL,
        "MURTS": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "MUEDCA": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "SpatialReuse": dm_type.BOOL,
        "AnticipatedChannelUsage": dm_type.BOOL
    },
    defaults: {
        "MaxDLMUMIMO": "0",
        "MaxULMUMIMO": "0",
        "MaxDLOFDMA": "0",
        "MaxULOFDMA": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STAMLDConfig.
export const STAMLD_STAMLDConfig = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STAMLDConfig.",
    schema: {
        "EMLMREnabled": dm_type.BOOL,
        "EMLSREnabled": dm_type.BOOL,
        "STREnabled": dm_type.BOOL,
        "NSTREnabled": dm_type.BOOL,
        "TIDLinkMapNegotiation": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown.{i}.
export const Device_BackhaulDown = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown.{i}.",
    schema: {
        "BackhaulDownALID": dm_type.STRING,
        "BackhaulDownMACAddress": dm_type.STRING,
        "BackhaulDownMediaType": dm_type.STRING
    },
    defaults: {
        "BackhaulDownALID": "",
        "BackhaulDownMACAddress": "",
        "BackhaulDownMediaType": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLSRFreqSeparation.{i}.
export const WiFi7bSTARole_EMLSRFreqSeparation = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLSRFreqSeparation.{i}.",
    schema: {
        "RUID": dm_type.BASE64,
        "FreqSeparation": dm_type.UINT
    },
    defaults: {
        "FreqSeparation": "0"
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.
export const Capabilities_WiFi7bSTARole = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.",
    schema: {
        "EMLMRSupport": dm_type.BOOL,
        "EMLSRSupport": dm_type.BOOL,
        "STRSupport": dm_type.BOOL,
        "NSTRSupport": dm_type.BOOL,
        "TIDLinkMapNegotiation": dm_type.BOOL,
        "EMLMRFreqSeparationNumberOfEntries": dm_type.UINT,
        "EMLSRFreqSeparationNumberOfEntries": dm_type.UINT,
        "STRFreqSeparationNumberOfEntries": dm_type.UINT,
        "NSTRFreqSeparationNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "EMLMRFreqSeparationNumberOfEntries": "0",
        "EMLSRFreqSeparationNumberOfEntries": "0",
        "STRFreqSeparationNumberOfEntries": "0",
        "NSTRFreqSeparationNumberOfEntries": "0"
    }
};

// Schema for Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.
export const AssociationEvent_AssociationEventData = {
    path: "Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "BSSID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "StatusCode": dm_type.UINT,
        "HTCapabilities": dm_type.BASE64,
        "VHTCapabilities": dm_type.BASE64,
        "HECapabilities": dm_type.BASE64,
        "ClientCapabilities": dm_type.BASE64,
        "OpClass": dm_type.UINT,
        "Channel": dm_type.UINT
    },
    defaults: {
        "BSSID": "",
        "MACAddress": "",
        "StatusCode": "0",
        "OpClass": "0",
        "Channel": "0"
    }
};

// Schema for Device.WiFi.AccessPoint.{i}.Passpoint.OSU.
export const Passpoint_OSU = {
    path: "Device.WiFi.AccessPoint.{i}.Passpoint.OSU.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SSID": dm_type.STRING | dm_type.WRITABLE,
        "Method": dm_type.STRING | dm_type.WRITABLE,
        "FriendlyNames": dm_type.STRING | dm_type.WRITABLE,
        "ServerURIs": dm_type.STRING | dm_type.WRITABLE,
        "ServiceDescriptions": dm_type.STRING | dm_type.WRITABLE,
        "ProviderNAIs": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "SSID": "",
        "Method": "",
        "FriendlyNames": "",
        "ServerURIs": "",
        "ServiceDescriptions": "",
        "ProviderNAIs": ""
    }
};

// Schema for Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.TIDLinkMap.{i}.
export const APMLD_TIDLinkMap = {
    path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.TIDLinkMap.{i}.",
    schema: {
        "Direction": dm_type.STRING,
        "TID": dm_type.UINT,
        "BSSID": dm_type.STRING,
        "LinkID": dm_type.UINT
    },
    defaults: {
        "Direction": "",
        "TID": "0",
        "BSSID": "",
        "LinkID": "0"
    }
};

// Schema for Device.WiFi.EndPoint.{i}.
export const EndPoint = {
    path: "Device.WiFi.EndPoint.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "ProfileReference": dm_type.STRING | dm_type.WRITABLE,
        "SSIDReference": dm_type.STRING,
        "ProfileNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "ProfileReference": "",
        "SSIDReference": "",
        "ProfileNumberOfEntries": "0"
    }
};
