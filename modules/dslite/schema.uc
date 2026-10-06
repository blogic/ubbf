'use strict';

// Auto-generated schema definitions for DSLite domain
// Generated from TR-181 specifications
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.DSLite.
schemas.DSLite = {
    path: "Device.DSLite.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "InterfaceSettingNumberOfEntries": "0"
    }
};

// Schema for Device.DSLite.InterfaceSetting.{i}.
schemas.InterfaceSetting = {
    path: "Device.DSLite.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "EndpointAssignmentPrecedence": dm_type.STRING | dm_type.WRITABLE,
        "EndpointAddressTypePrecedence": dm_type.STRING | dm_type.WRITABLE,
        "EndpointAddressInUse": dm_type.STRING,
        "EndpointName": dm_type.STRING | dm_type.WRITABLE,
        "EndpointAddress": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "TunnelInterface": dm_type.STRING,
        "TunneledInterface": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "",
        "Alias": "",
        "EndpointAssignmentPrecedence": "DHCPv6",
        "EndpointAddressTypePrecedence": "",
        "EndpointAddressInUse": "",
        "EndpointName": "",
        "EndpointAddress": "",
        "Origin": "",
        "TunnelInterface": "",
        "TunneledInterface": ""
    },
    constraints: {
        "EndpointAssignmentPrecedence": { enum: [ "DHCPv6", "Static" ] },
        "EndpointAddressTypePrecedence": { enum: [ "FQDN", "IPv6Address" ] },
        "EndpointName": { max_length: 256 },
        "EndpointAddress": { max_length: 45 }
    },
    addable: false
};
