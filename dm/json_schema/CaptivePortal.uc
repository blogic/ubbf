'use strict';

// Auto-generated schema definitions for CaptivePortal domain
// Generated from TR-181 specifications

// Schema for Device.CaptivePortal.
export const CaptivePortal = {
    path: "Device.CaptivePortal.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "AllowedList": dm_type.STRING | dm_type.WRITABLE,
        "URL": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "AllowedList": "",
        "URL": ""
    }
};
