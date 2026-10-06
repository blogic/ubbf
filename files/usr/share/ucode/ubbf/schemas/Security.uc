'use strict';

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
        "Enable": "true",
        "SerialNumber": "",
        "Issuer": "",
        "Subject": "",
        "SubjectAlt": "",
        "SignatureAlgorithm": ""
    }
};

export const CABundle = {
    path: "Device.Security.CABundle.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING,
        "CACertificates": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "Name": "",
        "CACertificates": ""
    }
};
