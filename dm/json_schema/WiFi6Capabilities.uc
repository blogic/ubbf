'use strict';

// Auto-generated schema definitions for WiFi6Capabilities domain
// Generated from TR-181 specifications

// Schema for WiFi6Capabilities.
export const WiFi6Capabilities = {
    path: "WiFi6Capabilities.",
    schema: {
        "HE160": dm_type.BOOL,
        "HE8080": dm_type.BOOL,
        "MCSNSS": dm_type.BASE64,
        "SUBeamformer": dm_type.BOOL,
        "SUBeamformee": dm_type.BOOL,
        "MUBeamformer": dm_type.BOOL,
        "Beamformee80orLess": dm_type.BOOL,
        "BeamformeeAbove80": dm_type.BOOL,
        "ULMUMIMO": dm_type.BOOL,
        "ULOFDMA": dm_type.BOOL,
        "DLOFDMA": dm_type.BOOL,
        "MaxDLMUMIMO": dm_type.UINT,
        "MaxULMUMIMO": dm_type.UINT,
        "MaxDLOFDMA": dm_type.UINT,
        "MaxULOFDMA": dm_type.UINT,
        "RTS": dm_type.BOOL,
        "MURTS": dm_type.BOOL,
        "MultiBSSID": dm_type.BOOL,
        "MUEDCA": dm_type.BOOL,
        "TWTRequestor": dm_type.BOOL,
        "TWTResponder": dm_type.BOOL,
        "SpatialReuse": dm_type.BOOL,
        "AnticipatedChannelUsage": dm_type.BOOL
    },
    defaults: {
        "MaxDLMUMIMO": "0",
        "MaxULMUMIMO": "0",
        "MaxDLOFDMA": "0",
        "MaxULOFDMA": "0"
    }
};
