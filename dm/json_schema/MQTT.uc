'use strict';

// Auto-generated schema definitions for MQTT domain
// Generated from TR-181 specifications

// Schema for Device.MQTT.Broker.{i}.Bridge.{i}.Server.{i}.
export const Bridge_Server = {
    path: "Device.MQTT.Broker.{i}.Bridge.{i}.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Priority": dm_type.UINT | dm_type.WRITABLE,
        "Weight": dm_type.LONG | dm_type.WRITABLE,
        "Address": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Priority": "0",
        "Weight": "0",
        "Address": "",
        "Port": "1883"
    }
};

// Schema for Device.MQTT.
export const MQTT = {
    path: "Device.MQTT.",
    schema: {
        "ClientNumberOfEntries": dm_type.UINT,
        "BrokerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ClientNumberOfEntries": "0",
        "BrokerNumberOfEntries": "0"
    }
};

// Schema for Device.MQTT.Client.{i}.UserProperty.{i}.
export const Client_UserProperty = {
    path: "Device.MQTT.Client.{i}.UserProperty.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.STRING | dm_type.WRITABLE,
        "PacketType": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Value": "",
        "PacketType": ""
    }
};

// Schema for Device.MQTT.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.MQTT.Client.{i}.Stats.",
    schema: {
        "BrokerConnectionEstablished": dm_type.DATETIME,
        "LastPublishMessageSent": dm_type.DATETIME,
        "LastPublishMessageReceived": dm_type.DATETIME,
        "PublishSent": dm_type.STRING,
        "PublishReceived": dm_type.STRING,
        "SubscribeSent": dm_type.STRING,
        "UnSubscribeSent": dm_type.STRING,
        "MQTTMessagesSent": dm_type.STRING,
        "MQTTMessagesReceived": dm_type.STRING,
        "ConnectionErrors": dm_type.STRING,
        "PublishErrors": dm_type.STRING
    },
    defaults: {
        "PublishSent": "",
        "PublishReceived": "",
        "SubscribeSent": "",
        "UnSubscribeSent": "",
        "MQTTMessagesSent": "",
        "MQTTMessagesReceived": "",
        "ConnectionErrors": "",
        "PublishErrors": ""
    }
};

// Schema for Device.MQTT.Broker.{i}.Bridge.{i}.Subscription.{i}.
export const Bridge_Subscription = {
    path: "Device.MQTT.Broker.{i}.Bridge.{i}.Subscription.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Topic": dm_type.STRING | dm_type.WRITABLE,
        "Direction": dm_type.STRING | dm_type.WRITABLE,
        "QoS": dm_type.UINT | dm_type.WRITABLE,
        "LocalPrefix": dm_type.STRING | dm_type.WRITABLE,
        "RemotePrefix": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "Topic": "",
        "Direction": "",
        "QoS": "0",
        "LocalPrefix": "",
        "RemotePrefix": ""
    }
};

// Schema for Device.MQTT.Client.{i}.Subscription.{i}.
export const Client_Subscription = {
    path: "Device.MQTT.Client.{i}.Subscription.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Topic": dm_type.STRING | dm_type.WRITABLE,
        "QoS": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "Topic": "",
        "QoS": "0"
    }
};

// Schema for Device.MQTT.Client.{i}.
export const Client = {
    path: "Device.MQTT.Client.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "ProtocolVersion": dm_type.STRING | dm_type.WRITABLE,
        "EnableEncryption": dm_type.BOOL | dm_type.WRITABLE,
        "BrokerAddress": dm_type.STRING | dm_type.WRITABLE,
        "BrokerPort": dm_type.UINT | dm_type.WRITABLE,
        "TransportProtocol": dm_type.STRING | dm_type.WRITABLE,
        "CleanSession": dm_type.BOOL | dm_type.WRITABLE,
        "CleanStart": dm_type.BOOL | dm_type.WRITABLE,
        "WillEnable": dm_type.BOOL | dm_type.WRITABLE,
        "WillQoS": dm_type.UINT | dm_type.WRITABLE,
        "WillRetain": dm_type.BOOL | dm_type.WRITABLE,
        "KeepAliveTime": dm_type.UINT | dm_type.WRITABLE,
        "SessionExpiryInterval": dm_type.UINT | dm_type.WRITABLE,
        "ReceiveMaximum": dm_type.UINT | dm_type.WRITABLE,
        "MaximumPacketSize": dm_type.UINT | dm_type.WRITABLE,
        "TopicAliasMaximum": dm_type.UINT | dm_type.WRITABLE,
        "RequestResponseInfo": dm_type.BOOL | dm_type.WRITABLE,
        "RequestProblemInfo": dm_type.BOOL | dm_type.WRITABLE,
        "AuthenticationMethod": dm_type.STRING | dm_type.WRITABLE,
        "ALPN": dm_type.STRING | dm_type.WRITABLE,
        "ClientID": dm_type.STRING | dm_type.WRITABLE,
        "WillDelayInterval": dm_type.UINT | dm_type.WRITABLE,
        "WillMessageExpiryInterval": dm_type.UINT | dm_type.WRITABLE,
        "WillContentType": dm_type.STRING | dm_type.WRITABLE,
        "WillResponseTopic": dm_type.STRING | dm_type.WRITABLE,
        "WillTopic": dm_type.STRING | dm_type.WRITABLE,
        "WillValue": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "PublishMessageExpiryInterval": dm_type.UINT | dm_type.WRITABLE,
        "MessageRetryTime": dm_type.UINT | dm_type.WRITABLE,
        "ConnectRetryTime": dm_type.UINT | dm_type.WRITABLE,
        "ConnectRetryIntervalMultiplier": dm_type.UINT | dm_type.WRITABLE,
        "ConnectRetryMaxInterval": dm_type.UINT | dm_type.WRITABLE,
        "ResponseInformation": dm_type.STRING,
        "SubscriptionNumberOfEntries": dm_type.UINT,
        "UserPropertyNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Status": "",
        "Interface": "",
        "ProtocolVersion": "",
        "EnableEncryption": "true",
        "BrokerAddress": "",
        "BrokerPort": "1883",
        "TransportProtocol": "TCP/IP",
        "CleanSession": "true",
        "CleanStart": "true",
        "WillQoS": "0",
        "KeepAliveTime": "60",
        "SessionExpiryInterval": "0",
        "ReceiveMaximum": "0",
        "MaximumPacketSize": "0",
        "TopicAliasMaximum": "0",
        "AuthenticationMethod": "",
        "ALPN": "[]",
        "ClientID": "",
        "WillDelayInterval": "5",
        "WillMessageExpiryInterval": "0",
        "WillContentType": "",
        "WillResponseTopic": "",
        "WillTopic": "",
        "WillValue": "",
        "Username": "",
        "Password": "",
        "PublishMessageExpiryInterval": "0",
        "MessageRetryTime": "5",
        "ConnectRetryTime": "5",
        "ConnectRetryIntervalMultiplier": "2000",
        "ConnectRetryMaxInterval": "30720",
        "ResponseInformation": "",
        "SubscriptionNumberOfEntries": "0",
        "UserPropertyNumberOfEntries": "0"
    }
};

// Schema for Device.MQTT.Broker.{i}.Stats.
export const Broker_Stats = {
    path: "Device.MQTT.Broker.{i}.Stats.",
    schema: {
        "TotalNumberOfClients": dm_type.UINT,
        "NumberOfActiveClients": dm_type.UINT,
        "NumberOfInactiveClients": dm_type.UINT,
        "Subscriptions": dm_type.UINT,
        "PublishSent": dm_type.STRING,
        "PublishReceived": dm_type.STRING,
        "MQTTMessagesSent": dm_type.STRING,
        "MQTTMessagesReceived": dm_type.STRING,
        "ConnectionErrors": dm_type.STRING,
        "PublishErrors": dm_type.STRING
    },
    defaults: {
        "TotalNumberOfClients": "0",
        "NumberOfActiveClients": "0",
        "NumberOfInactiveClients": "0",
        "Subscriptions": "0",
        "PublishSent": "",
        "PublishReceived": "",
        "MQTTMessagesSent": "",
        "MQTTMessagesReceived": "",
        "ConnectionErrors": "",
        "PublishErrors": ""
    }
};

// Schema for Device.MQTT.Broker.{i}.
export const Broker = {
    path: "Device.MQTT.Broker.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "BridgeNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Status": "",
        "Port": "1883",
        "Interface": "",
        "Username": "",
        "Password": "",
        "BridgeNumberOfEntries": "0"
    }
};

// Schema for Device.MQTT.Broker.{i}.Bridge.{i}.
export const Broker_Bridge = {
    path: "Device.MQTT.Broker.{i}.Bridge.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ProtocolVersion": dm_type.STRING | dm_type.WRITABLE,
        "TransportProtocol": dm_type.STRING | dm_type.WRITABLE,
        "CleanSession": dm_type.BOOL | dm_type.WRITABLE,
        "CleanStart": dm_type.BOOL | dm_type.WRITABLE,
        "KeepAliveTime": dm_type.UINT | dm_type.WRITABLE,
        "ClientID": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "MessageRetryTime": dm_type.UINT | dm_type.WRITABLE,
        "ConnectRetryTime": dm_type.UINT | dm_type.WRITABLE,
        "ServerSelectionAlgorithm": dm_type.STRING | dm_type.WRITABLE,
        "ServerConnection": dm_type.STRING,
        "ServerNumberOfEntries": dm_type.UINT,
        "SubscriptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Status": "",
        "ProtocolVersion": "",
        "TransportProtocol": "TCP/IP",
        "CleanSession": "true",
        "CleanStart": "true",
        "KeepAliveTime": "60",
        "ClientID": "",
        "Username": "",
        "Password": "",
        "MessageRetryTime": "5",
        "ConnectRetryTime": "30",
        "ServerSelectionAlgorithm": "",
        "ServerConnection": "",
        "ServerNumberOfEntries": "0",
        "SubscriptionNumberOfEntries": "0"
    }
};

// Schema for Device.MQTT.Capabilities.
export const Capabilities = {
    path: "Device.MQTT.Capabilities.",
    schema: {
        "ProtocolVersionsSupported": dm_type.STRING,
        "TransportProtocolSupported": dm_type.STRING,
        "MaxNumberOfClientSubscriptions": dm_type.UINT,
        "MaxNumberOfBrokerBridges": dm_type.UINT,
        "MaxNumberOfBrokerBridgeSubscriptions": dm_type.UINT
    },
    defaults: {
        "ProtocolVersionsSupported": "",
        "TransportProtocolSupported": "",
        "MaxNumberOfClientSubscriptions": "0",
        "MaxNumberOfBrokerBridges": "0",
        "MaxNumberOfBrokerBridgeSubscriptions": "0"
    }
};
