'use strict';

// Auto-generated schema definitions for DHCPv6 domain
// Generated from TR-181 specifications

// Schema for Device.DHCPv6.Server.Pool.{i}.Client.{i}.Option.{i}.
export const Client_Option = {
    path: "Device.DHCPv6.Server.Pool.{i}.Client.{i}.Option.{i}.",
    schema: {
        "Tag": dm_type.UINT,
        "Value": dm_type.HEXBIN
    },
    defaults: {
        "Tag": "0"
    }
};

// Schema for Device.DHCPv6.Server.
export const Server = {
    path: "Device.DHCPv6.Server.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "PoolNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "PoolNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv6.Client.{i}.Server.{i}.
export const Client_Server = {
    path: "Device.DHCPv6.Client.{i}.Server.{i}.",
    schema: {
        "SourceAddress": dm_type.STRING,
        "DUID": dm_type.HEXBIN,
        "InformationRefreshTime": dm_type.DATETIME
    },
    defaults: {
        "SourceAddress": ""
    }
};

// Schema for Device.DHCPv6.Server.Stats.
export const Server_Stats = {
    path: "Device.DHCPv6.Server.Stats.",
    schema: {
        "Solicit": dm_type.STRING,
        "Advertise": dm_type.STRING,
        "Request": dm_type.STRING,
        "Confirm": dm_type.STRING,
        "Renew": dm_type.STRING,
        "Rebind": dm_type.STRING,
        "Reply": dm_type.STRING,
        "Release": dm_type.STRING,
        "Decline": dm_type.STRING,
        "Reconfigure": dm_type.STRING,
        "InformationRequest": dm_type.STRING,
        "RelayForward": dm_type.STRING,
        "RelayReply": dm_type.STRING,
        "DiscardedPackets": dm_type.STRING,
        "TransmitFailure": dm_type.STRING,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Solicit": "",
        "Advertise": "",
        "Request": "",
        "Confirm": "",
        "Renew": "",
        "Rebind": "",
        "Reply": "",
        "Release": "",
        "Decline": "",
        "Reconfigure": "",
        "InformationRequest": "",
        "RelayForward": "",
        "RelayReply": "",
        "DiscardedPackets": "",
        "TransmitFailure": ""
    }
};

// Schema for Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Prefix.{i}.
export const Client_IPv6Prefix = {
    path: "Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Prefix.{i}.",
    schema: {
        "Prefix": dm_type.STRING,
        "PreferredLifetime": dm_type.DATETIME,
        "ValidLifetime": dm_type.DATETIME
    },
    defaults: {
        "Prefix": ""
    }
};

// Schema for Device.DHCPv6.Client.{i}.Stats.
export const Client_Stats = {
    path: "Device.DHCPv6.Client.{i}.Stats.",
    schema: {
        "Solicit": dm_type.STRING,
        "Advertise": dm_type.STRING,
        "Request": dm_type.STRING,
        "Confirm": dm_type.STRING,
        "Renew": dm_type.STRING,
        "Rebind": dm_type.STRING,
        "Reply": dm_type.STRING,
        "Release": dm_type.STRING,
        "Decline": dm_type.STRING,
        "Reconfigure": dm_type.STRING,
        "InformationRequest": dm_type.STRING,
        "DiscardedPackets": dm_type.STRING,
        "TransmitFailure": dm_type.STRING,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "Solicit": "",
        "Advertise": "",
        "Request": "",
        "Confirm": "",
        "Renew": "",
        "Rebind": "",
        "Reply": "",
        "Release": "",
        "Decline": "",
        "Reconfigure": "",
        "InformationRequest": "",
        "DiscardedPackets": "",
        "TransmitFailure": ""
    }
};

// Schema for Device.DHCPv6.Client.{i}.
export const Client = {
    path: "Device.DHCPv6.Client.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "DUID": dm_type.HEXBIN,
        "RequestAddresses": dm_type.BOOL | dm_type.WRITABLE,
        "RequestPrefixes": dm_type.BOOL | dm_type.WRITABLE,
        "RapidCommit": dm_type.BOOL | dm_type.WRITABLE,
        "SuggestedT1": dm_type.INT | dm_type.WRITABLE,
        "SuggestedT2": dm_type.INT | dm_type.WRITABLE,
        "SupportedOptions": dm_type.UINT,
        "RequestedOptions": dm_type.STRING | dm_type.WRITABLE,
        "AuthenticationProtocol": dm_type.STRING | dm_type.WRITABLE,
        "DSCPMark": dm_type.UINT | dm_type.WRITABLE,
        "ServerNumberOfEntries": dm_type.UINT,
        "SentOptionNumberOfEntries": dm_type.UINT,
        "ReceivedOptionNumberOfEntries": dm_type.UINT,
        "Renew()": { type: 'sync', input: [] }
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Interface": "",
        "Status": "Disabled",
        "RequestAddresses": "true",
        "RequestPrefixes": "false",
        "RapidCommit": "false",
        "SuggestedT1": "0",
        "SuggestedT2": "0",
        "SupportedOptions": "0",
        "RequestedOptions": "",
        "AuthenticationProtocol": "None",
        "DSCPMark": "48",
        "ServerNumberOfEntries": "0",
        "SentOptionNumberOfEntries": "0",
        "ReceivedOptionNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv6.Client.{i}.ReceivedOption.{i}.
export const Client_ReceivedOption = {
    path: "Device.DHCPv6.Client.{i}.ReceivedOption.{i}.",
    schema: {
        "Tag": dm_type.UINT,
        "Value": dm_type.HEXBIN,
        "Server": dm_type.STRING
    },
    defaults: {
        "Tag": "0",
        "Server": ""
    }
};

// Schema for Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Address.{i}.
export const Client_IPv6Address = {
    path: "Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Address.{i}.",
    schema: {
        "IPAddress": dm_type.STRING,
        "PreferredLifetime": dm_type.DATETIME,
        "ValidLifetime": dm_type.DATETIME
    },
    defaults: {
        "IPAddress": ""
    }
};

// Schema for Device.DHCPv6.Server.Pool.{i}.
export const Server_Pool = {
    path: "Device.DHCPv6.Server.Pool.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Order": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "DUID": dm_type.HEXBIN | dm_type.WRITABLE,
        "DUIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "VendorClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        "VendorClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "UserClassID": dm_type.HEXBIN | dm_type.WRITABLE,
        "UserClassIDExclude": dm_type.BOOL | dm_type.WRITABLE,
        "SourceAddress": dm_type.STRING | dm_type.WRITABLE,
        "SourceAddressMask": dm_type.STRING | dm_type.WRITABLE,
        "SourceAddressExclude": dm_type.BOOL | dm_type.WRITABLE,
        "IANAEnable": dm_type.BOOL | dm_type.WRITABLE,
        "IANAManualPrefixes": dm_type.STRING | dm_type.WRITABLE,
        "IANAPrefixes": dm_type.STRING,
        "IAPDEnable": dm_type.BOOL | dm_type.WRITABLE,
        "IAPDManualPrefixes": dm_type.STRING | dm_type.WRITABLE,
        "IAPDPrefixes": dm_type.STRING,
        "IAPDAddLength": dm_type.UINT | dm_type.WRITABLE,
        "DSCPMark": dm_type.UINT | dm_type.WRITABLE,
        "ClientNumberOfEntries": dm_type.UINT,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Order": "",
        "Interface": "",
        "DUID": "",
        "DUIDExclude": "false",
        "VendorClassID": "",
        "VendorClassIDExclude": "false",
        "UserClassID": "",
        "UserClassIDExclude": "false",
        "SourceAddress": "",
        "SourceAddressMask": "",
        "SourceAddressExclude": "false",
        "IANAEnable": "false",
        "IANAManualPrefixes": "[]",
        "IANAPrefixes": "",
        "IAPDEnable": "false",
        "IAPDManualPrefixes": "[]",
        "IAPDPrefixes": "",
        "IAPDAddLength": "0",
        "DSCPMark": "48",
        "ClientNumberOfEntries": "0",
        "OptionNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv6.Client.{i}.Retransmission.
export const Client_Retransmission = {
    path: "Device.DHCPv6.Client.{i}.Retransmission.",
    schema: {
        "SolicitMaxDelay": dm_type.UINT,
        "SolicitInitialTimeout": dm_type.UINT,
        "SolicitMaxTimeout": dm_type.UINT | dm_type.WRITABLE,
        "RequestInitialTimeout": dm_type.UINT,
        "RequestMaxTimeout": dm_type.UINT,
        "RequestMaxRetry": dm_type.UINT,
        "ConfirmMaxDelay": dm_type.UINT,
        "ConfirmInitialTimeout": dm_type.UINT,
        "ConfirmMaxTimeout": dm_type.UINT,
        "ConfirmMaxDuration": dm_type.UINT,
        "RenewInitialTimeout": dm_type.UINT,
        "RenewMaxTimeout": dm_type.UINT,
        "RebindInitialTimeout": dm_type.UINT,
        "RebindMaxTimeout": dm_type.UINT,
        "InformationRequestMaxDelay": dm_type.UINT,
        "InformationRequestInitialTimeout": dm_type.UINT,
        "InformationRequestMaxTimeout": dm_type.UINT,
        "ReleaseInitialTimeout": dm_type.UINT,
        "ReleaseMaxAttempts": dm_type.UINT,
        "DeclineInitialTimeout": dm_type.UINT,
        "DeclineMaxAttempts": dm_type.UINT,
        "ReconfigureInitialTimeout": dm_type.UINT,
        "ReconfigureMaxAttempts": dm_type.UINT,
        "HopCountLimit": dm_type.UINT,
        "InformationRefreshTime": dm_type.UINT,
        "MinInformationRefreshTime": dm_type.UINT,
        "MaxWaitTime": dm_type.UINT,
        "TimeoutRandomize": dm_type.INT
    },
    defaults: {
        "SolicitMaxDelay": "1",
        "SolicitInitialTimeout": "1",
        "SolicitMaxTimeout": "3600",
        "RequestInitialTimeout": "1",
        "RequestMaxTimeout": "30",
        "RequestMaxRetry": "10",
        "ConfirmMaxDelay": "1",
        "ConfirmInitialTimeout": "1",
        "ConfirmMaxTimeout": "4",
        "ConfirmMaxDuration": "10",
        "RenewInitialTimeout": "10",
        "RenewMaxTimeout": "600",
        "RebindInitialTimeout": "10",
        "RebindMaxTimeout": "600",
        "InformationRequestMaxDelay": "1",
        "InformationRequestInitialTimeout": "1",
        "InformationRequestMaxTimeout": "3600",
        "ReleaseInitialTimeout": "1",
        "ReleaseMaxAttempts": "4",
        "DeclineInitialTimeout": "1",
        "DeclineMaxAttempts": "4",
        "ReconfigureInitialTimeout": "2",
        "ReconfigureMaxAttempts": "8",
        "HopCountLimit": "32",
        "InformationRefreshTime": "86400",
        "MinInformationRefreshTime": "600",
        "MaxWaitTime": "60",
        "TimeoutRandomize": "100"
    }
};

// Schema for Device.DHCPv6.Server.Pool.{i}.Client.{i}.
export const Pool_Client = {
    path: "Device.DHCPv6.Server.Pool.{i}.Client.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "SourceAddress": dm_type.STRING,
        "Active": dm_type.BOOL,
        "IPv6AddressNumberOfEntries": dm_type.UINT,
        "IPv6PrefixNumberOfEntries": dm_type.UINT,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "SourceAddress": "",
        "IPv6AddressNumberOfEntries": "0",
        "IPv6PrefixNumberOfEntries": "0",
        "OptionNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv6.Server.Pool.{i}.Option.{i}.
export const Pool_Option = {
    path: "Device.DHCPv6.Server.Pool.{i}.Option.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT | dm_type.WRITABLE,
        "Value": dm_type.HEXBIN | dm_type.WRITABLE,
        "PassthroughClient": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Alias": "",
        "Tag": "0",
        "Value": "",
        "PassthroughClient": ""
    }
};

// Schema for Device.DHCPv6.
export const DHCPv6 = {
    path: "Device.DHCPv6.",
    schema: {
        "ClientNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ClientNumberOfEntries": "0"
    }
};

// Schema for Device.DHCPv6.Client.{i}.SentOption.{i}.
export const Client_SentOption = {
    path: "Device.DHCPv6.Client.{i}.SentOption.{i}.",
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
