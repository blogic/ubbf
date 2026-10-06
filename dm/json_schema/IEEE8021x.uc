'use strict';

// Auto-generated schema definitions for IEEE8021x domain
// Generated from TR-181 specifications

// Schema for Device.IEEE8021x.
export const IEEE8021x = {
    path: "Device.IEEE8021x.",
    schema: {
        "SupplicantNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupplicantNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.
export const Supplicant = {
    path: "Device.IEEE8021x.Supplicant.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "PAEState": dm_type.STRING,
        "EAPIdentity": dm_type.STRING | dm_type.WRITABLE,
        "MaxStart": dm_type.UINT | dm_type.WRITABLE,
        "StartPeriod": dm_type.UINT | dm_type.WRITABLE,
        "HeldPeriod": dm_type.UINT | dm_type.WRITABLE,
        "AuthPeriod": dm_type.UINT | dm_type.WRITABLE,
        "AuthenticationCapabilities": dm_type.STRING,
        "StartFailurePolicy": dm_type.STRING | dm_type.WRITABLE,
        "AuthenticationSuccessPolicy": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "PAEState": "",
        "EAPIdentity": "",
        "MaxStart": "0",
        "StartPeriod": "0",
        "HeldPeriod": "0",
        "AuthPeriod": "0",
        "AuthenticationCapabilities": "",
        "StartFailurePolicy": "",
        "AuthenticationSuccessPolicy": ""
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.EAPTLS.
export const Supplicant_EAPTLS = {
    path: "Device.IEEE8021x.Supplicant.{i}.EAPTLS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MutualAuthenticationEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Certificate": "",
        "CABundle": ""
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.Stats.
export const Supplicant_Stats = {
    path: "Device.IEEE8021x.Supplicant.{i}.Stats.",
    schema: {
        "ReceivedFrames": dm_type.UINT,
        "TransmittedFrames": dm_type.UINT,
        "TransmittedStartFrames": dm_type.UINT,
        "TransmittedLogoffFrames": dm_type.UINT,
        "TransmittedResponseIdFrames": dm_type.UINT,
        "TransmittedResponseFrames": dm_type.UINT,
        "ReceivedRequestIdFrames": dm_type.UINT,
        "ReceivedRequestFrames": dm_type.UINT,
        "ReceivedInvalidFrames": dm_type.UINT,
        "ReceivedLengthErrorFrames": dm_type.UINT,
        "LastFrameVersion": dm_type.UINT,
        "LastFrameSourceMACAddress": dm_type.STRING,
        "SuccessCount": dm_type.STRING,
        "FailureCount": dm_type.STRING
    },
    defaults: {
        "ReceivedFrames": "0",
        "TransmittedFrames": "0",
        "TransmittedStartFrames": "0",
        "TransmittedLogoffFrames": "0",
        "TransmittedResponseIdFrames": "0",
        "TransmittedResponseFrames": "0",
        "ReceivedRequestIdFrames": "0",
        "ReceivedRequestFrames": "0",
        "ReceivedInvalidFrames": "0",
        "ReceivedLengthErrorFrames": "0",
        "LastFrameVersion": "0",
        "LastFrameSourceMACAddress": "",
        "SuccessCount": "",
        "FailureCount": ""
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.EAPMD5.
export const Supplicant_EAPMD5 = {
    path: "Device.IEEE8021x.Supplicant.{i}.EAPMD5.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SharedSecret": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "SharedSecret": ""
    }
};
