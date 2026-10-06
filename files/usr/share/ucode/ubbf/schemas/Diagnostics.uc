'use strict';

export const Diagnostics = {
	path: 'Device.IP.Diagnostics.',
	schema: {
		'IPv4PingSupported': dm_type.BOOL,
		'IPv6PingSupported': dm_type.BOOL,
		'IPv4TraceRouteSupported': dm_type.BOOL,
		'IPv6TraceRouteSupported': dm_type.BOOL,
		'IPv4DownloadDiagnosticsSupported': dm_type.BOOL,
		'IPv6DownloadDiagnosticsSupported': dm_type.BOOL,
		'IPv4UploadDiagnosticsSupported': dm_type.BOOL,
		'IPv6UploadDiagnosticsSupported': dm_type.BOOL,
		'IPv4UDPEchoDiagnosticsSupported': dm_type.BOOL,
		'IPv6UDPEchoDiagnosticsSupported': dm_type.BOOL,
		'IPv4ServerSelectionDiagnosticsSupported': dm_type.BOOL,
		'IPv6ServerSelectionDiagnosticsSupported': dm_type.BOOL,
		'IPLayerCapacitySupported': dm_type.BOOL,
		'IPLayerMaxConnections': dm_type.UINT,
		'IPLayerMaxIncrementalResult': dm_type.UINT,
		'IPLayerCapSupportedSoftwareVersion': dm_type.STRING,
		'IPLayerCapSupportedControlProtocolVersion': dm_type.STRING,
		'IPLayerCapSupportedMetrics': dm_type.STRING,
		'IPPing()': {
			type: 'async',
			input: [
				'Host',
				'Interface',
				'ProtocolVersion',
				'NumberOfRepetitions',
				'Timeout',
				'DataBlockSize'
			],
			output: [
				'Status',
				'IPAddressUsed',
				'SuccessCount',
				'FailureCount',
				'AverageResponseTime',
				'MinimumResponseTime',
				'MaximumResponseTime',
				'AverageResponseTimeDetailed',
				'MinimumResponseTimeDetailed',
				'MaximumResponseTimeDetailed'
			]
		},
		'TraceRoute()': {
			type: 'async',
			input: [
				'Host',
				'Interface',
				'ProtocolVersion',
				'NumberOfTries',
				'Timeout',
				'DataBlockSize',
				'DSCP',
				'MaxHopCount'
			],
			output: [
				'Status',
				'IPAddressUsed',
				'ResponseTime',
				'RouteHops.{i}.Host',
				'RouteHops.{i}.HostAddress',
				'RouteHops.{i}.ErrorCode',
				'RouteHops.{i}.RTTimes'
			]
		},
		'DownloadDiagnostics()': {
			type: 'async',
			input: [
				'Interface',
				'DownloadURL',
				'ProtocolVersion'
			],
			output: [
				'Status',
				'IPAddressUsed',
				'ROMTime',
				'BOMTime',
				'EOMTime',
				'TestBytesReceived',
				'TotalBytesReceived',
				'TotalBytesSent',
				'TestBytesReceivedUnderFullLoading',
				'TotalBytesReceivedUnderFullLoading',
				'TotalBytesSentUnderFullLoading',
				'PeriodOfFullLoading',
				'TCPOpenRequestTime',
				'TCPOpenResponseTime'
			]
		},
		'UploadDiagnostics()': {
			type: 'async',
			input: [
				'Interface',
				'UploadURL',
				'TestFileLength',
				'ProtocolVersion'
			],
			output: [
				'Status',
				'IPAddressUsed',
				'ROMTime',
				'BOMTime',
				'EOMTime',
				'TestBytesSent',
				'TotalBytesReceived',
				'TotalBytesSent',
				'TestBytesSentUnderFullLoading',
				'TotalBytesReceivedUnderFullLoading',
				'TotalBytesSentUnderFullLoading',
				'PeriodOfFullLoading',
				'TCPOpenRequestTime',
				'TCPOpenResponseTime'
			]
		},
		'UDPEchoDiagnostics()': {
			type: 'async',
			input: [
				'Host',
				'Interface',
				'ProtocolVersion',
				'Port',
				'NumberOfRepetitions',
				'Timeout',
				'DataBlockSize',
				'DSCP',
				'InterTransmissionTime'
			],
			output: [
				'Status',
				'IPAddressUsed',
				'SuccessCount',
				'FailureCount',
				'AverageResponseTime',
				'MinimumResponseTime',
				'MaximumResponseTime'
			]
		},
		'ServerSelectionDiagnostics()': {
			type: 'async',
			input: [
				'Interface',
				'ProtocolVersion',
				'Protocol',
				'HostList',
				'NumberOfRepetitions',
				'Timeout'
			],
			output: [
				'Status',
				'FastestHost',
				'MinimumResponseTime',
				'AverageResponseTime',
				'MaximumResponseTime',
				'IPAddressUsed'
			]
		},
		'IPLayerCapacity()': {
			type: 'async',
			input: [
				'Interface',
				'Role',
				'Host',
				'Port',
				'JumboFramesPermitted',
				'DSCP',
				'ProtocolVersion',
				'UDPPayloadContent',
				'TestType',
				'IPDVEnable',
				'StartSendingRateIndex',
				'NumberTestSubIntervals',
				'NumberFirstModeTestSubIntervals',
				'TestSubInterval',
				'StatusFeedbackInterval',
				'SeqErrThresh',
				'ReordDupIgnoreEnable',
				'LowerThresh',
				'UpperThresh',
				'HighSpeedDelta',
				'SlowAdjThresh',
				'RateAdjAlgorithm'
			],
			output: [
				'Status',
				'BOMTime',
				'EOMTime',
				'TmaxUsed',
				'TestInterval',
				'TmaxRTTUsed',
				'TimestampResolutionUsed',
				'MaxIPLayerCapacity',
				'TimeOfMax',
				'MaxETHCapacityNoFCS',
				'MaxETHCapacityWithFCS',
				'MaxETHCapacityWithFCSVLAN',
				'LossRatioAtMax',
				'RTTRangeAtMax',
				'PDVRangeAtMax',
				'MinOnewayDelayAtMax',
				'ReorderedRatioAtMax',
				'ReplicatedRatioAtMax',
				'InterfaceEthMbpsAtMax',
				'IPLayerCapacitySummary',
				'LossRatioSummary',
				'RTTRangeSummary',
				'PDVRangeSummary',
				'MinOnewayDelaySummary',
				'MinRTTSummary',
				'ReorderedRatioSummary',
				'ReplicatedRatioSummary',
				'InterfaceEthMbpsSummary',
				'ModalResult.{i}.MaxIPLayerCapacity',
				'ModalResult.{i}.TimeOfMax',
				'ModalResult.{i}.MaxETHCapacityNoFCS',
				'ModalResult.{i}.MaxETHCapacityWithFCS',
				'ModalResult.{i}.MaxETHCapacityWithFCSVLAN',
				'ModalResult.{i}.LossRatioAtMax',
				'ModalResult.{i}.RTTRangeAtMax',
				'ModalResult.{i}.PDVRangeAtMax',
				'ModalResult.{i}.MinOnewayDelayAtMax',
				'ModalResult.{i}.ReorderedRatioAtMax',
				'ModalResult.{i}.ReplicatedRatioAtMax',
				'ModalResult.{i}.InterfaceEthMbpsAtMax',
				'IncrementalResult.{i}.IPLayerCapacity',
				'IncrementalResult.{i}.TimeOfSubInterval',
				'IncrementalResult.{i}.LossRatio',
				'IncrementalResult.{i}.RTTRange',
				'IncrementalResult.{i}.PDVRange',
				'IncrementalResult.{i}.MinOnewayDelay',
				'IncrementalResult.{i}.ReorderedRatio',
				'IncrementalResult.{i}.ReplicatedRatio',
				'IncrementalResult.{i}.InterfaceEthMbps'
			]
		}
	},
	defaults: {}
};

export const IPPing = {
	path: 'Device.IP.Diagnostics.IPPing.',
	schema: {
		'DiagnosticsState': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'ProtocolVersion': dm_type.STRING | dm_type.WRITABLE,
		'Host': dm_type.STRING | dm_type.WRITABLE,
		'NumberOfRepetitions': dm_type.UINT | dm_type.WRITABLE,
		'Timeout': dm_type.UINT | dm_type.WRITABLE,
		'DataBlockSize': dm_type.UINT | dm_type.WRITABLE,
		'DSCP': dm_type.UINT | dm_type.WRITABLE,
		'IPAddressUsed': dm_type.STRING,
		'SuccessCount': dm_type.UINT,
		'FailureCount': dm_type.UINT,
		'AverageResponseTime': dm_type.UINT,
		'MinimumResponseTime': dm_type.UINT,
		'MaximumResponseTime': dm_type.UINT,
		'AverageResponseTimeDetailed': dm_type.UINT,
		'MinimumResponseTimeDetailed': dm_type.UINT,
		'MaximumResponseTimeDetailed': dm_type.UINT
	},
	defaults: {
		'DiagnosticsState': 'None',
		'Interface': '',
		'ProtocolVersion': 'Any',
		'Host': '',
		'NumberOfRepetitions': '3',
		'Timeout': '1000',
		'DataBlockSize': '64',
		'DSCP': '0',
		'IPAddressUsed': '',
		'SuccessCount': '0',
		'FailureCount': '0',
		'AverageResponseTime': '0',
		'MinimumResponseTime': '0',
		'MaximumResponseTime': '0',
		'AverageResponseTimeDetailed': '0',
		'MinimumResponseTimeDetailed': '0',
		'MaximumResponseTimeDetailed': '0'
	}
};

export const TraceRoute = {
	path: 'Device.IP.Diagnostics.TraceRoute.',
	schema: {
		'DiagnosticsState': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'ProtocolVersion': dm_type.STRING | dm_type.WRITABLE,
		'Host': dm_type.STRING | dm_type.WRITABLE,
		'NumberOfTries': dm_type.UINT | dm_type.WRITABLE,
		'Timeout': dm_type.UINT | dm_type.WRITABLE,
		'DataBlockSize': dm_type.UINT | dm_type.WRITABLE,
		'DSCP': dm_type.UINT | dm_type.WRITABLE,
		'MaxHopCount': dm_type.UINT | dm_type.WRITABLE,
		'ResponseTime': dm_type.UINT,
		'IPAddressUsed': dm_type.STRING,
		'RouteHopsNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'DiagnosticsState': 'None',
		'Interface': '',
		'ProtocolVersion': 'Any',
		'Host': '',
		'NumberOfTries': '3',
		'Timeout': '5000',
		'DataBlockSize': '38',
		'DSCP': '0',
		'MaxHopCount': '30',
		'ResponseTime': '0',
		'IPAddressUsed': '',
		'RouteHopsNumberOfEntries': '0'
	}
};

export const TraceRoute_RouteHops = {
	path: 'Device.IP.Diagnostics.TraceRoute.RouteHops.{i}.',
	schema: {
		'Host': dm_type.STRING,
		'HostAddress': dm_type.STRING,
		'ErrorCode': dm_type.UINT,
		'RTTimes': dm_type.STRING
	},
	defaults: {}
};

export const UDPEchoConfig = {
	path: 'Device.IP.Diagnostics.UDPEchoConfig.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'SourceIPAddress': dm_type.STRING | dm_type.WRITABLE,
		'UDPPort': dm_type.UINT | dm_type.WRITABLE,
		'EchoPlusEnabled': dm_type.BOOL | dm_type.WRITABLE,
		'EchoPlusSupported': dm_type.BOOL,
		'PacketsReceived': dm_type.UINT,
		'PacketsResponded': dm_type.UINT,
		'BytesReceived': dm_type.UINT,
		'BytesResponded': dm_type.UINT,
		'TimeFirstPacketReceived': dm_type.DATETIME,
		'TimeLastPacketReceived': dm_type.DATETIME
	},
	defaults: {
		'Enable': 'false',
		'Interface': '',
		'SourceIPAddress': '',
		'UDPPort': '7',
		'EchoPlusEnabled': 'false',
		'EchoPlusSupported': 'true',
		'PacketsReceived': '0',
		'PacketsResponded': '0',
		'BytesReceived': '0',
		'BytesResponded': '0',
		'TimeFirstPacketReceived': '0001-01-01T00:00:00Z',
		'TimeLastPacketReceived': '0001-01-01T00:00:00Z'
	}
};

export const UDPEchoDiagnostics = {
	path: 'Device.IP.Diagnostics.UDPEchoDiagnostics.',
	schema: {
		'DiagnosticsState': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'Host': dm_type.STRING | dm_type.WRITABLE,
		'Port': dm_type.UINT | dm_type.WRITABLE,
		'NumberOfRepetitions': dm_type.UINT | dm_type.WRITABLE,
		'Timeout': dm_type.UINT | dm_type.WRITABLE,
		'DataBlockSize': dm_type.UINT | dm_type.WRITABLE,
		'DSCP': dm_type.UINT | dm_type.WRITABLE,
		'InterTransmissionTime': dm_type.UINT | dm_type.WRITABLE,
		'ProtocolVersion': dm_type.STRING | dm_type.WRITABLE,
		'IPAddressUsed': dm_type.STRING,
		'SuccessCount': dm_type.UINT,
		'FailureCount': dm_type.UINT,
		'AverageResponseTime': dm_type.UINT,
		'MinimumResponseTime': dm_type.UINT,
		'MaximumResponseTime': dm_type.UINT
	},
	defaults: {
		'DiagnosticsState': 'None',
		'Interface': '',
		'Host': '',
		'Port': '7',
		'NumberOfRepetitions': '1',
		'Timeout': '1000',
		'DataBlockSize': '24',
		'DSCP': '0',
		'InterTransmissionTime': '1000',
		'ProtocolVersion': 'Any',
		'IPAddressUsed': '',
		'SuccessCount': '0',
		'FailureCount': '0',
		'AverageResponseTime': '0',
		'MinimumResponseTime': '0',
		'MaximumResponseTime': '0'
	}
};

export const ServerSelectionDiagnostics = {
	path: 'Device.IP.Diagnostics.ServerSelectionDiagnostics.',
	schema: {
		'DiagnosticsState': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'ProtocolVersion': dm_type.STRING | dm_type.WRITABLE,
		'Protocol': dm_type.STRING | dm_type.WRITABLE,
		'HostList': dm_type.STRING | dm_type.WRITABLE,
		'NumberOfRepetitions': dm_type.UINT | dm_type.WRITABLE,
		'Timeout': dm_type.UINT | dm_type.WRITABLE,
		'FastestHost': dm_type.STRING,
		'MinimumResponseTime': dm_type.UINT,
		'AverageResponseTime': dm_type.UINT,
		'MaximumResponseTime': dm_type.UINT,
		'IPAddressUsed': dm_type.STRING
	},
	defaults: {
		'DiagnosticsState': 'None',
		'Interface': '',
		'ProtocolVersion': 'Any',
		'Protocol': 'ICMP',
		'HostList': '',
		'NumberOfRepetitions': '3',
		'Timeout': '1000',
		'FastestHost': '',
		'MinimumResponseTime': '0',
		'AverageResponseTime': '0',
		'MaximumResponseTime': '0',
		'IPAddressUsed': ''
	}
};
