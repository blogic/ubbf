'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.Security = {
    path: "Device.Security.",
    schema: {
        "CertificateNumberOfEntries": dm_type.UINT,
        "CABundleNumberOfEntries": dm_type.UINT,
        "SupportedBundleFormats": dm_type.STRING,
        "AddCertificateBundle()": {
            type: 'sync',
            input: ['Alias', 'Name', 'BundleFormat', 'Bundle'],
            output: ['Certificate']
        },
        "AddCABundle()": {
            type: 'sync',
            input: ['Name', 'Bundle'],
            output: ['CABundle', 'NumberOfCertificates']
        }
    },
    defaults: {
        "CertificateNumberOfEntries": "0",
        "CABundleNumberOfEntries": "0",
        "SupportedBundleFormats": "PEM"
    },
    since: {
        "SupportedBundleFormats": "2.21",
        "AddCertificateBundle()": "2.21",
        "AddCABundle()": "2.21"
    },
    constraints: {
        "SupportedBundleFormats": { list: true }
    }
};

schemas.Certificate = {
    path: "Device.Security.Certificate.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Enable": dm_type.BOOL,
        "LastModif": dm_type.DATETIME,
        "SerialNumber": dm_type.STRING,
        "Issuer": dm_type.STRING,
        "NotBefore": dm_type.DATETIME,
        "NotAfter": dm_type.DATETIME,
        "Subject": dm_type.STRING,
        "SubjectAlt": dm_type.STRING,
        "SignatureAlgorithm": dm_type.STRING,
        "GetCertificateURI()": { type: 'sync', input: [], output: ['CertificateURI', 'PrivateKeyURI'] },
        "Delete()": { type: 'sync', input: [], output: [] }
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Enable": "true",
        "SerialNumber": "",
        "Issuer": "",
        "Subject": "",
        "SubjectAlt": "",
        "SignatureAlgorithm": ""
    },
    since: {
        "Alias": "2.21",
        "Name": "2.21",
        "Delete()": "2.21"
    },
    addable: false
};

schemas.CABundle = {
    path: "Device.Security.CABundle.{i}.",
    schema: {
        "Enable": dm_type.BOOL,
        "Name": dm_type.STRING,
        "CACertificates": dm_type.STRING,
        "CADir()": { type: 'sync', input: [], output: ['CADir'] },
        "CAFile()": { type: 'sync', input: [], output: ['CAFile'] },
        "Update()": { type: 'sync', input: ['Bundle'], output: ['NumberOfCertificates'] },
        "Delete()": { type: 'sync', input: [], output: [] }
    },
    defaults: {
        "Enable": "true",
        "Name": "",
        "CACertificates": ""
    },
    since: {
        "Update()": "2.21",
        "Delete()": "2.21"
    },
    constraints: {
        "CACertificates": { list: true }
    },
    addable: false
};
