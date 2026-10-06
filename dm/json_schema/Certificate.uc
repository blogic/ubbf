'use strict';

// Auto-generated schema definitions for Certificate domain
// Generated from TR-181 specifications

// Schema for Certificate.{i}.
export const Certificate = {
    path: "Certificate.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SerialNumber": dm_type.STRING,
        "Issuer": dm_type.STRING
    },
    defaults: {
        "SerialNumber": "",
        "Issuer": ""
    }
};
