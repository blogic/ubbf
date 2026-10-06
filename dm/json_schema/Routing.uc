'use strict';

// Auto-generated schema definitions for Routing domain
// Generated from TR-181 specifications

// Schema for Device.Routing.RIP.
export const RIP = {
    path: "Device.Routing.RIP.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SupportedModes": dm_type.STRING,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SupportedModes": "",
        "InterfaceSettingNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Router.{i}.IPv6Forwarding.{i}.
export const Router_IPv6Forwarding = {
    path: "Device.Routing.Router.{i}.IPv6Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "DestIPPrefix": dm_type.STRING | dm_type.WRITABLE,
        "ForwardingPolicy": dm_type.INT | dm_type.WRITABLE,
        "NextHop": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "ForwardingMetric": dm_type.INT | dm_type.WRITABLE,
        "ExpirationTime": dm_type.DATETIME
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Type": "Normal",
        "DestIPPrefix": "",
        "ForwardingPolicy": "-1",
        "NextHop": "",
        "Interface": "",
        "Origin": "Static",
        "ForwardingMetric": "-1",
        "ExpirationTime": "9999-12-31T23:59:59Z"
    }
};

// Schema for Device.Routing.Babel.
export const Babel = {
    path: "Device.Routing.Babel.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "ImplementationVersion": dm_type.STRING,
        "SelfRouterID": dm_type.HEXBIN,
        "SelfSeqno": dm_type.UINT,
        "SupportedMetricCompAlgorithms": dm_type.STRING,
        "SupportedSecurityMechanisms": dm_type.STRING,
        "SupportedMACAlgorithms": dm_type.STRING,
        "SupportedDTLSCertTypes": dm_type.STRING,
        "StatsEnable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT,
        "RouteNumberOfEntries": dm_type.UINT,
        "MACKeySetNumberOfEntries": dm_type.UINT,
        "DTLSCertSetNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "ImplementationVersion": "",
        "SelfSeqno": "0",
        "SupportedMetricCompAlgorithms": "",
        "SupportedSecurityMechanisms": "",
        "SupportedMACAlgorithms": "",
        "SupportedDTLSCertTypes": "",
        "InterfaceSettingNumberOfEntries": "0",
        "RouteNumberOfEntries": "0",
        "MACKeySetNumberOfEntries": "0",
        "DTLSCertSetNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Router.{i}.IPv4Forwarding.{i}.
export const Router_IPv4Forwarding = {
    path: "Device.Routing.Router.{i}.IPv4Forwarding.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Type": dm_type.STRING | dm_type.WRITABLE,
        "StaticRoute": dm_type.BOOL,
        "DestIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "DestSubnetMask": dm_type.STRING | dm_type.WRITABLE,
        "ForwardingPolicy": dm_type.INT | dm_type.WRITABLE,
        "GatewayIPAddress": dm_type.STRING | dm_type.WRITABLE,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "Origin": dm_type.STRING,
        "ForwardingMetric": dm_type.INT | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Type": "Normal",
        "StaticRoute": "true",
        "DestIPAddress": "",
        "DestSubnetMask": "",
        "ForwardingPolicy": "-1",
        "GatewayIPAddress": "",
        "Interface": "",
        "Origin": "Static",
        "ForwardingMetric": "-1"
    }
};

// Schema for Device.Routing.
export const Routing = {
    path: "Device.Routing.",
    schema: {
        "RouterNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "RouterNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Babel.InterfaceSetting.{i}.Stats.
export const InterfaceSetting_Stats = {
    path: "Device.Routing.Babel.InterfaceSetting.{i}.Stats.",
    schema: {
        "SentMcastHello": dm_type.STRING,
        "SentMcastUpdate": dm_type.STRING,
        "SentUcastHello": dm_type.STRING,
        "SentUcastUpdate": dm_type.STRING,
        "SentIHU": dm_type.STRING,
        "ReceivedPackets": dm_type.STRING
    },
    defaults: {
        "SentMcastHello": "",
        "SentMcastUpdate": "",
        "SentUcastHello": "",
        "SentUcastUpdate": "",
        "SentIHU": "",
        "ReceivedPackets": ""
    }
};

// Schema for Device.Routing.Babel.MACKeySet.{i}.MACKey.{i}.
export const MACKeySet_MACKey = {
    path: "Device.Routing.Babel.MACKeySet.{i}.MACKey.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "KeyUseSend": dm_type.BOOL | dm_type.WRITABLE,
        "KeyUseVerify": dm_type.BOOL | dm_type.WRITABLE,
        "KeyValue": dm_type.HEXBIN,
        "MACKeyAlgorithm": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "MACKeyAlgorithm": ""
    }
};

// Schema for Device.Routing.Babel.MACKeySet.{i}.
export const Babel_MACKeySet = {
    path: "Device.Routing.Babel.MACKeySet.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "DefaultApply": dm_type.BOOL | dm_type.WRITABLE,
        "MACKeyNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "MACKeyNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.RouteInformation.
export const RouteInformation = {
    path: "Device.Routing.RouteInformation.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceSettingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceSettingNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Router.{i}.
export const Router = {
    path: "Device.Routing.Router.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "IPv4ForwardingNumberOfEntries": dm_type.UINT,
        "IPv6ForwardingNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "IPv4ForwardingNumberOfEntries": "0",
        "IPv6ForwardingNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Babel.DTLSCertSet.{i}.DTLSCert.{i}.
export const DTLSCertSet_DTLSCert = {
    path: "Device.Routing.Babel.DTLSCertSet.{i}.DTLSCert.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "CertValue": dm_type.STRING,
        "CertType": dm_type.STRING | dm_type.WRITABLE,
        "CertPrivateKey": dm_type.HEXBIN
    },
    defaults: {
        "Alias": "",
        "CertValue": "",
        "CertType": ""
    }
};

// Schema for Device.Routing.Babel.Constants.
export const Babel_Constants = {
    path: "Device.Routing.Babel.Constants.",
    schema: {
        "UDPPort": dm_type.UINT | dm_type.WRITABLE,
        "MulticastGroup": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "UDPPort": "0",
        "MulticastGroup": ""
    }
};

// Schema for Device.Routing.Babel.InterfaceSetting.{i}.
export const Babel_InterfaceSetting = {
    path: "Device.Routing.Babel.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "InterfaceReference": dm_type.STRING,
        "InterfaceMetricAlgorithm": dm_type.STRING,
        "SplitHorizonEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "McastHelloSeqno": dm_type.UINT,
        "McastHelloInterval": dm_type.UINT,
        "UpdateInterval": dm_type.UINT,
        "MACEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceMACKeySets": dm_type.STRING | dm_type.WRITABLE,
        "MACVerify": dm_type.BOOL | dm_type.WRITABLE,
        "DTLSEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "InterfaceDTLSCertSets": dm_type.STRING | dm_type.WRITABLE,
        "CachedInfoEnabled": dm_type.BOOL | dm_type.WRITABLE,
        "DTLSCertPrefer": dm_type.STRING | dm_type.WRITABLE,
        "PacketLogEnable": dm_type.BOOL | dm_type.WRITABLE,
        "PacketLog": dm_type.STRING,
        "NeighborNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "Disabled",
        "Alias": "",
        "InterfaceReference": "",
        "InterfaceMetricAlgorithm": "",
        "McastHelloSeqno": "0",
        "McastHelloInterval": "0",
        "UpdateInterval": "0",
        "InterfaceMACKeySets": "",
        "InterfaceDTLSCertSets": "",
        "DTLSCertPrefer": "",
        "PacketLog": "",
        "NeighborNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.Babel.Route.{i}.
export const Babel_Route = {
    path: "Device.Routing.Babel.Route.{i}.",
    schema: {
        "RoutePrefix": dm_type.STRING,
        "SourceRouterID": dm_type.HEXBIN,
        "Neighbor": dm_type.STRING,
        "ReceivedMetric": dm_type.INT,
        "CalculatedMetric": dm_type.INT,
        "RouteSeqno": dm_type.UINT,
        "NextHop": dm_type.STRING,
        "RouteFeasible": dm_type.BOOL,
        "RouteSelected": dm_type.BOOL
    },
    defaults: {
        "RoutePrefix": "",
        "Neighbor": "",
        "ReceivedMetric": "0",
        "CalculatedMetric": "0",
        "RouteSeqno": "0",
        "NextHop": ""
    }
};

// Schema for Device.Routing.RouteInformation.InterfaceSetting.{i}.Option.{i}.
export const InterfaceSetting_Option = {
    path: "Device.Routing.RouteInformation.InterfaceSetting.{i}.Option.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Tag": dm_type.UINT,
        "Value": dm_type.HEXBIN
    },
    defaults: {
        "Alias": "",
        "Tag": "0"
    }
};

// Schema for Device.Routing.RouteInformation.InterfaceSetting.{i}.
export const RouteInformation_InterfaceSetting = {
    path: "Device.Routing.RouteInformation.InterfaceSetting.{i}.",
    schema: {
        "Status": dm_type.STRING,
        "Interface": dm_type.STRING,
        "SourceRouter": dm_type.STRING,
        "PreferredRouteFlag": dm_type.STRING,
        "Prefix": dm_type.STRING,
        "ManagedAddressConfiguration": dm_type.BOOL,
        "OtherConfiguration": dm_type.BOOL,
        "RouteLifetime": dm_type.DATETIME,
        "ReachableTime": dm_type.UINT,
        "RetransTimer": dm_type.UINT,
        "HomeAgent": dm_type.BOOL,
        "OptionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Status": "",
        "Interface": "",
        "SourceRouter": "",
        "PreferredRouteFlag": "",
        "Prefix": "",
        "ReachableTime": "0",
        "RetransTimer": "0",
        "OptionNumberOfEntries": "0"
    }
};

// Schema for Device.Routing.RIP.InterfaceSetting.{i}.
export const RIP_InterfaceSetting = {
    path: "Device.Routing.RIP.InterfaceSetting.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "AcceptRA": dm_type.BOOL | dm_type.WRITABLE,
        "SendRA": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "false",
        "Status": "Disabled",
        "Alias": "",
        "Interface": ""
    }
};

// Schema for Device.Routing.Babel.InterfaceSetting.{i}.Neighbor.{i}.
export const InterfaceSetting_Neighbor = {
    path: "Device.Routing.Babel.InterfaceSetting.{i}.Neighbor.{i}.",
    schema: {
        "NeighborAddress": dm_type.STRING,
        "HelloMCastHistory": dm_type.HEXBIN,
        "HelloUCastHistory": dm_type.HEXBIN,
        "TXCost": dm_type.UINT,
        "ExpectedMCastHelloSeqno": dm_type.INT,
        "ExpectedUCastHelloSeqno": dm_type.INT,
        "UnicastHelloSeqno": dm_type.INT,
        "UnicastHelloInterval": dm_type.UINT,
        "RXCost": dm_type.UINT,
        "Cost": dm_type.UINT
    },
    defaults: {
        "NeighborAddress": "",
        "TXCost": "0",
        "ExpectedMCastHelloSeqno": "0",
        "ExpectedUCastHelloSeqno": "0",
        "UnicastHelloSeqno": "0",
        "UnicastHelloInterval": "0",
        "RXCost": "0",
        "Cost": "0"
    }
};

// Schema for Device.Routing.Babel.DTLSCertSet.{i}.
export const Babel_DTLSCertSet = {
    path: "Device.Routing.Babel.DTLSCertSet.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "DefaultApply": dm_type.BOOL | dm_type.WRITABLE,
        "DTLSCertNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "DTLSCertNumberOfEntries": "0"
    }
};
