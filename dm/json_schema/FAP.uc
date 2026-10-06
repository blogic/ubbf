'use strict';

// Auto-generated schema definitions for FAP domain
// Generated from TR-181 specifications

// Schema for Device.FAP.ApplicationPlatform.Control.FemtoAwareness.
export const Control_FemtoAwareness = {
    path: "Device.FAP.ApplicationPlatform.Control.FemtoAwareness.",
    schema: {
        "APIEnable": dm_type.BOOL | dm_type.WRITABLE,
        "QueueEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Queueing": dm_type.STRING | dm_type.WRITABLE,
        "MaxAPIUsersNumber": dm_type.UINT | dm_type.WRITABLE,
        "FemtozoneID": dm_type.STRING | dm_type.WRITABLE,
        "NotificationsUserIdentifierMSISDN": dm_type.BOOL | dm_type.WRITABLE,
        "SubscribeToNotificationsResponseCallbackData": dm_type.BOOL | dm_type.WRITABLE,
        "QueryFemtocellResponseTimezone": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Queueing": "",
        "MaxAPIUsersNumber": "0",
        "FemtozoneID": ""
    }
};

// Schema for Device.FAP.PerfMgmt.Config.{i}.
export const PerfMgmt_Config = {
    path: "Device.FAP.PerfMgmt.Config.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "URL": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "PeriodicUploadInterval": dm_type.UINT | dm_type.WRITABLE,
        "PeriodicUploadTime": dm_type.DATETIME | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "URL": "",
        "Username": "",
        "Password": "",
        "PeriodicUploadInterval": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.
export const ApplicationPlatform = {
    path: "Device.FAP.ApplicationPlatform.",
    schema: {
        "Version": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "MaxNumberOfApplications": dm_type.UINT,
        "CurrentNumberofApplications": dm_type.UINT
    },
    defaults: {
        "Version": "",
        "Status": "",
        "MaxNumberOfApplications": "0",
        "CurrentNumberofApplications": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Control.TerminalLocation.
export const Control_TerminalLocation = {
    path: "Device.FAP.ApplicationPlatform.Control.TerminalLocation.",
    schema: {
        "APIEnable": dm_type.BOOL | dm_type.WRITABLE,
        "QueueEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Queueing": dm_type.STRING | dm_type.WRITABLE,
        "MaxAPIUsersNumber": dm_type.UINT | dm_type.WRITABLE,
        "QueryMobileLocationResponseAddress": dm_type.STRING | dm_type.WRITABLE,
        "QueryMobileLocationResponseLongitudeLatitude": dm_type.BOOL | dm_type.WRITABLE,
        "QueryMobileLocationResponseAltitude": dm_type.BOOL | dm_type.WRITABLE,
        "QueryMobileLocationResponseTimestamp": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Queueing": "",
        "MaxAPIUsersNumber": "0",
        "QueryMobileLocationResponseAddress": "",
        "QueryMobileLocationResponseTimestamp": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Capabilities.
export const ApplicationPlatform_Capabilities = {
    path: "Device.FAP.ApplicationPlatform.Capabilities.",
    schema: {
        "PresenceApplicationSupport": dm_type.BOOL,
        "FemtoAwarenessAPISupport": dm_type.BOOL,
        "SMSAPISupport": dm_type.BOOL,
        "SubscribeToNotificationsOfSMSSentToApplicationSupport": dm_type.BOOL,
        "QuerySMSDeliveryStatusSupport": dm_type.BOOL,
        "MMSAPISupport": dm_type.BOOL,
        "QueryMMSDeliveryStatusSupport": dm_type.BOOL,
        "SubscribeToNotificationsOfMMSSentToApplicationSupport": dm_type.BOOL,
        "TerminalLocationAPISupport": dm_type.BOOL,
        "AuthenticationMethodsSupported": dm_type.STRING,
        "AccessLevelsSupported": dm_type.STRING,
        "SendSMSTargetAddressType": dm_type.STRING,
        "SendMMSTargetAddressType": dm_type.STRING
    },
    defaults: {
        "AuthenticationMethodsSupported": "",
        "AccessLevelsSupported": "",
        "SendSMSTargetAddressType": "",
        "SendMMSTargetAddressType": ""
    }
};

// Schema for Device.FAP.ApplicationPlatform.Monitoring.SMS.
export const Monitoring_SMS = {
    path: "Device.FAP.ApplicationPlatform.Monitoring.SMS.",
    schema: {
        "APIAvailable": dm_type.BOOL,
        "APIUsers": dm_type.UINT,
        "QueueState": dm_type.STRING,
        "QueueNum": dm_type.UINT,
        "QueueReceived": dm_type.UINT,
        "QueueDiscarded": dm_type.UINT
    },
    defaults: {
        "APIUsers": "0",
        "QueueState": "",
        "QueueNum": "0",
        "QueueReceived": "0",
        "QueueDiscarded": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Monitoring.TerminalLocation.
export const Monitoring_TerminalLocation = {
    path: "Device.FAP.ApplicationPlatform.Monitoring.TerminalLocation.",
    schema: {
        "APIAvailable": dm_type.BOOL,
        "APIUsers": dm_type.UINT,
        "QueueState": dm_type.STRING,
        "QueueNum": dm_type.UINT,
        "QueueReceived": dm_type.UINT,
        "QueueDiscarded": dm_type.UINT
    },
    defaults: {
        "APIUsers": "0",
        "QueueState": "",
        "QueueNum": "0",
        "QueueReceived": "0",
        "QueueDiscarded": "0"
    }
};

// Schema for Device.FAP.PerfMgmt.
export const PerfMgmt = {
    path: "Device.FAP.PerfMgmt.",
    schema: {
        "ConfigNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ConfigNumberOfEntries": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Control.SMS.
export const Control_SMS = {
    path: "Device.FAP.ApplicationPlatform.Control.SMS.",
    schema: {
        "APIEnable": dm_type.BOOL | dm_type.WRITABLE,
        "QueueEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Queueing": dm_type.STRING | dm_type.WRITABLE,
        "MaxAPIUsersNumber": dm_type.UINT | dm_type.WRITABLE,
        "MinSendSMSTimeInterval": dm_type.UINT | dm_type.WRITABLE,
        "EnableQuerySMSDeliveryStatus": dm_type.BOOL | dm_type.WRITABLE,
        "EnableSubscribeToNotificationsOfMessageSentToApplication": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Queueing": "",
        "MaxAPIUsersNumber": "0",
        "MinSendSMSTimeInterval": "0"
    }
};

// Schema for Device.FAP.GPS.ContinuousGPSStatus.
export const GPS_ContinuousGPSStatus = {
    path: "Device.FAP.GPS.ContinuousGPSStatus.",
    schema: {
        "CurrentFix": dm_type.BOOL,
        "GotFix": dm_type.BOOL,
        "TimingGood": dm_type.BOOL,
        "Latitude": dm_type.INT,
        "Longitude": dm_type.INT,
        "Elevation": dm_type.INT,
        "LastFixTime": dm_type.DATETIME,
        "LastFixDuration": dm_type.UINT,
        "FirstFixTimeout": dm_type.INT | dm_type.WRITABLE,
        "SatellitesTracked": dm_type.UINT,
        "SatelliteTrackingInterval": dm_type.UINT | dm_type.WRITABLE,
        "ReceiverStatus": dm_type.STRING,
        "LocationType": dm_type.STRING,
        "LockTimeOutDuration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Latitude": "0",
        "Longitude": "0",
        "Elevation": "0",
        "LastFixDuration": "0",
        "FirstFixTimeout": "0",
        "SatellitesTracked": "0",
        "SatelliteTrackingInterval": "0",
        "ReceiverStatus": "",
        "LocationType": "",
        "LockTimeOutDuration": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Control.MMS.
export const Control_MMS = {
    path: "Device.FAP.ApplicationPlatform.Control.MMS.",
    schema: {
        "APIEnable": dm_type.BOOL | dm_type.WRITABLE,
        "QueueEnable": dm_type.BOOL | dm_type.WRITABLE,
        "Queueing": dm_type.STRING | dm_type.WRITABLE,
        "MaxAPIUsersNumber": dm_type.UINT | dm_type.WRITABLE,
        "MinSendMMSTimeInterval": dm_type.UINT | dm_type.WRITABLE,
        "EnableQueryMMSDeliveryStatus": dm_type.BOOL | dm_type.WRITABLE,
        "EnableSubscribeToNotificationsOfMessageSentToApplication": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Queueing": "",
        "MaxAPIUsersNumber": "0",
        "MinSendMMSTimeInterval": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Monitoring.FemtoAwareness.
export const Monitoring_FemtoAwareness = {
    path: "Device.FAP.ApplicationPlatform.Monitoring.FemtoAwareness.",
    schema: {
        "APIAvailable": dm_type.BOOL,
        "APIUsers": dm_type.UINT,
        "QueueState": dm_type.STRING,
        "QueueNum": dm_type.UINT,
        "QueueReceived": dm_type.UINT,
        "QueueDiscarded": dm_type.UINT
    },
    defaults: {
        "APIUsers": "0",
        "QueueState": "",
        "QueueNum": "0",
        "QueueReceived": "0",
        "QueueDiscarded": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Control.
export const ApplicationPlatform_Control = {
    path: "Device.FAP.ApplicationPlatform.Control.",
    schema: {
        "AuthenticationMethod": dm_type.STRING | dm_type.WRITABLE,
        "TunnelInst": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "AuthenticationMethod": "",
        "TunnelInst": ""
    }
};

// Schema for Device.FAP.GPS.AGPSServerConfig.
export const GPS_AGPSServerConfig = {
    path: "Device.FAP.GPS.AGPSServerConfig.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "ServerURL": dm_type.STRING | dm_type.WRITABLE,
        "ServerPort": dm_type.UINT | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "ReferenceLatitude": dm_type.INT | dm_type.WRITABLE,
        "ReferenceLongitude": dm_type.INT | dm_type.WRITABLE,
        "ServerInUse": dm_type.BOOL
    },
    defaults: {
        "ServerURL": "",
        "ServerPort": "0",
        "Username": "",
        "Password": "",
        "ReferenceLatitude": "0",
        "ReferenceLongitude": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Monitoring.
export const ApplicationPlatform_Monitoring = {
    path: "Device.FAP.ApplicationPlatform.Monitoring.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "MonitoringInterval": dm_type.UINT | dm_type.WRITABLE,
        "AuthenticationRequestsReceived": dm_type.UINT,
        "AuthenticationRequestsRejected": dm_type.UINT
    },
    defaults: {
        "MonitoringInterval": "0",
        "AuthenticationRequestsReceived": "0",
        "AuthenticationRequestsRejected": "0"
    }
};

// Schema for Device.FAP.ApplicationPlatform.Monitoring.MMS.
export const Monitoring_MMS = {
    path: "Device.FAP.ApplicationPlatform.Monitoring.MMS.",
    schema: {
        "APIAvailable": dm_type.BOOL,
        "APIUsers": dm_type.UINT,
        "QueueState": dm_type.STRING,
        "QueueNum": dm_type.UINT,
        "QueueReceived": dm_type.UINT,
        "QueueDiscarded": dm_type.UINT
    },
    defaults: {
        "APIUsers": "0",
        "QueueState": "",
        "QueueNum": "0",
        "QueueReceived": "0",
        "QueueDiscarded": "0"
    }
};

// Schema for Device.FAP.GPS.
export const GPS = {
    path: "Device.FAP.GPS.",
    schema: {
        "ScanOnBoot": dm_type.BOOL | dm_type.WRITABLE,
        "ScanPeriodically": dm_type.BOOL | dm_type.WRITABLE,
        "PeriodicInterval": dm_type.UINT | dm_type.WRITABLE,
        "PeriodicTime": dm_type.DATETIME | dm_type.WRITABLE,
        "ContinuousGPS": dm_type.BOOL | dm_type.WRITABLE,
        "ScanTimeout": dm_type.UINT | dm_type.WRITABLE,
        "ScanStatus": dm_type.STRING,
        "ErrorDetails": dm_type.STRING,
        "LastScanTime": dm_type.DATETIME,
        "LastSuccessfulScanTime": dm_type.DATETIME,
        "LockedLatitude": dm_type.INT,
        "LockedLongitude": dm_type.INT,
        "NumberOfSatellites": dm_type.UINT
    },
    defaults: {
        "ScanOnBoot": "true",
        "ScanPeriodically": "false",
        "PeriodicInterval": "0",
        "ScanTimeout": "0",
        "ScanStatus": "",
        "ErrorDetails": "",
        "LockedLatitude": "0",
        "LockedLongitude": "0",
        "NumberOfSatellites": "0"
    }
};
