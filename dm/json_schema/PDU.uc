'use strict';

// Auto-generated schema definitions for PDU domain
// Generated from TR-181 specifications

// Schema for Device.PDU.
export const PDU = {
    path: "Device.PDU.",
    schema: {
        "SessionNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SessionNumberOfEntries": "0"
    }
};

// Schema for Device.PDU.Session.{i}.NetworkSlice.
export const Session_NetworkSlice = {
    path: "Device.PDU.Session.{i}.NetworkSlice.",
    schema: {
        "SliceServiceType": dm_type.STRING,
        "SliceDifferentiator": dm_type.UINT
    },
    defaults: {
        "SliceServiceType": "",
        "SliceDifferentiator": "0"
    }
};

// Schema for Device.PDU.Session.{i}.PCO.
export const Session_PCO = {
    path: "Device.PDU.Session.{i}.PCO.",
    schema: {
        "IPv6PCSCF": dm_type.STRING,
        "IPv6DNS": dm_type.STRING,
        "IPv4PCSCF": dm_type.STRING,
        "IPv4DNS": dm_type.STRING
    },
    defaults: {
        "IPv6PCSCF": "",
        "IPv6DNS": "",
        "IPv4PCSCF": "",
        "IPv4DNS": ""
    }
};

// Schema for Device.PDU.Session.{i}.QoSRule.{i}.
export const Session_QoSRule = {
    path: "Device.PDU.Session.{i}.QoSRule.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Identifier": dm_type.UINT,
        "Precedence": dm_type.UINT,
        "Segregation": dm_type.BOOL,
        "QFI": dm_type.UINT,
        "DQR": dm_type.BOOL,
        "FilterNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Identifier": "0",
        "Precedence": "0",
        "QFI": "0",
        "FilterNumberOfEntries": "0"
    }
};

// Schema for Device.PDU.Session.{i}.
export const Session = {
    path: "Device.PDU.Session.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING,
        "SessionID": dm_type.UINT,
        "PTI": dm_type.UINT,
        "SessionType": dm_type.STRING,
        "SSC": dm_type.UINT,
        "SessionAMBRDownlink": dm_type.ULONG,
        "SessionAMBRUplink": dm_type.ULONG,
        "LastError": dm_type.UINT,
        "PDUIPv4Address": dm_type.STRING,
        "PDUIPv6InterfaceIdentifier": dm_type.STRING,
        "RQTimerValue": dm_type.UINT,
        "AlwaysOn": dm_type.BOOL,
        "DNN": dm_type.STRING,
        "QoSRuleNumberOfEntries": dm_type.UINT,
        "QoSFlowNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Interface": "",
        "SessionID": "0",
        "PTI": "0",
        "SessionType": "",
        "SSC": "0",
        "SessionAMBRDownlink": "0",
        "SessionAMBRUplink": "0",
        "LastError": "0",
        "PDUIPv4Address": "",
        "PDUIPv6InterfaceIdentifier": "",
        "RQTimerValue": "0",
        "DNN": "",
        "QoSRuleNumberOfEntries": "0",
        "QoSFlowNumberOfEntries": "0"
    }
};

// Schema for Device.PDU.Session.{i}.QoSFlow.{i}.
export const Session_QoSFlow = {
    path: "Device.PDU.Session.{i}.QoSFlow.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "QFI": dm_type.UINT,
        "FiveQI": dm_type.UINT,
        "GFBRUplink": dm_type.ULONG,
        "GFBRDownlink": dm_type.ULONG,
        "MFBRUplink": dm_type.ULONG,
        "MFBRDownlink": dm_type.ULONG,
        "AveragingWindow": dm_type.UINT,
        "EPSBearer": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "QFI": "0",
        "FiveQI": "0",
        "GFBRUplink": "0",
        "GFBRDownlink": "0",
        "MFBRUplink": "0",
        "MFBRDownlink": "0",
        "AveragingWindow": "0",
        "EPSBearer": "0"
    }
};

// Schema for Device.PDU.Session.{i}.QoSRule.{i}.Filter.{i}.
export const QoSRule_Filter = {
    path: "Device.PDU.Session.{i}.QoSRule.{i}.Filter.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Direction": dm_type.STRING,
        "Type": dm_type.UINT,
        "Value": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Direction": "",
        "Type": "0",
        "Value": ""
    }
};
