'use strict';

// Auto-generated schema definitions for Users domain
// Generated from TR-181 specifications

// Schema for Device.Users.SupportedShell.{i}.
export const SupportedShell = {
    path: "Device.Users.SupportedShell.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Name": ""
    }
};

// Schema for Device.Users.Group.{i}.
export const Group = {
    path: "Device.Users.Group.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "GroupID": dm_type.UINT | dm_type.WRITABLE,
        "Groupname": dm_type.STRING | dm_type.WRITABLE,
        "RoleParticipation": dm_type.STRING | dm_type.WRITABLE,
        "StaticGroup": dm_type.BOOL
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "GroupID": "0",
        "Groupname": "",
        "RoleParticipation": "[]",
        "StaticGroup": "false"
    }
};

// Schema for Device.Users.Role.{i}.
export const Role = {
    path: "Device.Users.Role.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "RoleID": dm_type.UINT | dm_type.WRITABLE,
        "RoleName": dm_type.STRING | dm_type.WRITABLE,
        "StaticRole": dm_type.BOOL,
        "RequiredCapabilities": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "RoleID": "0",
        "RoleName": "",
        "StaticRole": "false",
        "RequiredCapabilities": ""
    }
};

// Schema for Device.Users.User.{i}.
export const User = {
    path: "Device.Users.User.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "UserID": dm_type.UINT | dm_type.WRITABLE,
        "RemoteAccessCapable": dm_type.BOOL | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "GroupParticipation": dm_type.STRING | dm_type.WRITABLE,
        "RoleParticipation": dm_type.STRING | dm_type.WRITABLE,
        "StaticUser": dm_type.BOOL,
        "Language": dm_type.STRING | dm_type.WRITABLE,
        "Shell": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "UserID": "0",
        "RemoteAccessCapable": "false",
        "Username": "",
        "Password": "",
        "GroupParticipation": "[]",
        "RoleParticipation": "[]",
        "StaticUser": "false",
        "Language": "",
        "Shell": ""
    }
};

// Schema for Device.Users.
export const Users = {
    path: "Device.Users.",
    schema: {
        "UserNumberOfEntries": dm_type.UINT,
        "GroupNumberOfEntries": dm_type.UINT,
        "RoleNumberOfEntries": dm_type.UINT,
        "SupportedShellNumberOfEntries": dm_type.UINT,
        "SupportedCapabilities": dm_type.STRING
    },
    defaults: {
        "UserNumberOfEntries": "0",
        "GroupNumberOfEntries": "0",
        "RoleNumberOfEntries": "0",
        "SupportedShellNumberOfEntries": "0",
        "SupportedCapabilities": ""
    }
};
