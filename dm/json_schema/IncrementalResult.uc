'use strict';

// Auto-generated schema definitions for IncrementalResult domain
// Generated from TR-181 specifications

// Schema for IncrementalResult.{i}.
export const IncrementalResult = {
    path: "IncrementalResult.{i}.",
    schema: {
        "IPLayerCapacity": dm_type.STRING,
        "TimeOfSubInterval": dm_type.DATETIME,
        "LossRatio": dm_type.STRING,
        "RTTRange": dm_type.STRING,
        "PDVRange": dm_type.STRING,
        "MinOnewayDelay": dm_type.STRING,
        "ReorderedRatio": dm_type.STRING,
        "ReplicatedRatio": dm_type.STRING,
        "InterfaceEthMbps": dm_type.STRING
    },
    defaults: {}
};
