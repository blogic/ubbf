'use strict';

// Auto-generated schema definitions for Controller domain
// Generated from TR-181 specifications

// Schema for Controller.{i}.MTP.{i}.UDS.
export const MTP_UDS = {
    path: "Controller.{i}.MTP.{i}.UDS.",
    schema: {
        "UnixDomainSocketRef": dm_type.STRING | dm_type.WRITABLE,
        "USPServiceRef": dm_type.STRING
    },
    defaults: {
        "UnixDomainSocketRef": "",
        "USPServiceRef": ""
    }
};

// Schema for Controller.{i}.MTP.{i}.
export const MTP = {
    path: "Controller.{i}.MTP.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Protocol": "",
        "Order": "0"
    }
};

// Schema for Controller.{i}.MTP.{i}.STOMP.
export const MTP_STOMP = {
    path: "Controller.{i}.MTP.{i}.STOMP.",
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

// Schema for Controller.{i}.
export const Controller = {
    path: "Controller.{i}.",
    schema: {
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
        "MTPNumberOfEntries": dm_type.UINT
    },
    defaults: {
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
        "MTPNumberOfEntries": "0"
    }
};

// Schema for Controller.{i}.MTP.{i}.WebSocket.
export const MTP_WebSocket = {
    path: "Controller.{i}.MTP.{i}.WebSocket.",
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

// Schema for Controller.{i}.MTP.{i}.MQTT.
export const MTP_MQTT = {
    path: "Controller.{i}.MTP.{i}.MQTT.",
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

// Schema for Controller.{i}.MTP.{i}.CoAP.
export const MTP_CoAP = {
    path: "Controller.{i}.MTP.{i}.CoAP.",
    schema: {
        "Host": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Path": dm_type.STRING | dm_type.WRITABLE,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Host": "",
        "Port": "0",
        "Path": "",
        "EnableEncryption": "true"
    }
};
