'use strict';

// Auto-generated schema definitions for MTP domain
// Generated from TR-181 specifications

// Schema for MTP.{i}.CoAP.
export const CoAP = {
    path: "MTP.{i}.CoAP.",
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

// Schema for MTP.{i}.MQTT.
export const MQTT = {
    path: "MTP.{i}.MQTT.",
    schema: {
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "ResponseTopicConfigured": dm_type.STRING | dm_type.WRITABLE,
        "ResponseTopicDiscovered": dm_type.STRING,
        "PublishQoS": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Reference": "",
        "ResponseTopicConfigured": "",
        "ResponseTopicDiscovered": "",
        "PublishQoS": "0"
    }
};

// Schema for MTP.{i}.UDS.
export const UDS = {
    path: "MTP.{i}.UDS.",
    schema: {
        "UnixDomainSocketRef": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "UnixDomainSocketRef": ""
    }
};

// Schema for MTP.{i}.WebSocket.
export const WebSocket = {
    path: "MTP.{i}.WebSocket.",
    schema: {
        "Interfaces": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Path": dm_type.STRING | dm_type.WRITABLE,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE,
        "KeepAliveInterval": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Interfaces": "",
        "Port": "8443",
        "Path": "",
        "EnableEncryption": "true",
        "KeepAliveInterval": "60"
    }
};

// Schema for MTP.{i}.STOMP.
export const STOMP = {
    path: "MTP.{i}.STOMP.",
    schema: {
        "Reference": dm_type.STRING | dm_type.WRITABLE,
        "Destination": dm_type.STRING | dm_type.WRITABLE,
        "DestinationFromServer": dm_type.STRING
    },
    defaults: {
        "Reference": "",
        "Destination": "",
        "DestinationFromServer": ""
    }
};

// Schema for MTP.{i}.
export const MTP = {
    path: "MTP.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "EnableMDNS": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "",
        "Protocol": "",
        "EnableMDNS": "true"
    }
};
