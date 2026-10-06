'use strict';

// Schema definitions for the Device.Cellular domain.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.Cellular = {
	path: "Device.Cellular.",
	schema: {
		"RoamingEnabled": dm_type.BOOL | dm_type.WRITABLE,
		"RoamingStatus": dm_type.STRING,
		"InterfaceNumberOfEntries": dm_type.UINT,
		"AccessPointNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"RoamingStatus": "",
		"InterfaceNumberOfEntries": "0",
		"AccessPointNumberOfEntries": "0"
	}
};

schemas.Interface = {
	path: "Device.Cellular.Interface.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING,
		"Name": dm_type.STRING,
		"Description": dm_type.STRING | dm_type.WRITABLE,
		"LastChange": dm_type.UINT,
		"LowerLayers": dm_type.STRING | dm_type.WRITABLE,
		"Upstream": dm_type.BOOL,
		"IMEI": dm_type.STRING,
		"SupportedAccessTechnologies": dm_type.STRING,
		"PreferredAccessTechnology": dm_type.STRING | dm_type.WRITABLE,
		"CurrentAccessTechnology": dm_type.STRING,
		"AvailableNetworks": dm_type.STRING,
		"NetworkRequested": dm_type.STRING | dm_type.WRITABLE,
		"NetworkInUse": dm_type.STRING,
		"RSSI": dm_type.INT,
		"RSRP": dm_type.INT,
		"RSRQ": dm_type.INT,
		"UpstreamMaxBitRate": dm_type.UINT,
		"DownstreamMaxBitRate": dm_type.UINT,
		"SIMReferenceList": dm_type.STRING | dm_type.WRITABLE,
		"X_UBBF_Device": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Status": "",
		"Alias": "",
		"Name": "",
		"Description": "",
		"LastChange": "0",
		"LowerLayers": "",
		"IMEI": "",
		"SupportedAccessTechnologies": "",
		"PreferredAccessTechnology": "Auto",
		"CurrentAccessTechnology": "",
		"AvailableNetworks": "",
		"NetworkRequested": "",
		"NetworkInUse": "",
		"RSSI": "0",
		"RSRP": "0",
		"RSRQ": "0",
		"UpstreamMaxBitRate": "0",
		"DownstreamMaxBitRate": "0",
		"SIMReferenceList": "",
		"X_UBBF_Device": ""
	},
	since: {
		"Description": "2.21"
	},
	constraints: {
		"Description": { max_length: 256 },
		"LowerLayers": { list: true, list_max_length: 1024 },
		"NetworkRequested": { max_length: 64 },
		"SIMReferenceList": { list: true }
	},
	addable: false
};

schemas.Interface_Stats = {
	path: "Device.Cellular.Interface.{i}.Stats.",
	schema: {
		"BytesSent": dm_type.ULONG,
		"BytesReceived": dm_type.ULONG,
		"PacketsSent": dm_type.ULONG,
		"PacketsReceived": dm_type.ULONG,
		"ErrorsSent": dm_type.ULONG,
		"ErrorsReceived": dm_type.ULONG,
		"UnicastPacketsSent": dm_type.ULONG,
		"UnicastPacketsReceived": dm_type.ULONG,
		"DiscardPacketsSent": dm_type.ULONG,
		"DiscardPacketsReceived": dm_type.ULONG,
		"MulticastPacketsSent": dm_type.ULONG,
		"MulticastPacketsReceived": dm_type.ULONG,
		"BroadcastPacketsSent": dm_type.ULONG,
		"BroadcastPacketsReceived": dm_type.ULONG,
		"UnknownProtoPacketsReceived": dm_type.ULONG,
		"Reset()": { type: 'sync', input: [] }
	},
	defaults: {
		"BytesSent": "18446744073709551615",
		"BytesReceived": "18446744073709551615",
		"PacketsSent": "18446744073709551615",
		"PacketsReceived": "18446744073709551615",
		"ErrorsSent": "18446744073709551615",
		"ErrorsReceived": "18446744073709551615",
		"UnicastPacketsSent": "18446744073709551615",
		"UnicastPacketsReceived": "18446744073709551615",
		"DiscardPacketsSent": "18446744073709551615",
		"DiscardPacketsReceived": "18446744073709551615",
		"MulticastPacketsSent": "18446744073709551615",
		"MulticastPacketsReceived": "18446744073709551615",
		"BroadcastPacketsSent": "18446744073709551615",
		"BroadcastPacketsReceived": "18446744073709551615",
		"UnknownProtoPacketsReceived": "18446744073709551615"
	}
};

schemas.Interface_USIM = {
	path: "Device.Cellular.Interface.{i}.USIM.",
	schema: {
		"Status": dm_type.STRING,
		"IMSI": dm_type.STRING,
		"ICCID": dm_type.STRING,
		"MSISDN": dm_type.STRING,
		"PINCheck": dm_type.STRING | dm_type.WRITABLE,
		"PIN": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Status": "",
		"IMSI": "",
		"ICCID": "",
		"MSISDN": "",
		"PINCheck": "",
		"PIN": ""
	},
	constraints: {
		"PINCheck": { enum: [ "OnNetworkAccess", "Reboot", "Off" ] },
		"PIN": { secured: true, max_length: 4 }
	}
};

schemas.AccessPoint = {
	path: "Device.Cellular.AccessPoint.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING,
		"APN": dm_type.STRING | dm_type.WRITABLE,
		"Username": dm_type.STRING | dm_type.WRITABLE,
		"Password": dm_type.STRING | dm_type.WRITABLE,
		"Proxy": dm_type.STRING | dm_type.WRITABLE,
		"ProxyPort": dm_type.UINT | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"IPVersion": dm_type.INT | dm_type.WRITABLE,
		"Type": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Alias": "",
		"APN": "",
		"Username": "",
		"Password": "",
		"Proxy": "",
		"ProxyPort": "0",
		"Interface": "",
		"IPVersion": "-1",
		"Type": ""
	},
	constraints: {
		"APN": { max_length: 100 },
		"Username": { max_length: 256 },
		"Password": { secured: true, max_length: 256 },
		"Proxy": { max_length: 45 },
		"ProxyPort": { min: 1, max: 65535 },
		"IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
		"Type": { list: true }
	}
};
