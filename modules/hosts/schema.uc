'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Commands that join the schema of Device.Hosts., which tr181/Hosts.uc owns.
schemas.Hosts_Commands = {
    schema: {
        "RemoveInactiveHosts()": {
            type: 'sync',
            input: [ 'MinimumInactiveTime' ],
            output: [ 'NumberOfRemovedHosts' ]
        }
    },
    since: {
        "RemoveInactiveHosts()": "2.20"
    }
};

// Schema for Device.Hosts.Host.{i}.IPv4Address.{i}.
schemas.Host_IPv4Address = {
    path: "Device.Hosts.Host.{i}.IPv4Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING
    },
    defaults: {
        "IPAddress": ""
    },
    addable: false
};

// Schema for Device.Hosts.Host.{i}.WANStats.
schemas.Host_WANStats = {
    path: "Device.Hosts.Host.{i}.WANStats.",
    schema: {
        "BytesSent": dm_type.ULONG,
        "BytesReceived": dm_type.ULONG,
        "PacketsSent": dm_type.ULONG,
        "PacketsReceived": dm_type.ULONG,
        "ErrorsSent": dm_type.UINT,
        "RetransCount": dm_type.UINT,
        "DiscardPacketsSent": dm_type.UINT
    },
    defaults: {
        "BytesSent": "18446744073709551615",
        "BytesReceived": "18446744073709551615",
        "PacketsSent": "18446744073709551615",
        "PacketsReceived": "18446744073709551615",
        "ErrorsSent": "4294967295",
        "RetransCount": "4294967295",
        "DiscardPacketsSent": "4294967295"
    }
};

// Schema for Device.Hosts.Host.{i}.
schemas.Host = {
    path: "Device.Hosts.Host.{i}.",
    schema: {
        "PhysAddress": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "DHCPClient": dm_type.STRING,
        "AssociatedDevice": dm_type.STRING,
        "Layer1Interface": dm_type.STRING,
        "Layer3Interface": dm_type.STRING,
        "InterfaceType": dm_type.STRING,
        "HostName": dm_type.STRING,
        "Active": dm_type.BOOL,
        "ActiveLastChange": dm_type.DATETIME,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "PhysAddress": "",
        "IPAddress": "",
        "DHCPClient": "",
        "AssociatedDevice": "",
        "Layer1Interface": "",
        "Layer3Interface": "",
        "InterfaceType": "",
        "HostName": "",
        "ActiveLastChange": "",
        "IPv4AddressNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0"
    },
    addable: false
};

// Schema for Device.Hosts.Host.{i}.IPv6Address.{i}.
schemas.Host_IPv6Address = {
    path: "Device.Hosts.Host.{i}.IPv6Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING
    },
    defaults: {
        "IPAddress": ""
    },
    addable: false
};
