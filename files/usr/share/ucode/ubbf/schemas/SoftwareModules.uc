'use strict';

// Auto-generated schema definitions for SoftwareModules domain
// Generated from TR-181 specifications

// Schema for Device.SoftwareModules.ExecEnv.{i}.ApplicationData.{i}.
export const ExecEnv_ApplicationData = {
    path: "Device.SoftwareModules.ExecEnv.{i}.ApplicationData.{i}.",
    schema: {
        "Name": dm_type.STRING,
        "Capacity": dm_type.UINT,
        "Encrypted": dm_type.BOOL,
        "Retain": dm_type.STRING,
        "AccessPath": dm_type.STRING,
        "Alias": dm_type.STRING,
        "ApplicationUUID": dm_type.STRING,
        "Utilization": dm_type.UINT,
        "Remove()": { type: 'sync', input: [] }
    },
    defaults: {
        "Name": "",
        "Capacity": "0",
        "Retain": "",
        "AccessPath": "",
        "Alias": "",
        "ApplicationUUID": "",
        "Utilization": "0"
    }
};

// Schema for Device.SoftwareModules.DeploymentUnit.{i}.
export const DeploymentUnit = {
    path: "Device.SoftwareModules.DeploymentUnit.{i}.",
    schema: {
        "UUID": dm_type.STRING,
        "DUID": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Status": dm_type.STRING,
        "Resolved": dm_type.BOOL,
        "URL": dm_type.STRING,
        "Description": dm_type.STRING,
        "Vendor": dm_type.STRING,
        "Version": dm_type.STRING,
        "VendorLogList": dm_type.STRING,
        "VendorConfigList": dm_type.STRING,
        "ExecutionUnitList": dm_type.STRING,
        "ExecutionEnvRef": dm_type.STRING,
        "InternalController": dm_type.STRING,
        "Installed": dm_type.DATETIME,
        "LastUpdate": dm_type.DATETIME,
        "ModuleVersion": dm_type.STRING,
        "Update()": {
            type: 'async',
            input: ['URL', 'Username', 'Password', 'Version', 'Signature'],
            output: []
        },
        "Uninstall()": {
            type: 'async',
            input: ['RetainData'],
            output: []
        }
    },
    defaults: {
        "UUID": "",
        "DUID": "",
        "Alias": "",
        "Name": "",
        "Status": "",
        "URL": "",
        "Description": "",
        "Vendor": "",
        "Version": "",
        "VendorLogList": "",
        "VendorConfigList": "",
        "ExecutionUnitList": "",
        "ExecutionEnvRef": "",
        "InternalController": "",
        "ModuleVersion": ""
    }
};

// Schema for Device.SoftwareModules.ExecEnvClass.{i}.Capability.{i}.
export const ExecEnvClass_Capability = {
    path: "Device.SoftwareModules.ExecEnvClass.{i}.Capability.{i}.",
    schema: {
        "Specification": dm_type.STRING,
        "SpecificationVersion": dm_type.STRING,
        "SpecificationURI": dm_type.STRING
    },
    defaults: {
        "Specification": "",
        "SpecificationVersion": "",
        "SpecificationURI": ""
    }
};

// Schema for Device.SoftwareModules.ExecutionUnit.{i}.AutoRestart.
export const ExecutionUnit_AutoRestart = {
    path: "Device.SoftwareModules.ExecutionUnit.{i}.AutoRestart.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "RetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "RetryMaximumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "RetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "MaximumRetryCount": dm_type.UINT | dm_type.WRITABLE,
        "ResetPeriod": dm_type.UINT | dm_type.WRITABLE,
        "RetryCount": dm_type.UINT | dm_type.WRITABLE,
        "LastRestarted": dm_type.DATETIME,
        "NextRestart": dm_type.DATETIME
    },
    defaults: {
        "Enable": "false",
        "RetryMinimumWaitInterval": "0",
        "RetryMaximumWaitInterval": "0",
        "RetryIntervalMultiplier": "0",
        "MaximumRetryCount": "0",
        "ResetPeriod": "0",
        "RetryCount": "0"
    }
};

// Schema for Device.SoftwareModules.
export const SoftwareModules = {
    path: "Device.SoftwareModules.",
    schema: {
        "ExecEnvClassNumberOfEntries": dm_type.UINT,
        "ExecEnvNumberOfEntries": dm_type.UINT,
        "DeploymentUnitNumberOfEntries": dm_type.UINT,
        "ExecutionUnitNumberOfEntries": dm_type.UINT,
        "InstallDU()": {
            type: 'async',
            input: [
                'URL',
                'UUID',
                'Username',
                'Password',
                'ExecutionEnvRef',
                'Vendor',
                'Version',
                'Privileged',
                'Signature',
                'AllocatedMemory',
                'AllocatedCPUPercent',
                'AllocatedDiskSpace',
                'NetworkConfig.ShareParentNetwork',
                'NetworkConfig.PortForwarding',
                'HostObject',
                'EnvVariable',
                'ApplicationData'
            ],
            output: [
                'UUID',
                'DeploymentUnitRef',
                'ExecutionUnitRefList'
            ]
        },
        'DUStateChange!': {
            type: 'event',
            input: [
                'UUID',
                'Version',
                'CurrentState',
                'OperationPerformed',
                'ExecutionEnvRef',
                'FaultCode',
                'FaultString'
            ]
        }
    },
    defaults: {
        "ExecEnvClassNumberOfEntries": "0",
        "ExecEnvNumberOfEntries": "0",
        "DeploymentUnitNumberOfEntries": "0",
        "ExecutionUnitNumberOfEntries": "0"
    }
};

// Schema for Device.SoftwareModules.ExecutionUnit.{i}.HostObject.{i}.
export const ExecutionUnit_HostObject = {
    path: "Device.SoftwareModules.ExecutionUnit.{i}.HostObject.{i}.",
    schema: {
        "Source": dm_type.STRING,
        "Destination": dm_type.STRING,
        "Options": dm_type.STRING,
        "Alias": dm_type.STRING
    },
    defaults: {
        "Source": "",
        "Destination": "",
        "Options": "",
        "Alias": ""
    }
};

// Schema for Device.SoftwareModules.ExecEnvClass.{i}.
export const ExecEnvClass = {
    path: "Device.SoftwareModules.ExecEnvClass.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Vendor": dm_type.STRING,
        "Version": dm_type.STRING,
        "DeploymentUnitRef": dm_type.STRING,
        "CapabilityNumberOfEntries": dm_type.UINT,
        "AddExecEnv()": {
            type: 'sync',
            input: [
                'Name',
                'Alias',
                'Vendor',
                'Version',
                'Type',
                'Enable',
                'AllocatedDiskSpace',
                'AllocatedMemory',
                'AllocatedCPUPercent',
                'AvailableRoles'
            ],
            output: ['ExecEnvRef']
        }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Vendor": "",
        "Version": "",
        "DeploymentUnitRef": "",
        "CapabilityNumberOfEntries": "0"
    }
};

// Schema for Device.SoftwareModules.ExecutionUnit.{i}.EnvVariable.{i}.
export const ExecutionUnit_EnvVariable = {
    path: "Device.SoftwareModules.ExecutionUnit.{i}.EnvVariable.{i}.",
    schema: {
        "Key": dm_type.STRING,
        "Value": dm_type.STRING,
        "Alias": dm_type.STRING
    },
    defaults: {
        "Key": "",
        "Value": "",
        "Alias": ""
    }
};

// Schema for Device.SoftwareModules.ExecutionUnit.{i}.NetworkConfig.
export const ExecutionUnit_NetworkConfig = {
    path: "Device.SoftwareModules.ExecutionUnit.{i}.NetworkConfig.",
    schema: {
        "AccessInterfaceRefList": dm_type.STRING,
        "PortMappingRefList": dm_type.STRING
    },
    defaults: {
        "AccessInterfaceRefList": "",
        "PortMappingRefList": ""
    }
};

// Schema for Device.SoftwareModules.ExecutionUnit.{i}.
export const ExecutionUnit = {
    path: "Device.SoftwareModules.ExecutionUnit.{i}.",
    schema: {
        "EUID": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "ExecEnvLabel": dm_type.STRING,
        "Status": dm_type.STRING,
        "ExecutionFaultCode": dm_type.STRING,
        "ExecutionFaultMessage": dm_type.STRING,
        "AutoStart": dm_type.BOOL | dm_type.WRITABLE,
        "RunLevel": dm_type.UINT | dm_type.WRITABLE,
        "Vendor": dm_type.STRING,
        "Version": dm_type.STRING,
        "Description": dm_type.STRING,
        "Privileged": dm_type.BOOL,
        "AllocatedDiskSpace": dm_type.INT,
        "DiskSpaceInUse": dm_type.INT,
        "AllocatedMemory": dm_type.INT,
        "MemoryInUse": dm_type.INT,
        "AllocatedCPUPercent": dm_type.INT,
        "CPUPercentInUse": dm_type.INT,
        "AllocatedEUUID": dm_type.UINT,
        "AllocatedEUGID": dm_type.STRING,
        "AllocatedHostUID": dm_type.UINT,
        "AllocatedHostGID": dm_type.STRING,
        "CreationTime": dm_type.DATETIME,
        "Uptime": dm_type.UINT,
        "ShutdownDelay": dm_type.UINT | dm_type.WRITABLE,
        "References": dm_type.STRING,
        "AssociatedProcessList": dm_type.STRING,
        "VendorLogList": dm_type.STRING,
        "VendorConfigList": dm_type.STRING,
        "ApplicationDataList": dm_type.STRING,
        "ExecutionEnvRef": dm_type.STRING,
        "HostObjectNumberOfEntries": dm_type.UINT,
        "EnvVariableNumberOfEntries": dm_type.UINT,
        "SetRequestedState()": {
            type: 'sync',
            input: ['RequestedState']
        },
        "Restart()": {
            type: 'sync',
            input: []
        }
    },
    defaults: {
        "EUID": "",
        "Alias": "",
        "Name": "",
        "ExecEnvLabel": "",
        "Status": "",
        "ExecutionFaultCode": "",
        "ExecutionFaultMessage": "",
        "RunLevel": "0",
        "Vendor": "",
        "Version": "",
        "Description": "",
        "AllocatedDiskSpace": "0",
        "DiskSpaceInUse": "0",
        "AllocatedMemory": "0",
        "MemoryInUse": "0",
        "AllocatedCPUPercent": "0",
        "CPUPercentInUse": "0",
        "AllocatedEUUID": "0",
        "AllocatedEUGID": "",
        "AllocatedHostUID": "0",
        "AllocatedHostGID": "",
        "Uptime": "0",
        "ShutdownDelay": "10",
        "References": "",
        "AssociatedProcessList": "",
        "VendorLogList": "",
        "VendorConfigList": "",
        "ApplicationDataList": "",
        "ExecutionEnvRef": "",
        "HostObjectNumberOfEntries": "0",
        "EnvVariableNumberOfEntries": "0"
    }
};

// Schema for Device.SoftwareModules.ExecEnv.{i}.
export const ExecEnv = {
    path: "Device.SoftwareModules.ExecEnv.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Type": dm_type.STRING,
        "InitialRunLevel": dm_type.UINT | dm_type.WRITABLE,
        "CurrentRunLevel": dm_type.INT,
        "InitialExecutionUnitRunLevel": dm_type.INT | dm_type.WRITABLE,
        "Vendor": dm_type.STRING,
        "Version": dm_type.STRING,
        "ParentExecEnv": dm_type.STRING,
        "AllocatedDiskSpace": dm_type.INT,
        "AllocatedMemory": dm_type.INT,
        "AllocatedCPUPercent": dm_type.INT,
        "AvailableDiskSpace": dm_type.INT,
        "AvailableMemory": dm_type.INT,
        "AvailableCPUPercent": dm_type.INT,
        "ActiveExecutionUnits": dm_type.STRING,
        "ProcessorRefList": dm_type.STRING,
        "CreatedAt": dm_type.DATETIME,
        "ExecEnvClassRef": dm_type.STRING,
        "ApplicationDataNumberOfEntries": dm_type.UINT,
        "RestartReason": dm_type.STRING,
        "RestartCount": dm_type.UINT,
        "LastRestarted": dm_type.DATETIME,
        "Signers": dm_type.STRING | dm_type.WRITABLE,
        "AvailableRoles": dm_type.STRING,
        "AvailableAccessInterfaces": dm_type.STRING,
        "AvailableUserRoles": dm_type.STRING,
        "SetRunLevel()": {
            type: 'sync',
            input: ['RequestedRunLevel']
        },
        "ModifyConstraints()": {
            type: 'async',
            input: ['AllocatedDiskSpace', 'AllocatedMemory', 'AllocatedCPUPercent'],
            output: []
        },
        "ModifyAvailableRoles()": {
            type: 'async',
            input: ['AvailableRoles'],
            output: []
        },
        "ModifyAvailableAccessInterfaces()": {
            type: 'async',
            input: ['AccessInterfaces'],
            output: []
        },
        "Restart()": {
            type: 'async',
            input: [],
            output: []
        },
        "Reset()": {
            type: 'async',
            input: [],
            output: []
        },
        "Remove()": {
            type: 'async',
            input: ['Force'],
            output: []
        }
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "Type": "",
        "InitialRunLevel": "0",
        "CurrentRunLevel": "0",
        "InitialExecutionUnitRunLevel": "0",
        "Vendor": "",
        "Version": "",
        "ParentExecEnv": "",
        "AllocatedDiskSpace": "-1",
        "AllocatedMemory": "-1",
        "AllocatedCPUPercent": "-1",
        "AvailableDiskSpace": "0",
        "AvailableMemory": "0",
        "AvailableCPUPercent": "0",
        "ActiveExecutionUnits": "",
        "ProcessorRefList": "",
        "CreatedAt": "0001-01-01T00:00:00Z",
        "ExecEnvClassRef": "",
        "ApplicationDataNumberOfEntries": "0",
        "RestartReason": "",
        "RestartCount": "0",
        "LastRestarted": "0001-01-01T00:00:00Z",
        "Signers": "",
        "AvailableRoles": "",
        "AvailableAccessInterfaces": "",
        "AvailableUserRoles": ""
    }
};
