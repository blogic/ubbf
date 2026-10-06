'use strict';

// Auto-generated schema definitions for DHCPv4 domain
// Generated from TR-181 specifications

// Schema for Device.DHCPv4.Relay.
export const Relay = {
    path: "Device.DHCPv4.Relay.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ForwardingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ForwardingNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv4.Server.
export const Server = {
    path: "Device.DHCPv4.Server.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "PoolNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "PoolNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv4.Server.Stats.
export const Server_Stats = {
    path: "Device.DHCPv4.Server.Stats.",
    schema: {
        "Discover": dm_type.ULONG,
        "Offer": dm_type.ULONG,
        "Request": dm_type.ULONG,
        "ACK": dm_type.ULONG,
        "NACK": dm_type.ULONG,
        "Decline": dm_type.ULONG,
        "Release": dm_type.ULONG,
        "Inform": dm_type.ULONG,
        "ForceRenew": dm_type.ULONG,
        "DiscardedPackets": dm_type.ULONG,
        "TransmitFailure": dm_type.ULONG,
        "RelayOptionDropped": dm_type.ULONG,
        "SecondServerDetected": dm_type.ULONG,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Discover": "18446744073709551615",
        "Offer": "18446744073709551615",
        "Request": "18446744073709551615",
        "ACK": "18446744073709551615",
        "NACK": "18446744073709551615",
        "Decline": "18446744073709551615",
        "Release": "18446744073709551615",
        "Inform": "18446744073709551615",
        "ForceRenew": "18446744073709551615",
        "DiscardedPackets": "18446744073709551615",
        "TransmitFailure": "18446744073709551615",
        "RelayOptionDropped": "18446744073709551615",
        "SecondServerDetected": "18446744073709551615"
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.Client.{i}.
export const Pool_Client = {
    path: "Device.DHCPv4.Server.Pool.{i}.Client.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Chaddr": dm_type.STRING,
        "Active": dm_type.BOOL,
        "IPv4AddressNumberOfEntries": dm_type.UINT,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Chaddr": "",
        "IPv4AddressNumberOfEntries": "0",
        "OptionNumberOfEntries": "0"
    },
    addable: false
};

// Schema for Device.DHCPv4.Client.{i}.Retransmission.
export const Client_Retransmission = {
    path: "Device.DHCPv4.Client.{i}.Retransmission.",
    schema: {
        "DiscoverInitialTimeout": dm_type.UINT | dm_type.WRITABLE,
        "DiscoverMaxTimeout": dm_type.UINT,
        "DiscoverMaxDuration": dm_type.UINT | dm_type.WRITABLE,
        "RequestInitialTimeout": dm_type.UINT,
        "RequestMaxTimeout": dm_type.UINT,
        "RequestMaxDuration": dm_type.UINT | dm_type.WRITABLE,
        "TimeoutRandomize": dm_type.INT
    },
    defaults: {
        "DiscoverInitialTimeout": "4",
        "DiscoverMaxTimeout": "64",
        "DiscoverMaxDuration": "0",
        "RequestInitialTimeout": "4",
        "RequestMaxTimeout": "64",
        "RequestMaxDuration": "0",
        "TimeoutRandomize": "1000"
    }
};

// Schema for Device.DHCPv4.
export const DHCPv4 = {
    path: "Device.DHCPv4.",
    schema: {
        "ClientNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ClientNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.Option.{i}.
export const Pool_Option = {
    path: "Device.DHCPv4.Server.Pool.{i}.Option.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN | dm_type.WRITABLE,
        "Force": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Tag": "0",
        "Value": "",
        "Force": "true"
    },
    since: {
        "Force": "2.21"
    },
    constraints: {
        "Tag": { min: 1, max: 254 },
        "Value": { min_length: 0, max_length: 255 }
    }
};

// Schema for Device.DHCPv4.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.DHCPv4.Client.{i}.Stats.",
    schema: {
        "Discover": dm_type.ULONG,
        "Offer": dm_type.ULONG,
        "Request": dm_type.ULONG,
        "Decline": dm_type.ULONG,
        "Release": dm_type.ULONG,
        "Inform": dm_type.ULONG,
        "ACK": dm_type.ULONG,
        "NACK": dm_type.ULONG,
        "ForceRenew": dm_type.ULONG,
        "DiscardedPackets": dm_type.ULONG,
        "TransmitFailure": dm_type.ULONG,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Discover": "18446744073709551615",
        "Offer": "18446744073709551615",
        "Request": "18446744073709551615",
        "Decline": "18446744073709551615",
        "Release": "18446744073709551615",
        "Inform": "18446744073709551615",
        "ACK": "18446744073709551615",
        "NACK": "18446744073709551615",
        "ForceRenew": "18446744073709551615",
        "DiscardedPackets": "18446744073709551615",
        "TransmitFailure": "18446744073709551615"
    }
};

// Schema for Device.DHCPv4.Client.{i}.ReqOption.{i}.
export const Client_ReqOption = {
    path: "Device.DHCPv4.Client.{i}.ReqOption.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN
    },
    defaults: {
        "Enable": "false",
        "Order": "",
        "Alias": "",
        "Tag": "0",
        "Value": ""
    },
    constraints: {
        "Order": { min: 1 },
        "Tag": { min: 1, max: 254 }
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.
export const Server_Pool = {
    path: "Device.DHCPv4.Server.Pool.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "VendorClassID": dm_type.STRING | dm_type.WRITABLE,
        "VendorClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "VendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "ClientID": dm_type.HEXBIN | dm_type.WRITABLE,
        "ClientIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "UserClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        "UserClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "Chaddr": dm_type.STRING | dm_type.WRITABLE,
        "ChaddrMask": dm_type.STRING | dm_type.WRITABLE,
        "ChaddrExclude": dm_type.BOOL | dm_type.WRITABLE,
        "MinAddress": dm_type.STRING | dm_type.WRITABLE,
        "MaxAddress": dm_type.STRING | dm_type.WRITABLE,
        "ReservedAddresses": dm_type.STRING | dm_type.WRITABLE,
        "SubnetMask": dm_type.STRING | dm_type.WRITABLE,
        "DNSServers": dm_type.STRING | dm_type.WRITABLE,
        "DomainName": dm_type.STRING | dm_type.WRITABLE,
        "IPRouters": dm_type.STRING | dm_type.WRITABLE,
//        "WINSServers": dm_type.STRING | dm_type.WRITABLE,
        "LeaseTime": dm_type.INT | dm_type.WRITABLE,
//        "DSCPMark": dm_type.UINT | dm_type.WRITABLE,
        "StaticAddressNumberOfEntries": dm_type.UINT,
        "OptionNumberOfEntries": dm_type.UINT,
        "ClientNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Order": "",
        "Interface": "",
        "VendorClassID": "",
        "VendorClassIDExclude": "false",
        "VendorClassIDMode": "Exact",
        "ClientID": "",
        "ClientIDExclude": "false",
        "UserClassID": "",
        "UserClassIDExclude": "false",
        "Chaddr": "",
        "ChaddrMask": "",
        "ChaddrExclude": "false",
//        "AllowedDevices": "",
        "MinAddress": "",
        "MaxAddress": "",
        "ReservedAddresses": "",
        "SubnetMask": "",
        "DNSServers": "",
        "DomainName": "",
        "IPRouters": "",
//        "WINSServers": "[]",
        "LeaseTime": "86400",
//        "DSCPMark": "48",
        "StaticAddressNumberOfEntries": "0",
        "OptionNumberOfEntries": "0",
        "ClientNumberOfEntries": "0"
    },
    constraints: {
        "Order": { min: 1 },
        "Interface": { max_length: 256 },
        "VendorClassID": { max_length: 255 },
        "VendorClassIDMode": { enum: [ "Exact", "Prefix", "Suffix", "Substring" ] },
        "Chaddr": { max_length: 17 },
        "ChaddrMask": { max_length: 17 },
        "MinAddress": { max_length: 15 },
        "MaxAddress": { max_length: 15 },
        "ReservedAddresses": { list: true, max_length: 15 },
        "SubnetMask": { max_length: 15 },
        "DNSServers": { list: true, max_length: 15 },
        "DomainName": { max_length: 64 },
        "IPRouters": { list: true, max_length: 15 },
        "LeaseTime": { min: -1 },
        "ClientID": { max_length: 255 },
        "UserClassID": { max_length: 255 }
    }
};

// Schema for Device.DHCPv4.Relay.Forwarding.{i}.
export const Relay_Forwarding = {
    path: "Device.DHCPv4.Relay.Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Order": dm_type.UINT | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "VendorClassID": dm_type.STRING | dm_type.WRITABLE,
        "VendorClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "VendorClassIDMode": dm_type.STRING | dm_type.WRITABLE,
        "ClientID": dm_type.HEXBIN | dm_type.WRITABLE,
        "ClientIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "UserClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        "UserClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "Chaddr": dm_type.STRING | dm_type.WRITABLE,
        "ChaddrMask": dm_type.STRING | dm_type.WRITABLE,
        "ChaddrExclude": dm_type.BOOL | dm_type.WRITABLE,
        "LocallyServed": dm_type.BOOL | dm_type.WRITABLE,
        "DHCPServerIPAddress": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Order": "",
        "Interface": "",
        "VendorClassID": "",
        "VendorClassIDExclude": "false",
        "VendorClassIDMode": "Exact",
        "ClientID": "",
        "ClientIDExclude": "false",
        "UserClassID": "",
        "UserClassIDExclude": "false",
        "Chaddr": "",
        "ChaddrMask": "",
        "ChaddrExclude": "false",
        "LocallyServed": "false",
        "DHCPServerIPAddress": ""
    },
    constraints: {
        "Order": { min: 1 },
        "Interface": { max_length: 256 },
        "VendorClassID": { max_length: 255 },
        "VendorClassIDMode": { enum: [ "Exact", "Prefix", "Suffix", "Substring" ] },
        "Chaddr": { max_length: 17 },
        "ChaddrMask": { max_length: 17 },
        "DHCPServerIPAddress": { max_length: 15 },
        "ClientID": { max_length: 255 },
        "UserClassID": { max_length: 255 }
    }
};

// Schema for Device.DHCPv4.Client.{i}.SentOption.{i}.
export const Client_SentOption = {
    path: "Device.DHCPv4.Client.{i}.SentOption.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Tag": "0",
        "Value": ""
    },
    constraints: {
        "Tag": { min: 1, max: 254 },
        "Value": { min_length: 0, max_length: 255 }
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.
export const Pool_StaticAddress = {
    path: "Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Chaddr": dm_type.STRING | dm_type.WRITABLE,
        "Yiaddr": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Chaddr": "",
        "Yiaddr": "",
        "Status": "Disabled"
    },
    since: {
        "Status": "2.21"
    },
    constraints: {
        "Chaddr": { max_length: 17 },
        "Yiaddr": { max_length: 15 }
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.Client.{i}.Option.{i}.
export const Client_Option = {
    path: "Device.DHCPv4.Server.Pool.{i}.Client.{i}.Option.{i}.",
    schema: {
        "Tag": dm_type.UINT,
        "Value": dm_type.HEXBIN
    },
    defaults: {
        "Tag": "0"
    },
    addable: false
};

// Schema for Device.DHCPv4.Client.{i}.
export const Client = {
    path: "Device.DHCPv4.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "DHCPStatus": dm_type.STRING,
        "IPAddress": dm_type.STRING,
        "SubnetMask": dm_type.STRING,
        "IPRouters": dm_type.STRING,
        "DNSServers": dm_type.STRING,
        "LeaseTimeRemaining": dm_type.INT,
        "DHCPServer": dm_type.STRING,
        "PassthroughEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PassthroughDHCPPool": dm_type.STRING | dm_type.WRITABLE,
        "AuthenticationProtocol": dm_type.STRING | dm_type.WRITABLE,
        "DSCPMark": dm_type.UINT | dm_type.WRITABLE,
        "SentOptionNumberOfEntries": dm_type.UINT,
        "ReqOptionNumberOfEntries": dm_type.UINT,
        "Renew()": { type: 'sync', input: [] },
        "Release()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Interface": "",
        "Status": "Disabled",
        "DHCPStatus": "",
        "IPAddress": "",
        "SubnetMask": "",
        "IPRouters": "",
        "DNSServers": "",
        "LeaseTimeRemaining": "0",
        "DHCPServer": "",
        "PassthroughEnable": "false",
        "PassthroughDHCPPool": "",
        "AuthenticationProtocol": "None",
        "DSCPMark": "48",
        "SentOptionNumberOfEntries": "0",
        "ReqOptionNumberOfEntries": "0"
    },
    since: {
        "Release()": "2.20"
    },
    constraints: {
        "Interface": { max_length: 256 },
        "PassthroughDHCPPool": { max_length: 256 },
        "AuthenticationProtocol": { enum: [ "None", "ConfigurationToken", "DelayedAuthentication" ] },
        "DSCPMark": { min: 0, max: 63 }
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.Client.{i}.IPv4Address.{i}.
export const Client_IPv4Address = {
    path: "Device.DHCPv4.Server.Pool.{i}.Client.{i}.IPv4Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING,
        "LeaseTimeRemaining": dm_type.DATETIME
    },
    defaults: {
        "IPAddress": ""
    },
    addable: false
};
