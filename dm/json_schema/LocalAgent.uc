'use strict';

// Auto-generated schema definitions for LocalAgent domain
// Generated from TR-181 specifications

// Schema for Device.LocalAgent.MTP.{i}.UDS.
export const MTP_UDS = {
    path: "Device.LocalAgent.MTP.{i}.UDS.",
    schema: {
        "UnixDomainSocketRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "UnixDomainSocketRef": ""
    }
};

// Schema for Device.LocalAgent.Controller.{i}.MTP.{i}.STOMP.
export const MTP_STOMP = {
    path: "Device.LocalAgent.Controller.{i}.MTP.{i}.STOMP.",
    schema: {
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "Destination": dm_type.STRING | dm_type.WRITABLE,
        "USPServiceRef": dm_type.STRING
    },
    defaults: {
        "Reference": "",
        "Destination": "",
        "USPServiceRef": ""
    }
};

// Schema for Device.LocalAgent.Controller.{i}.MTP.{i}.
export const Controller_MTP = {
    path: "Device.LocalAgent.Controller.{i}.MTP.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Protocol": "",
        "Order": "0"
    }
};

// Schema for Device.LocalAgent.Threshold.{i}.
export const Threshold = {
    path: "Device.LocalAgent.Threshold.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "OperatingMode": dm_type.STRING | dm_type.WRITABLE,
        "ReferencePath": dm_type.STRING | dm_type.WRITABLE,
        "ThresholdParam": dm_type.STRING | dm_type.WRITABLE,
        "ThresholdOperator": dm_type.STRING | dm_type.WRITABLE,
        "ThresholdValue": dm_type.STRING | dm_type.WRITABLE,
        "Controller": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "OperatingMode": "Normal",
        "ReferencePath": "",
        "ThresholdParam": "",
        "ThresholdOperator": "Rise",
        "ThresholdValue": "",
        "Controller": ""
    }
};

// Schema for Device.LocalAgent.MTP.{i}.CoAP.
export const MTP_CoAP = {
    path: "Device.LocalAgent.MTP.{i}.CoAP.",
    schema: {
        "Interfaces": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Path": dm_type.STRING | dm_type.WRITABLE,
        "IsEncrypted": dm_type.BOOL,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Interfaces": "",
        "Port": "5683",
        "Path": "",
        "EnableEncryption": "true"
    }
};

// Schema for Device.LocalAgent.ControllerTrust.Challenge.{i}.
export const ControllerTrust_Challenge = {
    path: "Device.LocalAgent.ControllerTrust.Challenge.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "Role": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.BASE64 | dm_type.WRITABLE,
        "ValueType": dm_type.STRING | dm_type.WRITABLE,
        "Instruction": dm_type.BASE64 | dm_type.WRITABLE,
        "InstructionType": dm_type.STRING | dm_type.WRITABLE,
        "Retries": dm_type.UINT | dm_type.WRITABLE,
        "LockoutPeriod": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Description": "",
        "Role": "",
        "Enable": "false",
        "Type": "",
        "ValueType": "",
        "InstructionType": "",
        "Retries": "0",
        "LockoutPeriod": "30"
    }
};

// Schema for Device.LocalAgent.ControllerTrust.Credential.{i}.
export const ControllerTrust_Credential = {
    path: "Device.LocalAgent.ControllerTrust.Credential.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Role": dm_type.STRING | dm_type.WRITABLE,
        "Credential": dm_type.STRING | dm_type.WRITABLE,
        "AllowedUses": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Role": "",
        "Credential": "",
        "AllowedUses": ""
    }
};

// Schema for Device.LocalAgent.ControllerTrust.Role.{i}.
export const ControllerTrust_Role = {
    path: "Device.LocalAgent.ControllerTrust.Role.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "PermissionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Name": "",
        "PermissionNumberOfEntries": "0"
    }
};

// Schema for Device.LocalAgent.Monitor.{i}.
export const Monitor = {
    path: "Device.LocalAgent.Monitor.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Interval": dm_type.UINT | dm_type.WRITABLE,
        "ReferenceList": dm_type.STRING | dm_type.WRITABLE,
        "Controller": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Interval": "0",
        "ReferenceList": "",
        "Controller": ""
    }
};

// Schema for Device.LocalAgent.Controller.{i}.MTP.{i}.WebSocket.
export const MTP_WebSocket = {
    path: "Device.LocalAgent.Controller.{i}.MTP.{i}.WebSocket.",
    schema: {
        "Host": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Path": dm_type.STRING | dm_type.WRITABLE,
        "IsEncrypted": dm_type.BOOL,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE,
        "KeepAliveInterval": dm_type.UINT | dm_type.WRITABLE,
        "CurrentRetryCount": dm_type.UINT,
        "SessionRetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "SessionRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "USPServiceRef": dm_type.STRING
    },
    defaults: {
        "Host": "",
        "Port": "0",
        "Path": "",
        "EnableEncryption": "true",
        "KeepAliveInterval": "0",
        "CurrentRetryCount": "0",
        "SessionRetryMinimumWaitInterval": "5",
        "SessionRetryIntervalMultiplier": "2000",
        "USPServiceRef": ""
    }
};

// Schema for Device.LocalAgent.Watchdog.{i}.
export const Watchdog = {
    path: "Device.LocalAgent.Watchdog.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ReloadTimerValue": dm_type.UINT | dm_type.WRITABLE,
        "RemainingTimerValue": dm_type.UINT,
        "Status": dm_type.STRING,
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "SeverityIndication": dm_type.STRING | dm_type.WRITABLE,
        "Controller": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "ReloadTimerValue": "0",
        "RemainingTimerValue": "0",
        "Status": "Inactive",
        "Reference": "",
        "SeverityIndication": "Info",
        "Controller": ""
    }
};

// Schema for Device.LocalAgent.Controller.{i}.BootParameter.{i}.
export const Controller_BootParameter = {
    path: "Device.LocalAgent.Controller.{i}.BootParameter.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ParameterName": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "ParameterName": ""
    }
};

// Schema for Device.LocalAgent.Controller.{i}.
export const Controller = {
    path: "Device.LocalAgent.Controller.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "EndpointID": dm_type.STRING | dm_type.WRITABLE,
        "ControllerCode": dm_type.STRING | dm_type.WRITABLE,
        "ProvisioningCode": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "AssignedRole": dm_type.STRING | dm_type.WRITABLE,
        "InheritedRole": dm_type.STRING,
        "Credential": dm_type.STRING | dm_type.WRITABLE,
        "PeriodicNotifInterval": dm_type.UINT | dm_type.WRITABLE,
        "PeriodicNotifTime": dm_type.DATETIME | dm_type.WRITABLE,
        "USPNotifRetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "USPNotifRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "MTPNumberOfEntries": dm_type.UINT,
        "BootParameterNumberOfEntries": dm_type.UINT,
        "OnBoardingComplete": dm_type.BOOL | dm_type.WRITABLE,
        "OnBoardingRestartTime": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "EndpointID": "",
        "ControllerCode": "",
        "ProvisioningCode": "",
        "Enable": "false",
        "AssignedRole": "",
        "InheritedRole": "",
        "Credential": "",
        "PeriodicNotifInterval": "0",
        "USPNotifRetryMinimumWaitInterval": "5",
        "USPNotifRetryIntervalMultiplier": "2000",
        "MTPNumberOfEntries": "0",
        "BootParameterNumberOfEntries": "0",
        "OnBoardingComplete": "false",
        "OnBoardingRestartTime": "0"
    }
};

// Schema for Device.LocalAgent.MTP.{i}.
export const MTP = {
    path: "Device.LocalAgent.MTP.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "EnableMDNS": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Status": "",
        "Protocol": "",
        "EnableMDNS": "true"
    }
};

// Schema for Device.LocalAgent.Controller.{i}.E2ESession.
export const Controller_E2ESession = {
    path: "Device.LocalAgent.Controller.{i}.E2ESession.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SessionMode": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "SessionExpiration": dm_type.UINT | dm_type.WRITABLE,
        "SessionRetryMinimumWaitInterval": dm_type.UINT | dm_type.WRITABLE,
        "SessionRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "CurrentRetryCount": dm_type.UINT,
        "SegmentedPayloadChunkSize": dm_type.UINT | dm_type.WRITABLE,
        "MaxUSPRecordSize": dm_type.UINT | dm_type.WRITABLE,
        "MaxRetransmitTries": dm_type.INT | dm_type.WRITABLE,
        "PayloadSecurity": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "SessionMode": "",
        "Status": "",
        "SessionExpiration": "0",
        "SessionRetryMinimumWaitInterval": "5",
        "SessionRetryIntervalMultiplier": "2000",
        "CurrentRetryCount": "0",
        "SegmentedPayloadChunkSize": "0",
        "MaxUSPRecordSize": "0",
        "MaxRetransmitTries": "0",
        "PayloadSecurity": "TLS"
    }
};

// Schema for Device.LocalAgent.Controller.{i}.MTP.{i}.MQTT.
export const MTP_MQTT = {
    path: "Device.LocalAgent.Controller.{i}.MTP.{i}.MQTT.",
    schema: {
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "Topic": dm_type.STRING | dm_type.WRITABLE,
        "PublishRetainResponse": dm_type.BOOL | dm_type.WRITABLE,
        "PublishRetainNotify": dm_type.BOOL | dm_type.WRITABLE,
        "AgentMTPReference": dm_type.STRING | dm_type.WRITABLE,
        "USPServiceRef": dm_type.STRING
    },
    defaults: {
        "Reference": "",
        "Topic": "",
        "PublishRetainResponse": "false",
        "PublishRetainNotify": "false",
        "AgentMTPReference": "",
        "USPServiceRef": ""
    }
};

// Schema for Device.LocalAgent.
export const LocalAgent = {
    path: "Device.LocalAgent.",
    schema: {
        "SupportedThresholdOperator": dm_type.STRING,
        "ThresholdNumberOfEntries": dm_type.UINT,
        "WatchdogNumberOfEntries": dm_type.UINT,
        "SubscriptionNumberOfEntries": dm_type.UINT,
        "RequestNumberOfEntries": dm_type.UINT,
        "MonitorNumberOfEntries": dm_type.UINT,
        "SupportedNumberOfSubscriptions": dm_type.INT
    },
    defaults: {
        "SupportedThresholdOperator": "",
        "ThresholdNumberOfEntries": "0",
        "WatchdogNumberOfEntries": "0",
        "SubscriptionNumberOfEntries": "0",
        "RequestNumberOfEntries": "0",
        "MonitorNumberOfEntries": "0",
        "SupportedNumberOfSubscriptions": "-1"
    }
};

// Schema for Device.LocalAgent.Subscription.{i}.
export const Subscription = {
    path: "Device.LocalAgent.Subscription.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Recipient": dm_type.STRING,
        "TriggerAction": dm_type.STRING | dm_type.WRITABLE,
        "TriggerConfigSettings": dm_type.STRING | dm_type.WRITABLE,
        "ID": dm_type.STRING | dm_type.WRITABLE,
        "CreationDate": dm_type.DATETIME,
        "NotifType": dm_type.STRING | dm_type.WRITABLE,
        "ReferenceList": dm_type.STRING | dm_type.WRITABLE,
        "Persistent": dm_type.BOOL | dm_type.WRITABLE,
        "TimeToLive": dm_type.UINT | dm_type.WRITABLE,
        "NotifRetry": dm_type.BOOL | dm_type.WRITABLE,
        "NotifExpiration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Recipient": "",
        "TriggerAction": "Notify",
        "TriggerConfigSettings": "",
        "ID": "",
        "NotifType": "",
        "ReferenceList": "",
        "Persistent": "false",
        "TimeToLive": "0",
        "NotifRetry": "false",
        "NotifExpiration": "0"
    }
};

// Schema for Device.LocalAgent.Controller.{i}.TransferCompletePolicy.
export const Controller_TransferCompletePolicy = {
    path: "Device.LocalAgent.Controller.{i}.TransferCompletePolicy.",
    schema: {
        "ResultTypeFilter": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "ResultTypeFilter": ""
    }
};

// Schema for Device.LocalAgent.Request.{i}.
export const Request = {
    path: "Device.LocalAgent.Request.{i}.",
    schema: {
        "Originator": dm_type.STRING,
        "Command": dm_type.STRING,
        "CommandKey": dm_type.STRING,
        "Status": dm_type.STRING
    },
    defaults: {
        "Originator": "",
        "Command": "",
        "CommandKey": "",
        "Status": ""
    }
};

// Schema for Device.LocalAgent.ControllerTrust.Role.{i}.Permission.{i}.
export const Role_Permission = {
    path: "Device.LocalAgent.ControllerTrust.Role.{i}.Permission.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Targets": dm_type.STRING | dm_type.WRITABLE,
        "Param": dm_type.STRING | dm_type.WRITABLE,
        "Obj": dm_type.STRING | dm_type.WRITABLE,
        "InstantiatedObj": dm_type.STRING | dm_type.WRITABLE,
        "CommandEvent": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Order": "0",
        "Targets": "[]",
        "Param": "----",
        "Obj": "----",
        "InstantiatedObj": "----",
        "CommandEvent": "----"
    }
};

// Schema for Device.LocalAgent.Certificate.{i}.
export const Certificate = {
    path: "Device.LocalAgent.Certificate.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SerialNumber": dm_type.STRING,
        "Issuer": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "SerialNumber": "",
        "Issuer": ""
    }
};

// Schema for Device.LocalAgent.ControllerTrust.
export const ControllerTrust = {
    path: "Device.LocalAgent.ControllerTrust.",
    schema: {
        "UntrustedRole": dm_type.STRING | dm_type.WRITABLE,
        "BannedRole": dm_type.STRING | dm_type.WRITABLE,
        "SecuredRoles": dm_type.STRING | dm_type.WRITABLE,
        "TOFUAllowed": dm_type.BOOL | dm_type.WRITABLE,
        "TOFUInactivityTimer": dm_type.UINT | dm_type.WRITABLE,
        "RoleNumberOfEntries": dm_type.UINT,
        "CredentialNumberOfEntries": dm_type.UINT,
        "ChallengeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "UntrustedRole": "",
        "BannedRole": "",
        "SecuredRoles": "",
        "TOFUInactivityTimer": "0",
        "RoleNumberOfEntries": "0",
        "CredentialNumberOfEntries": "0",
        "ChallengeNumberOfEntries": "0"
    }
};
