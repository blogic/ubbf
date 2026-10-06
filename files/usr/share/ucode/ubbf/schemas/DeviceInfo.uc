'use strict';

// Auto-generated schema definitions for DeviceInfo domain
// Generated from TR-181 specifications

// Schema for Device.DeviceInfo.
export const DeviceInfo = {
    path: "Device.DeviceInfo.",
    schema: {
        "DeviceCategory": dm_type.STRING,
        "Manufacturer": dm_type.STRING,
        "ManufacturerOUI": dm_type.STRING,
        "CID": dm_type.STRING,
        "ModelName": dm_type.STRING,
        "ModelNumber": dm_type.STRING,
        "Description": dm_type.STRING,
        "ProductClass": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "HardwareVersion": dm_type.STRING,
        "SoftwareVersion": dm_type.STRING,
        "ActiveFirmwareImage": dm_type.STRING,
        "BootFirmwareImage": dm_type.STRING | dm_type.WRITABLE,
        "AdditionalHardwareVersion": dm_type.STRING,
        "AdditionalSoftwareVersion": dm_type.STRING,
        "ProvisioningCode": dm_type.STRING | dm_type.WRITABLE,
        "UpTime": dm_type.UINT,
        "FirstUseDate": dm_type.DATETIME,
        "HostName": dm_type.STRING | dm_type.WRITABLE,
        "FirmwareImageNumberOfEntries": dm_type.UINT,
        "VendorConfigFileNumberOfEntries": dm_type.UINT,
        "ProcessorNumberOfEntries": dm_type.UINT,
        "LogRotateNumberOfEntries": dm_type.UINT,
        "VendorLogFileNumberOfEntries": dm_type.UINT,
        "LocationNumberOfEntries": dm_type.UINT,
        "DeviceImageNumberOfEntries": dm_type.UINT,
        "FriendlyName": dm_type.STRING | dm_type.WRITABLE,
        "PEN": dm_type.STRING,
        "MaxNumberOfActivateTimeWindows": dm_type.UINT
    },
    defaults: {
        "DeviceCategory": "",
        "Manufacturer": "",
        "ManufacturerOUI": "",
        "CID": "",
        "ModelName": "",
        "ModelNumber": "",
        "Description": "",
        "ProductClass": "",
        "SerialNumber": "",
        "HardwareVersion": "",
        "SoftwareVersion": "",
        "ActiveFirmwareImage": "",
        "BootFirmwareImage": "",
        "AdditionalHardwareVersion": "",
        "AdditionalSoftwareVersion": "",
        "ProvisioningCode": "",
        "UpTime": "0",
        "FirstUseDate": "0001-01-01T00:00:00Z",
        "HostName": "OpenWrt",
        "FirmwareImageNumberOfEntries": "0",
        "VendorConfigFileNumberOfEntries": "0",
        "ProcessorNumberOfEntries": "0",
        "LogRotateNumberOfEntries": "0",
        "VendorLogFileNumberOfEntries": "0",
        "LocationNumberOfEntries": "0",
        "DeviceImageNumberOfEntries": "0",
        "FriendlyName": "OpenWrt",
        "PEN": "",
        "MaxNumberOfActivateTimeWindows": "0"
    }
};

// Schema for Device.DeviceInfo.ProcessFaults.ProcessFault.{i}.
export const ProcessFaults_ProcessFault = {
    path: "Device.DeviceInfo.ProcessFaults.ProcessFault.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "ProcessID": dm_type.STRING,
        "ProcessName": dm_type.STRING,
        "FaultLocation": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "FirmwareVersion": dm_type.STRING,
        "Arguments": dm_type.STRING,
        "Reason": dm_type.STRING,
        "Remove()": { type: 'async', input: [], output: [] },
        "Upload()": { type: 'async', input: ['URL', 'Username', 'Password'], output: [] }
    },
    defaults: {
        "Alias": "",
        "ProcessID": "",
        "ProcessName": "",
        "FaultLocation": "",
        "FirmwareVersion": "",
        "Arguments": "",
        "Reason": ""
    }
};

// Schema for Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}.
export const TemperatureStatus_TemperatureSensor = {
    path: "Device.DeviceInfo.TemperatureStatus.TemperatureSensor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ResetTime": dm_type.DATETIME,
        "Name": dm_type.STRING,
        "Value": dm_type.INT,
        "LastUpdate": dm_type.DATETIME,
        "MinValue": dm_type.INT,
        "MinTime": dm_type.DATETIME,
        "MaxValue": dm_type.INT,
        "MaxTime": dm_type.DATETIME,
        "LowAlarmValue": dm_type.INT | dm_type.WRITABLE,
        "LowAlarmTime": dm_type.DATETIME,
        "HighAlarmValue": dm_type.INT | dm_type.WRITABLE,
        "PollingInterval": dm_type.UINT | dm_type.WRITABLE,
        "HighAlarmTime": dm_type.DATETIME,
        "Reset()": {
            type: 'sync',
            input: []
        }
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "Name": "",
        "Value": "0",
        "MinValue": "0",
        "MaxValue": "0",
        "LowAlarmValue": "0",
        "HighAlarmValue": "0",
        "PollingInterval": "0"
    }
};

// Schema for Device.DeviceInfo.VendorLogFile.{i}.
export const VendorLogFile = {
    path: "Device.DeviceInfo.VendorLogFile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "MaximumSize": dm_type.UINT,
        "Persistent": dm_type.BOOL,
        "Upload()": {
            type: 'async',
            input: ['URL', 'Username', 'Password'],
            output: []
        }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "MaximumSize": "0"
    }
};

// Schema for Device.DeviceInfo.TemperatureStatus.
export const TemperatureStatus = {
    path: "Device.DeviceInfo.TemperatureStatus.",
    schema: {
        "TemperatureSensorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "TemperatureSensorNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.ProcessStatus.Process.{i}.
export const ProcessStatus_Process = {
    path: "Device.DeviceInfo.ProcessStatus.Process.{i}.",
    schema: {
        "PID": dm_type.UINT,
        "Command": dm_type.STRING,
        "Size": dm_type.UINT,
        "Priority": dm_type.UINT,
        "CPUTime": dm_type.UINT,
        "State": dm_type.STRING
    },
    defaults: {
        "PID": "0",
        "Command": "",
        "Size": "0",
        "Priority": "0",
        "CPUTime": "0",
        "State": ""
    }
};

// Schema for Device.DeviceInfo.KernelFaults.
export const KernelFaults = {
    path: "Device.DeviceInfo.KernelFaults.",
    schema: {
        "StoragePath": dm_type.STRING,
        "LastUpgradeCount": dm_type.UINT,
        "PreviousBootCount": dm_type.UINT,
        "MinFreeSpace": dm_type.UINT | dm_type.WRITABLE,
        "RotateKernelFaultEntries": dm_type.BOOL | dm_type.WRITABLE,
        "MaxKernelFaultEntries": dm_type.UINT | dm_type.WRITABLE,
        "KernelFaultNumberOfEntries": dm_type.UINT,
        "RemoveAllKernelFaults()": { type: 'async', input: [], output: [] }
    },
    defaults: {
        "StoragePath": "/etc/ubbf",
        "LastUpgradeCount": "0",
        "PreviousBootCount": "0",
        "MinFreeSpace": "0",
        "RotateKernelFaultEntries": "true",
        "MaxKernelFaultEntries": "100",
        "KernelFaultNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.PowerStatus.PowerSensor.{i}.
export const PowerStatus_PowerSensor = {
    path: "Device.DeviceInfo.PowerStatus.PowerSensor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME,
        "Voltage": dm_type.INT,
        "Current": dm_type.INT,
        "Power": dm_type.INT
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "Name": "",
        "Voltage": "0",
        "Current": "0",
        "Power": "0"
    }
};

// Schema for Device.DeviceInfo.Reboots.Reboot.{i}.
export const Reboots_Reboot = {
    path: "Device.DeviceInfo.Reboots.Reboot.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "FirmwareUpdated": dm_type.BOOL,
        "Cause": dm_type.STRING,
        "Reason": dm_type.STRING,
        "Remove()": { type: 'async', input: [], output: [] }
    },
    defaults: {
        "Alias": "",
        "Cause": "",
        "Reason": "Unknown"
    }
};

// Schema for Device.DeviceInfo.DeviceImageFile.{i}.
export const DeviceImageFile = {
    path: "Device.DeviceInfo.DeviceImageFile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Location": dm_type.STRING,
        "Image": dm_type.BASE64
    },
    defaults: {
        "Alias": "",
        "Location": ""
    }
};

// Schema for Device.DeviceInfo.ProcessFaults.
export const ProcessFaults = {
    path: "Device.DeviceInfo.ProcessFaults.",
    schema: {
        "StoragePath": dm_type.STRING,
        "LastUpgradeCount": dm_type.UINT,
        "PreviousBootCount": dm_type.UINT,
        "MinFreeSpace": dm_type.UINT | dm_type.WRITABLE,
        "RotateProcessFaultEntries": dm_type.BOOL | dm_type.WRITABLE,
        "MaxProcessFaultEntries": dm_type.UINT | dm_type.WRITABLE,
        "ProcessFaultNumberOfEntries": dm_type.UINT,
        "RemoveAllProcessFaults()": { type: 'async', input: [], output: [] }
    },
    defaults: {
        "StoragePath": "/etc/ubbf",
        "LastUpgradeCount": "0",
        "PreviousBootCount": "0",
        "MinFreeSpace": "0",
        "RotateProcessFaultEntries": "true",
        "MaxProcessFaultEntries": "100",
        "ProcessFaultNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.PowerStatus.
export const PowerStatus = {
    path: "Device.DeviceInfo.PowerStatus.",
    schema: {
        "PowerSensorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "PowerSensorNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.ProcessStatus.
export const ProcessStatus = {
    path: "Device.DeviceInfo.ProcessStatus.",
    schema: {
        "CPUUsage": dm_type.UINT,
        "ProcessNumberOfEntries": dm_type.UINT,
        "CPUNumberOfEntries": dm_type.UINT,
        "X_UBBF_LoadAverage": dm_type.STRING
    },
    defaults: {
        "CPUUsage": "0",
        "ProcessNumberOfEntries": "0",
        "CPUNumberOfEntries": "0",
        "X_UBBF_LoadAverage": ""
    }
};

// Schema for Device.DeviceInfo.NetworkProperties.
export const NetworkProperties = {
    path: "Device.DeviceInfo.NetworkProperties.",
    schema: {
        "MaxTCPWindowSize": dm_type.UINT,
        "TCPImplementation": dm_type.STRING
    },
    defaults: {
        "MaxTCPWindowSize": "0",
        "TCPImplementation": ""
    }
};

// Schema for Device.DeviceInfo.Reboots.
export const Reboots = {
    path: "Device.DeviceInfo.Reboots.",
    schema: {
        "BootCount": dm_type.UINT,
        "CurrentVersionBootCount": dm_type.UINT,
        "WatchdogBootCount": dm_type.UINT,
        "ColdBootCount": dm_type.UINT,
        "WarmBootCount": dm_type.UINT,
        "MaxRebootEntries": dm_type.INT | dm_type.WRITABLE,
        "RebootNumberOfEntries": dm_type.UINT,
        "RemoveAllReboots()": { type: 'async', input: [], output: [] }
    },
    defaults: {
        "BootCount": "0",
        "CurrentVersionBootCount": "0",
        "WatchdogBootCount": "0",
        "ColdBootCount": "0",
        "WarmBootCount": "0",
        "MaxRebootEntries": "100",
        "RebootNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.KernelFaults.KernelFault.{i}.
export const KernelFaults_KernelFault = {
    path: "Device.DeviceInfo.KernelFaults.KernelFault.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "FaultLocation": dm_type.STRING,
        "LastInstruction": dm_type.STRING,
        "TimeStamp": dm_type.DATETIME,
        "FirmwareVersion": dm_type.STRING,
        "ProcessName": dm_type.STRING,
        "Reason": dm_type.STRING,
        "Remove()": { type: 'async', input: [], output: [] },
        "Upload()": { type: 'async', input: ['URL', 'Username', 'Password'], output: [] }
    },
    defaults: {
        "Alias": "",
        "FaultLocation": "",
        "LastInstruction": "",
        "FirmwareVersion": "",
        "ProcessName": "",
        "Reason": ""
    }
};

// Schema for Device.DeviceInfo.Processor.{i}.
export const Processor = {
    path: "Device.DeviceInfo.Processor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Architecture": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Architecture": ""
    }
};

// Schema for Device.DeviceInfo.LogRotate.{i}.LogFile.{i}.
export const LogRotate_LogFile = {
    path: "Device.DeviceInfo.LogRotate.{i}.LogFile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Size": dm_type.UINT,
        "LastChange": dm_type.DATETIME
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Size": "0"
    }
};

// Schema for Device.DeviceInfo.MemoryStatus.
export const MemoryStatus = {
    path: "Device.DeviceInfo.MemoryStatus.",
    schema: {
        "Total": dm_type.UINT,
        "Free": dm_type.UINT,
        "TotalPersistent": dm_type.UINT,
        "FreePersistent": dm_type.UINT
    },
    defaults: {
        "Total": "0",
        "Free": "0",
        "TotalPersistent": "0",
        "FreePersistent": "0"
    }
};

// Schema for Device.DeviceInfo.VendorConfigFile.{i}.
export const VendorConfigFile = {
    path: "Device.DeviceInfo.VendorConfigFile.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Version": dm_type.STRING,
        "Date": dm_type.DATETIME,
        "Description": dm_type.STRING,
        "UseForBackupRestore": dm_type.BOOL,
        "Backup()": {
            type: 'async',
            input: ['URL', 'Username', 'Password'],
            output: []
        },
        "Restore()": {
            type: 'async',
            input: ['URL', 'Username', 'Password', 'FileSize', 'CheckSumAlgorithm', 'CheckSum'],
            output: []
        }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Version": "",
        "Description": ""
    }
};

// Schema for Device.DeviceInfo.FirmwareImage.{i}.
export const FirmwareImage = {
    path: "Device.DeviceInfo.FirmwareImage.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Version": dm_type.STRING,
        "Available": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "BootFailureLog": dm_type.STRING,
        "Download()": {
            type: 'async',
            input: ['URL', 'AutoActivate', 'Username', 'Password', 'FileSize', 'CheckSumAlgorithm', 'CheckSum'],
            output: ['MaxRetries', 'StartTime', 'CompleteTime']
        },
        "Activate()": {
            type: 'async',
            input: ['TimeWindow'],
            output: ['UserMessage']
        }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Version": "",
        "Status": "",
        "BootFailureLog": ""
    }
};

// Schema for Device.DeviceInfo.LogRotate.{i}.
export const LogRotate = {
    path: "Device.DeviceInfo.LogRotate.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "NumberOfFiles": dm_type.UINT | dm_type.WRITABLE,
        "MaxFileSize": dm_type.UINT | dm_type.WRITABLE,
        "RollOver": dm_type.UINT | dm_type.WRITABLE,
        "Retention": dm_type.UINT | dm_type.WRITABLE,
        "Compression": dm_type.STRING | dm_type.WRITABLE,
        "LogFileNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "NumberOfFiles": "0",
        "MaxFileSize": "0",
        "RollOver": "0",
        "Retention": "0",
        "Compression": "None",
        "LogFileNumberOfEntries": "0"
    }
};

// Schema for Device.DeviceInfo.ProcessStatus.CPU.{i}.
export const ProcessStatus_CPU = {
    path: "Device.DeviceInfo.ProcessStatus.CPU.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
//      "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "UpTime": dm_type.UINT,
        "UserModeUtilization": dm_type.UINT,
        "SystemModeUtilization": dm_type.UINT,
        "IdleModeUtilization": dm_type.UINT,
        "CPUUtilization": dm_type.UINT
//      "PollInterval": dm_type.UINT | dm_type.WRITABLE,
//      "NumSamples": dm_type.UINT | dm_type.WRITABLE,
//      "CriticalRiseThreshold": dm_type.UINT | dm_type.WRITABLE,
//      "CriticalFallThreshold": dm_type.UINT | dm_type.WRITABLE,
//      "CriticalRiseTimeStamp": dm_type.DATETIME,
//      "CriticalFallTimeStamp": dm_type.DATETIME,
//      "EnableCriticalLog": dm_type.BOOL | dm_type.WRITABLE,
//      "VendorLogFileRef": dm_type.STRING,
//      "FilePath": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "UpTime": "0",
        "UserModeUtilization": "0",
        "SystemModeUtilization": "0",
        "IdleModeUtilization": "0",
        "CPUUtilization": "0"
    }
};

// Schema for Device.DeviceInfo.MemoryStatus.MemoryMonitor.
export const MemoryStatus_MemoryMonitor = {
    path: "Device.DeviceInfo.MemoryStatus.MemoryMonitor.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MemUtilization": dm_type.UINT,
        "PollingInterval": dm_type.UINT | dm_type.WRITABLE,
        "CriticalRiseThreshold": dm_type.UINT | dm_type.WRITABLE,
        "CriticalFallThreshold": dm_type.UINT | dm_type.WRITABLE,
        "CriticalRiseTimeStamp": dm_type.DATETIME,
        "CriticalFallTimeStamp": dm_type.DATETIME,
        "EnableCriticalLog": dm_type.BOOL | dm_type.WRITABLE,
        "VendorLogFileRef": dm_type.STRING,
        "FilePath": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "MemUtilization": "0",
        "PollingInterval": "0",
        "CriticalRiseThreshold": "80",
        "CriticalFallThreshold": "60",
        "EnableCriticalLog": "false",
        "VendorLogFileRef": "",
        "FilePath": ""
    }
};
