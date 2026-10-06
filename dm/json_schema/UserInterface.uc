'use strict';

// Auto-generated schema definitions for UserInterface domain
// Generated from TR-181 specifications

// Schema for Device.UserInterface.RemoteAccess.
export const RemoteAccess = {
    path: "Device.UserInterface.RemoteAccess.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "SupportedProtocols": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Port": "0",
        "SupportedProtocols": "",
        "Protocol": ""
    }
};

// Schema for Device.UserInterface.Messages.
export const Messages = {
    path: "Device.UserInterface.Messages.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Title": dm_type.STRING | dm_type.WRITABLE,
        "SubTitle": dm_type.STRING | dm_type.WRITABLE,
        "Text": dm_type.STRING | dm_type.WRITABLE,
        "IconType": dm_type.STRING | dm_type.WRITABLE,
        "MessageColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "BackgroundColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "TitleColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "SubTitleColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "RequestedNumberOfRepetitions": dm_type.UINT | dm_type.WRITABLE,
        "ExecutedNumberOfRepetitions": dm_type.UINT
    },
    defaults: {
        "Enable": "true",
        "Title": "",
        "SubTitle": "",
        "Text": "",
        "IconType": "",
        "RequestedNumberOfRepetitions": "0",
        "ExecutedNumberOfRepetitions": "0"
    }
};

// Schema for Device.UserInterface.HTTPAccess.{i}.Session.{i}.
export const HTTPAccess_Session = {
    path: "Device.UserInterface.HTTPAccess.{i}.Session.{i}.",
    schema: {
        "SessionID": dm_type.STRING,
        "User": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "Port": dm_type.UINT,
        "Protocol": dm_type.STRING,
        "StartDate": dm_type.DATETIME
    },
    defaults: {
        "SessionID": "",
        "User": "",
        "IPAddress": "",
        "Port": "0",
        "Protocol": ""
    }
};

// Schema for Device.UserInterface.LocalDisplay.
export const LocalDisplay = {
    path: "Device.UserInterface.LocalDisplay.",
    schema: {
        "Movable": dm_type.BOOL | dm_type.WRITABLE,
        "Resizable": dm_type.BOOL | dm_type.WRITABLE,
        "PosX": dm_type.INT | dm_type.WRITABLE,
        "PosY": dm_type.INT | dm_type.WRITABLE,
        "Width": dm_type.UINT | dm_type.WRITABLE,
        "Height": dm_type.UINT | dm_type.WRITABLE,
        "DisplayWidth": dm_type.UINT,
        "DisplayHeight": dm_type.UINT
    },
    defaults: {
        "PosX": "0",
        "PosY": "0",
        "Width": "0",
        "Height": "0",
        "DisplayWidth": "0",
        "DisplayHeight": "0"
    }
};

// Schema for Device.UserInterface.HTTPAccess.{i}.
export const HTTPAccess = {
    path: "Device.UserInterface.HTTPAccess.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "AccessType": dm_type.STRING | dm_type.WRITABLE,
        "AllowedRoles": dm_type.STRING | dm_type.WRITABLE,
        "Certificate": dm_type.STRING | dm_type.WRITABLE,
        "CABundle": dm_type.STRING | dm_type.WRITABLE,
        "CACertificate": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "AllowedHosts": dm_type.STRING | dm_type.WRITABLE,
        "AllowedPathPrefixes": dm_type.STRING | dm_type.WRITABLE,
        "AllowAllIPv4": dm_type.BOOL | dm_type.WRITABLE,
        "IPv4AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
        "AllowAllIPv6": dm_type.BOOL | dm_type.WRITABLE,
        "IPv6AllowedSourcePrefix": dm_type.STRING | dm_type.WRITABLE,
        "AutoDisableDuration": dm_type.UINT | dm_type.WRITABLE,
        "TimeLeft": dm_type.UINT,
        "ActivationDate": dm_type.DATETIME,
        "SessionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Order": "",
        "Status": "",
        "AccessType": "LocalAccess",
        "AllowedRoles": "[]",
        "Certificate": "",
        "CABundle": "",
        "CACertificate": "",
        "Interface": "",
        "Port": "443",
        "Protocol": "",
        "AllowedHosts": "",
        "AllowedPathPrefixes": "[/]",
        "AllowAllIPv4": "false",
        "IPv4AllowedSourcePrefix": "",
        "AllowAllIPv6": "false",
        "IPv6AllowedSourcePrefix": "",
        "AutoDisableDuration": "0",
        "TimeLeft": "0",
        "SessionNumberOfEntries": "0"
    }
};

// Schema for Device.UserInterface.
export const UserInterface = {
    path: "Device.UserInterface.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "PasswordRequired": dm_type.BOOL | dm_type.WRITABLE,
        "PasswordUserSelectable": dm_type.BOOL | dm_type.WRITABLE,
        "UpgradeAvailable": dm_type.BOOL | dm_type.WRITABLE,
        "WarrantyDate": dm_type.DATETIME | dm_type.WRITABLE,
        "ISPName": dm_type.STRING | dm_type.WRITABLE,
        "ISPHelpDesk": dm_type.STRING | dm_type.WRITABLE,
        "ISPHomePage": dm_type.STRING | dm_type.WRITABLE,
        "ISPHelpPage": dm_type.STRING | dm_type.WRITABLE,
        "ISPLogo": dm_type.BASE64 | dm_type.WRITABLE,
        "ISPLogoSize": dm_type.UINT | dm_type.WRITABLE,
        "ISPMailServer": dm_type.STRING | dm_type.WRITABLE,
        "ISPNewsServer": dm_type.STRING | dm_type.WRITABLE,
        "TextColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "BackgroundColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "ButtonColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "ButtonTextColor": dm_type.HEXBIN | dm_type.WRITABLE,
        "AutoUpdateServer": dm_type.STRING | dm_type.WRITABLE,
        "UserUpdateServer": dm_type.STRING | dm_type.WRITABLE,
        "AvailableLanguages": dm_type.STRING,
        "CurrentLanguage": dm_type.STRING | dm_type.WRITABLE,
        "HTTPAccessSupportedProtocols": dm_type.STRING,
        "HTTPAccessNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "true",
        "ISPName": "",
        "ISPHelpDesk": "",
        "ISPHomePage": "",
        "ISPHelpPage": "",
        "ISPLogoSize": "0",
        "ISPMailServer": "",
        "ISPNewsServer": "",
        "AutoUpdateServer": "",
        "UserUpdateServer": "",
        "AvailableLanguages": "",
        "CurrentLanguage": "",
        "HTTPAccessSupportedProtocols": "",
        "HTTPAccessNumberOfEntries": "0"
    }
};
