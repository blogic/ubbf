'use strict';

// Auto-generated schema definitions for Result domain
// Generated from TR-181 specifications

// Schema for Result.{i}.
export const Result = {
    path: "Result.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "AnswerType": dm_type.STRING,
        "HostNameReturned": dm_type.STRING,
        "IPAddresses": dm_type.STRING,
        "DNSServerIP": dm_type.STRING,
        "ResponseTime": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "AnswerType": "",
        "HostNameReturned": "",
        "IPAddresses": "",
        "DNSServerIP": "",
        "ResponseTime": "0"
    }
};
