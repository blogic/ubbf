'use strict';

// Schema definitions for the Schedules domain, from TR-181 2.18
// (dm/json_schema/Schedules.uc).
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.Schedules.
schemas.Schedules = {
    path: "Device.Schedules.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ScheduleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "true",
        "ScheduleNumberOfEntries": "0"
    }
};

// Schema for Device.Schedules.Schedule.{i}.
schemas.Schedule = {
    path: "Device.Schedules.Schedule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Day": dm_type.STRING | dm_type.WRITABLE,
        "StartTime": dm_type.STRING | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE,
        "InverseMode": dm_type.BOOL | dm_type.WRITABLE,
        "TimeLeft": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Status": "Inactive",
        "Description": "",
        "Day": "",
        "StartTime": "",
        "Duration": "0",
        "InverseMode": "false",
        "TimeLeft": "0"
    },
    constraints: {
        "Status": { enum: [ "Active", "Inactive", "StackDisabled", "Error" ] },
        "Description": { max_length: 256 },
        "Day": { list: true, enum: [ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ] },
        "StartTime": { max_length: 5 },
        "Duration": { min: 1 }
    }
};
