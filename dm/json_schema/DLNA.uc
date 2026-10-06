'use strict';

// Auto-generated schema definitions for DLNA domain
// Generated from TR-181 specifications

// Schema for Device.DLNA.Capabilities.
export const Capabilities = {
    path: "Device.DLNA.Capabilities.",
    schema: {
        "HNDDeviceClass": dm_type.STRING,
        "DeviceCapability": dm_type.STRING,
        "HIDDeviceClass": dm_type.STRING,
        "ImageClassProfileID": dm_type.STRING,
        "AudioClassProfileID": dm_type.STRING,
        "AVClassProfileID": dm_type.STRING,
        "MediaCollectionProfileID": dm_type.STRING,
        "PrinterClassProfileID": dm_type.STRING
    },
    defaults: {
        "HNDDeviceClass": "",
        "DeviceCapability": "",
        "HIDDeviceClass": "",
        "ImageClassProfileID": "",
        "AudioClassProfileID": "",
        "AVClassProfileID": "",
        "MediaCollectionProfileID": "",
        "PrinterClassProfileID": ""
    }
};
