'use strict';

// Auto-generated schema definitions for IPv6rd domain
// Generated from TR-181 specifications

// Schema for Device.IPv6rd.InterfaceSetting.{i}.
export const InterfaceSetting = {
    path: "Device.IPv6rd.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "BorderRelayIPv4Addresses": dm_type.STRING | dm_type.WRITABLE,
        "AllTrafficToBorderRelay": dm_type.BOOL | dm_type.WRITABLE,
        "SPIPv6Prefix": dm_type.STRING | dm_type.WRITABLE,
        "IPv4MaskLength": dm_type.UINT | dm_type.WRITABLE,
        "AddressSource": dm_type.STRING | dm_type.WRITABLE,
        "TunnelInterface": dm_type.STRING,
        "TunneledInterface": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "BorderRelayIPv4Addresses": "",
        "SPIPv6Prefix": "",
        "IPv4MaskLength": "0",
        "AddressSource": "",
        "TunnelInterface": "",
        "TunneledInterface": ""
    }
};

// Schema for Device.IPv6rd.
export const IPv6rd = {
    path: "Device.IPv6rd.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceSettingNumberOfEntries": "0"
    }
};
