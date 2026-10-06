'use strict';

// Auto-generated schema definitions for DNS domain
// Generated from TR-181 specifications

// Schema for Device.DNS.SD.Service.{i}.
export const SD_Service = {
    path: "Device.DNS.SD.Service.{i}.",
    schema: {
        "InstanceName": dm_type.STRING,
        "ApplicationProtocol": dm_type.STRING,
        "TransportProtocol": dm_type.STRING,
        "Domain": dm_type.STRING,
        "Port": dm_type.UINT,
        "Target": dm_type.STRING,
        "Status": dm_type.STRING,
        "LastUpdate": dm_type.DATETIME,
        "Host": dm_type.STRING,
        "TimeToLive": dm_type.UINT,
        "Priority": dm_type.UINT,
        "Weight": dm_type.UINT,
        "TextRecordNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InstanceName": "",
        "ApplicationProtocol": "",
        "TransportProtocol": "",
        "Domain": "",
        "Port": "0",
        "Target": "",
        "Status": "",
        "Host": "",
        "TimeToLive": "0",
        "Priority": "0",
        "Weight": "0",
        "TextRecordNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Zone.{i}.
export const Zone = {
    path: "Device.DNS.Zone.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "HostNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Origin": "System",
        "Interface": "",
        "HostNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Relay.
export const Relay = {
    path: "Device.DNS.Relay.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ConfigNumberOfEntries": dm_type.UINT,
        "ForwardNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ConfigNumberOfEntries": "0",
        "ForwardNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.SD.Advertise.{i}.
export const SD_Advertise = {
    path: "Device.DNS.SD.Advertise.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Status": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "InstanceName": dm_type.STRING | dm_type.WRITABLE,
        "ApplicationProtocol": dm_type.STRING | dm_type.WRITABLE,
        "TransportProtocol": dm_type.STRING | dm_type.WRITABLE,
        "Domain": dm_type.STRING | dm_type.WRITABLE,
        "Port": dm_type.UINT | dm_type.WRITABLE,
        "TextRecordNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Status": "Disabled",
        "Interface": "",
        "InstanceName": "",
        "ApplicationProtocol": "",
        "TransportProtocol": "",
        "Domain": "local",
        "Port": "0",
        "TextRecordNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Client.Server.{i}.
export const Client_Server = {
    path: "Device.DNS.Client.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "DNSServer": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "DNSServer": "",
        "Interface": "",
        "Type": "Static"
    }
};

// Schema for Device.DNS.Client.
export const Client = {
    path: "Device.DNS.Client.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ServerNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ServerNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.Relay.Config.{i}.
export const Relay_Config = {
    path: "Device.DNS.Relay.Config.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Forwarders": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "CacheSize": dm_type.UINT,
        "CacheMinTTL": dm_type.UINT,
        "CacheMaxTTL": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Forwarders": "[]",
        "Interface": "",
        "CacheSize": "0",
        "CacheMinTTL": "0",
        "CacheMaxTTL": "86400"
    }
};

// Schema for Device.DNS.SD.
export const SD = {
    path: "Device.DNS.SD.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "AdvertiseNumberOfEntries": dm_type.UINT,
        "ServiceNumberOfEntries": dm_type.UINT,
        "AdvertisedInterfaces": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Status": "",
        "AdvertiseNumberOfEntries": "0",
        "ServiceNumberOfEntries": "0",
        "AdvertisedInterfaces": ""
    }
};

// Schema for Device.DNS.SD.Advertise.{i}.TextRecord.{i}.
export const Advertise_TextRecord = {
    path: "Device.DNS.SD.Advertise.{i}.TextRecord.{i}.",
    schema: {
        "Key": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Key": "",
        "Value": ""
    }
};

// Schema for Device.DNS.
export const DNS = {
    path: "Device.DNS.",
    schema: {
        "SupportedRecordTypes": dm_type.STRING,
        "ZoneNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupportedRecordTypes": "",
        "ZoneNumberOfEntries": "0"
    }
};

// Schema for Device.DNS.SD.Service.{i}.TextRecord.{i}.
export const Service_TextRecord = {
    path: "Device.DNS.SD.Service.{i}.TextRecord.{i}.",
    schema: {
        "Key": dm_type.STRING,
        "Value": dm_type.STRING
    },
    defaults: {
        "Key": "",
        "Value": ""
    }
};

// Schema for Device.DNS.Relay.Forwarding.{i}.
export const Relay_Forwarding = {
    path: "Device.DNS.Relay.Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "DNSServer": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Type": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "DNSServer": "",
        "Interface": "",
        "Type": "Static"
    }
};

// Schema for Device.DNS.Zone.{i}.Host.{i}.
export const Zone_Host = {
    path: "Device.DNS.Zone.{i}.Host.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "Host": dm_type.STRING | dm_type.WRITABLE,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Origin": "System",
        "Host": ""
    }
};
