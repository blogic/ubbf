'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Vendor extensions for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.
const Device_Radio_X_UBBF = {
	schema: {
		"X_UBBF_OnboardProtocol": dm_type.STRING
	},
	defaults: {
		"X_UBBF_OnboardProtocol": ""
	}
};

schemas.WiFiDataElements = {
	path: "Device.WiFi.DataElements.",
	schema: {
	},
	defaults: {
	}
};

schemas.DataElements_Network = {
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
		"SteeringMandates": "18446744073709551615",
		"SteeringOpportunities": "18446744073709551615",
		"MSCSDisallowedStaList": "",
		"SCSDisallowedStaList": "",
		"SSIDNumberOfEntries": "0",
		"DeviceNumberOfEntries": "0",
		"STABlockNumberOfEntries": "0",
		"PreferredBackhaulsNumberOfEntries": "0",
		"ProvisionedDPPNumberOfEntries": "0"
	}
};

schemas.Network_SSID = {
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
	},
	addable: false
};

schemas.Network_STABlock = {
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
	},
	constraints: {
		"BlockedSTA": { max_length: 17 },
		"BSSID": { list: true, max_length: 17 }
	}
};

schemas.STABlock_Schedule = {
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
	},
	constraints: {
		"Day": { list: true, enum: [ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ] },
		"StartTime": { max_length: 5 },
		"Duration": { min: 1 }
	}
};

schemas.Network_PreferredBackhauls = {
	path: "Device.WiFi.DataElements.Network.PreferredBackhauls.{i}.",
	schema: {
		"BackhaulMACAddress": dm_type.STRING,
		"bSTAMACAddress": dm_type.STRING
	},
	defaults: {
		"BackhaulMACAddress": "",
		"bSTAMACAddress": ""
	},
	addable: false
};

schemas.Network_ProvisionedDPP = {
	path: "Device.WiFi.DataElements.Network.ProvisionedDPP.{i}.",
	schema: {
		"Alias": dm_type.STRING,
		"DPPURI": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Alias": "",
		"DPPURI": ""
	},
	constraints: {
		"DPPURI": { max_length: 2048 }
	}
};

schemas.Network_MultiAPSteeringSummaryStats = {
	path: "Device.WiFi.DataElements.Network.MultiAPSteeringSummaryStats.",
	schema: {
		"NoCandidateAPFailures": dm_type.ULONG,
		"BlacklistAttempts": dm_type.ULONG,
		"BlacklistSuccesses": dm_type.ULONG,
		"BlacklistFailures": dm_type.ULONG,
		"BTMAttempts": dm_type.ULONG,
		"BTMSuccesses": dm_type.ULONG,
		"BTMFailures": dm_type.ULONG,
		"BTMQueryResponses": dm_type.ULONG
	},
	defaults: {
		"NoCandidateAPFailures": "18446744073709551615",
		"BlacklistAttempts": "18446744073709551615",
		"BlacklistSuccesses": "18446744073709551615",
		"BlacklistFailures": "18446744073709551615",
		"BTMAttempts": "18446744073709551615",
		"BTMSuccesses": "18446744073709551615",
		"BTMFailures": "18446744073709551615",
		"BTMQueryResponses": "18446744073709551615"
	}
};

schemas.Network_Device = {
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
	},
	constraints: {
		"APMetricsReportingInterval": { max: 255 },
		"AssociatedSTAReportingInterval": { max: 255 },
		"LocalSteeringDisallowedSTAList": { list: true, max_length: 17 },
		"BTMSteeringDisallowedSTAList": { list: true, max_length: 17 }
	},
	addable: false
};

schemas.Device_Default8021Q = {
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
	},
	constraints: {
		"PrimaryVID": { max: 4095 },
		"DefaultPCP": { max: 7 }
	}
};

schemas.Device_SSIDtoVIDMapping = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.SSIDtoVIDMapping.{i}.",
	schema: {
		"SSID": dm_type.STRING,
		"VID": dm_type.UINT
	},
	defaults: {
		"SSID": "",
		"VID": "0"
	},
	addable: false
};

schemas.Device_CACStatus = {
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
	},
	addable: false
};

schemas.CACStatus_CACAvailableChannel = {
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
	},
	addable: false
};

schemas.CACStatus_CACNonOccupancyChannel = {
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
	},
	addable: false
};

schemas.CACStatus_CACActiveChannel = {
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
	},
	addable: false
};

schemas.Device_IEEE1905Security = {
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
	},
	addable: false
};

schemas.Device_SPRule = {
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
	},
	addable: false
};

schemas.Device_WPS = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.WPS.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING
	},
	defaults: {
		"Status": ""
	}
};

schemas.Device_AnticipatedChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	},
	addable: false
};

schemas.Device_AnticipatedChannelUsage = {
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
	},
	addable: false
};

schemas.AnticipatedChannelUsage_Entry = {
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
	},
	addable: false
};

schemas.Device_AFCAvailableSpectrum = {
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

schemas.Device_MultiAPDevice = {
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
	},
	until: {
		"EasyMeshControllerOperationMode": "2.21"
	}
};

schemas.MultiAPDevice_Backhaul = {
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
	},
	until: {
		"LinkType": "2.21",
		"BackhaulMACAddress": "2.21",
		"BackhaulDeviceID": "2.21",
		"MACAddress": "2.21"
	}
};

schemas.Backhaul_Stats = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.Stats.",
	schema: {
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.ULONG,
		"ErrorsReceived": dm_type.ULONG,
		"LinkUtilization": dm_type.UINT,
		"SignalStrength": dm_type.UINT,
		"LastDataDownlinkRate": dm_type.UINT,
		"LastDataUplinkRate": dm_type.UINT,
		"TimeStamp": dm_type.DATETIME
	},
	defaults: {
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "18446744073709551615",
		"ErrorsReceived": "18446744073709551615",
		"LinkUtilization": "0",
		"SignalStrength": "0",
		"LastDataDownlinkRate": "0",
		"LastDataUplinkRate": "0"
	}
};

schemas.Backhaul_CurrentOperatingClassProfile = {
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
	},
	addable: false
};

schemas.Device_BackhaulDown = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown.{i}.",
	schema: {
		"BackhaulDownALID": dm_type.STRING,
		"BackhaulDownMACAddress": dm_type.STRING
	},
	defaults: {
		"BackhaulDownALID": "",
		"BackhaulDownMACAddress": ""
	},
	addable: false
};

const Device_Radio_base = {
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

schemas.Device_Radio = {
	path: Device_Radio_base.path,
	schema: { ...Device_Radio_base.schema, ...Device_Radio_X_UBBF.schema },
	defaults: { ...Device_Radio_base.defaults, ...Device_Radio_X_UBBF.defaults },
	constraints: {
		"SteeringPolicy": { max: 2 },
		"ChannelUtilizationThreshold": { max: 255 },
		"RCPISteeringThreshold": { max: 220 },
		"STAReportingRCPIThreshold": { max: 220 }
	},
	addable: false
};

schemas.Radio_Capabilities = {
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

schemas.Capabilities_CapableOperatingClassProfile = {
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
	},
	addable: false
};

schemas.Capabilities_AKMFrontHaul = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMFrontHaul.{i}.",
	schema: {
		"OUI": dm_type.BASE64,
		"Type": dm_type.UINT
	},
	defaults: {
		"Type": "0"
	},
	addable: false
};

schemas.Capabilities_AKMBackhaul = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMBackhaul.{i}.",
	schema: {
		"OUI": dm_type.BASE64,
		"Type": dm_type.UINT
	},
	defaults: {
		"Type": "0"
	},
	addable: false
};

schemas.Capabilities_WiFi6APRole = {
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

schemas.Capabilities_WiFi6bSTARole = {
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

schemas.Capabilities_WiFi7APRole = {
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

schemas.WiFi7APRole_EMLMRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLMRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7APRole_EMLSRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLSRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7APRole_STRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.STRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7APRole_NSTRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.NSTRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.Capabilities_WiFi7bSTARole = {
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

schemas.WiFi7bSTARole_EMLMRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLMRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7bSTARole_EMLSRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLSRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7bSTARole_STRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.STRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.WiFi7bSTARole_NSTRFreqSeparation = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.NSTRFreqSeparation.{i}.",
	schema: {
		"RUID": dm_type.BASE64,
		"FreqSeparation": dm_type.UINT
	},
	defaults: {
		"FreqSeparation": "0"
	},
	addable: false
};

schemas.Radio_CurrentOperatingClassProfile = {
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
	},
	addable: false
};

schemas.Radio_UnassociatedSTA = {
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
	},
	addable: false
};

schemas.Radio_DisAllowedOpClassChannels = {
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
	},
	constraints: {
		"OpClass": { max: 255 },
		"ChannelList": { list: true, max: 255 }
	}
};

schemas.Radio_OpClassPreference = {
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
	},
	addable: false
};

schemas.Radio_ScanResult = {
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
	},
	addable: false
};

schemas.ScanResult_OpClassScan = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.",
	schema: {
		"OperatingClass": dm_type.UINT,
		"ChannelScanNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"OperatingClass": "0",
		"ChannelScanNumberOfEntries": "0"
	},
	addable: false
};

schemas.OpClassScan_ChannelScan = {
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
	},
	addable: false
};

schemas.ChannelScan_NeighborBSS = {
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
	},
	addable: false
};

schemas.Radio_CACCapability = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.",
	schema: {
		"CACMethodNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"CACMethodNumberOfEntries": "0"
	}
};

schemas.CACCapability_CACMethod = {
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
	},
	addable: false,
	max_instances: 4
};

schemas.CACMethod_OpClassChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	},
	addable: false
};

schemas.Radio_ScanCapability = {
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

schemas.ScanCapability_OpClassChannels = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels.{i}.",
	schema: {
		"OpClass": dm_type.UINT,
		"ChannelList": dm_type.STRING
	},
	defaults: {
		"OpClass": "0",
		"ChannelList": ""
	},
	addable: false
};

schemas.Radio_SpatialReuse = {
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

schemas.Radio_BackhaulSta = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BackhaulSta.",
	schema: {
		"MACAddress": dm_type.STRING
	},
	defaults: {
		"MACAddress": ""
	}
};

schemas.Radio_MultiAPRadio = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.MultiAPRadio.",
	schema: {
		"RadarDetections": dm_type.UINT
	},
	defaults: {
		"RadarDetections": "0"
	},
	until: {
		"RadarDetections": "2.21"
	}
};

schemas.Radio_BSS = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.",
	schema: {
		"BSSID": dm_type.STRING,
		"SSID": dm_type.STRING,
		"Enabled": dm_type.BOOL,
		"LastChange": dm_type.UINT,
		"TimeStamp": dm_type.DATETIME,
		"UnicastBytesSent": dm_type.ULONG,
		"UnicastBytesReceived": dm_type.ULONG,
		"MulticastBytesSent": dm_type.ULONG,
		"MulticastBytesReceived": dm_type.ULONG,
		"BroadcastBytesSent": dm_type.ULONG,
		"BroadcastBytesReceived": dm_type.ULONG,
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
		"UnicastBytesSent": "18446744073709551615",
		"UnicastBytesReceived": "18446744073709551615",
		"MulticastBytesSent": "18446744073709551615",
		"MulticastBytesReceived": "18446744073709551615",
		"BroadcastBytesSent": "18446744073709551615",
		"BroadcastBytesReceived": "18446744073709551615",
		"ByteCounterUnits": "",
		"AssociationAllowanceStatus": "0",
		"FronthaulAKMsAllowed": "",
		"BackhaulAKMsAllowed": "",
		"BasicDataTransmitRates": "0",
		"STANumberOfEntries": "0",
		"QMDescriptorNumberOfEntries": "0"
	},
	constraints: {
		"FronthaulAKMsAllowed": { list: true, enum: [ "psk", "dpp", "sae", "psk+sae", "dpp+sae", "dpp+psk+sae", "SuiteSelector" ] },
		"BackhaulAKMsAllowed": { list: true, enum: [ "psk", "dpp", "sae", "psk+sae", "dpp+sae", "dpp+psk+sae", "SuiteSelector" ] },
		"BackhaulSuiteSelector": { min_length: 4, max_length: 4 },
		"FronthaulSuiteSelector": { min_length: 4, max_length: 4 }
	},
	addable: false
};

schemas.BSS_MultiAPSteering = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MultiAPSteering.",
	schema: {
		"BlacklistAttempts": dm_type.ULONG,
		"BTMAttempts": dm_type.ULONG,
		"BTMQueryResponses": dm_type.ULONG
	},
	defaults: {
		"BlacklistAttempts": "18446744073709551615",
		"BTMAttempts": "18446744073709551615",
		"BTMQueryResponses": "18446744073709551615"
	}
};

schemas.BSS_MUConfig = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUConfig.",
	schema: {
		"DLOFDMAEnable": dm_type.BOOL | dm_type.WRITABLE,
		"ULOFDMAEnable": dm_type.BOOL | dm_type.WRITABLE,
		"DLMUMIMOEnable": dm_type.BOOL | dm_type.WRITABLE,
		"ULMUMIMOEnable": dm_type.BOOL | dm_type.WRITABLE
	},
	defaults: {}
};

schemas.BSS_MUStats = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MUStats.",
	schema: {
		"DLTotalPPDUCount": dm_type.UINT,
		"DLHEPPDUCount": dm_type.UINT,
		"DLMUPPDUCount": dm_type.UINT,
		"DLOFDMAPPDUCount": dm_type.UINT,
		"DLMUMIMOPPDUCount": dm_type.UINT,
		"DLOFDMAMUMIMOPPDUCount": dm_type.UINT,
		"ULTotalPPDUCount": dm_type.UINT,
		"ULHEPPDUCount": dm_type.UINT,
		"ULMUPPDUCount": dm_type.UINT,
		"ULOFDMAPPDUCount": dm_type.UINT,
		"ULMUMIMOPPDUCount": dm_type.UINT,
		"ULOFDMAMUMIMOPPDUCount": dm_type.UINT,
		"DLRU26PPDUCount": dm_type.UINT,
		"DLRU52PPDUCount": dm_type.UINT,
		"DLRU106PPDUCount": dm_type.UINT,
		"DLRU242PPDUCount": dm_type.UINT,
		"DLRU484PPDUCount": dm_type.UINT,
		"DLRU996PPDUCount": dm_type.UINT,
		"DLRU1992PPDUCount": dm_type.UINT,
		"ULRU26PPDUCount": dm_type.UINT,
		"ULRU52PPDUCount": dm_type.UINT,
		"ULRU106PPDUCount": dm_type.UINT,
		"ULRU242PPDUCount": dm_type.UINT,
		"ULRU484PPDUCount": dm_type.UINT,
		"ULRU996PPDUCount": dm_type.UINT,
		"ULRU1992PPDUCount": dm_type.UINT
	},
	defaults: {
		"DLTotalPPDUCount": "4294967295",
		"DLHEPPDUCount": "4294967295",
		"DLMUPPDUCount": "4294967295",
		"DLOFDMAPPDUCount": "4294967295",
		"DLMUMIMOPPDUCount": "4294967295",
		"DLOFDMAMUMIMOPPDUCount": "4294967295",
		"ULTotalPPDUCount": "4294967295",
		"ULHEPPDUCount": "4294967295",
		"ULMUPPDUCount": "4294967295",
		"ULOFDMAPPDUCount": "4294967295",
		"ULMUMIMOPPDUCount": "4294967295",
		"ULOFDMAMUMIMOPPDUCount": "4294967295",
		"DLRU26PPDUCount": "4294967295",
		"DLRU52PPDUCount": "4294967295",
		"DLRU106PPDUCount": "4294967295",
		"DLRU242PPDUCount": "4294967295",
		"DLRU484PPDUCount": "4294967295",
		"DLRU996PPDUCount": "4294967295",
		"DLRU1992PPDUCount": "4294967295",
		"ULRU26PPDUCount": "4294967295",
		"ULRU52PPDUCount": "4294967295",
		"ULRU106PPDUCount": "4294967295",
		"ULRU242PPDUCount": "4294967295",
		"ULRU484PPDUCount": "4294967295",
		"ULRU996PPDUCount": "4294967295",
		"ULRU1992PPDUCount": "4294967295"
	}
};

schemas.BSS_QMDescriptor = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.QMDescriptor.{i}.",
	schema: {
		"BSSID": dm_type.STRING,
		"ClientMAC": dm_type.STRING,
		"DescriptorElement": dm_type.HEXBIN
	},
	defaults: {
		"BSSID": "",
		"ClientMAC": ""
	},
	addable: false
};

schemas.BSS_SetQoSManagementInput = {
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

schemas.BSS_ThroughputTestResult = {
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

schemas.BSS_LatencyTestResult = {
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

schemas.BSS_STA = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.",
	schema: {
		"MACAddress": dm_type.STRING,
		"TimeStamp": dm_type.DATETIME,
		"HTCapabilities": dm_type.BASE64,
		"VHTCapabilities": dm_type.BASE64,
		"ClientCapabilities": dm_type.BASE64,
		"LastDataDownlinkRate": dm_type.UINT,
		"LastDataUplinkRate": dm_type.UINT,
		"UtilizationReceive": dm_type.ULONG,
		"UtilizationTransmit": dm_type.ULONG,
		"EstMACDataRateDownlink": dm_type.UINT,
		"EstMACDataRateUplink": dm_type.UINT,
		"SignalStrength": dm_type.UINT,
		"LastConnectTime": dm_type.UINT,
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.ULONG,
		"ErrorsReceived": dm_type.ULONG,
		"RetransCount": dm_type.ULONG,
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
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "18446744073709551615",
		"ErrorsReceived": "18446744073709551615",
		"RetransCount": "18446744073709551615",
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
	},
	constraints: {
		"CellularDataPreference": { enum: [ "Excluded", "Should not use", "Should use" ] },
		"ReAssociationDelay": { max: 65535 }
	},
	addable: false
};

schemas.STA_MultiAPSTA = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.",
	schema: {
		"AssociationTime": dm_type.DATETIME,
		"Noise": dm_type.UINT,
		"SteeringHistoryNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Noise": "0",
		"SteeringHistoryNumberOfEntries": "0"
	},
	until: {
		"AssociationTime": "2.21",
		"Noise": "2.21"
	}
};

schemas.MultiAPSTA_SteeringSummaryStats = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringSummaryStats.",
	schema: {
		"NoCandidateAPFailures": dm_type.ULONG,
		"BlacklistAttempts": dm_type.ULONG,
		"BlacklistSuccesses": dm_type.ULONG,
		"BlacklistFailures": dm_type.ULONG,
		"BTMAttempts": dm_type.ULONG,
		"BTMSuccesses": dm_type.ULONG,
		"BTMFailures": dm_type.ULONG,
		"BTMQueryResponses": dm_type.ULONG,
		"LastSteerTime": dm_type.UINT
	},
	defaults: {
		"NoCandidateAPFailures": "18446744073709551615",
		"BlacklistAttempts": "18446744073709551615",
		"BlacklistSuccesses": "18446744073709551615",
		"BlacklistFailures": "18446744073709551615",
		"BTMAttempts": "18446744073709551615",
		"BTMSuccesses": "18446744073709551615",
		"BTMFailures": "18446744073709551615",
		"BTMQueryResponses": "18446744073709551615",
		"LastSteerTime": "0"
	}
};

schemas.MultiAPSTA_SteeringHistory = {
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
	},
	addable: false
};

schemas.STA_TIDQueueSizes = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.TIDQueueSizes.{i}.",
	schema: {
		"TID": dm_type.UINT,
		"Size": dm_type.UINT
	},
	defaults: {
		"TID": "0",
		"Size": "0"
	},
	addable: false
};

schemas.STA_WiFi6Capabilities = {
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

schemas.Device_APMLD = {
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
	},
	addable: false
};

schemas.APMLD_TIDLinkMap = {
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
	},
	addable: false
};

schemas.APMLD_AffiliatedAP = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.AffiliatedAP.{i}.",
	schema: {
		"BSSID": dm_type.STRING,
		"LinkID": dm_type.UINT,
		"RUID": dm_type.BASE64,
		"DisabledSubChannels": dm_type.UINT,
		"PacketsSent": dm_type.UINT,
		"PacketsReceived": dm_type.UINT,
		"UnicastBytesSent": dm_type.UINT,
		"UnicastBytesReceived": dm_type.UINT,
		"ErrorsSent": dm_type.UINT,
		"MulticastBytesSent": dm_type.UINT,
		"MulticastBytesReceived": dm_type.UINT,
		"BroadcastBytesSent": dm_type.UINT,
		"BroadcastBytesReceived": dm_type.UINT,
		"EstServiceParametersBE": dm_type.BASE64,
		"EstServiceParametersBK": dm_type.BASE64,
		"EstServiceParametersVI": dm_type.BASE64,
		"EstServiceParametersVO": dm_type.BASE64
	},
	defaults: {
		"BSSID": "",
		"LinkID": "0",
		"DisabledSubChannels": "0",
		"PacketsSent": "4294967295",
		"PacketsReceived": "4294967295",
		"UnicastBytesSent": "4294967295",
		"UnicastBytesReceived": "4294967295",
		"ErrorsSent": "4294967295",
		"MulticastBytesSent": "4294967295",
		"MulticastBytesReceived": "4294967295",
		"BroadcastBytesSent": "4294967295",
		"BroadcastBytesReceived": "4294967295"
	},
	addable: false
};

schemas.APMLD_APMLDConfig = {
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

schemas.APMLDConfig_TIDToOpClassPolicy = {
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
	},
	constraints: {
		"TID": { min: 0, max: 255 },
		"OpClass": { list: true, max: 255 },
		"Direction": { enum: [ "Up", "Down" ] }
	}
};

schemas.APMLD_STAMLD = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.",
	schema: {
		"MLDMACAddress": dm_type.STRING,
		"Hostname": dm_type.STRING,
		"IPv4Address": dm_type.STRING,
		"IPv6Address": dm_type.STRING,
		"IsbSTA": dm_type.BOOL,
		"LastConnectTime": dm_type.UINT,
		"BytesSent": dm_type.UINT,
		"BytesReceived": dm_type.UINT,
		"PacketsSent": dm_type.UINT,
		"PacketsReceived": dm_type.UINT,
		"ErrorsSent": dm_type.UINT,
		"ErrorsReceived": dm_type.UINT,
		"RetransCount": dm_type.UINT,
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
		"BytesSent": "4294967295",
		"BytesReceived": "4294967295",
		"PacketsSent": "4294967295",
		"PacketsReceived": "4294967295",
		"ErrorsSent": "4294967295",
		"ErrorsReceived": "4294967295",
		"RetransCount": "4294967295",
		"RSNCapabilities": "0",
		"STATIDLinkMapNumberOfEntries": "0",
		"AffiliatedSTANumberOfEntries": "0"
	},
	addable: false
};

schemas.STAMLD_STATIDLinkMap = {
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
	},
	addable: false
};

schemas.STAMLD_STAMLDConfig = {
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

schemas.STAMLD_WiFi7Capabilities = {
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

schemas.STAMLD_AffiliatedSTA = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.AffiliatedSTA.{i}.",
	schema: {
		"MACAddress": dm_type.STRING,
		"BSSID": dm_type.STRING,
		"BytesSent": dm_type.UINT,
		"BytesReceived": dm_type.UINT,
		"PacketsSent": dm_type.UINT,
		"PacketsReceived": dm_type.UINT,
		"ErrorsSent": dm_type.UINT,
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
		"BytesSent": "4294967295",
		"BytesReceived": "4294967295",
		"PacketsSent": "4294967295",
		"PacketsReceived": "4294967295",
		"ErrorsSent": "4294967295",
		"SignalStrength": "0",
		"EstMACDataRateDownlink": "0",
		"EstMACDataRateUplink": "0",
		"LastDataDownlinkRate": "0",
		"LastDataUplinkRate": "0",
		"UtilizationReceive": "0",
		"UtilizationTransmit": "0"
	},
	addable: false
};

schemas.APMLD_LinkToOpClassMap = {
	path: "Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.LinkToOpClassMap.{i}.",
	schema: {
		"LinkID": dm_type.UINT,
		"OpClass": dm_type.UINT
	},
	defaults: {
		"LinkID": "0",
		"OpClass": "0"
	},
	addable: false
};

schemas.Device_bSTAMLD = {
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

schemas.bSTAMLD_bSTAMLDConfig = {
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

schemas.DataElements_AssociationEvent = {
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
	},
	until: {
		"AssociationEventDataNumberOfEntries": "2.20"
	}
};

schemas.AssociationEvent_AssociationEventData = {
	path: "Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.",
	schema: {
		"TimeStamp": dm_type.DATETIME,
		"BSSID": dm_type.STRING,
		"MACAddress": dm_type.STRING,
		"StatusCode": dm_type.UINT,
		"HTCapabilities": dm_type.BASE64,
		"VHTCapabilities": dm_type.BASE64,
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
	},
	addable: false
};

schemas.AssociationEventData_WiFi6Capabilities = {
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

schemas.DataElements_DisassociationEvent = {
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
	},
	until: {
		"DisassociationEventDataNumberOfEntries": "2.20"
	}
};

schemas.DisassociationEvent_DisassociationEventData = {
	path: "Device.WiFi.DataElements.DisassociationEvent.DisassociationEventData.{i}.",
	schema: {
		"BSSID": dm_type.STRING,
		"MACAddress": dm_type.STRING,
		"ReasonCode": dm_type.UINT,
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.UINT,
		"ErrorsReceived": dm_type.UINT,
		"RetransCount": dm_type.UINT,
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
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "4294967295",
		"ErrorsReceived": "4294967295",
		"RetransCount": "4294967295",
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
	},
	addable: false
};

schemas.DataElements_FailedConnectionEvent = {
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
	},
	until: {
		"FailedConnectionEventDataNumberOfEntries": "2.20"
	}
};

schemas.FailedConnectionEvent_FailedConnectionEventData = {
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
	},
	addable: false
};

// Auto-generated schema definitions for IEEE1905 domain
// Generated from TR-181 specifications

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.VendorProperties.{i}.
schemas.IEEE1905Device_VendorProperties = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.VendorProperties.{i}.",
    schema: {
        "MessageType": dm_type.HEXBIN,
        "OUI": dm_type.STRING,
        "Information": dm_type.HEXBIN
    },
    defaults: {
        "OUI": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.ForwardingTable.ForwardingRule.{i}.
schemas.ForwardingTable_ForwardingRule = {
    path: "Device.IEEE1905.AL.ForwardingTable.ForwardingRule.{i}.",
    schema: {
        "InterfaceList": dm_type.STRING | dm_type.WRITABLE,
        "MACDestinationAddress": dm_type.STRING | dm_type.WRITABLE,
        "MACDestinationAddressFlag": dm_type.BOOL | dm_type.WRITABLE,
        "MACSourceAddress": dm_type.STRING | dm_type.WRITABLE,
        "MACSourceAddressFlag": dm_type.BOOL | dm_type.WRITABLE,
        "EtherType": dm_type.UINT | dm_type.WRITABLE,
        "EtherTypeFlag": dm_type.BOOL | dm_type.WRITABLE,
        "Vid": dm_type.UINT | dm_type.WRITABLE,
        "VidFlag": dm_type.BOOL | dm_type.WRITABLE,
        "PCP": dm_type.UINT | dm_type.WRITABLE,
        "PCPFlag": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "InterfaceList": "",
        "MACDestinationAddress": "",
        "MACDestinationAddressFlag": "false",
        "MACSourceAddress": "",
        "MACSourceAddressFlag": "false",
        "EtherType": "0",
        "EtherTypeFlag": "false",
        "Vid": "0",
        "VidFlag": "false",
        "PCP": "0",
        "PCPFlag": "false"
    },
    constraints: {
        "InterfaceList": { list: true, max_length: 256 },
        "MACDestinationAddress": { max_length: 17 },
        "MACSourceAddress": { max_length: 17 },
        "Vid": { min: 0, max: 4095 },
        "PCP": { min: 0, max: 7 }
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.Link.{i}.Metric.
schemas.Link_Metric = {
    path: "Device.IEEE1905.AL.Interface.{i}.Link.{i}.Metric.",
    schema: {
        "IEEE802dot1Bridge": dm_type.BOOL,
        "PacketErrors": dm_type.UINT,
        "PacketErrorsReceived": dm_type.UINT,
        "TransmittedPackets": dm_type.UINT,
        "PacketsReceived": dm_type.UINT,
        "MACThroughputCapacity": dm_type.UINT,
        "LinkAvailability": dm_type.UINT,
        "PHYRate": dm_type.UINT,
        "RSSI": dm_type.UINT
    },
    defaults: {
        "PacketErrors": "4294967295",
        "PacketErrorsReceived": "4294967295",
        "TransmittedPackets": "4294967295",
        "PacketsReceived": "4294967295",
        "MACThroughputCapacity": "0",
        "LinkAvailability": "0",
        "PHYRate": "0",
        "RSSI": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.NonIEEE1905Neighbor.{i}.
schemas.IEEE1905Device_NonIEEE1905Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.NonIEEE1905Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborInterfaceId": dm_type.STRING
    },
    defaults: {
        "LocalInterface": "",
        "NeighborInterfaceId": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.Interface.{i}.VendorProperties.{i}.
schemas.Interface_VendorProperties = {
    path: "Device.IEEE1905.AL.Interface.{i}.VendorProperties.{i}.",
    schema: {
        "OUI": dm_type.STRING,
        "Information": dm_type.HEXBIN
    },
    defaults: {
        "OUI": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv4Address.{i}.
schemas.IEEE1905Device_IPv4Address = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv4Address.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "IPv4Address": dm_type.STRING,
        "IPv4AddressType": dm_type.STRING,
        "DHCPServer": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "IPv4Address": "",
        "IPv4AddressType": "",
        "DHCPServer": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.BridgingTuple.{i}.
schemas.IEEE1905Device_BridgingTuple = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.BridgingTuple.{i}.",
    schema: {
        "InterfaceList": dm_type.STRING
    },
    defaults: {
        "InterfaceList": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv6Address.{i}.
schemas.IEEE1905Device_IPv6Address = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IPv6Address.{i}.",
    schema: {
        "MACAddress": dm_type.STRING,
        "IPv6Address": dm_type.STRING,
        "IPv6AddressType": dm_type.STRING,
        "IPv6AddressOrigin": dm_type.STRING
    },
    defaults: {
        "MACAddress": "",
        "IPv6Address": "",
        "IPv6AddressType": "",
        "IPv6AddressOrigin": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.
schemas.AL_NetworkTopology = {
    path: "Device.IEEE1905.AL.NetworkTopology.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "MaxChangeLogEntries": dm_type.UINT | dm_type.WRITABLE,
        "LastChange": dm_type.STRING,
        "IEEE1905DeviceNumberOfEntries": dm_type.UINT,
        "ChangeLogNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "MaxChangeLogEntries": "0",
        "LastChange": "",
        "IEEE1905DeviceNumberOfEntries": "0",
        "ChangeLogNumberOfEntries": "0"
    },
    constraints: {
        "MaxChangeLogEntries": { min: 1 }
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.Link.{i}.
schemas.Interface_Link = {
    path: "Device.IEEE1905.AL.Interface.{i}.Link.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "IEEE1905Id": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING
    },
    defaults: {
        "InterfaceId": "",
        "IEEE1905Id": "",
        "MediaType": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.Interface.{i}.
schemas.IEEE1905Device_Interface = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.Interface.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "PowerState": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING,
        "NetworkMembership": dm_type.STRING,
        "Role": dm_type.STRING,
        "APChannelBand": dm_type.HEXBIN,
        "FrequencyIndex1": dm_type.HEXBIN,
        "FrequencyIndex2": dm_type.HEXBIN
    },
    defaults: {
        "InterfaceId": "",
        "MediaType": "",
        "PowerState": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": "",
        "NetworkMembership": "",
        "Role": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.ChangeLog.{i}.
schemas.NetworkTopology_ChangeLog = {
    path: "Device.IEEE1905.AL.NetworkTopology.ChangeLog.{i}.",
    schema: {
        "TimeStamp": dm_type.DATETIME,
        "EventType": dm_type.STRING,
        "ReporterDeviceId": dm_type.STRING,
        "ReporterInterfaceId": dm_type.STRING,
        "NeighborType": dm_type.STRING,
        "NeighborId": dm_type.STRING
    },
    defaults: {
        "EventType": "",
        "ReporterDeviceId": "",
        "ReporterInterfaceId": "",
        "NeighborType": "",
        "NeighborId": ""
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.Metric.{i}.
schemas.IEEE1905Neighbor_Metric = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.Metric.{i}.",
    schema: {
        "NeighborMACAddress": dm_type.STRING,
        "IEEE802dot1Bridge": dm_type.BOOL,
        "PacketErrors": dm_type.UINT,
        "PacketErrorsReceived": dm_type.UINT,
        "TransmittedPackets": dm_type.UINT,
        "PacketsReceived": dm_type.UINT,
        "MACThroughputCapacity": dm_type.UINT,
        "LinkAvailability": dm_type.UINT,
        "PHYRate": dm_type.UINT,
        "RSSI": dm_type.UINT
    },
    defaults: {
        "NeighborMACAddress": "",
        "PacketErrors": "4294967295",
        "PacketErrorsReceived": "4294967295",
        "TransmittedPackets": "4294967295",
        "PacketsReceived": "4294967295",
        "MACThroughputCapacity": "0",
        "LinkAvailability": "0",
        "PHYRate": "0",
        "RSSI": "0"
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.ForwardingTable.
schemas.AL_ForwardingTable = {
    path: "Device.IEEE1905.AL.ForwardingTable.",
    schema: {
        "SetForwardingEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "ForwardingRuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ForwardingRuleNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.
schemas.NetworkTopology_IEEE1905Device = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.",
    schema: {
        "IEEE1905Id": dm_type.STRING,
        "Version": dm_type.STRING,
        "RegistrarFreqBand": dm_type.STRING,
        "FriendlyName": dm_type.STRING,
        "ManufacturerName": dm_type.STRING,
        "ManufacturerModel": dm_type.STRING,
        "ControlURL": dm_type.STRING,
        "AssocWiFiNetworkDeviceRef": dm_type.STRING,
        "VendorPropertiesNumberOfEntries": dm_type.UINT,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT,
        "InterfaceNumberOfEntries": dm_type.UINT,
        "NonIEEE1905NeighborNumberOfEntries": dm_type.UINT,
        "IEEE1905NeighborNumberOfEntries": dm_type.UINT,
        "L2NeighborNumberOfEntries": dm_type.UINT,
        "BridgingTupleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "IEEE1905Id": "",
        "Version": "",
        "RegistrarFreqBand": "",
        "FriendlyName": "",
        "ManufacturerName": "",
        "ManufacturerModel": "",
        "ControlURL": "",
        "AssocWiFiNetworkDeviceRef": "",
        "VendorPropertiesNumberOfEntries": "0",
        "IPv4AddressNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0",
        "InterfaceNumberOfEntries": "0",
        "NonIEEE1905NeighborNumberOfEntries": "0",
        "IEEE1905NeighborNumberOfEntries": "0",
        "L2NeighborNumberOfEntries": "0",
        "BridgingTupleNumberOfEntries": "0"
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.
schemas.IEEE1905Device_IEEE1905Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.IEEE1905Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborDeviceId": dm_type.STRING,
        "MetricNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LocalInterface": "",
        "NeighborDeviceId": "",
        "MetricNumberOfEntries": "0"
    },
    addable: false
};

// Schema for Device.IEEE1905.AL.Security.
schemas.AL_Security = {
    path: "Device.IEEE1905.AL.Security.",
    schema: {
        "SetupMethod": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "SetupMethod": "",
        "Password": ""
    },
    constraints: {
        "SetupMethod": { list: true, enum: [ "UCPK", "PBC", "NFCNK" ] },
        "Password": { secured: true }
    }
};

// Schema for Device.IEEE1905.AL.NetworkingRegistrar.
schemas.AL_NetworkingRegistrar = {
    path: "Device.IEEE1905.AL.NetworkingRegistrar.",
    schema: {
        "Registrar2dot4": dm_type.STRING,
        "Registrar5": dm_type.STRING,
        "Registrar60": dm_type.STRING
    },
    defaults: {
        "Registrar2dot4": "",
        "Registrar5": "",
        "Registrar60": ""
    }
};

// Schema for Device.IEEE1905.AL.Interface.{i}.
schemas.AL_Interface = {
    path: "Device.IEEE1905.AL.Interface.{i}.",
    schema: {
        "InterfaceId": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "InterfaceStackReference": dm_type.STRING,
        "MediaType": dm_type.STRING,
        "GenericPhyOUI": dm_type.STRING,
        "GenericPhyVariant": dm_type.HEXBIN,
        "GenericPhyURL": dm_type.STRING,
        "SetIntfPowerStateEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "PowerState": dm_type.STRING | dm_type.WRITABLE,
        "VendorPropertiesNumberOfEntries": dm_type.UINT,
        "LinkNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceId": "",
        "Status": "",
        "LastChange": "0",
        "LowerLayers": "",
        "InterfaceStackReference": "",
        "MediaType": "",
        "GenericPhyOUI": "",
        "GenericPhyURL": "",
        "PowerState": "",
        "VendorPropertiesNumberOfEntries": "0",
        "LinkNumberOfEntries": "0"
    },
    constraints: {
        "PowerState": { enum: [ "On", "Power_Save", "Off", "Unsupported" ] }
    },
    addable: false
};

// Schema for Device.IEEE1905.
schemas.IEEE1905 = {
    path: "Device.IEEE1905.",
    schema: {
        "Version": dm_type.STRING
    },
    defaults: {
        "Version": ""
    }
};

// Schema for Device.IEEE1905.AL.
schemas.AL = {
    path: "Device.IEEE1905.AL.",
    schema: {
        "IEEE1905Id": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "RegistrarFreqBand": dm_type.STRING,
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "IEEE1905Id": "",
        "Status": "",
        "LastChange": "0",
        "LowerLayers": "",
        "RegistrarFreqBand": "",
        "InterfaceNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.L2Neighbor.{i}.
schemas.IEEE1905Device_L2Neighbor = {
    path: "Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.{i}.L2Neighbor.{i}.",
    schema: {
        "LocalInterface": dm_type.STRING,
        "NeighborInterfaceId": dm_type.STRING,
        "BehindInterfaceIds": dm_type.STRING
    },
    defaults: {
        "LocalInterface": "",
        "NeighborInterfaceId": "",
        "BehindInterfaceIds": ""
    },
    addable: false
};

schemas.EasyMesh = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.",
	schema: {
		"Bridge": dm_type.STRING | dm_type.WRITABLE,
	},
	defaults: {
		"Bridge": "",
	}
};

schemas.Agent = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"ReceivedPolicy": dm_type.STRING,
		"Reset()": {
			type: 'async',
			input: ['privkey', 'pubkey_x', 'pubkey_y', 'hash', 'curve', 'disable_dpp'],
			output: []
		}
	},
	defaults: {
		"Enable": "false",
		"ReceivedPolicy": "",
	}
};

schemas.Controller = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"PolicyNumberOfEntries": dm_type.UINT,
	},
	defaults: {
		"Enable": "false",
		"PolicyNumberOfEntries": "0",
	}
};

schemas.Controller_Policy = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy.{i}.",
	schema: {
		"ALMAC": dm_type.STRING | dm_type.WRITABLE,
		"Data": dm_type.STRING | dm_type.WRITABLE,
	},
	defaults: {
		"ALMAC": "",
		"Data": "",
	}
};

schemas.Steering = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Backend": dm_type.STRING | dm_type.WRITABLE,
		"LogLevel": dm_type.UINT | dm_type.WRITABLE,
		"PeriodicInterval": dm_type.UINT | dm_type.WRITABLE,
		"MetricStaleInterval": dm_type.UINT | dm_type.WRITABLE,
		"APMetricsReportingInterval": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "false",
		"Backend": "umap",
		"LogLevel": "3",
		"PeriodicInterval": "10000",
		"MetricStaleInterval": "30000",
		"APMetricsReportingInterval": "30",
	}
};

schemas.Steering_SignalQuality = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.SignalQuality.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"LowRCPICount": dm_type.UINT | dm_type.WRITABLE,
		"HighRCPICount": dm_type.UINT | dm_type.WRITABLE,
		"SignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"Hysteresis": dm_type.UINT | dm_type.WRITABLE,
		"DiffSNRMargin": dm_type.UINT | dm_type.WRITABLE,
		"UnassocCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"BeaconCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"LowRCPICount": "3",
		"HighRCPICount": "4",
		"SignalThreshold2G": "-75",
		"SignalThreshold5G": "-67",
		"SignalThreshold6G": "-67",
		"ReportSignalThreshold2G": "-70",
		"ReportSignalThreshold5G": "-62",
		"ReportSignalThreshold6G": "-62",
		"Hysteresis": "2",
		"DiffSNRMargin": "8",
		"UnassocCollectTime": "5000",
		"BeaconCollectTime": "10000",
		"Cooldown": "180000",
	}
};

schemas.Steering_APLoad = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.APLoad.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"OverloadThreshold": dm_type.UINT | dm_type.WRITABLE,
		"TargetThreshold": dm_type.UINT | dm_type.WRITABLE,
		"MinSteerSignal": dm_type.INT | dm_type.WRITABLE,
		"ConfinedDuration": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
		"MinConnectedTime": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"OverloadThreshold": "80",
		"TargetThreshold": "60",
		"MinSteerSignal": "-75",
		"ConfinedDuration": "300000",
		"Cooldown": "300000",
		"MinConnectedTime": "30000",
	}
};

schemas.Steering_BandPreference = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BandPreference.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"RSSICutoff": dm_type.INT | dm_type.WRITABLE,
		"PathlossDelta": dm_type.UINT | dm_type.WRITABLE,
		"PathlossDelta5To6": dm_type.UINT | dm_type.WRITABLE,
		"UpgradeMargin": dm_type.UINT | dm_type.WRITABLE,
		"DowngradeCount": dm_type.UINT | dm_type.WRITABLE,
		"SettlingDelay": dm_type.UINT | dm_type.WRITABLE,
		"CooldownSuccess": dm_type.UINT | dm_type.WRITABLE,
		"CooldownFailure": dm_type.UINT | dm_type.WRITABLE,
		"MaxFailuresPerBand": dm_type.UINT | dm_type.WRITABLE,
		"FailureDecayTime": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"RSSICutoff": "-75",
		"PathlossDelta": "10",
		"PathlossDelta5To6": "3",
		"UpgradeMargin": "5",
		"DowngradeCount": "3",
		"SettlingDelay": "6000",
		"CooldownSuccess": "180000",
		"CooldownFailure": "30000",
		"MaxFailuresPerBand": "3",
		"FailureDecayTime": "600",
	}
};

schemas.Steering_BackhaulLink = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.BackhaulLink.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"SignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"SignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold2G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold5G": dm_type.INT | dm_type.WRITABLE,
		"ReportSignalThreshold6G": dm_type.INT | dm_type.WRITABLE,
		"SignalDiffThreshold": dm_type.UINT | dm_type.WRITABLE,
		"RCPILowTrigger": dm_type.UINT | dm_type.WRITABLE,
		"RCPIRecoveryTrigger": dm_type.UINT | dm_type.WRITABLE,
		"ThroughputDropPct": dm_type.UINT | dm_type.WRITABLE,
		"ThroughputTrigger": dm_type.UINT | dm_type.WRITABLE,
		"TopologyImpactThreshold": dm_type.UINT | dm_type.WRITABLE,
		"MinAssocTime": dm_type.UINT | dm_type.WRITABLE,
		"UnassocCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"BeaconCollectTime": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"SignalThreshold2G": "-72",
		"SignalThreshold5G": "-64",
		"SignalThreshold6G": "-64",
		"ReportSignalThreshold2G": "-67",
		"ReportSignalThreshold5G": "-59",
		"ReportSignalThreshold6G": "-59",
		"SignalDiffThreshold": "8",
		"RCPILowTrigger": "5",
		"RCPIRecoveryTrigger": "6",
		"ThroughputDropPct": "40",
		"ThroughputTrigger": "5",
		"TopologyImpactThreshold": "10",
		"MinAssocTime": "30",
		"UnassocCollectTime": "10000",
		"BeaconCollectTime": "10000",
		"Cooldown": "300000",
	}
};

schemas.Steering_DFSEvacuation = {
	path: "Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Steering.DFSEvacuation.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"DisassocTimer": dm_type.UINT | dm_type.WRITABLE,
		"EvacuateTimeout": dm_type.UINT | dm_type.WRITABLE,
		"CACTimeout": dm_type.UINT | dm_type.WRITABLE,
		"ReturnTimeout": dm_type.UINT | dm_type.WRITABLE,
	},
	defaults: {
		"Enable": "true",
		"DisassocTimer": "15000",
		"EvacuateTimeout": "60000",
		"CACTimeout": "660000",
		"ReturnTimeout": "60000",
	}
};
