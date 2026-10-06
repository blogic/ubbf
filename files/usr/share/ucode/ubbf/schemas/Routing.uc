'use strict';

export const Routing = {
	path: "Device.Routing.",
	schema: {
		"RouterNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"RouterNumberOfEntries": "0"
	}
};

export const Router = {
	path: "Device.Routing.Router.{i}.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"Alias": dm_type.STRING | dm_type.WRITABLE,
		"IPv4ForwardingNumberOfEntries": dm_type.UINT,
		"IPv6ForwardingNumberOfEntries": dm_type.UINT
	},
	defaults: {
		"Enable": "true",
		"Status": "Enabled",
		"Alias": "",
		"IPv4ForwardingNumberOfEntries": "0",
		"IPv6ForwardingNumberOfEntries": "0"
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
		"ForwardingMetric": dm_type.INT | dm_type.WRITABLE
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
		"ForwardingMetric": "-1"
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
		"ExpirationTime": dm_type.DATETIME
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
		"ExpirationTime": "9999-12-31T23:59:59Z"
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
	}
};
