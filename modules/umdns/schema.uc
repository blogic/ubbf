'use strict';

// Schema definitions for the Device.DNS.SD domain.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.DNS.SD.
schemas.SD = {
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
    },
    until: {
        "AdvertisedInterfaces": "2.20"
    },
    constraints: {
        "AdvertisedInterfaces": { list: true }
    }
};

// Schema for Device.DNS.SD.Advertise.{i}.
schemas.SD_Advertise = {
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
    },
    constraints: {
        "Interface": { max_length: 256 },
        "InstanceName": { max_length: 63 },
        "ApplicationProtocol": { max_length: 15 },
        "TransportProtocol": { enum: [ "TCP", "UDP" ] },
        "Domain": { max_length: 256 },
        "Port": { max: 65535 }
    }
};

// Schema for Device.DNS.SD.Advertise.{i}.TextRecord.{i}.
schemas.Advertise_TextRecord = {
    path: "Device.DNS.SD.Advertise.{i}.TextRecord.{i}.",
    schema: {
        "Key": dm_type.STRING | dm_type.WRITABLE,
        "Value": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Key": "",
        "Value": ""
    },
    constraints: {
        "Key": { max_length: 255 },
        "Value": { max_length: 255 }
    }
};

// Schema for Device.DNS.SD.Service.{i}.
schemas.SD_Service = {
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
    },
    addable: false
};

// Schema for Device.DNS.SD.Service.{i}.TextRecord.{i}.
schemas.Service_TextRecord = {
    path: "Device.DNS.SD.Service.{i}.TextRecord.{i}.",
    schema: {
        "Key": dm_type.STRING,
        "Value": dm_type.STRING
    },
    defaults: {
        "Key": "",
        "Value": ""
    },
    addable: false
};
