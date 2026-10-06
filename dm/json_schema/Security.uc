'use strict';

// Auto-generated schema definitions for Security domain
// Generated from TR-181 specifications

// Schema for Device.Security.
export const Security = {
    path: "Device.Security.",
    schema: {
        "CertificateNumberOfEntries": dm_type.UINT,
        "CABundleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "CertificateNumberOfEntries": "0",
        "CABundleNumberOfEntries": "0"
    }
};

// Schema for Device.Security.CABundle.{i}.
export const CABundle = {
    path: "Device.Security.CABundle.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING,
        "CACertificates": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Name": "",
        "CACertificates": ""
    }
};

// Schema for Device.Security.Certificate.{i}.
export const Certificate = {
    path: "Device.Security.Certificate.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "LastModif": dm_type.DATETIME,
        "SerialNumber": dm_type.STRING,
        "Issuer": dm_type.STRING,
        "NotBefore": dm_type.DATETIME,
        "NotAfter": dm_type.DATETIME,
        "Subject": dm_type.STRING,
        "SubjectAlt": dm_type.STRING,
        "SignatureAlgorithm": dm_type.STRING
    },
    defaults: {
        "SerialNumber": "",
        "Issuer": "",
        "Subject": "",
        "SubjectAlt": "",
        "SignatureAlgorithm": ""
    }
};
