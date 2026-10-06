'use strict';

// Auto-generated schema definitions for FaultMgmt domain
// Generated from TR-181 specifications

// Schema for Device.FaultMgmt.ExpeditedEvent.{i}.
export const ExpeditedEvent = {
    path: "Device.FaultMgmt.ExpeditedEvent.{i}.",
    schema: {
        "EventTime": dm_type.DATETIME,
        "AlarmIdentifier": dm_type.STRING,
        "NotificationType": dm_type.STRING,
        "ManagedObjectInstance": dm_type.STRING,
        "EventType": dm_type.STRING,
        "ProbableCause": dm_type.STRING,
        "SpecificProblem": dm_type.STRING,
        "PerceivedSeverity": dm_type.STRING,
        "AdditionalText": dm_type.STRING,
        "AdditionalInformation": dm_type.STRING
    },
    defaults: {
        "AlarmIdentifier": "",
        "NotificationType": "",
        "ManagedObjectInstance": "",
        "EventType": "",
        "ProbableCause": "",
        "SpecificProblem": "",
        "PerceivedSeverity": "",
        "AdditionalText": "",
        "AdditionalInformation": ""
    }
};

// Schema for Device.FaultMgmt.
export const FaultMgmt = {
    path: "Device.FaultMgmt.",
    schema: {
        "SupportedAlarmNumberOfEntries": dm_type.UINT,
        "MaxCurrentAlarmEntries": dm_type.UINT,
        "CurrentAlarmNumberOfEntries": dm_type.UINT,
        "HistoryEventNumberOfEntries": dm_type.UINT,
        "ExpeditedEventNumberOfEntries": dm_type.UINT,
        "QueuedEventNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupportedAlarmNumberOfEntries": "0",
        "MaxCurrentAlarmEntries": "0",
        "CurrentAlarmNumberOfEntries": "0",
        "HistoryEventNumberOfEntries": "0",
        "ExpeditedEventNumberOfEntries": "0",
        "QueuedEventNumberOfEntries": "0"
    }
};

// Schema for Device.FaultMgmt.QueuedEvent.{i}.
export const QueuedEvent = {
    path: "Device.FaultMgmt.QueuedEvent.{i}.",
    schema: {
        "EventTime": dm_type.DATETIME,
        "AlarmIdentifier": dm_type.STRING,
        "NotificationType": dm_type.STRING,
        "ManagedObjectInstance": dm_type.STRING,
        "EventType": dm_type.STRING,
        "ProbableCause": dm_type.STRING,
        "SpecificProblem": dm_type.STRING,
        "PerceivedSeverity": dm_type.STRING,
        "AdditionalText": dm_type.STRING,
        "AdditionalInformation": dm_type.STRING
    },
    defaults: {
        "AlarmIdentifier": "",
        "NotificationType": "",
        "ManagedObjectInstance": "",
        "EventType": "",
        "ProbableCause": "",
        "SpecificProblem": "",
        "PerceivedSeverity": "",
        "AdditionalText": "",
        "AdditionalInformation": ""
    }
};

// Schema for Device.FaultMgmt.SupportedAlarm.{i}.
export const SupportedAlarm = {
    path: "Device.FaultMgmt.SupportedAlarm.{i}.",
    schema: {
        "EventType": dm_type.STRING,
        "ProbableCause": dm_type.STRING,
        "SpecificProblem": dm_type.STRING,
        "PerceivedSeverity": dm_type.STRING,
        "ReportingMechanism": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "EventType": "",
        "ProbableCause": "",
        "SpecificProblem": "",
        "PerceivedSeverity": "",
        "ReportingMechanism": ""
    }
};

// Schema for Device.FaultMgmt.CurrentAlarm.{i}.
export const CurrentAlarm = {
    path: "Device.FaultMgmt.CurrentAlarm.{i}.",
    schema: {
        "AlarmIdentifier": dm_type.STRING,
        "AlarmRaisedTime": dm_type.DATETIME,
        "AlarmChangedTime": dm_type.DATETIME,
        "ManagedObjectInstance": dm_type.STRING,
        "EventType": dm_type.STRING,
        "ProbableCause": dm_type.STRING,
        "SpecificProblem": dm_type.STRING,
        "PerceivedSeverity": dm_type.STRING,
        "AdditionalText": dm_type.STRING,
        "AdditionalInformation": dm_type.STRING
    },
    defaults: {
        "AlarmIdentifier": "",
        "ManagedObjectInstance": "",
        "EventType": "",
        "ProbableCause": "",
        "SpecificProblem": "",
        "PerceivedSeverity": "",
        "AdditionalText": "",
        "AdditionalInformation": ""
    }
};

// Schema for Device.FaultMgmt.HistoryEvent.{i}.
export const HistoryEvent = {
    path: "Device.FaultMgmt.HistoryEvent.{i}.",
    schema: {
        "EventTime": dm_type.DATETIME,
        "AlarmIdentifier": dm_type.STRING,
        "NotificationType": dm_type.STRING,
        "ManagedObjectInstance": dm_type.STRING,
        "EventType": dm_type.STRING,
        "ProbableCause": dm_type.STRING,
        "SpecificProblem": dm_type.STRING,
        "PerceivedSeverity": dm_type.STRING,
        "AdditionalText": dm_type.STRING,
        "AdditionalInformation": dm_type.STRING
    },
    defaults: {
        "AlarmIdentifier": "",
        "NotificationType": "",
        "ManagedObjectInstance": "",
        "EventType": "",
        "ProbableCause": "",
        "SpecificProblem": "",
        "PerceivedSeverity": "",
        "AdditionalText": "",
        "AdditionalInformation": ""
    }
};
