'use strict';

// Auto-generated schema definitions for TrustedElements domain
// Generated from TR-181 specifications

// Schema for Device.TrustedElements.
export const TrustedElements = {
    path: "Device.TrustedElements.",
    schema: {
        "SIMNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SIMNumberOfEntries": "0"
    }
};

// Schema for Device.TrustedElements.SIM.{i}.Profile.{i}.
export const SIM_Profile = {
    path: "Device.TrustedElements.SIM.{i}.Profile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "IMSI": dm_type.STRING,
        "ICCID": dm_type.STRING,
        "State": dm_type.STRING,
        "Class": dm_type.STRING,
        "GID1": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "IMSI": "",
        "ICCID": "",
        "State": "",
        "Class": "",
        "GID1": ""
    }
};

// Schema for Device.TrustedElements.SIM.{i}.
export const SIM = {
    path: "Device.TrustedElements.SIM.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Status": dm_type.STRING | dm_type.WRITABLE,
        "IMSI": dm_type.STRING,
        "ICCID": dm_type.STRING,
        "MSISDN": dm_type.STRING,
        "SMSC": dm_type.STRING | dm_type.WRITABLE,
        "EID": dm_type.STRING,
        "ProfileNumberOfEntries": dm_type.UINT,
        "ESIMProfileAddStatus": dm_type.STRING,
        "ESIMClassEnabledProfile": dm_type.STRING,
        "ESIMTestMode": dm_type.BOOL,
        "Type": dm_type.STRING,
        "GID1": dm_type.STRING,
        "Usage": dm_type.STRING,
        "PINCheck": dm_type.STRING | dm_type.WRITABLE,
        "PIN": dm_type.STRING | dm_type.WRITABLE,
        "ProtectionScheme": dm_type.UINT,
        "HomeNetworkPublicKeyID": dm_type.UINT,
        "RoutingIndicator": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "IMSI": "",
        "ICCID": "",
        "MSISDN": "",
        "SMSC": "",
        "EID": "",
        "ProfileNumberOfEntries": "0",
        "ESIMProfileAddStatus": "",
        "ESIMClassEnabledProfile": "",
        "Type": "",
        "GID1": "",
        "Usage": "",
        "PINCheck": "",
        "PIN": "",
        "ProtectionScheme": "0",
        "HomeNetworkPublicKeyID": "0",
        "RoutingIndicator": "0"
    }
};
