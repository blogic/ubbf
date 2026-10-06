'use strict';

// Auto-generated schema definitions for GatewayInfo domain
// Generated from TR-181 specifications

// Schema for Device.GatewayInfo.
export const GatewayInfo = {
    path: "Device.GatewayInfo.",
    schema: {
        "ManagementProtocol": dm_type.STRING,
        "EndpointID": dm_type.STRING,
        "MACAddress": dm_type.STRING,
        "ManufacturerOUI": dm_type.STRING,
        "ProductClass": dm_type.STRING,
        "SerialNumber": dm_type.STRING
    },
    defaults: {
        "ManagementProtocol": "",
        "EndpointID": "",
        "MACAddress": "",
        "ManufacturerOUI": "",
        "ProductClass": "",
        "SerialNumber": ""
    }
};
