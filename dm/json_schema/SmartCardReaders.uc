'use strict';

// Auto-generated schema definitions for SmartCardReaders domain
// Generated from TR-181 specifications

// Schema for Device.SmartCardReaders.SmartCardReader.{i}.
export const SmartCardReader = {
    path: "Device.SmartCardReaders.SmartCardReader.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING,
        "ResetTime": dm_type.DATETIME,
        "DecryptionFailedCounter": dm_type.UINT,
        "DecryptionFailedNoKeyCounter": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Status": "",
        "Name": "",
        "DecryptionFailedCounter": "0",
        "DecryptionFailedNoKeyCounter": "0"
    }
};

// Schema for Device.SmartCardReaders.SmartCardReader.{i}.SmartCard.
export const SmartCardReader_SmartCard = {
    path: "Device.SmartCardReaders.SmartCardReader.{i}.SmartCard.",
    schema: {
        "Status": dm_type.STRING,
        "Type": dm_type.STRING,
        "Application": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "ATR": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Type": "",
        "Application": "",
        "SerialNumber": "",
        "ATR": ""
    }
};

// Schema for Device.SmartCardReaders.
export const SmartCardReaders = {
    path: "Device.SmartCardReaders.",
    schema: {
        "SmartCardReaderNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SmartCardReaderNumberOfEntries": "0"
    }
};
