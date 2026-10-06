'use strict';

// Auto-generated schema definitions for Resources domain
// Generated from TR-181 specifications

// Schema for Resources.
export const Resources = {
    path: "Resources.",
    schema: {
        "AllocatedDiskSpace": dm_type.INT,
        "AllocatedMemory": dm_type.INT,
        "AllocatedCPUPercent": dm_type.INT
    },
    defaults: {
        "AllocatedDiskSpace": "0",
        "AllocatedMemory": "0",
        "AllocatedCPUPercent": "0"
    }
};
