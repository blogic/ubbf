'use strict';

// Schema definitions for the Device.IEEE8021x domain.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.IEEE8021x.
schemas.IEEE8021x = {
    path: "Device.IEEE8021x.",
    schema: {
        "SupplicantNumberOfEntries": dm_type.UINT,
        "X_UBBF_AuthenticatorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupplicantNumberOfEntries": "0",
        "X_UBBF_AuthenticatorNumberOfEntries": "0"
    }
};

// Schema for Device.IEEE8021x.X_UBBF_Authenticator.{i}., a wired 802.1x
// authenticator on a port, which TR-181 does not model. The names follow
// the hostapd options. Alias keeps its TR-181 name, which the core and the
// USP unique key handling use.
schemas.X_UBBF_Authenticator = {
    path: "Device.IEEE8021x.X_UBBF_Authenticator.{i}.",
    schema: {
        "enable": dm_type.BOOL | dm_type.WRITABLE,
        "status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "interface": dm_type.STRING | dm_type.WRITABLE,
        "auth_server_addr": dm_type.STRING | dm_type.WRITABLE,
        "auth_server_port": dm_type.UINT | dm_type.WRITABLE,
        "auth_server_shared_secret": dm_type.STRING | dm_type.WRITABLE,
        "acct_server_addr": dm_type.STRING | dm_type.WRITABLE,
        "acct_server_port": dm_type.UINT | dm_type.WRITABLE,
        "acct_server_shared_secret": dm_type.STRING | dm_type.WRITABLE,
        "nas_identifier": dm_type.STRING | dm_type.WRITABLE,
        "eap_reauth_period": dm_type.UINT | dm_type.WRITABLE,
        "client_number_of_entries": dm_type.UINT
    },
    defaults: {
        "enable": "false",
        "status": "Disabled",
        "Alias": "",
        "interface": "",
        "auth_server_addr": "",
        "auth_server_port": "1812",
        "auth_server_shared_secret": "",
        "acct_server_addr": "",
        "acct_server_port": "1813",
        "acct_server_shared_secret": "",
        "nas_identifier": "",
        "eap_reauth_period": "3600",
        "client_number_of_entries": "0"
    },
    constraints: {
        "status": { enum: [ "Disabled", "Enabled", "Error_Misconfigured", "Error" ] },
        "Alias": { max_length: 64 },
        "interface": { max_length: 256 },
        "auth_server_addr": { max_length: 45 },
        "auth_server_port": { min: 1, max: 65535 },
        "auth_server_shared_secret": { secured: true, max_length: 256 },
        "acct_server_addr": { max_length: 45 },
        "acct_server_port": { min: 1, max: 65535 },
        "acct_server_shared_secret": { secured: true, max_length: 256 },
        "nas_identifier": { max_length: 253 }
    }
};

// Schema for Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}., the
// stations that hostapd knows on the port.
schemas.X_UBBF_Authenticator_client = {
    path: "Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}.",
    schema: {
        "mac_address": dm_type.STRING,
        "authorized": dm_type.BOOL
    },
    defaults: {
        "mac_address": "",
        "authorized": "false"
    },
    constraints: {
        "mac_address": { max_length: 17 }
    },
    addable: false
};

// Schema for Device.IEEE8021x.Supplicant.{i}.
// TR-181 gives no defaults for the four timers; these are the IEEE
// 802.1X-2004 values (9.5.1), which wpa_supplicant also uses.
schemas.Supplicant = {
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
        "AuthenticationSuccessPolicy": dm_type.STRING | dm_type.WRITABLE,
        "Reset()": { type: 'sync', input: [] },
        "Disconnect()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "PAEState": "Disconnected",
        "EAPIdentity": "",
        "MaxStart": "3",
        "StartPeriod": "30",
        "HeldPeriod": "60",
        "AuthPeriod": "30",
        "AuthenticationCapabilities": "",
        "StartFailurePolicy": "AssumeAuthentication",
        "AuthenticationSuccessPolicy": "NoAction"
    },
    constraints: {
        "Status": { enum: [ "Disabled", "Enabled", "Error_Misconfigured", "Error" ] },
        "Alias": { max_length: 64 },
        "Interface": { max_length: 256 },
        "PAEState": { enum: [ "Disconnected", "Logoff", "Connecting", "Authenticating", "Authenticated", "Held", "Restart", "ForceAuth", "ForceUnauth" ] },
        "EAPIdentity": { max_length: 256 },
        "MaxStart": { min: 1, max: 10 },
        "StartPeriod": { min: 1 },
        "HeldPeriod": { min: 1 },
        "AuthenticationCapabilities": { list: true, enum: [ "EAP-TLS", "EAP-MD5" ] },
        "StartFailurePolicy": { enum: [ "FailAuthentication", "AssumeAuthentication" ] },
        "AuthenticationSuccessPolicy": { enum: [ "NoAction", "RenewConnection" ] }
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.Stats.
schemas.Supplicant_Stats = {
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
        "SuccessCount": dm_type.UINT,
        "FailureCount": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
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
        "SuccessCount": "0",
        "FailureCount": "0"
    },
    constraints: {
        "LastFrameSourceMACAddress": { max_length: 17 }
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.EAPMD5.
schemas.Supplicant_EAPMD5 = {
    path: "Device.IEEE8021x.Supplicant.{i}.EAPMD5.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SharedSecret": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "SharedSecret": ""
    },
    constraints: {
        "SharedSecret": { secured: true, max_length: 256 }
    }
};

// Schema for Device.IEEE8021x.Supplicant.{i}.EAPTLS.
schemas.Supplicant_EAPTLS = {
    path: "Device.IEEE8021x.Supplicant.{i}.EAPTLS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MutualAuthenticationEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "MutualAuthenticationEnable": "false",
        "Certificate": "",
        "CABundle": ""
    }
};
