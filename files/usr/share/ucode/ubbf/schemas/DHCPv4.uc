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
        "Discover": dm_type.STRING,
        "Offer": dm_type.STRING,
        "Request": dm_type.STRING,
        "ACK": dm_type.STRING,
        "NACK": dm_type.STRING,
        "Decline": dm_type.STRING,
        "Release": dm_type.STRING,
        "Inform": dm_type.STRING,
        "ForceRenew": dm_type.STRING,
        "DiscardedPackets": dm_type.STRING,
        "TransmitFailure": dm_type.STRING,
        "RelayOptionDropped": dm_type.STRING,
        "SecondServerDetected": dm_type.STRING,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Discover": "",
        "Offer": "",
        "Request": "",
        "ACK": "",
        "NACK": "",
        "Decline": "",
        "Release": "",
        "Inform": "",
        "ForceRenew": "",
        "DiscardedPackets": "",
        "TransmitFailure": "",
        "RelayOptionDropped": "",
        "SecondServerDetected": ""
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
    }
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
        "Value": dm_type.HEXBIN | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Tag": "0",
        "Value": ""
    }
};

// Schema for Device.DHCPv4.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.DHCPv4.Client.{i}.Stats.",
    schema: {
        "Discover": dm_type.STRING,
        "Offer": dm_type.STRING,
        "Request": dm_type.STRING,
        "Decline": dm_type.STRING,
        "Release": dm_type.STRING,
        "Inform": dm_type.STRING,
        "ACK": dm_type.STRING,
        "NACK": dm_type.STRING,
        "ForceRenew": dm_type.STRING,
        "DiscardedPackets": dm_type.STRING,
        "TransmitFailure": dm_type.STRING,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Discover": "",
        "Offer": "",
        "Request": "",
        "Decline": "",
        "Release": "",
        "Inform": "",
        "ACK": "",
        "NACK": "",
        "ForceRenew": "",
        "DiscardedPackets": "",
        "TransmitFailure": ""
    }
};

// Schema for Device.DHCPv4.Client.{i}.ReqOption.{i}.
export const Client_ReqOption = {
    path: "Device.DHCPv4.Client.{i}.ReqOption.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Order": dm_type.STRING | dm_type.WRITABLE,
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
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.
export const Server_Pool = {
    path: "Device.DHCPv4.Server.Pool.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
//        "Order": dm_type.STRING | dm_type.WRITABLE,
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
//        "Order": "",
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
    }
};

// Schema for Device.DHCPv4.Relay.Forwarding.{i}.
export const Relay_Forwarding = {
    path: "Device.DHCPv4.Relay.Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
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
    }
};

// Schema for Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.
export const Pool_StaticAddress = {
    path: "Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Chaddr": dm_type.STRING | dm_type.WRITABLE,
        "Yiaddr": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Chaddr": "",
        "Yiaddr": ""
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
    }
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
        "Renew()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Interface": "",
        "Status": "Disabled",
        "DHCPStatus": "",
        "IPAddress": "",
        "SubnetMask": "",
        "IPRouters": "[]",
        "DNSServers": "[]",
        "LeaseTimeRemaining": "0",
        "DHCPServer": "",
        "PassthroughEnable": "false",
        "PassthroughDHCPPool": "",
        "AuthenticationProtocol": "None",
        "DSCPMark": "48",
        "SentOptionNumberOfEntries": "0",
        "ReqOptionNumberOfEntries": "0"
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
    }
};
