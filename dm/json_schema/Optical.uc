'use strict';

// Auto-generated schema definitions for Optical domain
// Generated from TR-181 specifications

// Schema for Device.Optical.Interface.{i}.Stats.
export const Interface_Stats = {
    path: "Device.Optical.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": ""
    }
};

// Schema for Device.Optical.Interface.{i}.
export const Interface = {
    path: "Device.Optical.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.INT | dm_type.WRITABLE,
        "SFPReferenceList": dm_type.STRING,
        "OpticalSignalLevel": dm_type.STRING,
        "LowerOpticalThreshold": dm_type.STRING,
        "UpperOpticalThreshold": dm_type.STRING,
        "TransmitOpticalLevel": dm_type.STRING,
        "LowerTransmitPowerThreshold": dm_type.STRING,
        "UpperTransmitPowerThreshold": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "SFPReferenceList": "",
        "OpticalSignalLevel": "",
        "LowerOpticalThreshold": "",
        "UpperOpticalThreshold": "",
        "TransmitOpticalLevel": "",
        "LowerTransmitPowerThreshold": "",
        "UpperTransmitPowerThreshold": ""
    }
};

// Schema for Device.Optical.
export const Optical = {
    path: "Device.Optical.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};
