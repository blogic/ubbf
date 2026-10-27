'use strict';

export const WiFi = {
	path: "Device.WiFi.",
	schema: {
		"RadioNumberOfEntries": dm_type.UINT,
		"SSIDNumberOfEntries": dm_type.UINT,
		"AccessPointNumberOfEntries": dm_type.UINT,
		"EndPointNumberOfEntries": dm_type.UINT,
		"X_UBBF_QoSMapNumberOfEntries": dm_type.UINT,
		"Reset()": { type: 'sync', input: [] },
		"X_UBBF_SetEnabled()": { type: 'sync', input: ['Enabled'] },
		"X_UBBF_ChannelHistoryReset()": { type: 'sync', input: [] },
		"NeighboringWiFiDiagnostic()": {
			type: 'async',
			input: [],
			output: [
				'Status',
				'ResultNumberOfEntries',
				'Result.{i}.Radio',
				'Result.{i}.SSID',
				'Result.{i}.BSSID',
				'Result.{i}.Mode',
				'Result.{i}.Channel',
				'Result.{i}.SignalStrength',
				'Result.{i}.SecurityModeEnabled',
				'Result.{i}.EncryptionMode',
				'Result.{i}.OperatingFrequencyBand',
				'Result.{i}.OperatingStandards',
				'Result.{i}.OperatingChannelBandwidth',
				'Result.{i}.Noise'
			]
		}
	},
	defaults: {
		"RadioNumberOfEntries": "0",
		"SSIDNumberOfEntries": "0",
		"AccessPointNumberOfEntries": "0",
		"EndPointNumberOfEntries": "0",
		"X_UBBF_QoSMapNumberOfEntries": "0"
	}
};

export const WiFi_X_UBBF_QoSMap = {
	path: "Device.WiFi.X_UBBF_QoSMap.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"UserPriority": dm_type.UINT | dm_type.WRITABLE,
		"DSCPList": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Alias": "",
		"UserPriority": "0",
		"DSCPList": ""
	}
};

export const Radio = {
	path: "Device.WiFi.Radio.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING,
		"Name": dm_type.STRING,
		"Description": dm_type.STRING | dm_type.WRITABLE,
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
		"TransmitPowerSupported": dm_type.INT,
		"TransmitPower": dm_type.INT | dm_type.WRITABLE,
		"IEEE80211hSupported": dm_type.BOOL,
		"IEEE80211hEnabled": dm_type.BOOL | dm_type.WRITABLE,
		"RegulatoryDomain": dm_type.STRING | dm_type.WRITABLE,
		"RetryLimit": dm_type.UINT | dm_type.WRITABLE,
		"FragmentationThreshold": dm_type.UINT | dm_type.WRITABLE,
		"RTSThreshold": dm_type.UINT | dm_type.WRITABLE,
		"BeaconPeriod": dm_type.UINT | dm_type.WRITABLE,
		"DTIMPeriod": dm_type.UINT | dm_type.WRITABLE,
		"PacketAggregationEnable": dm_type.BOOL | dm_type.WRITABLE,
		"PreambleType": dm_type.STRING | dm_type.WRITABLE,
		"X_UBBF_ReducedNeighborReportEnable": dm_type.BOOL | dm_type.WRITABLE,
		"X_UBBF_BackgroundDFSEnable": dm_type.BOOL | dm_type.WRITABLE,
		"X_UBBF_ChannelHistoryNumberOfEntries": dm_type.UINT,
		"X_UBBF_ChannelSwitch()": { type: 'sync', input: ['Channel'] }
	},
	defaults: {
		"Enable": "true",
		"Status": "Down",
		"Alias": "",
		"Name": "",
		"Description": "",
		"LastChange": "0",
		"LowerLayers": "",
		"MaxBitRate": "0",
		"Upstream": "false",
		"SupportedFrequencyBands": "",
		"OperatingFrequencyBand": "",
		"SupportedStandards": "",
		"OperatingStandards": "",
		"PossibleChannels": "",
		"ChannelsInUse": "",
		"Channel": "0",
		"AutoChannelSupported": "true",
		"AutoChannelEnable": "true",
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
		"TransmitPowerSupported": "100",
		"TransmitPower": "100",
		"IEEE80211hSupported": "true",
		"IEEE80211hEnabled": "false",
		"RegulatoryDomain": "",
		"RetryLimit": "0",
		"FragmentationThreshold": "0",
		"RTSThreshold": "0",
		"BeaconPeriod": "100",
		"DTIMPeriod": "1",
		"PacketAggregationEnable": "true",
		"PreambleType": "long",
		"X_UBBF_ReducedNeighborReportEnable": "true",
		"X_UBBF_BackgroundDFSEnable": "true",
		"X_UBBF_ChannelHistoryNumberOfEntries": "0"
	},
	since: {
		"Description": "2.21"
	},
	constraints: {
		"Description": { max_length: 256 },
		"LowerLayers": { list: true, list_max_length: 1024 },
		"OperatingStandards": { list: true },
		"Channel": { min: 1, max: 255 },
		"ExtensionChannel": { enum: [ "AboveControlChannel", "BelowControlChannel", "Auto" ] },
		"GuardInterval": { enum: [ "400nsec", "800nsec", "1xLTF_0.8us", "1xLTF_1.6us", "2xLTF_0.8us", "2xLTF_1.6us", "4xLTF_0.8us", "4xLTF_3.2us", "Auto" ] },
		"TransmitPower": { min: -1, max: 100 },
		"RegulatoryDomain": { min_length: 3, max_length: 3 },
		"RetryLimit": { min: 0, max: 7 },
		"PreambleType": { enum: [ "short", "long", "auto" ] }
	},
	addable: false
};

export const Radio_X_UBBF_ChannelHistory = {
	path: "Device.WiFi.Radio.{i}.X_UBBF_ChannelHistory.{i}.",
	schema: {
		"Timestamp": dm_type.DATETIME,
		"FromChannel": dm_type.UINT,
		"ToChannel": dm_type.UINT,
		"Frequency": dm_type.UINT,
		"BSSID": dm_type.STRING,
		"Reason": dm_type.STRING
	},
	defaults: {
		"Timestamp": "",
		"FromChannel": "0",
		"ToChannel": "0",
		"Frequency": "0",
		"BSSID": "",
		"Reason": ""
	}
};

export const Radio_Stats = {
	path: "Device.WiFi.Radio.{i}.Stats.",
	schema: {
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.UINT,
		"ErrorsReceived": dm_type.UINT,
		"DiscardPacketsSent": dm_type.UINT,
		"DiscardPacketsReceived": dm_type.UINT,
		"Noise": dm_type.INT,
		"Reset()": { type: 'sync', input: [] }
	},
	defaults: {
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "4294967295",
		"ErrorsReceived": "4294967295",
		"DiscardPacketsSent": "4294967295",
		"DiscardPacketsReceived": "4294967295",
		"Noise": "0"
	}
};

export const SSID = {
	path: "Device.WiFi.SSID.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING,
		"Name": dm_type.STRING,
		"Description": dm_type.STRING | dm_type.WRITABLE,
		"LastChange": dm_type.UINT,
		"LowerLayers": dm_type.STRING | dm_type.WRITABLE,
		"Upstream": dm_type.BOOL,
		"BSSID": dm_type.STRING,
		"MACAddress": dm_type.STRING,
		"SSID": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Status": "Down",
		"Alias": "",
		"Name": "",
		"Description": "",
		"LastChange": "0",
		"LowerLayers": "",
		"Upstream": "false",
		"BSSID": "",
		"MACAddress": "",
		"SSID": ""
	},
	since: {
		"Description": "2.21"
	},
	constraints: {
		"Description": { max_length: 256 },
		"LowerLayers": { list: true, list_max_length: 1024 },
		"SSID": { max_length: 32 }
	}
};

export const SSID_Stats = {
	path: "Device.WiFi.SSID.{i}.Stats.",
	schema: {
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.UINT,
		"ErrorsReceived": dm_type.UINT,
		"UnicastPacketsSent": dm_type.ULONG,
		"DiscardPacketsSent": dm_type.UINT,
		"DiscardPacketsReceived": dm_type.UINT,
		"MulticastPacketsSent": dm_type.ULONG,
		"UnicastPacketsReceived": dm_type.ULONG,
		"MulticastPacketsReceived": dm_type.ULONG,
		"BroadcastPacketsSent": dm_type.ULONG,
		"BroadcastPacketsReceived": dm_type.ULONG,
		"UnknownProtoPacketsReceived": dm_type.UINT,
		"Reset()": { type: 'sync', input: [] }
	},
	defaults: {
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "4294967295",
		"ErrorsReceived": "4294967295",
		"UnicastPacketsSent": "18446744073709551615",
		"DiscardPacketsSent": "4294967295",
		"DiscardPacketsReceived": "4294967295",
		"MulticastPacketsSent": "18446744073709551615",
		"UnicastPacketsReceived": "18446744073709551615",
		"MulticastPacketsReceived": "18446744073709551615",
		"BroadcastPacketsSent": "18446744073709551615",
		"BroadcastPacketsReceived": "18446744073709551615",
		"UnknownProtoPacketsReceived": "4294967295"
	}
};

export const AccessPoint = {
	path: "Device.WiFi.AccessPoint.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING,
		"SSIDReference": dm_type.STRING | dm_type.WRITABLE,
		"SSIDAdvertisementEnabled": dm_type.BOOL | dm_type.WRITABLE,
		"WMMCapability": dm_type.BOOL,
		"UAPSDCapability": dm_type.BOOL,
		"WMMEnable": dm_type.BOOL | dm_type.WRITABLE,
		"UAPSDEnable": dm_type.BOOL | dm_type.WRITABLE,
		"AssociatedDeviceNumberOfEntries": dm_type.UINT,
		"IsolationEnable": dm_type.BOOL | dm_type.WRITABLE,
		"MACAddressControlEnabled": dm_type.BOOL | dm_type.WRITABLE,
		"AllowedMACAddress": dm_type.STRING | dm_type.WRITABLE,
		"MaxAllowedAssociations": dm_type.UINT | dm_type.WRITABLE,
		"APMLDTemplateRef": dm_type.STRING | dm_type.WRITABLE,
		"X_UBBF_Role": dm_type.STRING | dm_type.WRITABLE,
		"X_UBBF_VendorIENumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "false",
		"Status": "Disabled",
		"Alias": "",
		"SSIDReference": "",
		"SSIDAdvertisementEnabled": "true",
		"WMMCapability": "true",
		"UAPSDCapability": "true",
		"WMMEnable": "true",
		"UAPSDEnable": "true",
		"AssociatedDeviceNumberOfEntries": "0",
		"IsolationEnable": "false",
		"MACAddressControlEnabled": "false",
		"AllowedMACAddress": "",
		"MaxAllowedAssociations": "0",
		"APMLDTemplateRef": "",
		"X_UBBF_Role": "Other",
		"X_UBBF_VendorIENumberOfEntries": "0"
	},
	constraints: {
		"SSIDReference": { max_length: 256 },
		"AllowedMACAddress": { list: true, max_length: 17 }
	}
};

export const AccessPoint_X_UBBF_VendorIE = {
	path: "Device.WiFi.AccessPoint.{i}.X_UBBF_VendorIE.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Payload": dm_type.HEXBIN | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Alias": "",
		"Payload": ""
	}
};

export const AccessPoint_Security = {
	path: "Device.WiFi.AccessPoint.{i}.Security.",
	schema: {
		"ModesSupported": dm_type.STRING,
		"ModeEnabled": dm_type.STRING | dm_type.WRITABLE,
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
		"MFPConfig": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"ModesSupported": "None,WPA-Personal,WPA2-Personal,WPA-WPA2-Personal,WPA3-Personal,WPA3-Personal-Transition,WPA-Enterprise,WPA2-Enterprise,WPA-WPA2-Enterprise,WPA3-Enterprise",
		"ModeEnabled": "WPA2-Personal",
		"KeyPassphrase": "",
		"RekeyingInterval": "3600",
		"SAEPassphrase": "",
		"RadiusServerIPAddr": "",
		"SecondaryRadiusServerIPAddr": "",
		"RadiusServerPort": "1812",
		"SecondaryRadiusServerPort": "1812",
		"RadiusSecret": "",
		"SecondaryRadiusSecret": "",
		"MFPConfig": "Disabled"
	},
	constraints: {
		"PreSharedKey": { secured: true, max_length: 32 },
		"KeyPassphrase": { secured: true, min_length: 8, max_length: 63 },
		"SAEPassphrase": { secured: true },
		"RadiusServerIPAddr": { max_length: 45 },
		"SecondaryRadiusServerIPAddr": { max_length: 45 },
		"RadiusSecret": { secured: true },
		"SecondaryRadiusSecret": { secured: true },
		"MFPConfig": { enum: [ "Disabled", "Optional", "Required" ] }
	}
};

export const AccessPoint_WPS = {
	path: "Device.WiFi.AccessPoint.{i}.WPS.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"ConfigMethodsSupported": dm_type.STRING,
		"ConfigMethodsEnabled": dm_type.STRING | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Version": dm_type.STRING,
		"PIN": dm_type.STRING | dm_type.WRITABLE,
		"InitiateWPSPBC()": {
			type: 'async',
			input: [],
			output: ['Status']
		}
	},
	defaults: {
		"Enable": "false",
		"ConfigMethodsSupported": "PushButton",
		"ConfigMethodsEnabled": "PushButton",
		"Status": "Disabled",
		"Version": "2.0",
		"PIN": ""
	},
	constraints: {
		"ConfigMethodsEnabled": { list: true },
		"PIN": { secured: true, max_length: 8 }
	}
};

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
		"Enable": "false",
		"ServerIPAddr": "",
		"SecondaryServerIPAddr": "",
		"ServerPort": "1813",
		"SecondaryServerPort": "1813",
		"Secret": "",
		"SecondarySecret": "",
		"InterimInterval": "0"
	},
	constraints: {
		"ServerIPAddr": { max_length: 45 },
		"SecondaryServerIPAddr": { max_length: 45 },
		"Secret": { secured: true },
		"SecondarySecret": { secured: true },
		"InterimInterval": { ranges: [ [ 0, 0 ], [ 60, null ] ] }
	}
};

export const AccessPoint_AssociatedDevice = {
	path: "Device.WiFi.AccessPoint.{i}.AssociatedDevice.{i}.",
	schema: {
		"MACAddress": dm_type.STRING,
		"OperatingStandard": dm_type.STRING,
		"AuthenticationState": dm_type.BOOL,
		"LastDataDownlinkRate": dm_type.UINT,
		"LastDataUplinkRate": dm_type.UINT,
		"AssociationTime": dm_type.DATETIME,
		"SignalStrength": dm_type.INT,
		"Noise": dm_type.INT,
		"Retransmissions": dm_type.UINT,
		"Active": dm_type.BOOL
	},
	defaults: {
		"MACAddress": "",
		"OperatingStandard": "",
		"AuthenticationState": "false",
		"LastDataDownlinkRate": "0",
		"LastDataUplinkRate": "0",
		"SignalStrength": "0",
		"Noise": "0",
		"Retransmissions": "0",
		"Active": "false"
	},
	addable: false
};

export const AccessPoint_AC = {
	path: "Device.WiFi.AccessPoint.{i}.AC.{i}.",
	schema: {
		"AccessCategory": dm_type.STRING,
		"Alias": dm_type.STRING,
		"AckPolicy": dm_type.BOOL | dm_type.WRITABLE,
		"OutQLenHistogramIntervals": dm_type.STRING | dm_type.WRITABLE,
		"OutQLenHistogramSampleInterval": dm_type.UINT | dm_type.WRITABLE
	},
	defaults: {
		"AccessCategory": "",
		"Alias": "",
		"OutQLenHistogramIntervals": "",
		"OutQLenHistogramSampleInterval": "0"
	},
	constraints: {
		"OutQLenHistogramIntervals": { list: true }
	},
	addable: false,
	max_instances: 4
};

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
	},
	constraints: {
		"ProfileReference": { max_length: 256 }
	}
};

export const NeighboringWiFiDiagnostic = {
	path: "Device.WiFi.NeighboringWiFiDiagnostic.",
	schema: {
		"DiagnosticsState": dm_type.STRING,
		"ResultNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"DiagnosticsState": "None",
		"ResultNumberOfEntries": "0"
	}
};

export const NeighboringWiFiDiagnostic_Result = {
	path: "Device.WiFi.NeighboringWiFiDiagnostic.Result.{i}.",
	schema: {
		"Radio": dm_type.STRING,
		"SSID": dm_type.STRING,
		"BSSID": dm_type.STRING,
		"Mode": dm_type.STRING,
		"Channel": dm_type.UINT,
		"SignalStrength": dm_type.INT,
		"SecurityModeEnabled": dm_type.STRING,
		"EncryptionMode": dm_type.STRING,
		"OperatingFrequencyBand": dm_type.STRING,
		"OperatingStandards": dm_type.STRING,
		"OperatingChannelBandwidth": dm_type.STRING,
		"Noise": dm_type.INT
	},
	defaults: {
		"Radio": "",
		"SSID": "",
		"BSSID": "",
		"Mode": "Infrastructure",
		"Channel": "0",
		"SignalStrength": "0",
		"SecurityModeEnabled": "None",
		"EncryptionMode": "None",
		"OperatingFrequencyBand": "",
		"OperatingStandards": "",
		"OperatingChannelBandwidth": "20MHz",
		"Noise": "0"
	}
};

export const APMLDTemplate = {
	path: "Device.WiFi.Templates.APMLDTemplate.{i}.",
	schema: {
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"APMLDTemplateID": dm_type.STRING | dm_type.WRITABLE,
		"MLOEnable": dm_type.BOOL | dm_type.WRITABLE,
		"STREnable": dm_type.BOOL | dm_type.WRITABLE,
		"NSTREnable": dm_type.BOOL | dm_type.WRITABLE,
		"EMLSREnable": dm_type.BOOL | dm_type.WRITABLE,
		"EMLMREnable": dm_type.BOOL | dm_type.WRITABLE,
		"TIDToLinkMapNegotiation": dm_type.BOOL | dm_type.WRITABLE
	},
	defaults: {
		"Alias": "",
		"APMLDTemplateID": "",
		"MLOEnable": "false",
		"STREnable": "false",
		"NSTREnable": "false",
		"EMLSREnable": "false",
		"EMLMREnable": "false",
		"TIDToLinkMapNegotiation": "false"
	},
	constraints: {
		"Alias": { max_length: 64 }
	}
};
