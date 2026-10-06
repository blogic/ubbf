'use strict';

// Auto-generated schema definitions for LMAP domain
// Generated from TR-181 specifications

// Schema for Device.LMAP.Event.{i}.OneOff.
export const Event_OneOff = {
    path: "Device.LMAP.Event.{i}.OneOff.",
    schema: {
        "StartTime": dm_type.DATETIME | dm_type.WRITABLE
    },
    defaults: {}
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Task.{i}.Registry.{i}.
export const Task_Registry = {
    path: "Device.LMAP.MeasurementAgent.{i}.Task.{i}.Registry.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "RegistryEntry": dm_type.STRING | dm_type.WRITABLE,
        "Roles": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "RegistryEntry": "",
        "Roles": ""
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.
export const Schedule_Action = {
    path: "Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "State": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Task": dm_type.STRING | dm_type.WRITABLE,
        "OutputDestination": dm_type.STRING | dm_type.WRITABLE,
        "SuppressionTags": dm_type.STRING | dm_type.WRITABLE,
        "Tags": dm_type.STRING | dm_type.WRITABLE,
        "Storage": dm_type.ULONG,
        "LastInvocation": dm_type.DATETIME,
        "LastSuccessfulCompletion": dm_type.DATETIME,
        "LastSuccessfulStatusCode": dm_type.INT,
        "LastSuccessfulMessage": dm_type.STRING,
        "LastFailedCompletion": dm_type.DATETIME,
        "LastFailedStatusCode": dm_type.INT,
        "LastFailedMessage": dm_type.STRING,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "State": "",
        "Order": "0",
        "Task": "",
        "OutputDestination": "",
        "SuppressionTags": "",
        "Tags": "",
        "Storage": "0",
        "LastSuccessfulStatusCode": "0",
        "LastSuccessfulMessage": "",
        "LastFailedStatusCode": "0",
        "LastFailedMessage": "",
        "OptionNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.
export const LMAP = {
    path: "Device.LMAP.",
    schema: {
        "MeasurementAgentNumberOfEntries": dm_type.UINT,
        "ReportNumberOfEntries": dm_type.UINT,
        "EventNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MeasurementAgentNumberOfEntries": "0",
        "ReportNumberOfEntries": "0",
        "EventNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Task.{i}.Option.{i}.
export const Task_Option = {
    path: "Device.LMAP.MeasurementAgent.{i}.Task.{i}.Option.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Order": "0",
        "Name": "",
        "Value": ""
    }
};

// Schema for Device.LMAP.Report.{i}.
export const Report = {
    path: "Device.LMAP.Report.{i}.",
    schema: {
        "ReportDate": dm_type.DATETIME,
        "AgentIdentifier": dm_type.STRING,
        "GroupIdentifier": dm_type.STRING,
        "MeasurementPoint": dm_type.STRING,
        "ResultNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "AgentIdentifier": "",
        "GroupIdentifier": "",
        "MeasurementPoint": "",
        "ResultNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.ResultRow.{i}.
export const ReportTable_ResultRow = {
    path: "Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.ResultRow.{i}.",
    schema: {
        "Values": dm_type.STRING
    },
    defaults: {
        "Values": ""
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.Stats.
export const Action_Stats = {
    path: "Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.Stats.",
    schema: {
        "Invocations": dm_type.ULONG,
        "Suppressions": dm_type.ULONG,
        "Overlaps": dm_type.ULONG,
        "Failures": dm_type.ULONG
    },
    defaults: {
        "Invocations": "0",
        "Suppressions": "0",
        "Overlaps": "0",
        "Failures": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Instruction.{i}.
export const MeasurementAgent_Instruction = {
    path: "Device.LMAP.MeasurementAgent.{i}.Instruction.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "LastChange": dm_type.DATETIME,
        "InstructionSchedules": dm_type.STRING | dm_type.WRITABLE,
        "InstructionTasks": dm_type.STRING | dm_type.WRITABLE,
        "ReportChannels": dm_type.STRING | dm_type.WRITABLE,
        "MeasurementSuppressionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "InstructionSchedules": "",
        "InstructionTasks": "",
        "ReportChannels": "",
        "MeasurementSuppressionNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.CommunicationChannel.{i}.
export const MeasurementAgent_CommunicationChannel = {
    path: "Device.LMAP.MeasurementAgent.{i}.CommunicationChannel.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "UseBulkDataProfile": dm_type.BOOL | dm_type.WRITABLE,
        "BulkDataProfile": dm_type.STRING | dm_type.WRITABLE,
        "Target": dm_type.STRING | dm_type.WRITABLE,
        "TargetPublicCredential": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "BulkDataProfile": "",
        "Target": "",
        "TargetPublicCredential": "",
        "Interface": ""
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.
export const MeasurementAgent_Schedule = {
    path: "Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "State": dm_type.STRING,
        "Start": dm_type.STRING | dm_type.WRITABLE,
        "End": dm_type.STRING | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE,
        "Tags": dm_type.STRING | dm_type.WRITABLE,
        "SuppressionTags": dm_type.STRING | dm_type.WRITABLE,
        "ExecutionMode": dm_type.STRING | dm_type.WRITABLE,
        "LastInvocation": dm_type.DATETIME,
        "Storage": dm_type.ULONG,
        "ActionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "State": "",
        "Start": "",
        "End": "",
        "Duration": "0",
        "Tags": "",
        "SuppressionTags": "",
        "ExecutionMode": "Pipelined",
        "Storage": "0",
        "ActionNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.TaskCapability.{i}.
export const MeasurementAgent_TaskCapability = {
    path: "Device.LMAP.MeasurementAgent.{i}.TaskCapability.{i}.",
    schema: {
        "Name": dm_type.STRING,
        "Version": dm_type.STRING,
        "TaskCapabilityRegistryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Name": "",
        "Version": "",
        "TaskCapabilityRegistryNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Task.{i}.
export const MeasurementAgent_Task = {
    path: "Device.LMAP.MeasurementAgent.{i}.Task.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Tags": dm_type.STRING | dm_type.WRITABLE,
        "OptionNumberOfEntries": dm_type.UINT,
        "RegistryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Tags": "",
        "OptionNumberOfEntries": "0",
        "RegistryNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.Option.{i}.
export const Action_Option = {
    path: "Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Action.{i}.Option.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Order": "0",
        "Name": "",
        "Value": ""
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.
export const Report_Result = {
    path: "Device.LMAP.Report.{i}.Result.{i}.",
    schema: {
        "TaskName": dm_type.STRING,
        "ScheduleName": dm_type.STRING,
        "ActionName": dm_type.STRING,
        "EventTime": dm_type.DATETIME,
        "StartTime": dm_type.DATETIME,
        "EndTime": dm_type.DATETIME,
        "CycleNumber": dm_type.STRING,
        "Status": dm_type.INT,
        "Tags": dm_type.STRING,
        "OptionNumberOfEntries": dm_type.UINT,
        "ResultConflictNumberOfEntries": dm_type.UINT,
        "ResultReportTableNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "TaskName": "",
        "ScheduleName": "",
        "ActionName": "",
        "CycleNumber": "",
        "Status": "0",
        "Tags": "",
        "OptionNumberOfEntries": "0",
        "ResultConflictNumberOfEntries": "0",
        "ResultReportTableNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.Event.{i}.PeriodicTimer.
export const Event_PeriodicTimer = {
    path: "Device.LMAP.Event.{i}.PeriodicTimer.",
    schema: {
        "StartTime": dm_type.DATETIME | dm_type.WRITABLE,
        "EndTime": dm_type.DATETIME | dm_type.WRITABLE,
        "Interval": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Interval": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Instruction.{i}.MeasurementSuppression.{i}.
export const Instruction_MeasurementSuppression = {
    path: "Device.LMAP.MeasurementAgent.{i}.Instruction.{i}.MeasurementSuppression.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "State": dm_type.STRING,
        "StopRunning": dm_type.BOOL | dm_type.WRITABLE,
        "Start": dm_type.STRING | dm_type.WRITABLE,
        "End": dm_type.STRING | dm_type.WRITABLE,
        "SuppressionMatch": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "State": "",
        "StopRunning": "false",
        "Start": "",
        "End": "",
        "SuppressionMatch": ""
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Stats.
export const Schedule_Stats = {
    path: "Device.LMAP.MeasurementAgent.{i}.Schedule.{i}.Stats.",
    schema: {
        "Invocations": dm_type.ULONG,
        "Suppressions": dm_type.ULONG,
        "Overlaps": dm_type.ULONG,
        "Failures": dm_type.ULONG
    },
    defaults: {
        "Invocations": "0",
        "Suppressions": "0",
        "Overlaps": "0",
        "Failures": "0"
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.
export const Result_ReportTable = {
    path: "Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.",
    schema: {
        "ColumnLabels": dm_type.STRING,
        "ResultReportRowNumberOfEntries": dm_type.UINT,
        "RegistryNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ColumnLabels": "",
        "ResultReportRowNumberOfEntries": "0",
        "RegistryNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.Controller.
export const MeasurementAgent_Controller = {
    path: "Device.LMAP.MeasurementAgent.{i}.Controller.",
    schema: {
        "ControllerTimeout": dm_type.INT | dm_type.WRITABLE,
        "ControlSchedules": dm_type.STRING | dm_type.WRITABLE,
        "ControlTasks": dm_type.STRING | dm_type.WRITABLE,
        "ControlChannels": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ControllerTimeout": "0",
        "ControlSchedules": "",
        "ControlTasks": "",
        "ControlChannels": ""
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.Option.{i}.
export const Result_Option = {
    path: "Device.LMAP.Report.{i}.Result.{i}.Option.{i}.",
    schema: {
        "Order": dm_type.UINT,
        "Name": dm_type.INT,
        "Value": dm_type.STRING
    },
    defaults: {
        "Order": "0",
        "Name": "0",
        "Value": ""
    }
};

// Schema for Device.LMAP.Event.{i}.CalendarTimer.
export const Event_CalendarTimer = {
    path: "Device.LMAP.Event.{i}.CalendarTimer.",
    schema: {
        "StartTime": dm_type.DATETIME | dm_type.WRITABLE,
        "EndTime": dm_type.DATETIME | dm_type.WRITABLE,
        "ScheduleMonths": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleDaysOfMonth": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleDaysOfWeek": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleHoursOfDay": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleMinutesOfHour": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleSecondsOfMinute": dm_type.STRING | dm_type.WRITABLE,
        "EnableScheduleTimezoneOffset": dm_type.BOOL | dm_type.WRITABLE,
        "ScheduleTimezoneOffset": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "ScheduleMonths": "",
        "ScheduleDaysOfMonth": "",
        "ScheduleDaysOfWeek": "",
        "ScheduleHoursOfDay": "",
        "ScheduleMinutesOfHour": "",
        "ScheduleSecondsOfMinute": "",
        "ScheduleTimezoneOffset": "0"
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.Conflict.{i}.
export const Result_Conflict = {
    path: "Device.LMAP.Report.{i}.Result.{i}.Conflict.{i}.",
    schema: {
        "TaskName": dm_type.STRING,
        "ScheduleName": dm_type.STRING,
        "ActionName": dm_type.STRING
    },
    defaults: {
        "TaskName": "",
        "ScheduleName": "",
        "ActionName": ""
    }
};

// Schema for Device.LMAP.Event.{i}.
export const Event = {
    path: "Device.LMAP.Event.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "RandomnessSpread": dm_type.INT | dm_type.WRITABLE,
        "CycleInterval": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Type": "Immediate",
        "RandomnessSpread": "0",
        "CycleInterval": "0"
    }
};

// Schema for Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.Registry.{i}.
export const ReportTable_Registry = {
    path: "Device.LMAP.Report.{i}.Result.{i}.ReportTable.{i}.Registry.{i}.",
    schema: {
        "RegistryEntry": dm_type.STRING,
        "Roles": dm_type.STRING
    },
    defaults: {
        "RegistryEntry": "",
        "Roles": ""
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.
export const MeasurementAgent = {
    path: "Device.LMAP.MeasurementAgent.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Version": dm_type.STRING,
        "LastStarted": dm_type.DATETIME,
        "CapabilityTags": dm_type.STRING,
        "Identifier": dm_type.STRING | dm_type.WRITABLE,
        "GroupIdentifier": dm_type.STRING | dm_type.WRITABLE,
        "MeasurementPoint": dm_type.STRING | dm_type.WRITABLE,
        "UseAgentIdentifierInReports": dm_type.BOOL | dm_type.WRITABLE,
        "UseGroupIdentifierInReports": dm_type.BOOL | dm_type.WRITABLE,
        "UseMeasurementPointInReports": dm_type.BOOL | dm_type.WRITABLE,
        "PublicCredential": dm_type.STRING | dm_type.WRITABLE,
        "PrivateCredential": dm_type.STRING | dm_type.WRITABLE,
        "EventLog": dm_type.STRING,
        "TaskCapabilityNumberOfEntries": dm_type.UINT,
        "ScheduleNumberOfEntries": dm_type.UINT,
        "TaskNumberOfEntries": dm_type.UINT,
        "CommunicationChannelNumberOfEntries": dm_type.UINT,
        "InstructionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Version": "",
        "CapabilityTags": "",
        "Identifier": "",
        "GroupIdentifier": "",
        "MeasurementPoint": "",
        "UseAgentIdentifierInReports": "true",
        "UseGroupIdentifierInReports": "false",
        "UseMeasurementPointInReports": "false",
        "PublicCredential": "",
        "PrivateCredential": "",
        "EventLog": "",
        "TaskCapabilityNumberOfEntries": "0",
        "ScheduleNumberOfEntries": "0",
        "TaskNumberOfEntries": "0",
        "CommunicationChannelNumberOfEntries": "0",
        "InstructionNumberOfEntries": "0"
    }
};

// Schema for Device.LMAP.MeasurementAgent.{i}.TaskCapability.{i}.Registry.{i}.
export const TaskCapability_Registry = {
    path: "Device.LMAP.MeasurementAgent.{i}.TaskCapability.{i}.Registry.{i}.",
    schema: {
        "RegistryEntry": dm_type.STRING,
        "Roles": dm_type.STRING
    },
    defaults: {
        "RegistryEntry": "",
        "Roles": ""
    }
};
