'use strict';

// Auto-generated schema definitions for ControllerTrust domain
// Generated from TR-181 specifications

// Schema for ControllerTrust.Credential.{i}.
export const Credential = {
    path: "ControllerTrust.Credential.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Role": dm_type.STRING | dm_type.WRITABLE,
        "Credential": dm_type.STRING | dm_type.WRITABLE,
        "AllowedUses": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Role": "",
        "Credential": "",
        "AllowedUses": ""
    }
};

// Schema for ControllerTrust.Challenge.{i}.
export const Challenge = {
    path: "ControllerTrust.Challenge.{i}.",
    schema: {
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Role": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.BASE64 | dm_type.WRITABLE,
        "ValueType": dm_type.STRING | dm_type.WRITABLE,
        "Instruction": dm_type.BASE64 | dm_type.WRITABLE,
        "InstructionType": dm_type.STRING | dm_type.WRITABLE,
        "Retries": dm_type.UINT | dm_type.WRITABLE,
        "LockoutPeriod": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Description": "",
        "Role": "",
        "Enable": "false",
        "Type": "",
        "ValueType": "",
        "InstructionType": "",
        "Retries": "0",
        "LockoutPeriod": "30"
    }
};

// Schema for ControllerTrust.Role.{i}.Permission.{i}.
export const Role_Permission = {
    path: "ControllerTrust.Role.{i}.Permission.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Targets": dm_type.STRING | dm_type.WRITABLE,
        "Param": dm_type.STRING | dm_type.WRITABLE,
        "Obj": dm_type.STRING | dm_type.WRITABLE,
        "InstantiatedObj": dm_type.STRING | dm_type.WRITABLE,
        "CommandEvent": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Order": "0",
        "Targets": "[]",
        "Param": "----",
        "Obj": "----",
        "InstantiatedObj": "----",
        "CommandEvent": "----"
    }
};

// Schema for ControllerTrust.
export const ControllerTrust = {
    path: "ControllerTrust.",
    schema: {
        "UntrustedRole": dm_type.STRING | dm_type.WRITABLE,
        "BannedRole": dm_type.STRING | dm_type.WRITABLE,
        "SecuredRoles": dm_type.STRING | dm_type.WRITABLE,
        "TOFUAllowed": dm_type.BOOL | dm_type.WRITABLE,
        "TOFUInactivityTimer": dm_type.UINT | dm_type.WRITABLE,
        "RoleNumberOfEntries": dm_type.UINT,
        "CredentialNumberOfEntries": dm_type.UINT,
        "ChallengeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "UntrustedRole": "",
        "BannedRole": "",
        "SecuredRoles": "",
        "TOFUInactivityTimer": "0",
        "RoleNumberOfEntries": "0",
        "CredentialNumberOfEntries": "0",
        "ChallengeNumberOfEntries": "0"
    }
};

// Schema for ControllerTrust.Role.{i}.
export const Role = {
    path: "ControllerTrust.Role.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "PermissionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Name": "",
        "PermissionNumberOfEntries": "0"
    }
};
