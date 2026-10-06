'use strict';

// Auto-generated schema definitions for SessionManagement domain
// Generated from TR-181 specifications

// Schema for Device.SessionManagement.Session.{i}.
export const Session = {
    path: "Device.SessionManagement.Session.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Interface": dm_type.STRING,
        "SessionID": dm_type.UINT,
        "SessionType": dm_type.STRING,
        "APN": dm_type.STRING,
        "Reference": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Interface": "",
        "SessionID": "0",
        "SessionType": "",
        "APN": "",
        "Reference": ""
    }
};

// Schema for Device.SessionManagement.PDU.{i}.QoSFlow.{i}.
export const PDU_QoSFlow = {
    path: "Device.SessionManagement.PDU.{i}.QoSFlow.{i}.",
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

// Schema for Device.SessionManagement.PDN.{i}.
export const PDN = {
    path: "Device.SessionManagement.PDN.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "QCI": dm_type.UINT,
        "UpstreamMaxBitRate": dm_type.ULONG,
        "DownstreamMaxBitRate": dm_type.ULONG,
        "UpstreamGuaranteedBitRate": dm_type.ULONG,
        "DownstreamGuaranteedBitRate": dm_type.ULONG,
        "UpstreamAggregateBitRate": dm_type.ULONG,
        "DownstreamAggregateBitRate": dm_type.ULONG
    },
    defaults: {
        "Alias": "",
        "QCI": "0",
        "UpstreamMaxBitRate": "0",
        "DownstreamMaxBitRate": "0",
        "UpstreamGuaranteedBitRate": "0",
        "DownstreamGuaranteedBitRate": "0",
        "UpstreamAggregateBitRate": "0",
        "DownstreamAggregateBitRate": "0"
    }
};

// Schema for Device.SessionManagement.
export const SessionManagement = {
    path: "Device.SessionManagement.",
    schema: {
        "SessionNumberOfEntries": dm_type.UINT,
        "PDPNumberOfEntries": dm_type.UINT,
        "PDNNumberOfEntries": dm_type.UINT,
        "PDUNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SessionNumberOfEntries": "0",
        "PDPNumberOfEntries": "0",
        "PDNNumberOfEntries": "0",
        "PDUNumberOfEntries": "0"
    }
};

// Schema for Device.SessionManagement.PDU.{i}.
export const PDU = {
    path: "Device.SessionManagement.PDU.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "PTI": dm_type.UINT,
        "SSC": dm_type.UINT,
        "SessionAMBRDownlink": dm_type.ULONG,
        "SessionAMBRUplink": dm_type.ULONG,
        "RQTimerValue": dm_type.UINT,
        "AlwaysOn": dm_type.BOOL,
        "QoSRuleNumberOfEntries": dm_type.UINT,
        "QoSFlowNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "PTI": "0",
        "SSC": "0",
        "SessionAMBRDownlink": "0",
        "SessionAMBRUplink": "0",
        "RQTimerValue": "0",
        "QoSRuleNumberOfEntries": "0",
        "QoSFlowNumberOfEntries": "0"
    }
};

// Schema for Device.SessionManagement.PDP.{i}.
export const PDP = {
    path: "Device.SessionManagement.PDP.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "TrafficClass": dm_type.STRING,
        "UpstreamMaxBitRate": dm_type.ULONG,
        "DownstreamMaxBitRate": dm_type.ULONG,
        "UpstreamGuaranteedBitRate": dm_type.ULONG,
        "DownstreamGuaranteedBitRate": dm_type.ULONG,
        "DeliveryOrder": dm_type.STRING,
        "MaximumSDUSize": dm_type.UINT,
        "SDUErrorRatio": dm_type.STRING,
        "ResidualBitErrorRatio": dm_type.STRING,
        "DeliveryOfErroneousSDUs": dm_type.STRING,
        "TransferDelay": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "TrafficClass": "",
        "UpstreamMaxBitRate": "0",
        "DownstreamMaxBitRate": "0",
        "UpstreamGuaranteedBitRate": "0",
        "DownstreamGuaranteedBitRate": "0",
        "DeliveryOrder": "",
        "MaximumSDUSize": "0",
        "SDUErrorRatio": "",
        "ResidualBitErrorRatio": "",
        "DeliveryOfErroneousSDUs": "",
        "TransferDelay": "0"
    }
};

// Schema for Device.SessionManagement.Session.{i}.PCO.
export const Session_PCO = {
    path: "Device.SessionManagement.Session.{i}.PCO.",
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

// Schema for Device.SessionManagement.PDU.{i}.QoSRule.{i}.Filter.{i}.
export const QoSRule_Filter = {
    path: "Device.SessionManagement.PDU.{i}.QoSRule.{i}.Filter.{i}.",
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

// Schema for Device.SessionManagement.PDU.{i}.QoSRule.{i}.
export const PDU_QoSRule = {
    path: "Device.SessionManagement.PDU.{i}.QoSRule.{i}.",
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

// Schema for Device.SessionManagement.PDU.{i}.NetworkSlice.
export const PDU_NetworkSlice = {
    path: "Device.SessionManagement.PDU.{i}.NetworkSlice.",
    schema: {
        "SliceServiceType": dm_type.STRING,
        "SliceDifferentiator": dm_type.UINT
    },
    defaults: {
        "SliceServiceType": "",
        "SliceDifferentiator": "0"
    }
};
