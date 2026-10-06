'use strict';

// Schema definitions for the Device.X_UBBF.QoSify domain.
//
// Included by handler.uc with { schemas } as the scope; there is nothing to
// export from an included file, so each definition is added to that object.

schemas.QoSify = {
	path: 'Device.X_UBBF.QoSify.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Status': dm_type.STRING,
		'ClassifierNumberOfEntries': dm_type.UINT,
		'DNSClassifierNumberOfEntries': dm_type.UINT,
		'DSCPMapNumberOfEntries': dm_type.UINT,
		'InterfaceConfigNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'Enable': 'false',
		'Status': 'Disabled',
		'ClassifierNumberOfEntries': '0',
		'DNSClassifierNumberOfEntries': '0',
		'DSCPMapNumberOfEntries': '0',
		'InterfaceConfigNumberOfEntries': '0'
	}
};

schemas.Config = {
	path: 'Device.X_UBBF.QoSify.Config.',
	schema: {
		'DefaultTCPDSCP': dm_type.STRING | dm_type.WRITABLE,
		'DefaultUDPDSCP': dm_type.STRING | dm_type.WRITABLE,
		'ICMPDSCP': dm_type.STRING | dm_type.WRITABLE,
		'PriorityDSCP': dm_type.STRING | dm_type.WRITABLE,
		'BulkDSCP': dm_type.STRING | dm_type.WRITABLE,
		'BulkTriggerPPS': dm_type.UINT | dm_type.WRITABLE,
		'BulkTriggerTimeout': dm_type.UINT | dm_type.WRITABLE,
		'PriorityMaxAvgPktLen': dm_type.UINT | dm_type.WRITABLE
	},
	defaults: {
		'DefaultTCPDSCP': 'CS0',
		'DefaultUDPDSCP': 'CS0',
		'ICMPDSCP': 'CS0',
		'PriorityDSCP': 'AF41',
		'BulkDSCP': 'LE',
		'BulkTriggerPPS': '150',
		'BulkTriggerTimeout': '5',
		'PriorityMaxAvgPktLen': '500'
	}
};

schemas.Classifier = {
	path: 'Device.X_UBBF.QoSify.Classifier.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Order': dm_type.UINT | dm_type.WRITABLE,
		'Protocol': dm_type.INT | dm_type.WRITABLE,
		'DestPort': dm_type.INT | dm_type.WRITABLE,
		'DestPortRangeEnd': dm_type.INT | dm_type.WRITABLE,
		'SourceIP': dm_type.STRING | dm_type.WRITABLE,
		'DSCPMark': dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		'Enable': 'false',
		'Alias': '',
		'Order': '0',
		'Protocol': '-1',
		'DestPort': '-1',
		'DestPortRangeEnd': '-1',
		'SourceIP': '',
		'DSCPMark': 'CS0'
	}
};

schemas.DNSClassifier = {
	path: 'Device.X_UBBF.QoSify.DNSClassifier.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Order': dm_type.UINT | dm_type.WRITABLE,
		'Domain': dm_type.STRING | dm_type.WRITABLE,
		'MatchType': dm_type.STRING | dm_type.WRITABLE,
		'CNAMEOnly': dm_type.BOOL | dm_type.WRITABLE,
		'DSCPMark': dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		'Enable': 'false',
		'Alias': '',
		'Order': '0',
		'Domain': '',
		'MatchType': 'Suffix',
		'CNAMEOnly': 'false',
		'DSCPMark': 'CS0'
	}
};

schemas.DSCPMap = {
	path: 'Device.X_UBBF.QoSify.DSCPMap.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Name': dm_type.STRING | dm_type.WRITABLE,
		'IngressDSCP': dm_type.STRING | dm_type.WRITABLE,
		'EgressDSCP': dm_type.STRING | dm_type.WRITABLE,
		'Description': dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		'Enable': 'false',
		'Alias': '',
		'Name': '',
		'IngressDSCP': 'CS0',
		'EgressDSCP': 'CS0',
		'Description': ''
	}
};

schemas.InterfaceConfig = {
	path: 'Device.X_UBBF.QoSify.InterfaceConfig.{i}.',
	schema: {
		'Enable': dm_type.BOOL | dm_type.WRITABLE,
		'Alias': dm_type.STRING | dm_type.WRITABLE,
		'Interface': dm_type.STRING | dm_type.WRITABLE,
		'InterfaceName': dm_type.STRING,
		'BandwidthUp': dm_type.STRING | dm_type.WRITABLE,
		'BandwidthDown': dm_type.STRING | dm_type.WRITABLE,
		'Ingress': dm_type.BOOL | dm_type.WRITABLE,
		'Egress': dm_type.BOOL | dm_type.WRITABLE,
		'Mode': dm_type.STRING | dm_type.WRITABLE,
		'NAT': dm_type.BOOL | dm_type.WRITABLE,
		'HostIsolate': dm_type.BOOL | dm_type.WRITABLE,
		'Active': dm_type.BOOL
	},
	defaults: {
		'Enable': 'false',
		'Alias': '',
		'Interface': '',
		'InterfaceName': '',
		'BandwidthUp': '',
		'BandwidthDown': '',
		'Ingress': 'true',
		'Egress': 'true',
		'Mode': 'diffserv4',
		'NAT': 'true',
		'HostIsolate': 'true',
		'Active': 'false'
	}
};

schemas.Stats = {
	path: 'Device.X_UBBF.QoSify.Stats.',
	schema: {
		'DNSCacheHits': dm_type.ULONG,
		'DNSCacheMisses': dm_type.ULONG,
		'DNSCacheSize': dm_type.UINT,
		'eBPFMapEntries': dm_type.UINT,
		'LastReloadTime': dm_type.DATETIME,
		'ClassNumberOfEntries': dm_type.UINT,
		'FQDNNumberOfEntries': dm_type.UINT
	},
	defaults: {
		'DNSCacheHits': '0',
		'DNSCacheMisses': '0',
		'DNSCacheSize': '0',
		'eBPFMapEntries': '0',
		'LastReloadTime': '0001-01-01T00:00:00Z',
		'ClassNumberOfEntries': '0',
		'FQDNNumberOfEntries': '0'
	}
};

schemas.StatsClass = {
	path: 'Device.X_UBBF.QoSify.Stats.Class.{i}.',
	schema: {
		'Name': dm_type.STRING,
		'Packets': dm_type.ULONG,
		'Bytes': dm_type.ULONG
	},
	defaults: {
		'Name': '',
		'Packets': '0',
		'Bytes': '0'
	}
};

schemas.StatsFQDN = {
	path: 'Device.X_UBBF.QoSify.Stats.FQDN.{i}.',
	schema: {
		'Name': dm_type.STRING,
		'Class': dm_type.STRING,
		'Hits': dm_type.ULONG,
		'Packets': dm_type.ULONG,
		'Bytes': dm_type.ULONG
	},
	defaults: {
		'Name': '',
		'Class': '',
		'Hits': '0',
		'Packets': '0',
		'Bytes': '0'
	}
};
