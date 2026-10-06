'use strict';

// Auto-generated schema definitions for UnixDomainSockets domain
// Generated from TR-181 specifications

// Schema for Device.UnixDomainSockets.UnixDomainSocket.{i}.
export const UnixDomainSocket = {
    path: "Device.UnixDomainSockets.UnixDomainSocket.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Mode": dm_type.STRING,
        "Path": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Mode": "",
        "Path": ""
    }
};

// Schema for Device.UnixDomainSockets.
export const UnixDomainSockets = {
    path: "Device.UnixDomainSockets.",
    schema: {
        "UnixDomainSocketNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "UnixDomainSocketNumberOfEntries": "0"
    }
};
