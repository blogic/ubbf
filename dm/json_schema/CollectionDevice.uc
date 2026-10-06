'use strict';

// Auto-generated schema definitions for CollectionDevice domain
// Generated from TR-181 specifications

// Schema for Device.CollectionDevice.{i}.
export const CollectionDevice = {
    path: "Device.CollectionDevice.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "IsNativeDevice": dm_type.BOOL,
        "DataElementsDeviceRef": dm_type.STRING,
        "IEEE1905DeviceRef": dm_type.STRING,
        "LLDPDeviceRef": dm_type.STRING,
        "UPnPDeviceRef": dm_type.STRING,
        "HostDeviceRef": dm_type.STRING,
        "GhnAssociatedDeviceRef": dm_type.STRING,
        "MoCAAssociatedDeviceRef": dm_type.STRING,
        "HomePlugAssociatedDeviceRef": dm_type.STRING,
        "HPNAAssociatedDeviceRef": dm_type.STRING,
        "UPAAssociatedDeviceRef": dm_type.STRING,
        "WiFiAssociatedDeviceRef": dm_type.STRING,
        "ZigBeeAssociatedDeviceRef": dm_type.STRING,
        "ThreadAssociatedNodeRef": dm_type.STRING,
        "ProxiedDeviceRef": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "DataElementsDeviceRef": "",
        "IEEE1905DeviceRef": "",
        "LLDPDeviceRef": "",
        "UPnPDeviceRef": "",
        "HostDeviceRef": "",
        "GhnAssociatedDeviceRef": "",
        "MoCAAssociatedDeviceRef": "",
        "HomePlugAssociatedDeviceRef": "",
        "HPNAAssociatedDeviceRef": "",
        "UPAAssociatedDeviceRef": "",
        "WiFiAssociatedDeviceRef": "",
        "ZigBeeAssociatedDeviceRef": "",
        "ThreadAssociatedNodeRef": "",
        "ProxiedDeviceRef": ""
    }
};
