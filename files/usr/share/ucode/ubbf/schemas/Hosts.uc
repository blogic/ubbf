'use strict';

// Auto-generated schema definitions for Hosts domain
// Generated from TR-181 specifications

// Schema for Device.Hosts.AccessControl.{i}.Schedule.{i}.
export const AccessControl_Schedule = {
    path: "Device.Hosts.AccessControl.{i}.Schedule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Day": dm_type.STRING | dm_type.WRITABLE,
        "StartTime": dm_type.STRING | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Day": "",
        "StartTime": "",
        "Duration": "0"
    },
    constraints: {
        "Day": { list: true, enum: [ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ] },
        "StartTime": { max_length: 5 },
        "Duration": { min: 1 }
    }
};

// Schema for Device.Hosts.AccessControl.{i}.
export const AccessControl = {
    path: "Device.Hosts.AccessControl.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "PhysAddress": dm_type.STRING | dm_type.WRITABLE,
        "PhysAddressMask": dm_type.STRING | dm_type.WRITABLE,
        "HostName": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "AccessPolicy": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleRef": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Origin": "Controller",
        "PhysAddress": "",
        "PhysAddressMask": "",
        "HostName": "",
        "Enable": "false",
        "AccessPolicy": "Allow",
        "ScheduleRef": "",
        "ScheduleNumberOfEntries": "0"
    },
    until: {
        "ScheduleNumberOfEntries": "2.21"
    },
    constraints: {
        "PhysAddress": { max_length: 64 },
        "PhysAddressMask": { max_length: 64 },
        "HostName": { max_length: 256 },
        "AccessPolicy": { enum: [ "Allow", "Deny" ] },
        "ScheduleRef": { list: true }
    }
};

// Schema for Device.Hosts.
export const Hosts = {
    path: "Device.Hosts.",
    schema: {
        "HostNumberOfEntries": dm_type.UINT,
        "CleanupHostsThreshold": dm_type.INT | dm_type.WRITABLE,
        "AccessControlNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "HostNumberOfEntries": "0",
        "CleanupHostsThreshold": "-1",
        "AccessControlNumberOfEntries": "0"
    },
    since: {
        "CleanupHostsThreshold": "2.20"
    },
    constraints: {
        "CleanupHostsThreshold": { min: -1 }
    }
};
