'use strict';

// Auto-generated schema definitions for NeighborDiscovery domain
// Generated from TR-181 specifications

// Schema for Device.NeighborDiscovery.
export const NeighborDiscovery = {
    path: "Device.NeighborDiscovery.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceSettingNumberOfEntries": "0"
    }
};

// Schema for Device.NeighborDiscovery.InterfaceSetting.{i}.
export const InterfaceSetting = {
    path: "Device.NeighborDiscovery.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "DADTransmits": dm_type.UINT | dm_type.WRITABLE,
        "RetransTimer": dm_type.UINT | dm_type.WRITABLE,
        "RtrSolicitationInterval": dm_type.UINT | dm_type.WRITABLE,
        "MaxRtrSolicitations": dm_type.UINT | dm_type.WRITABLE,
        "NUDEnable": dm_type.BOOL | dm_type.WRITABLE,
        "RSEnable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "DADTransmits": "1",
        "RetransTimer": "1000",
        "RtrSolicitationInterval": "4000",
        "MaxRtrSolicitations": "3"
    }
};
