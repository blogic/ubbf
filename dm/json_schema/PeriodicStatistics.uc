'use strict';

// Auto-generated schema definitions for PeriodicStatistics domain
// Generated from TR-181 specifications

// Schema for Device.PeriodicStatistics.SampleSet.{i}.Parameter.{i}.
export const SampleSet_Parameter = {
    path: "Device.PeriodicStatistics.SampleSet.{i}.Parameter.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "SampleMode": dm_type.STRING | dm_type.WRITABLE,
        "CalculationMode": dm_type.STRING | dm_type.WRITABLE,
        "LowThreshold": dm_type.INT | dm_type.WRITABLE,
        "HighThreshold": dm_type.INT | dm_type.WRITABLE,
        "SampleSeconds": dm_type.UINT,
        "SuspectData": dm_type.UINT,
        "Values": dm_type.STRING,
        "ValuesIfHistogram": dm_type.STRING,
        "Failures": dm_type.UINT,
        "HistogramBinBoundaries": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Reference": "",
        "SampleMode": "Current",
        "CalculationMode": "Latest",
        "LowThreshold": "0",
        "HighThreshold": "0",
        "SampleSeconds": "[]",
        "SuspectData": "[]",
        "Values": "[]",
        "ValuesIfHistogram": "[]",
        "Failures": "0",
        "HistogramBinBoundaries": ""
    }
};

// Schema for Device.PeriodicStatistics.SampleSet.{i}.
export const SampleSet = {
    path: "Device.PeriodicStatistics.SampleSet.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Controller": dm_type.STRING,
        "SampleInterval": dm_type.UINT | dm_type.WRITABLE,
        "ReportSamples": dm_type.UINT | dm_type.WRITABLE,
        "TimeReference": dm_type.DATETIME | dm_type.WRITABLE,
        "ReportStartTime": dm_type.DATETIME,
        "ReportEndTime": dm_type.DATETIME,
        "SampleSeconds": dm_type.UINT,
        "ParameterNumberOfEntries": dm_type.UINT,
        "FetchSamples": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Status": "Disabled",
        "Name": "",
        "Controller": "",
        "SampleInterval": "3600",
        "ReportSamples": "24",
        "TimeReference": "0001-01-01T00:00:00Z",
        "ReportStartTime": "0001-01-01T00:00:00Z",
        "ReportEndTime": "0001-01-01T00:00:00Z",
        "SampleSeconds": "[]",
        "ParameterNumberOfEntries": "0",
        "FetchSamples": "1"
    }
};

// Schema for Device.PeriodicStatistics.
export const PeriodicStatistics = {
    path: "Device.PeriodicStatistics.",
    schema: {
        "MinSampleInterval": dm_type.UINT,
        "MaxReportSamples": dm_type.UINT,
        "SampleSetNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "MinSampleInterval": "0",
        "MaxReportSamples": "0",
        "SampleSetNumberOfEntries": "0"
    }
};
