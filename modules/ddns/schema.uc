'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

schemas.Server = {
    path: "Device.DynamicDNS.Server.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "ServiceName": dm_type.STRING | dm_type.WRITABLE,
        "ServerAddress": dm_type.STRING | dm_type.WRITABLE,
        "ServerPort": dm_type.UINT | dm_type.WRITABLE,
        "SupportedProtocols": dm_type.STRING,
        "Protocol": dm_type.STRING | dm_type.WRITABLE,
        "CheckInterval": dm_type.UINT | dm_type.WRITABLE,
        "RetryInterval": dm_type.UINT | dm_type.WRITABLE,
        "MaxRetries": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Name": "",
        "Alias": "",
        "ServiceName": "",
        "ServerAddress": "",
        "ServerPort": "0",
        "SupportedProtocols": "HTTP,HTTPS",
        "Protocol": "HTTPS",
        "CheckInterval": "0",
        "RetryInterval": "0",
        "MaxRetries": "0"
    },
    constraints: {
        "Name": { max_length: 64 },
        "ServiceName": { max_length: 256 },
        "ServerAddress": { max_length: 256 },
        "ServerPort": { min: 0, max: 65535 },
        "Protocol": { enum: [ "HTTP", "HTTPS" ] }
    }
};

schemas.DynamicDNS = {
    path: "Device.DynamicDNS.",
    schema: {
        "ClientNumberOfEntries": dm_type.UINT,
        "ServerNumberOfEntries": dm_type.UINT,
        "SupportedServices": dm_type.STRING
    },
    defaults: {
        "ClientNumberOfEntries": "0",
        "ServerNumberOfEntries": "0",
        "SupportedServices": ""
    }
};

schemas.Client_Hostname = {
    path: "Device.DynamicDNS.Client.{i}.Hostname.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Name": dm_type.STRING | dm_type.WRITABLE,
        "LastUpdate": dm_type.DATETIME
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Name": "",
        "LastUpdate": "0001-01-01T00:00:00Z"
    },
    constraints: {
        "Status": { enum: [ "Registered", "UpdateNeeded", "Updating", "Error", "Disabled" ] },
        "Name": { max_length: 256 }
    }
};

schemas.Client = {
    path: "Device.DynamicDNS.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "LastError": dm_type.STRING,
        "Server": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Username": dm_type.STRING | dm_type.WRITABLE,
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "HostnameNumberOfEntries": dm_type.UINT,
        "IPVersion": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "LastError": "NO_ERROR",
        "Server": "",
        "Interface": "",
        "Username": "",
        "Password": "",
        "HostnameNumberOfEntries": "0",
        "IPVersion": "-1"
    },
    since: {
        "IPVersion": "2.21"
    },
    constraints: {
        "Status": { enum: [ "Connecting", "Authenticating", "Updated", "Error_Misconfigured", "Error", "Disabled" ] },
        "LastError": {
            enum: [ "NO_ERROR", "MISCONFIGURATION_ERROR", "DNS_ERROR", "CONNECTION_ERROR", "AUTHENTICATION_ERROR",
                    "TIMEOUT_ERROR", "PROTOCOL_ERROR" ]
        },
        "Server": { max_length: 256 },
        "Interface": { max_length: 256 },
        "Username": { max_length: 256 },
        "Password": { secured: true, max_length: 256 },
        "IPVersion": { ranges: [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ] }
    }
};
