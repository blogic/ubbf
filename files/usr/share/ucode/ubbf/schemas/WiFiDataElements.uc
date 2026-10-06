'use strict';

export const WiFiDataElements = {
	path: "Device.WiFi.DataElements.",
	schema: {
	},
	defaults: {
	}
};

export const DataElements_Network = {
	path: "Device.WiFi.DataElements.Network.",
	schema: {
		"ID": dm_type.STRING,
		"TimeStamp": dm_type.DATETIME,
		"ControllerID": dm_type.STRING,
		"ColocatedAgentID": dm_type.STRING,
		"SteeringMandates": dm_type.ULONG,
		"SteeringOpportunities": dm_type.ULONG,
		"MSCSDisallowedStaList": dm_type.STRING,
		"SCSDisallowedStaList": dm_type.STRING,
		"SSIDNumberOfEntries": dm_type.UINT,
		"DeviceNumberOfEntries": dm_type.UINT,
		"STABlockNumberOfEntries": dm_type.UINT,
		"PreferredBackhaulsNumberOfEntries": dm_type.UINT,
		"ProvisionedDPPNumberOfEntries": dm_type.UINT,
		"SetTrafficSeparation()": {
			type: 'async',
			input: [
				'Enable',
				'X_UBBF_PrimaryVLANID',
				'SSIDtoVIDMapping.{i}.SSID',
				'SSIDtoVIDMapping.{i}.VID'
			],
			output: ['Status']
		},
		"SetServicePrioritization()": {
			type: 'async',
			input: [
				'Enable',
				'SPRule.{i}.ID',
				'SPRule.{i}.Precedence',
				'SPRule.{i}.Output',
				'SPRule.{i}.AlwaysMatch',
				'DSCPMap'
			],
			output: ['Status']
		},
		"SetPreferredBackhauls()": {
			type: 'async',
			input: [
				'PreferredBackhauls.{i}.BackhaulMACAddress',
				'PreferredBackhauls.{i}.bSTAMACAddress'
			],
			output: ['Status']
		},
		"SetSSID()": {
			type: 'async',
			input: [
				'SSID',
				'AddRemoveChange',
				'Enable',
				'PassPhrase',
				'Band',
				'AKMsAllowed',
				'SuiteSelector',
				'AdvertisementEnabled',
				'MFPConfig',
				'MobilityDomain',
				'HaulType',
				'Type'
			],
			output: ['Status']
		},
		"SetMSCSDisallowed()": {
			type: 'async',
			input: ['MSCSDisallowedStaList'],
			output: ['Status']
		},
		"SetSCSDisallowed()": {
			type: 'async',
			input: ['SCSDisallowedStaList'],
			output: ['Status']
		},
		"ControllerBTMSteer!": {
			type: 'event',
			input: ['BSSID', 'STAMAC', 'BTMStatusCode']
		},
		"AgentOnboard!": {
			type: 'event',
			input: ['DeviceID', 'BackhaulSta', 'BackhaulMACAddress', 'BackhaulALID']
		}
	},
	defaults: {
		"ID": "",
		"TimeStamp": "",
		"ControllerID": "",
		"ColocatedAgentID": "",
		"SteeringMandates": "0",
		"SteeringOpportunities": "0",
		"MSCSDisallowedStaList": "",
		"SCSDisallowedStaList": "",
		"SSIDNumberOfEntries": "0",
		"DeviceNumberOfEntries": "0",
		"STABlockNumberOfEntries": "0",
		"PreferredBackhaulsNumberOfEntries": "0",
		"ProvisionedDPPNumberOfEntries": "0"
	}
};

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
		"Enable": "true",
		"Band": "",
		"AKMsAllowed": "",
		"MFPConfig": "",
		"MobilityDomain": "",
		"HaulType": "",
		"Type": ""
	}
};

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
		// APMetricsWiFi6 removed in TR-181 v2.19
		"CountryCode": dm_type.STRING,
		"LocalSteeringDisallowedSTAList": dm_type.STRING | dm_type.WRITABLE,
		"BTMSteeringDisallowedSTAList": dm_type.STRING | dm_type.WRITABLE,
		"DFSEnable": dm_type.BOOL,
		"ReportIndependentScans": dm_type.BOOL | dm_type.WRITABLE,
		// AssociatedSTAinAPMetricsWiFi6 removed in TR-181 v2.19
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
		"BackhaulDownNumberOfEntries": dm_type.UINT,
		"InitiateWPSPBC()": {
			type: 'async',
			output: ['Status']
		},
		"RefreshAPMetrics()": {
			type: 'async',
			input: ['RUID'],
			output: ['Status']
		},
		"SetAnticipatedChannelPreference()": {
			type: 'async',
			input: ['OpClass', 'ChannelList'],
			output: ['Status']
		},
		"SetSTASteeringState()": {
			type: 'async',
			input: ['Disallowed'],
			output: ['Status']
		},
		"BackhaulChange!": {
			type: 'event',
			input: ['MACAddress', 'TargetBSSID', 'ResultCode', 'ReasonCode']
		}
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

export const Device_AnticipatedChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	}
};

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

export const Device_MultiAPDevice = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.",
	schema: {
		"LastContactTime": dm_type.DATETIME,
		"AssocIEEE1905DeviceRef": dm_type.STRING,
		"EasyMeshControllerOperationMode": dm_type.STRING,
		"EasyMeshAgentOperationMode": dm_type.STRING
	},
	defaults: {
		"AssocIEEE1905DeviceRef": "",
		"EasyMeshControllerOperationMode": "",
		"EasyMeshAgentOperationMode": ""
	}
};

export const MultiAPDevice_Backhaul = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.",
	schema: {
		"LinkType": dm_type.STRING,
		"BackhaulMACAddress": dm_type.STRING,
		"BackhaulDeviceID": dm_type.STRING,
		"MACAddress": dm_type.STRING,
		"CurrentOperatingClassProfileNumberOfEntries": dm_type.UINT,
		"SteerWiFiBackhaul()": {
			type: 'async',
			input: ['TargetBSS', 'Channel', 'TimeOut'],
			output: ['Status']
		}
	},
	defaults: {
		"LinkType": "",
		"BackhaulMACAddress": "",
		"BackhaulDeviceID": "",
		"MACAddress": "",
		"CurrentOperatingClassProfileNumberOfEntries": "0"
	}
};

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

export const Device_BackhaulDown = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown.{i}.",
	schema: {
		"BackhaulDownALID": dm_type.STRING,
		"BackhaulDownMACAddress": dm_type.STRING
	},
	defaults: {
		"BackhaulDownALID": "",
		"BackhaulDownMACAddress": ""
	}
};

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
		"OpClassPreferenceNumberOfEntries": dm_type.UINT,
		"ChannelScanRequest()": {
			type: 'async',
			input: ['OpClass', 'ChannelList'],
			output: []
		},
		"ChannelSelectionRequest()": {
			type: 'async',
			input: [
				'Class.{i}.OpClass',
				'Class.{i}.Channel.{i}.Channel',
				'Class.{i}.Channel.{i}.Preference'
			],
			output: ['Status']
		},
		"SetSpatialReuse()": {
			type: 'async',
			input: [
				'BSSColor', 'HESIGASpatialReuseValue15Allowed',
				'SRGInformationValid', 'NonSRGOffsetValid', 'PSRDisallowed',
				'NonSRGOBSSPDMaxOffset', 'SRGOBSSPDMinOffset', 'SRGOBSSPDMaxOffset',
				'SRGBSSColorBitmap', 'SRGPartialBSSIDBitmap'
			],
			output: ['Status']
		},
		"SetTxPowerLimit()": {
			type: 'async',
			input: ['TransmitPowerLimit', 'OperatingClass'],
			output: ['Status']
		},
		"RadioEnable()": {
			type: 'async',
			input: ['Enable'],
			output: ['Status']
		}
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

export const Radio_Capabilities = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.",
	schema: {
		"HTCapabilities": dm_type.BASE64,
		"VHTCapabilities": dm_type.BASE64,
		// HECapabilities removed in TR-181 v2.18
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

export const Capabilities_CapableOperatingClassProfile = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.CapableOperatingClassProfile.{i}.",
	schema: {
		"Class": dm_type.UINT,
		"MaxTxPower": dm_type.INT,
		"NonOperable": dm_type.STRING,
		"NumberOfNonOperChan": dm_type.UINT
	},
	defaults: {
		"Class": "0",
		"MaxTxPower": "0",
		"NonOperable": "",
		"NumberOfNonOperChan": "0"
	}
};

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

export const Radio_DisAllowedOpClassChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.DisAllowedOpClassChannels.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"OpClass": dm_type.UINT | dm_type.WRITABLE,
		"ChannelList": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"OpClass": "0",
		"ChannelList": ""
	}
};

export const Radio_OpClassPreference = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.OpClassPreference.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING,
		"Preference": dm_type.UINT,
		"ReasonCode": dm_type.UINT
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": "",
		"Preference": "0",
		"ReasonCode": "0"
	}
};

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

export const Radio_CACCapability = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.",
	schema: {
		"CACMethodNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"CACMethodNumberOfEntries": "0"
	}
};

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

export const CACMethod_OpClassChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	}
};

export const Radio_ScanCapability = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.",
	schema: {
		"OnBootOnly": dm_type.BOOL,
		"Impact": dm_type.UINT,
		"MinimumInterval": dm_type.UINT,
		"OpClassChannelsNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"OnBootOnly": "false",
		"Impact": "0",
		"MinimumInterval": "0",
		"OpClassChannelsNumberOfEntries": "0"
	}
};

export const ScanCapability_OpClassChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	}
};

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

export const Radio_BackhaulSta = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BackhaulSta.",
	schema: {
		"MACAddress": dm_type.STRING
	},
	defaults: {
		"MACAddress": ""
	}
};

export const Radio_MultiAPRadio = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.MultiAPRadio.",
	schema: {
		"RadarDetections": dm_type.UINT
	},
	defaults: {
		"RadarDetections": "0"
	}
};

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
		"QMDescriptorNumberOfEntries": dm_type.UINT,
		"SetQMDescriptors()": {
			type: 'async',
			input: [
				'QMDescriptor.{i}.BSSID',
				'QMDescriptor.{i}.ClientMAC',
				'QMDescriptor.{i}.DescriptorElement'
			],
			output: ['Status']
		},
		"SetEHTOperations()": {
			type: 'async',
			input: [
				'EHTDefaultPEDuration', 'GroupAddressedBUIndicationLimit',
				'GroupAddressedBUIndicationExponent', 'BasicEHTMCSAndNssSet',
				'Control', 'CCFS0', 'CCFS1', 'DisabledSubchannelBitmap'
			],
			output: ['Status']
		}
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
		"ByteCounterUnits": "",
		"AssociationAllowanceStatus": "0",
		"FronthaulAKMsAllowed": "",
		"BackhaulAKMsAllowed": "",
		"BasicDataTransmitRates": "0",
		"STANumberOfEntries": "0",
		"QMDescriptorNumberOfEntries": "0"
	}
};

export const BSS_MultiAPSteering = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MultiAPSteering.",
	schema: {
		"BlacklistAttempts": dm_type.STRING,
		"BTMAttempts": dm_type.STRING,
		"BTMQueryResponses": dm_type.STRING
	},
	defaults: {
		"BlacklistAttempts": "",
		"BTMAttempts": "",
		"BTMQueryResponses": ""
	}
};

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
		"TIDQueueSizesNumberOfEntries": dm_type.UINT,
		"ClientSteer()": {
			type: 'async',
			input: [
				'TargetBSSID',
				'RequestMode',
				'BTMDisassociationImminent',
				'BTMAbridged',
				'LinkRemovalImminent',
				'SteeringOpportunityWindow',
				'BTMDisassociationTimer',
				'TargetBSSOperatingClass',
				'TargetBSSChannel'
			],
			output: ['Status']
		}
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

export const DataElements_AssociationEvent = {
	path: "Device.WiFi.DataElements.AssociationEvent.",
	schema: {
		"AssociationEventDataNumberOfEntries": dm_type.UINT,
		"Associated!": {
			type: 'event',
			input: ['TimeStamp', 'BSSID', 'MACAddress', 'StatusCode',
				'HTCapabilities', 'VHTCapabilities', 'ClientCapabilities',
				'OpClass', 'Channel']
		}
	},
	defaults: {
		"AssociationEventDataNumberOfEntries": "0"
	}
};

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

export const DataElements_DisassociationEvent = {
	path: "Device.WiFi.DataElements.DisassociationEvent.",
	schema: {
		"DisassociationEventDataNumberOfEntries": dm_type.UINT,
		"Disassociated!": {
			type: 'event',
			input: ['BSSID', 'MACAddress', 'ReasonCode',
				'BytesSent', 'BytesReceived', 'PacketsSent', 'PacketsReceived',
				'ErrorsSent', 'ErrorsReceived', 'RetransCount', 'TimeStamp']
		}
	},
	defaults: {
		"DisassociationEventDataNumberOfEntries": "0"
	}
};

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

export const DataElements_FailedConnectionEvent = {
	path: "Device.WiFi.DataElements.FailedConnectionEvent.",
	schema: {
		"FailedConnectionEventDataNumberOfEntries": dm_type.UINT,
		"FailedConnection!": {
			type: 'event',
			input: ['BSSID', 'MACAddress', 'StatusCode', 'ReasonCode', 'TimeStamp']
		}
	},
	defaults: {
		"FailedConnectionEventDataNumberOfEntries": "0"
	}
};

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
