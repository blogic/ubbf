'use strict';

import { KEY_TYPES, MIN_RSA_BITS } from 'ubbf.utils.ssh_keys';

// Auto-generated schema definitions for SSH domain
// Generated from TR-181 specifications

// Schema for Device.SSH.Server.{i}.Stats.
export const Server_Stats = {
    path: "Device.SSH.Server.{i}.Stats.",
    schema: {
        "NumberOfFailedAttempts": dm_type.UINT,
        "NumberOfFailedAttemptsSinceActivation": dm_type.UINT,
        "NumberOfSuccessfulAttempts": dm_type.UINT,
        "NumberOfSuccessfulAttemptsSinceActivation": dm_type.UINT
    },
    defaults: {
        "NumberOfFailedAttempts": "0",
        "NumberOfFailedAttemptsSinceActivation": "0",
        "NumberOfSuccessfulAttempts": "0",
        "NumberOfSuccessfulAttemptsSinceActivation": "0"
    }
};

// Schema for Device.SSH.
export const SSH = {
    path: "Device.SSH.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ServerNumberOfEntries": dm_type.UINT,
        "AuthorizedKeyNumberOfEntries": dm_type.UINT,
        "X_UBBF_PubkeyAcceptedKeyTypes": dm_type.STRING | dm_type.WRITABLE,
        "X_UBBF_MinRSAKeyBits": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "ServerNumberOfEntries": "0",
        "AuthorizedKeyNumberOfEntries": "0",
        "X_UBBF_PubkeyAcceptedKeyTypes": join(",", KEY_TYPES),
        "X_UBBF_MinRSAKeyBits": sprintf("%d", MIN_RSA_BITS)
    },
    constraints: {
        "X_UBBF_PubkeyAcceptedKeyTypes": { list: true, enum: KEY_TYPES },
        "X_UBBF_MinRSAKeyBits": { min: 1024, max: 16384 }
    }
};

// Schema for Device.SSH.Server.{i}.Session.{i}.
export const Server_Session = {
    path: "Device.SSH.Server.{i}.Session.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "User": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "Port": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "User": "",
        "IPAddress": "",
        "Port": "0"
    }
};

// Schema for Device.SSH.Server.{i}.AccessLog.{i}.
export const Server_AccessLog = {
    path: "Device.SSH.Server.{i}.AccessLog.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "User": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "Port": dm_type.UINT,
        "Status": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "User": "",
        "IPAddress": "",
        "Port": "0",
        "Status": ""
    }
};

// Schema for Device.SSH.Server.{i}.
export const Server = {
    path: "Device.SSH.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "IdleTimeout": dm_type.UINT | dm_type.WRITABLE,
        "KeepAlive": dm_type.UINT | dm_type.WRITABLE,
        "AllowRootLogin": dm_type.BOOL | dm_type.WRITABLE,
        "AllowPasswordLogin": dm_type.BOOL | dm_type.WRITABLE,
        "AllowRootPasswordLogin": dm_type.BOOL | dm_type.WRITABLE,
        "MaxAuthTries": dm_type.UINT | dm_type.WRITABLE
//        "AllowAllIPv4": dm_type.BOOL | dm_type.WRITABLE,
//        "IPv4AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
//        "AllowAllIPv6": dm_type.BOOL | dm_type.WRITABLE,
//        "IPv6AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
//        "ActivationDate": dm_type.DATETIME,
//        "AutoDisableDuration": dm_type.UINT | dm_type.WRITABLE,
//        "PID": dm_type.UINT,
//        "UserGroupAccess": dm_type.STRING | dm_type.WRITABLE,
//        "SessionNumberOfEntries": dm_type.UINT,
//        "MaxAccessLogEntries": dm_type.INT | dm_type.WRITABLE,
//        "AccessLogNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Interface": "",
        "Port": "22",
        "IdleTimeout": "180",
        "KeepAlive": "300",
        "AllowRootLogin": "false",
        "AllowPasswordLogin": "false",
        "AllowRootPasswordLogin": "false",
        "MaxAuthTries": "3"
    }
};

// Schema for Device.SSH.AuthorizedKey.{i}.
export const AuthorizedKey = {
    path: "Device.SSH.AuthorizedKey.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "User": dm_type.STRING | dm_type.WRITABLE,
        "Key": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "User": "",
        "Key": ""
    }
};

// Schema for Device.SSH.X_UBBF_BlockList.
// Vendor extension: tracks SSH failed-auth events received from dropbear via
// the bbf-device auth-event ubus method, and installs offending IPs into the
// inet ubbf-sshguard nft blocklist set once FailCount reaches Threshold. Bans
// are permanent for the kernel's lifetime; only Reset() or a reboot clears them.
export const X_UBBF_BlockList = {
    path: "Device.SSH.X_UBBF_BlockList.",
    schema: {
        "Threshold": dm_type.UINT | dm_type.WRITABLE,
        "EntryNumberOfEntries": dm_type.UINT,
        "Reset()": {
            type: 'sync',
            input: [],
            output: []
        }
    },
    defaults: {
        "Threshold": "3",
        "EntryNumberOfEntries": "0"
    }
};

// Schema for Device.SSH.X_UBBF_BlockList.Entry.{i}.
// Per-IP failure record. Read-only mirror of /tmp/ubbf/ip-block-list.json
// maintained by ubbf-device. ACS can only observe; to clear use Reset().
export const X_UBBF_BlockList_Entry = {
    path: "Device.SSH.X_UBBF_BlockList.Entry.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "FailCount": dm_type.UINT,
        "Blocked": dm_type.BOOL
    },
    defaults: {
        "Alias": "",
        "IPAddress": "",
        "FailCount": "0",
        "Blocked": "false"
    }
};
