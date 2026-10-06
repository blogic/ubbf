'use strict';

// Auto-generated schema definitions for RouteHops domain
// Generated from TR-181 specifications

// Schema for RouteHops.{i}.
export const RouteHops = {
    path: "RouteHops.{i}.",
    schema: {
        "Host": dm_type.STRING,
        "HostAddress": dm_type.STRING,
        "ErrorCode": dm_type.UINT,
        "RTTimes": dm_type.UINT
    },
    defaults: {
        "Host": "",
        "HostAddress": "",
        "ErrorCode": "0",
        "RTTimes": "0"
    }
};
