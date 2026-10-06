'use strict';

// Schema definitions for the Device.Cellular domain.
//
// Included by handler.uc with { schemas } as the scope; there is nothing to
// export from an included file, so each definition is added to that object.

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
	}
};

schemas.Interface_Stats = {
	path: "Device.Cellular.Interface.{i}.Stats.",
	schema: {
		"BytesSent": dm_type.STRING,
		"BytesReceived": dm_type.STRING,
		"PacketsSent": dm_type.STRING,
		"PacketsReceived": dm_type.STRING,
		"ErrorsSent": dm_type.STRING,
		"ErrorsReceived": dm_type.STRING,
		"UnicastPacketsSent": dm_type.STRING,
		"UnicastPacketsReceived": dm_type.STRING,
		"DiscardPacketsSent": dm_type.STRING,
		"DiscardPacketsReceived": dm_type.STRING,
		"MulticastPacketsSent": dm_type.STRING,
		"MulticastPacketsReceived": dm_type.STRING,
		"BroadcastPacketsSent": dm_type.STRING,
		"BroadcastPacketsReceived": dm_type.STRING,
		"UnknownProtoPacketsReceived": dm_type.STRING,
		"Reset()": { type: 'sync', input: [] }
	},
	defaults: {
		"BytesSent": "0",
		"BytesReceived": "0",
		"PacketsSent": "0",
		"PacketsReceived": "0",
		"ErrorsSent": "0",
		"ErrorsReceived": "0",
		"UnicastPacketsSent": "0",
		"UnicastPacketsReceived": "0",
		"DiscardPacketsSent": "0",
		"DiscardPacketsReceived": "0",
		"MulticastPacketsSent": "0",
		"MulticastPacketsReceived": "0",
		"BroadcastPacketsSent": "0",
		"BroadcastPacketsReceived": "0",
		"UnknownProtoPacketsReceived": "0"
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
		"PIN": { secured: true }
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
		"Password": { secured: true }
	}
};
