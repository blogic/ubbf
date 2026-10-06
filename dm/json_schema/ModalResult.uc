'use strict';

// Auto-generated schema definitions for ModalResult domain
// Generated from TR-181 specifications

// Schema for ModalResult.{i}.
export const ModalResult = {
    path: "ModalResult.{i}.",
    schema: {
        "MaxIPLayerCapacity": dm_type.STRING,
        "TimeOfMax": dm_type.DATETIME,
        "MaxETHCapacityNoFCS": dm_type.STRING,
        "MaxETHCapacityWithFCS": dm_type.STRING,
        "MaxETHCapacityWithFCSVLAN": dm_type.STRING,
        "LossRatioAtMax": dm_type.STRING,
        "RTTRangeAtMax": dm_type.STRING,
        "PDVRangeAtMax": dm_type.STRING,
        "MinOnewayDelayAtMax": dm_type.STRING,
        "ReorderedRatioAtMax": dm_type.STRING,
        "ReplicatedRatioAtMax": dm_type.STRING,
        "InterfaceEthMbpsAtMax": dm_type.STRING
    },
    defaults: {}
};
