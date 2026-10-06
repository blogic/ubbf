'use strict';

// Auto-generated schema definitions for Schedules domain
// Generated from TR-181 specifications

// Schema for Device.Schedules.
export const Schedules = {
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
export const Schedule = {
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
        "Status": "",
        "Description": "",
        "Day": "",
        "StartTime": "",
        "Duration": "0",
        "InverseMode": "false",
        "TimeLeft": "0"
    }
};
