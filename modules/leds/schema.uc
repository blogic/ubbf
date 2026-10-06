'use strict';

// Auto-generated schema definitions for LEDs domain
// Generated from TR-181 specifications
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.LEDs.LED.{i}.CurrentCycleElement.
schemas.LED_CurrentCycleElement = {
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
schemas.LED = {
    path: "Device.LEDs.LED.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        // Read-only, although TR-181 allows writes: Name links the
        // stored row to its LED in /sys/class/leds.
        "Name": dm_type.STRING,
        "Status": dm_type.STRING,
        "Reason": dm_type.STRING,
        "CyclePeriodRepetitions": dm_type.INT,
        "Location": dm_type.STRING,
        "RelativeXPosition": dm_type.UINT,
        "RelativeYPosition": dm_type.UINT,
        "MaxBrightness": dm_type.UINT,
        "CycleElementNumberOfEntries": dm_type.UINT,
        "ControllingPeripheral": dm_type.STRING
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
        "CycleElementNumberOfEntries": "0",
        "ControllingPeripheral": ""
    },
    since: {
        "ControllingPeripheral": "2.21"
    },
    addable: false
};

// Schema for Device.LEDs.
schemas.LEDs = {
    path: "Device.LEDs.",
    schema: {
        "LEDNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "LEDNumberOfEntries": "0"
    }
};

// Schema for Device.LEDs.LED.{i}.CycleElement.{i}.
schemas.LED_CycleElement = {
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
    },
    constraints: {
        "Order": { min: 1 },
        "Brightness": { min: 0, max: 100 },
        "Color": { min_length: 3, max_length: 3 }
    }
};
