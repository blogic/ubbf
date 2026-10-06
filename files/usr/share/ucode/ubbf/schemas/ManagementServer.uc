'use strict';

// Hand-written schema for the ManagementServer domain (CWMP-only object).
// No generator source exists: the TR-181 USP-flavour XML under dm/spec/
// defines Device.CWMPManagementServer with zero parameters, so this file
// is curated against TR-069 v1.6.1 and dm/tr181.csv rows 846-860.

// Schema for Device.ManagementServer.
export const ManagementServer = {
    path: "Device.ManagementServer.",
    schema: {
	"EnableCWMP": dm_type.BOOL | dm_type.WRITABLE,
	"URL": dm_type.STRING | dm_type.WRITABLE,
	"Username": dm_type.STRING | dm_type.WRITABLE,
	"Password": dm_type.STRING | dm_type.WRITABLE,
	"PeriodicInformEnable": dm_type.BOOL | dm_type.WRITABLE,
	"PeriodicInformInterval": dm_type.UINT | dm_type.WRITABLE,
	"PeriodicInformTime": dm_type.DATETIME | dm_type.WRITABLE,
	"ParameterKey": dm_type.STRING,
	"ConnectionRequestURL": dm_type.STRING,
	"ConnectionRequestUsername": dm_type.STRING | dm_type.WRITABLE,
	"ConnectionRequestPassword": dm_type.STRING | dm_type.WRITABLE,
	"UpgradesManaged": dm_type.BOOL | dm_type.WRITABLE,
	"CWMPRetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
	"CWMPRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
	"AliasBasedAddressing": dm_type.BOOL,
	// Both only mean anything to a CPE that offers alias-based
	// addressing, and AliasBasedAddressing reads false here. Writable
	// they would accept a value nothing could act on, so they are
	// read-only and an ACS gets 9008 rather than a silent success.
	"InstanceMode": dm_type.STRING,
	"AutoCreateInstances": dm_type.BOOL,
	"InstanceWildcardsSupported": dm_type.BOOL,
	"X_UBBF_LastSuccessfulSession": dm_type.DATETIME,
	"X_UBBF_InformWatchdogTime": dm_type.STRING | dm_type.WRITABLE,
	"X_UBBF_TLSMinVersion": dm_type.STRING | dm_type.WRITABLE,
	"X_UBBF_TLSCipherList": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
	"EnableCWMP": "true",
	"URL": "",
	"Username": "",
	"Password": "",
	"PeriodicInformEnable": "true",
	"PeriodicInformInterval": "300",
	"PeriodicInformTime": "0001-01-01T00:00:00Z",
	"ParameterKey": "",
	"ConnectionRequestURL": "",
	"ConnectionRequestUsername": "",
	"ConnectionRequestPassword": "",
	"UpgradesManaged": "false",
	"CWMPRetryMinimumWaitInterval": "5",
	"CWMPRetryIntervalMultiplier": "2000",
	"AliasBasedAddressing": "false",
	"InstanceMode": "InstanceNumber",
	"AutoCreateInstances": "false",
	"InstanceWildcardsSupported": "false",
	"X_UBBF_LastSuccessfulSession": "0001-01-01T00:00:00Z",
	"X_UBBF_InformWatchdogTime": "",
	"X_UBBF_TLSMinVersion": "1.2",
	"X_UBBF_TLSCipherList": ""
    },
    // ManagementServer is absent from the USP-flavour spec under dm/spec/,
    // so the generator emits nothing for it and these are stated here.
    constraints: {
	"PeriodicInformInterval": { min: 1, max: 4294967295 },
	"CWMPRetryMinimumWaitInterval": { min: 1, max: 65535 },
	// 3.2.1.1 states k in thousandths, so 1000 is a multiplier of 1.0
	// and anything below it would shorten the wait on every retry.
	"CWMPRetryIntervalMultiplier": { min: 1000, max: 65535 },
	"X_UBBF_InformWatchdogTime": { lengths: [ [ 0, 0 ], [ 5, 5 ] ] },
	"X_UBBF_TLSMinVersion": { enum: [ "1.2", "1.3" ] },
	// cwmpd's buffer for the list
	"X_UBBF_TLSCipherList": { max_length: 511 }
    }
};
