'use strict';

// Auto-generated schema definitions for LEDs domain
// Generated from TR-181 specifications

// Schema for Device.LEDs.LED.{i}.CurrentCycleElement.
export const LED_CurrentCycleElement = {
    path: "Device.LEDs.LED.{i}.CurrentCycleElement.",
    schema: {
        "CycleElementReference": dm_type.STRING,
        "Color": dm_type.HEXBIN,
        "Duration": dm_type.UINT
    },
    defaults: {
        "CycleElementReference": "",
        "Duration": "0"
    }
};

// Schema for Device.LEDs.LED.{i}.
export const LED = {
    path: "Device.LEDs.LED.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Reason": dm_type.STRING,
        "CyclePeriodRepetitions": dm_type.INT,
        "Location": dm_type.STRING,
        "RelativeXPosition": dm_type.UINT,
        "RelativeYPosition": dm_type.UINT,
        "MaxBrightness": dm_type.UINT,
        "CycleElementNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Status": "",
        "Reason": "",
        "CyclePeriodRepetitions": "0",
        "Location": "",
        "RelativeXPosition": "0",
        "RelativeYPosition": "0",
        "MaxBrightness": "0",
        "CycleElementNumberOfEntries": "0"
    }
};

// Schema for Device.LEDs.
export const LEDs = {
    path: "Device.LEDs.",
    schema: {
        "LEDNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LEDNumberOfEntries": "0"
    }
};

// Schema for Device.LEDs.LED.{i}.CycleElement.{i}.
export const LED_CycleElement = {
    path: "Device.LEDs.LED.{i}.CycleElement.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Color": dm_type.HEXBIN | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE,
        "FadeInterval": dm_type.UINT | dm_type.WRITABLE,
        "Brightness": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Order": "0",
        "Duration": "0",
        "FadeInterval": "0",
        "Brightness": "0"
    }
};
