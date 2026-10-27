'use strict';

// Schema definitions for Device.Hardware, from TR-181 2.21
// (dm/json_spec/2.21.0/Device.Hardware.*). The model entries in handler.uc
// carry the version tags: CPUs from 2.20, Buttons from 2.21.
// PowerManagement.Standby is not supported: no board has a deep sleep.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.Hardware.
schemas.Hardware = {
    path: "Device.Hardware.",
    schema: {},
    defaults: {}
};

// Schema for Device.Hardware.CPUs.
schemas.CPUs = {
    path: "Device.Hardware.CPUs.",
    schema: {
        "CPUNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CPUNumberOfEntries": "0"
    }
};

// Schema for Device.Hardware.CPUs.CPU.{i}.
schemas.CPU = {
    path: "Device.Hardware.CPUs.CPU.{i}.",
    schema: {
        "Alias": dm_type.STRING
    },
    defaults: {
        "Alias": ""
    },
    addable: false
};

// Schema for Device.Hardware.CPUs.CPU.{i}.DVFS.
schemas.DVFS = {
    path: "Device.Hardware.CPUs.CPU.{i}.DVFS.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Supported": dm_type.BOOL,
        "CurrentFrequency": dm_type.UINT,
        "MinFrequency": dm_type.UINT,
        "MaxFrequency": dm_type.UINT,
        "ScalingMinFrequency": dm_type.UINT | dm_type.WRITABLE,
        "ScalingMaxFrequency": dm_type.UINT | dm_type.WRITABLE,
        "ScalingAvailableFrequencies": dm_type.STRING,
        "ScalingGovernor": dm_type.STRING | dm_type.WRITABLE,
        "ScalingAvailableGovernors": dm_type.STRING
    },
    defaults: {
        "Enable": "true",
        "Status": "Unsupported",
        "Supported": "false",
        "CurrentFrequency": "0",
        "MinFrequency": "0",
        "MaxFrequency": "0",
        "ScalingMinFrequency": "0",
        "ScalingMaxFrequency": "0",
        "ScalingAvailableFrequencies": "",
        "ScalingGovernor": "",
        "ScalingAvailableGovernors": ""
    },
    constraints: {
        "Status": { enum: [ "Disabled", "Enabled", "Unsupported" ] },
        "ScalingAvailableFrequencies": { list: true },
        "ScalingAvailableGovernors": { list: true, enum: [ "conservative", "userspace", "powersave", "ondemand", "performance", "schedutil" ] }
    }
};

// Schema for Device.Hardware.Buttons.
schemas.Buttons = {
    path: "Device.Hardware.Buttons.",
    schema: {
        "ButtonNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ButtonNumberOfEntries": "0"
    }
};

// Schema for Device.Hardware.Buttons.Button.{i}. Label and Location are not
// supported: the gpio-keys nodes of the device tree carry no position, and
// the label is left out with it.
schemas.Button = {
    path: "Device.Hardware.Buttons.Button.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        // "Label": dm_type.STRING,
        "Status": dm_type.STRING,
        // "Location": dm_type.STRING,
        "InputFile": dm_type.STRING,
        "TriggerConditionNumberOfEntries": dm_type.UINT,
        "Push()": {
            type: 'async',
            input: ['Duration'],
            output: []
        },
        "Release()": {
            type: 'async',
            input: ['Duration'],
            output: []
        }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Status": "Released",
        "InputFile": "",
        "TriggerConditionNumberOfEntries": "0"
    },
    constraints: {
        "Status": { enum: [ "Pressed", "Released", "Error_Misconfigured" ] },
        "InputFile": { max_length: 2048 }
    },
    addable: false
};

// Schema for Device.Hardware.Buttons.Button.{i}.TriggerCondition.{i}.
schemas.TriggerCondition = {
    path: "Device.Hardware.Buttons.Button.{i}.TriggerCondition.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "Min": dm_type.UINT | dm_type.WRITABLE,
        "Max": dm_type.UINT | dm_type.WRITABLE,
        "Timeout": dm_type.UINT | dm_type.WRITABLE,
        "Active": dm_type.BOOL,
        "ActiveTime": dm_type.UINT | dm_type.WRITABLE,
        "Triggered!": {
            type: 'event',
            input: ['Name', 'ButtonName', 'Type', 'Interval']
        }
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Name": "",
        "Type": "Pressed",
        "Min": "0",
        "Max": "0",
        "Timeout": "0",
        "Active": "false",
        "ActiveTime": "0"
    },
    constraints: {
        "Type": { enum: [ "Pressed", "Released", "LongPressed" ] }
    }
};
