'use strict';

// Vendor extensions for Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.
export const Device_Radio_X_UBBF = {
	schema: {
		"X_UBBF_OnboardProtocol": dm_type.STRING
	},
	defaults: {
		"X_UBBF_OnboardProtocol": ""
	}
};

// Schema for Device.IP.Interface.{i}.X_UBBF_DNSProbe.
export const Interface_X_UBBF_DNSProbe = {
	path: "Device.IP.Interface.{i}.X_UBBF_DNSProbe.",
	schema: {
		"Enable": dm_type.BOOL | dm_type.WRITABLE,
		"Host": dm_type.STRING | dm_type.WRITABLE,
		"Interval": dm_type.UINT | dm_type.WRITABLE,
		"Timeout": dm_type.UINT | dm_type.WRITABLE,
		"FailThreshold": dm_type.UINT | dm_type.WRITABLE,
		"Cooldown": dm_type.UINT | dm_type.WRITABLE,
		"Family": dm_type.STRING | dm_type.WRITABLE,
		"Status": dm_type.STRING,
		"ConsecutiveFailures": dm_type.UINT,
		"LastTriggerTime": dm_type.DATETIME
	},
	defaults: {
		"Enable": "false",
		"Host": "",
		"Interval": "60",
		"Timeout": "5",
		"FailThreshold": "3",
		"Cooldown": "300",
		"Family": "IPv4",
		"Status": "Disabled",
		"ConsecutiveFailures": "0",
		"LastTriggerTime": "0001-01-01T00:00:00Z"
	}
};
