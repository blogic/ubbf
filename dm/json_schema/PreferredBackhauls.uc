'use strict';

// Auto-generated schema definitions for PreferredBackhauls domain
// Generated from TR-181 specifications

// Schema for PreferredBackhauls.{i}.
export const PreferredBackhauls = {
    path: "PreferredBackhauls.{i}.",
    schema: {
        "BackhaulMACAddress": dm_type.STRING,
        "bSTAMACAddress": dm_type.STRING
    },
    defaults: {
        "BackhaulMACAddress": "",
        "bSTAMACAddress": ""
    }
};
