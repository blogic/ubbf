'use strict';

// Hand-maintained from TR-181 2.19 (dm/spec/tr-181-2-19-0-softwaremodules*.xml); included by handler.uc with { schemas } as the scope.

schemas.SoftwareModules = {
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
                'Privileged',
                'ExecutionEnvRef',
                'Signature',
                'ShutdownDelay',
                'RequiredRoles',
                'OptionalRoles',
                'RequiredUserRoles',
                'RegisterTrustPaths',
                'AutoRestart.Enable',
                'AutoRestart.RetryMinimumWaitInterval',
                'AutoRestart.RetryMaximumWaitInterval',
                'AutoRestart.RetryIntervalMultiplier',
                'AutoRestart.MaximumRetryCount',
                'AutoRestart.ResetPeriod',
                'Resources.AllocatedDiskSpace',
                'Resources.AllocatedMemory',
                'Resources.AllocatedCPUPercent',
                'ApplicationData.{i}.Name',
                'ApplicationData.{i}.Capacity',
                'ApplicationData.{i}.Encrypted',
                'ApplicationData.{i}.Retain',
                'ApplicationData.{i}.AccessPath',
                'HostObject.{i}.Source',
                'HostObject.{i}.Destination',
                'HostObject.{i}.Options',
                'EnvVariable.{i}.Key',
                'EnvVariable.{i}.Value',
                'ModuleVersion',
                'NetworkConfig.AccessInterfaces',
                'NetworkConfig.PortMapping.{i}.Interface',
                'NetworkConfig.PortMapping.{i}.ExternalPort',
                'NetworkConfig.PortMapping.{i}.InternalPort',
                'NetworkConfig.PortMapping.{i}.Protocol'
            ],
            output: ['UUID', 'Version', 'ExecEnvRef']
        },
        'DUStateChange!': {
            type: 'event',
            input: [
                'UUID',
                'DeploymentUnitRef',
                'Version',
                'CurrentState',
                'Resolved',
                'ExecutionUnitRefList',
                'StartTime',
                'CompleteTime',
                'OperationPerformed',
                'Fault.FaultCode',
                'Fault.FaultString'
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

schemas.ExecEnvClass = {
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
                'Alias',
                'Name',
                'ParentExecEnv',
                'AvailableRoles',
                'AvailableUserRoles',
                'Enable',
                'AllocatedDiskSpace',
                'AllocatedMemory',
                'AllocatedCPUPercent'
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

schemas.ExecEnvClass_Capability = {
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

schemas.ExecEnv = {
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
            input: ['Force', 'AllocatedDiskSpace', 'AllocatedMemory', 'AllocatedCPUPercent'],
            output: []
        },
        "ModifyAvailableRoles()": {
            type: 'async',
            input: ['AvailableRoles', 'AvailableUserRoles'],
            output: []
        },
        "ModifyAvailableAccessInterfaces()": {
            type: 'async',
            input: ['AccessInterfaces'],
            output: []
        },
        "Restart()": {
            type: 'async',
            input: ['Reason', 'Force'],
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
        },
        "Restarted!": {
            type: 'event',
            input: ['RestartTime', 'RestartReason']
        }
    },
    defaults: {
        "Enable": "true",
        "Status": "Up",
        "Alias": "",
        "Name": "",
        "Type": "",
        "InitialRunLevel": "0",
        "CurrentRunLevel": "-1",
        "InitialExecutionUnitRunLevel": "-1",
        "Vendor": "",
        "Version": "",
        "ParentExecEnv": "",
        "AllocatedDiskSpace": "-1",
        "AllocatedMemory": "-1",
        "AllocatedCPUPercent": "-1",
        "AvailableDiskSpace": "-1",
        "AvailableMemory": "-1",
        "AvailableCPUPercent": "-1",
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

schemas.ExecEnv_ApplicationData = {
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
        "Encrypted": "false",
        "Retain": "",
        "AccessPath": "",
        "Alias": "",
        "ApplicationUUID": "",
        "Utilization": "0"
    }
};

schemas.DeploymentUnit = {
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
            input: [
                'URL',
                'Username',
                'Password',
                'Privileged',
                'Signature',
                'RequiredRoles',
                'OptionalRoles',
                'RequiredUserRoles',
                'RegisterTrustPaths',
                'Resources.AllocatedDiskSpace',
                'Resources.AllocatedMemory',
                'Resources.AllocatedCPUPercent',
                'ApplicationData.{i}.Name',
                'ApplicationData.{i}.Capacity',
                'ApplicationData.{i}.Encrypted',
                'ApplicationData.{i}.Retain',
                'ApplicationData.{i}.AccessPath',
                'HostObject.{i}.Source',
                'HostObject.{i}.Destination',
                'HostObject.{i}.Options',
                'EnvVariable.{i}.Key',
                'EnvVariable.{i}.Value',
                'RetainData',
                'ModuleVersion',
                'NetworkConfig.AccessInterfaces',
                'NetworkConfig.PortMapping.{i}.Interface',
                'NetworkConfig.PortMapping.{i}.ExternalPort',
                'NetworkConfig.PortMapping.{i}.InternalPort',
                'NetworkConfig.PortMapping.{i}.Protocol'
            ],
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
        "Status": "Installed",
        "Resolved": "false",
        "URL": "",
        "Description": "",
        "Vendor": "",
        "Version": "",
        "VendorLogList": "",
        "VendorConfigList": "",
        "ExecutionUnitList": "",
        "ExecutionEnvRef": "",
        "InternalController": "",
        "Installed": "0001-01-01T00:00:00Z",
        "LastUpdate": "0001-01-01T00:00:00Z",
        "ModuleVersion": ""
    }
};

schemas.ExecutionUnit = {
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
        "Status": "Idle",
        "ExecutionFaultCode": "NoFault",
        "ExecutionFaultMessage": "",
        "AutoStart": "false",
        "RunLevel": "0",
        "Vendor": "",
        "Version": "",
        "Description": "",
        "Privileged": "false",
        "AllocatedDiskSpace": "-1",
        "DiskSpaceInUse": "-1",
        "AllocatedMemory": "-1",
        "MemoryInUse": "-1",
        "AllocatedCPUPercent": "-1",
        "CPUPercentInUse": "-1",
        "AllocatedEUUID": "0",
        "AllocatedEUGID": "0",
        "AllocatedHostUID": "0",
        "AllocatedHostGID": "0",
        "CreationTime": "0001-01-01T00:00:00Z",
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

schemas.ExecutionUnit_HostObject = {
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

schemas.ExecutionUnit_EnvVariable = {
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

schemas.ExecutionUnit_AutoRestart = {
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
        "RetryCount": "0",
        "LastRestarted": "0001-01-01T00:00:00Z",
        "NextRestart": "9999-12-31T23:59:59Z"
    }
};

schemas.ExecutionUnit_NetworkConfig = {
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
