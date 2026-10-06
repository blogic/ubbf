'use strict';

// Auto-generated schema definitions for Hosts domain
// Generated from TR-181 specifications

// Schema for Device.Hosts.Host.{i}.IPv4Address.{i}.
export const Host_IPv4Address = {
    path: "Device.Hosts.Host.{i}.IPv4Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING
    },
    defaults: {
        "IPAddress": ""
    }
};

// Schema for Device.Hosts.AccessControl.{i}.Schedule.{i}.
export const AccessControl_Schedule = {
    path: "Device.Hosts.AccessControl.{i}.Schedule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Day": dm_type.STRING | dm_type.WRITABLE,
        "StartTime": dm_type.STRING | dm_type.WRITABLE,
        "Duration": dm_type.UINT | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "Day": "",
        "StartTime": "",
        "Duration": "0"
    }
};

// Schema for Device.Hosts.AccessControl.{i}.
export const AccessControl = {
    path: "Device.Hosts.AccessControl.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Origin": dm_type.STRING,
        "PhysAddress": dm_type.STRING | dm_type.WRITABLE,
        "PhysAddressMask": dm_type.STRING | dm_type.WRITABLE,
        "HostName": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "AccessPolicy": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleRef": dm_type.STRING | dm_type.WRITABLE,
        "ScheduleNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Origin": "Controller",
        "PhysAddress": "",
        "PhysAddressMask": "",
        "HostName": "",
        "Enable": "false",
        "AccessPolicy": "Allow",
        "ScheduleRef": "[]",
        "ScheduleNumberOfEntries": "0"
    }
};

// Schema for Device.Hosts.Host.{i}.WANStats.
export const Host_WANStats = {
    path: "Device.Hosts.Host.{i}.WANStats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "RetransCount": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "RetransCount": "",
        "DiscardPacketsSent": ""
    }
};

// Schema for Device.Hosts.
export const Hosts = {
    path: "Device.Hosts.",
    schema: {
        "HostNumberOfEntries": dm_type.UINT,
        "AccessControlNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "HostNumberOfEntries": "0",
        "AccessControlNumberOfEntries": "0"
    }
};

// Schema for Device.Hosts.Host.{i}.
export const Host = {
    path: "Device.Hosts.Host.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "PhysAddress": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "AddressSource": dm_type.STRING,
        "DHCPClient": dm_type.STRING,
        "LeaseTimeRemaining": dm_type.INT,
        "AssociatedDevice": dm_type.STRING,
        "Layer1Interface": dm_type.STRING,
        "Layer3Interface": dm_type.STRING,
        "InterfaceType": dm_type.STRING,
        "VendorClassID": dm_type.STRING,
        "ClientID": dm_type.HEXBIN,
        "UserClassID": dm_type.HEXBIN,
        "HostName": dm_type.STRING,
        "Active": dm_type.BOOL,
        "ActiveLastChange": dm_type.DATETIME,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "IPv6AddressNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "PhysAddress": "",
        "IPAddress": "",
        "AddressSource": "",
        "DHCPClient": "",
        "LeaseTimeRemaining": "0",
        "AssociatedDevice": "",
        "Layer1Interface": "",
        "Layer3Interface": "",
        "InterfaceType": "",
        "VendorClassID": "",
        "ClientID": "",
        "UserClassID": "",
        "HostName": "",
        "ActiveLastChange": "",
        "IPv4AddressNumberOfEntries": "0",
        "IPv6AddressNumberOfEntries": "0"
    }
};

// Schema for Device.Hosts.Host.{i}.IPv6Address.{i}.
export const Host_IPv6Address = {
    path: "Device.Hosts.Host.{i}.IPv6Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING
    },
    defaults: {
        "IPAddress": ""
    }
};
