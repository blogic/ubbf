'use strict';

// Auto-generated schema definitions for NetworkConfig domain
// Generated from TR-181 specifications

// Schema for NetworkConfig.
export const NetworkConfig = {
    path: "NetworkConfig.",
    schema: {
        "AccessInterfaces": dm_type.STRING
    },
    defaults: {
        "AccessInterfaces": ""
    }
};

// Schema for NetworkConfig.PortMapping.{i}.
export const PortMapping = {
    path: "NetworkConfig.PortMapping.{i}.",
    schema: {
        "Interface": dm_type.STRING,
        "ExternalPort": dm_type.UINT,
        "InternalPort": dm_type.UINT,
        "Protocol": dm_type.STRING
    },
    defaults: {
        "Interface": "",
        "ExternalPort": "0",
        "InternalPort": "0",
        "Protocol": ""
    }
};
