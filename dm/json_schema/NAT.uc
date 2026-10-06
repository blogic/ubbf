'use strict';

// Auto-generated schema definitions for NAT domain
// Generated from TR-181 specifications

// Schema for Device.NAT.PortTrigger.{i}.
export const PortTrigger = {
    path: "Device.NAT.PortTrigger.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Origin": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "PortEndRange": dm_type.UINT | dm_type.WRITABLE,
        "AutoDisableDuration": dm_type.UINT | dm_type.WRITABLE,
        "ActivationDate": dm_type.DATETIME,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleRef": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE,
        "RuleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Origin": "Controller",
        "Description": "",
        "Interface": "",
        "Port": "0",
        "PortEndRange": "0",
        "AutoDisableDuration": "0",
        "ActivationDate": "0001-01-01T00:00:00Z",
        "Protocol": "",
        "ScheduleRef": "[]",
        "Log": "false",
        "LogRef": "[]",
        "RuleNumberOfEntries": "0"
    }
};

// Schema for Device.NAT.InterfaceSetting.{i}.
export const InterfaceSetting = {
    path: "Device.NAT.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "SourceNetwork": dm_type.STRING | dm_type.WRITABLE,
        "TCPTranslationTimeout": dm_type.INT | dm_type.WRITABLE,
        "UDPTranslationTimeout": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "SourceNetwork": "[]",
        "TCPTranslationTimeout": "300",
        "UDPTranslationTimeout": "30"
    }
};

// Schema for Device.NAT.PortTrigger.{i}.Rule.{i}.
export const PortTrigger_Rule = {
    path: "Device.NAT.PortTrigger.{i}.Rule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "PortEndRange": dm_type.UINT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Port": "0",
        "PortEndRange": "0",
        "Protocol": ""
    }
};

// Schema for Device.NAT.
export const NAT = {
    path: "Device.NAT.",
    schema: {
        "InterfaceSettingNumberOfEntries": dm_type.UINT,
        "PortMappingNumberOfEntries": dm_type.UINT,
        "MaxNumberOfPortMappings": dm_type.UINT,
        "PortTriggerNumberOfEntries": dm_type.UINT,
        "MaxNumberOfPortTriggers": dm_type.UINT
    },
    defaults: {
        "InterfaceSettingNumberOfEntries": "0",
        "PortMappingNumberOfEntries": "0",
        "MaxNumberOfPortMappings": "0",
        "PortTriggerNumberOfEntries": "0",
        "MaxNumberOfPortTriggers": "0"
    }
};

// Schema for Device.NAT.PortMapping.{i}.
export const PortMapping = {
    path: "Device.NAT.PortMapping.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Origin": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "AllInterfaces": dm_type.BOOL | dm_type.WRITABLE,
        "LeaseDuration": dm_type.UINT | dm_type.WRITABLE,
        "RemainingLeaseTime": dm_type.UINT,
        "RemoteHost": dm_type.STRING | dm_type.WRITABLE,
        "ExternalPort": dm_type.UINT | dm_type.WRITABLE,
        "ExternalPortEndRange": dm_type.UINT | dm_type.WRITABLE,
        "InternalPort": dm_type.UINT | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "InternalClient": dm_type.STRING | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleRef": dm_type.STRING | dm_type.WRITABLE,
        "Log": dm_type.BOOL | dm_type.WRITABLE,
        "LogRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Origin": "Controller",
        "Alias": "",
        "Interface": "",
        "AllInterfaces": "false",
        "LeaseDuration": "0",
        "RemainingLeaseTime": "0",
        "RemoteHost": "",
        "ExternalPort": "0",
        "ExternalPortEndRange": "0",
        "InternalPort": "0",
        "Protocol": "",
        "InternalClient": "",
        "Description": "",
        "ScheduleRef": "[]",
        "Log": "false",
        "LogRef": "[]"
    }
};
