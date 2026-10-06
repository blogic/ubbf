'use strict';

export const Routing = {
	path: "Device.Routing.",
	schema: {
		"RouterNumberOfEntries": dm_type.UINT,
		"PolicyNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"RouterNumberOfEntries": "0",
		"PolicyNumberOfEntries": "0"
	},
	since: {
		"PolicyNumberOfEntries": "2.20"
	}
};

export const Router = {
	path: "Device.Routing.Router.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"ID": dm_type.UINT,
		"Name": dm_type.STRING | dm_type.WRITABLE,
		"IPv4ForwardingNumberOfEntries": dm_type.UINT,
		"IPv6ForwardingNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "true",
		"Status": "Enabled",
		"Alias": "",
		"ID": "0",
		"Name": "",
		"IPv4ForwardingNumberOfEntries": "0",
		"IPv6ForwardingNumberOfEntries": "0"
	},
	since: {
		"ID": "2.20",
		"Name": "2.20"
	},
	constraints: {
		"Alias": { max_length: 64 },
		"Name": { max_length: 256 }
	}
};

export const Policy = {
	path: "Device.Routing.Policy.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"RouterRef": dm_type.STRING | dm_type.WRITABLE,
		"Priority": dm_type.UINT | dm_type.WRITABLE,
		"IPVersion": dm_type.INT | dm_type.WRITABLE,
		"Protocol": dm_type.INT | dm_type.WRITABLE,
		"SourceInterface": dm_type.STRING | dm_type.WRITABLE,
		"DestInterface": dm_type.STRING | dm_type.WRITABLE,
		"SourceIPPrefix": dm_type.STRING | dm_type.WRITABLE,
		"DestIPPrefix": dm_type.STRING | dm_type.WRITABLE,
		"SourcePort": dm_type.INT | dm_type.WRITABLE,
		"SourcePortRangeMax": dm_type.INT | dm_type.WRITABLE,
		"DestPort": dm_type.INT | dm_type.WRITABLE,
		"DestPortRangeMax": dm_type.INT | dm_type.WRITABLE,
		"ForwardingPolicy": dm_type.INT | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Alias": "",
		"Status": "Disabled",
		"RouterRef": "",
		"Priority": "0",
		"IPVersion": "-1",
		"Protocol": "-1",
		"SourceInterface": "",
		"DestInterface": "",
		"SourceIPPrefix": "",
		"DestIPPrefix": "",
		"SourcePort": "-1",
		"SourcePortRangeMax": "-1",
		"DestPort": "-1",
		"DestPortRangeMax": "-1",
		"ForwardingPolicy": "-1"
	},
	constraints: {
		"Alias": { max_length: 64 },
		"RouterRef": { max_length: 256 },
		"IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] },
		"Protocol": { min: -1, max: 255 },
		"SourceInterface": { max_length: 256 },
		"DestInterface": { max_length: 256 },
		"SourceIPPrefix": { max_length: 49 },
		"DestIPPrefix": { max_length: 49 },
		"SourcePort": { min: -1, max: 65535 },
		"SourcePortRangeMax": { min: -1, max: 65535 },
		"DestPort": { min: -1, max: 65535 },
		"DestPortRangeMax": { min: -1, max: 65535 },
		"ForwardingPolicy": { min: -1 }
	}
};

export const Router_IPv4Forwarding = {
	path: "Device.Routing.Router.{i}.IPv4Forwarding.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"StaticRoute": dm_type.BOOL,
		"DestIPAddress": dm_type.STRING | dm_type.WRITABLE,
		"DestSubnetMask": dm_type.STRING | dm_type.WRITABLE,
		"ForwardingPolicy": dm_type.INT | dm_type.WRITABLE,
		"GatewayIPAddress": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"Origin": dm_type.STRING,
		"ForwardingMetric": dm_type.INT | dm_type.WRITABLE,
		"MTU": dm_type.UINT | dm_type.WRITABLE,
		"SourceIPAddress": dm_type.STRING | dm_type.WRITABLE,
		"SourceSubnetMask": dm_type.STRING | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Status": "Disabled",
		"Alias": "",
		"StaticRoute": "true",
		"DestIPAddress": "",
		"DestSubnetMask": "",
		"ForwardingPolicy": "-1",
		"GatewayIPAddress": "",
		"Interface": "",
		"Origin": "Static",
		"ForwardingMetric": "-1",
		"MTU": "-1",
		"SourceIPAddress": "",
		"SourceSubnetMask": ""
	},
	since: {
		"MTU": "2.20",
		"SourceIPAddress": "2.20",
		"SourceSubnetMask": "2.20"
	},
	constraints: {
		"MTU": { ranges: [ [ -1, -1 ], [ 576, null ] ] },
		"SourceIPAddress": { max_length: 15 },
		"SourceSubnetMask": { max_length: 15 },
		"Alias": { max_length: 64 },
		"DestIPAddress": { max_length: 15 },
		"DestSubnetMask": { max_length: 15 },
		"ForwardingPolicy": { min: -1 },
		"GatewayIPAddress": { max_length: 15 },
		"Interface": { max_length: 256 },
		"ForwardingMetric": { min: -1 }
	}
};

export const Router_IPv6Forwarding = {
	path: "Device.Routing.Router.{i}.IPv6Forwarding.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"DestIPPrefix": dm_type.STRING | dm_type.WRITABLE,
		"ForwardingPolicy": dm_type.INT | dm_type.WRITABLE,
		"NextHop": dm_type.STRING | dm_type.WRITABLE,
		"Interface": dm_type.STRING | dm_type.WRITABLE,
		"Origin": dm_type.STRING,
		"ForwardingMetric": dm_type.INT | dm_type.WRITABLE,
		"ExpirationTime": dm_type.DATETIME,
		"SourceIPPrefix": dm_type.STRING | dm_type.WRITABLE,
		"MTU": dm_type.UINT | dm_type.WRITABLE
	},
	defaults: {
		"Enable": "false",
		"Status": "Disabled",
		"Alias": "",
		"DestIPPrefix": "",
		"ForwardingPolicy": "-1",
		"NextHop": "",
		"Interface": "",
		"Origin": "Static",
		"ForwardingMetric": "-1",
		"ExpirationTime": "9999-12-31T23:59:59Z",
		"SourceIPPrefix": "",
		"MTU": "-1"
	},
	since: {
		"SourceIPPrefix": "2.20",
		"MTU": "2.20"
	},
	constraints: {
		"SourceIPPrefix": { max_length: 49 },
		"MTU": { ranges: [ [ -1, -1 ], [ 1280, null ] ] },
		"Alias": { max_length: 64 },
		"DestIPPrefix": { max_length: 49 },
		"ForwardingPolicy": { min: -1 },
		"NextHop": { max_length: 45 },
		"Interface": { max_length: 256 },
		"ForwardingMetric": { min: -1 }
	}
};

export const RouteInformation = {
	path: "Device.Routing.RouteInformation.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"InterfaceSettingNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "true",
		"InterfaceSettingNumberOfEntries": "0"
	}
};

export const RouteInformation_InterfaceSetting = {
	path: "Device.Routing.RouteInformation.InterfaceSetting.{i}.",
	schema: {
		"Status": dm_type.STRING,
		"Interface": dm_type.STRING,
		"SourceRouter": dm_type.STRING,
		"RouteLifetime": dm_type.DATETIME
	},
	defaults: {
		"Status": "",
		"Interface": "",
		"SourceRouter": "",
		"RouteLifetime": ""
	},
	addable: false
};
