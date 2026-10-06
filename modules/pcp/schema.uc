'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.PCP = {
    path: "Device.PCP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SupportedVersions": dm_type.STRING,
        "PreferredVersion": dm_type.UINT | dm_type.WRITABLE,
        "OptionList": dm_type.STRING,
        "ClientNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "SupportedVersions": "0,1,2",
        "PreferredVersion": "2",
        "OptionList": "1,3",
        "ClientNumberOfEntries": "0"
    },
    // libpcpnatpmp speaks NAT-PMP (0) and PCP 1 and 2
    constraints: {
        "PreferredVersion": { min: 0, max: 2 }
    }
};

schemas.Client = {
    path: "Device.PCP.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "WANInterface": dm_type.STRING,
        "Status": dm_type.STRING,
        "MAPEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PEEREnable": dm_type.BOOL | dm_type.WRITABLE,
        "THIRDPARTYEnable": dm_type.BOOL | dm_type.WRITABLE,
        "THIRDPARTYStatus": dm_type.STRING,
        "FILTEREnable": dm_type.BOOL | dm_type.WRITABLE,
        "ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "WANInterface": "",
        "Status": "Disabled",
        "MAPEnable": "false",
        "PEEREnable": "false",
        "THIRDPARTYEnable": "false",
        "THIRDPARTYStatus": "Disabled",
        "FILTEREnable": "false",
        "ServerNumberOfEntries": "0"
    }
};

schemas.Client_Server = {
    path: "Device.PCP.Client.{i}.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "ServerNameOrAddress": dm_type.STRING | dm_type.WRITABLE,
        "ServerAddressInUse": dm_type.STRING,
        "AdditionalServerAddresses": dm_type.STRING,
        "ExternalIPAddress": dm_type.STRING,
        "CurrentVersion": dm_type.UINT,
        "PreferredLifetime": dm_type.UINT | dm_type.WRITABLE,
        "Capabilities": dm_type.STRING,
        "InboundMappingNumberOfEntries": dm_type.UINT,
        "OutboundMappingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "true",
        "Status": "Disabled",
        "Alias": "",
        "Origin": "Static",
        "ServerNameOrAddress": "",
        "ServerAddressInUse": "",
        "AdditionalServerAddresses": "",
        "ExternalIPAddress": "",
        "CurrentVersion": "0",
        "PreferredLifetime": "0",
        "Capabilities": "",
        "InboundMappingNumberOfEntries": "0",
        "OutboundMappingNumberOfEntries": "0"
    },
    constraints: {
        "ServerNameOrAddress": { max_length: 256 }
    }
};

schemas.Server_InboundMapping = {
    path: "Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ErrorCode": dm_type.UINT,
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "Lifetime": dm_type.UINT | dm_type.WRITABLE,
        "SuggestedExternalIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "SuggestedExternalPort": dm_type.UINT | dm_type.WRITABLE,
        "InternalPort": dm_type.UINT | dm_type.WRITABLE,
        "ProtocolNumber": dm_type.INT | dm_type.WRITABLE,
        "ThirdPartyAddress": dm_type.STRING | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "AssignedExternalIPAddress": dm_type.STRING,
        "AssignedExternalPort": dm_type.UINT,
        "AssignedExternalPortEndRange": dm_type.UINT,
        "FilterNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "ErrorCode": "0",
        "Alias": "",
        "Origin": "Static",
        "Lifetime": "0",
        "SuggestedExternalIPAddress": "",
        "SuggestedExternalPort": "0",
        "InternalPort": "0",
        "ProtocolNumber": "0",
        "ThirdPartyAddress": "",
        "Description": "",
        "AssignedExternalIPAddress": "",
        "AssignedExternalPort": "0",
        "AssignedExternalPortEndRange": "0",
        "FilterNumberOfEntries": "0"
    },
    constraints: {
        "SuggestedExternalIPAddress": { max_length: 45 },
        "SuggestedExternalPort": { min: 0, max: 65535 },
        "InternalPort": { min: 1, max: 65535 },
        "ProtocolNumber": { min: -1, max: 255 },
        "ThirdPartyAddress": { max_length: 45 },
        "Description": { max_length: 256 }
    }
};

schemas.InboundMapping_Filter = {
    path: "Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.Filter.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "RemoteHostIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "PrefixLength": dm_type.UINT | dm_type.WRITABLE,
        "RemotePort": dm_type.UINT | dm_type.WRITABLE,
        "RemotePortEndRange": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "RemoteHostIPAddress": "",
        "PrefixLength": "128",
        "RemotePort": "0",
        "RemotePortEndRange": "0"
    },
    constraints: {
        "RemoteHostIPAddress": { max_length: 45 },
        "PrefixLength": { min: 1, max: 128 },
        "RemotePort": { min: 0, max: 65535 },
        "RemotePortEndRange": { min: 0, max: 65535 }
    }
};

schemas.Server_OutboundMapping = {
    path: "Device.PCP.Client.{i}.Server.{i}.OutboundMapping.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ErrorCode": dm_type.UINT,
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "Lifetime": dm_type.UINT | dm_type.WRITABLE,
        "SuggestedExternalIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "SuggestedExternalPort": dm_type.UINT | dm_type.WRITABLE,
        "RemoteHostIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "InternalPort": dm_type.UINT | dm_type.WRITABLE,
        "RemotePort": dm_type.UINT | dm_type.WRITABLE,
        "ProtocolNumber": dm_type.INT | dm_type.WRITABLE,
        "ThirdPartyAddress": dm_type.STRING | dm_type.WRITABLE,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "AssignedExternalIPAddress": dm_type.STRING,
        "AssignedExternalPort": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "ErrorCode": "0",
        "Alias": "",
        "Origin": "Static",
        "Lifetime": "0",
        "SuggestedExternalIPAddress": "",
        "SuggestedExternalPort": "0",
        "RemoteHostIPAddress": "",
        "InternalPort": "0",
        "RemotePort": "0",
        "ProtocolNumber": "0",
        "ThirdPartyAddress": "",
        "Description": "",
        "AssignedExternalIPAddress": "",
        "AssignedExternalPort": "0"
    },
    constraints: {
        "SuggestedExternalIPAddress": { max_length: 45 },
        "SuggestedExternalPort": { min: 0, max: 65535 },
        "RemoteHostIPAddress": { max_length: 45 },
        "InternalPort": { min: 1, max: 65535 },
        "RemotePort": { min: 1, max: 65535 },
        "ProtocolNumber": { min: -1, max: 255 },
        "ThirdPartyAddress": { max_length: 45 },
        "Description": { max_length: 256 }
    }
};
