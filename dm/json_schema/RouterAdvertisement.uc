'use strict';

// Auto-generated schema definitions for RouterAdvertisement domain
// Generated from TR-181 specifications

// Schema for Device.RouterAdvertisement.InterfaceSetting.{i}.Option.{i}.
export const InterfaceSetting_Option = {
    path: "Device.RouterAdvertisement.InterfaceSetting.{i}.Option.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Tag": "0"
    }
};

// Schema for Device.RouterAdvertisement.
export const RouterAdvertisement = {
    path: "Device.RouterAdvertisement.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceSettingNumberOfEntries": "0"
    }
};

// Schema for Device.RouterAdvertisement.InterfaceSetting.{i}.
export const InterfaceSetting = {
    path: "Device.RouterAdvertisement.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "RDNSSMode": dm_type.STRING | dm_type.WRITABLE,
        "RDNSS": dm_type.STRING | dm_type.WRITABLE,
        "DNSSL": dm_type.STRING | dm_type.WRITABLE,
        "ManualPrefixes": dm_type.STRING | dm_type.WRITABLE,
        "Prefixes": dm_type.STRING,
        "MaxRtrAdvInterval": dm_type.UINT | dm_type.WRITABLE,
        "MinRtrAdvInterval": dm_type.UINT | dm_type.WRITABLE,
        "AdvDefaultLifetime": dm_type.UINT | dm_type.WRITABLE,
        "AdvManagedFlag": dm_type.BOOL | dm_type.WRITABLE,
        "AdvOtherConfigFlag": dm_type.BOOL | dm_type.WRITABLE,
        "AdvMobileAgentFlag": dm_type.BOOL | dm_type.WRITABLE,
        "AdvPreferredRouterFlag": dm_type.STRING | dm_type.WRITABLE,
        "AdvNDProxyFlag": dm_type.BOOL | dm_type.WRITABLE,
        "AdvLinkMTU": dm_type.UINT | dm_type.WRITABLE,
        "AdvReachableTime": dm_type.UINT | dm_type.WRITABLE,
        "AdvRetransTimer": dm_type.UINT | dm_type.WRITABLE,
        "AdvCurHopLimit": dm_type.UINT | dm_type.WRITABLE,
        "AdvRDNSSLifetime": dm_type.UINT | dm_type.WRITABLE,
        "AdvDNSSLLifetime": dm_type.UINT | dm_type.WRITABLE,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": "",
        "RDNSSMode": "Static",
        "RDNSS": "[]",
        "DNSSL": "[]",
        "ManualPrefixes": "[]",
        "Prefixes": "",
        "MaxRtrAdvInterval": "600",
        "MinRtrAdvInterval": "200",
        "AdvDefaultLifetime": "1800",
        "AdvManagedFlag": "false",
        "AdvOtherConfigFlag": "false",
        "AdvMobileAgentFlag": "false",
        "AdvPreferredRouterFlag": "Medium",
        "AdvNDProxyFlag": "false",
        "AdvLinkMTU": "0",
        "AdvReachableTime": "0",
        "AdvRetransTimer": "0",
        "AdvCurHopLimit": "0",
        "AdvRDNSSLifetime": "0",
        "AdvDNSSLLifetime": "0",
        "OptionNumberOfEntries": "0"
    }
};
