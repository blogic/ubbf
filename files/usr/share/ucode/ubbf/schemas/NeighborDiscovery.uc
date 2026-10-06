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
    },
    constraints: {
        "RetransTimer": { min: 1 },
        "RtrSolicitationInterval": { min: 4000 }
    }
};

// Schema for Device.NeighborDiscovery.InterfaceSetting.{i}.ARP.
export const InterfaceSetting_ARP = {
    path: "Device.NeighborDiscovery.InterfaceSetting.{i}.ARP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "BaseReachableTime": dm_type.UINT | dm_type.WRITABLE,
        "MaxRetries": dm_type.UINT | dm_type.WRITABLE,
        "RetryInterval": dm_type.UINT | dm_type.WRITABLE,
        "ProxyARPEnable": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "Status": "Disabled",
        "BaseReachableTime": "60000",
        "MaxRetries": "3",
        "RetryInterval": "1000",
        "ProxyARPEnable": "false"
    }
};

// Schema for Device.NeighborDiscovery.InterfaceSetting.{i}.NDP.
export const InterfaceSetting_NDP = {
    path: "Device.NeighborDiscovery.InterfaceSetting.{i}.NDP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "DADTransmits": dm_type.UINT | dm_type.WRITABLE,
        "RetransTimer": dm_type.UINT | dm_type.WRITABLE,
        "BaseReachableTime": dm_type.UINT | dm_type.WRITABLE,
        "RtrSolicitationInterval": dm_type.UINT | dm_type.WRITABLE,
        "MaxRtrSolicitationInterval": dm_type.UINT | dm_type.WRITABLE,
        "UnlimitedMaxRtrSolicitations": dm_type.BOOL | dm_type.WRITABLE,
        "MaxRtrSolicitations": dm_type.UINT | dm_type.WRITABLE,
        "NUDEnable": dm_type.BOOL | dm_type.WRITABLE,
        "RSEnable": dm_type.BOOL | dm_type.WRITABLE,
        "MaxRtrSolicitationDelay": dm_type.UINT | dm_type.WRITABLE,
        "MaxRtrSolicitationDuration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "Status": "Disabled",
        "DADTransmits": "1",
        "RetransTimer": "1000",
        "BaseReachableTime": "30000",
        "RtrSolicitationInterval": "4000",
        "MaxRtrSolicitationInterval": "600000",
        "UnlimitedMaxRtrSolicitations": "false",
        "MaxRtrSolicitations": "3",
        "NUDEnable": "true",
        "RSEnable": "true",
        "MaxRtrSolicitationDelay": "1000",
        "MaxRtrSolicitationDuration": "0"
    },
    constraints: {
        "MaxRtrSolicitationInterval": { min: 1 }
    }
};
