'use strict';

// Auto-generated schema definitions for XPON domain
// Generated from TR-181 specifications

// Schema for Device.XPON.ONU.{i}.SoftwareImage.{i}.
export const ONU_SoftwareImage = {
    path: "Device.XPON.ONU.{i}.SoftwareImage.{i}.",
    schema: {
        "ID": dm_type.UINT,
        "Version": dm_type.STRING,
        "IsCommitted": dm_type.BOOL,
        "IsActive": dm_type.BOOL,
        "IsValid": dm_type.BOOL
    },
    defaults: {
        "ID": "0",
        "Version": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.Port.{i}.PM.
export const Port_PM = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.Port.{i}.PM.",
    schema: {
        "FramesSent": dm_type.STRING,
        "FramesReceived": dm_type.STRING
    },
    defaults: {
        "FramesSent": "",
        "FramesReceived": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.
export const ONU_ANI = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "PONMode": dm_type.STRING,
        "TransceiverNumberOfEntries": dm_type.UINT,
        "SFPReferenceList": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "PONMode": "",
        "TransceiverNumberOfEntries": "0",
        "SFPReferenceList": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.Authentication.
export const TC_Authentication = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.Authentication.",
    schema: {
        "Password": dm_type.STRING | dm_type.WRITABLE,
        "HexadecimalPassword": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "Password": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.
export const TC_GEM = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.",
    schema: {
        "PortNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "PortNumberOfEntries": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.Alarms.
export const TC_Alarms = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.Alarms.",
    schema: {
        "LOS": dm_type.BOOL,
        "LOF": dm_type.BOOL,
        "SF": dm_type.BOOL,
        "SD": dm_type.BOOL,
        "LCDG": dm_type.BOOL,
        "TF": dm_type.BOOL,
        "SUF": dm_type.BOOL,
        "MEM": dm_type.BOOL,
        "DACT": dm_type.BOOL,
        "DIS": dm_type.BOOL,
        "MIS": dm_type.BOOL,
        "PEE": dm_type.BOOL,
        "RDI": dm_type.BOOL,
        "LODS": dm_type.BOOL,
        "ROGUE": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.Stats.
export const ANI_Stats = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "UnicastPacketsSent": dm_type.STRING,
        "UnicastPacketsReceived": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "MulticastPacketsSent": dm_type.STRING,
        "MulticastPacketsReceived": dm_type.STRING,
        "BroadcastPacketsSent": dm_type.STRING,
        "BroadcastPacketsReceived": dm_type.STRING,
        "UnknownProtoPacketsReceived": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "UnicastPacketsSent": "",
        "UnicastPacketsReceived": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "MulticastPacketsSent": "",
        "MulticastPacketsReceived": "",
        "BroadcastPacketsSent": "",
        "BroadcastPacketsReceived": "",
        "UnknownProtoPacketsReceived": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.PM.PHY.
export const PM_PHY = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.PM.PHY.",
    schema: {
        "CorrectedFECBytes": dm_type.STRING,
        "CorrectedFECCodewords": dm_type.STRING,
        "UncorrectableFECCodewords": dm_type.STRING,
        "TotalFECCodewords": dm_type.STRING,
        "PSBdHECErrorCount": dm_type.STRING,
        "HeaderHECErrorCount": dm_type.STRING,
        "UnknownProfile": dm_type.STRING
    },
    defaults: {
        "CorrectedFECBytes": "",
        "CorrectedFECCodewords": "",
        "UncorrectableFECCodewords": "",
        "TotalFECCodewords": "",
        "PSBdHECErrorCount": "",
        "HeaderHECErrorCount": "",
        "UnknownProfile": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.Transceiver.{i}.
export const ANI_Transceiver = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.Transceiver.{i}.",
    schema: {
        "ID": dm_type.UINT,
        "Identifier": dm_type.UINT,
        "VendorName": dm_type.STRING,
        "VendorPartNumber": dm_type.STRING,
        "VendorRevision": dm_type.STRING,
        "PONMode": dm_type.STRING,
        "Connector": dm_type.STRING,
        "NominalBitRateDownstream": dm_type.UINT,
        "NominalBitRateUpstream": dm_type.UINT,
        "RxPower": dm_type.INT,
        "TxPower": dm_type.INT,
        "Voltage": dm_type.UINT,
        "Bias": dm_type.UINT,
        "Temperature": dm_type.INT
    },
    defaults: {
        "ID": "0",
        "Identifier": "0",
        "VendorName": "",
        "VendorPartNumber": "",
        "VendorRevision": "",
        "PONMode": "",
        "Connector": "",
        "NominalBitRateDownstream": "0",
        "NominalBitRateUpstream": "0",
        "RxPower": "0",
        "TxPower": "0",
        "Voltage": "0",
        "Bias": "0",
        "Temperature": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.Port.{i}.
export const GEM_Port = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.GEM.Port.{i}.",
    schema: {
        "PortID": dm_type.UINT,
        "Direction": dm_type.STRING,
        "PortType": dm_type.STRING
    },
    defaults: {
        "PortID": "0",
        "Direction": "",
        "PortType": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.PM.GEM.
export const PM_GEM = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.PM.GEM.",
    schema: {
        "FramesSent": dm_type.STRING,
        "FramesReceived": dm_type.STRING,
        "FrameHeaderHECErrors": dm_type.STRING,
        "KeyErrors": dm_type.STRING
    },
    defaults: {
        "FramesSent": "",
        "FramesReceived": "",
        "FrameHeaderHECErrors": "",
        "KeyErrors": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.PM.PLOAM.
export const PM_PLOAM = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.PM.PLOAM.",
    schema: {
        "MICErrors": dm_type.STRING,
        "DownstreamMessageCount": dm_type.STRING,
        "RangingTime": dm_type.STRING,
        "UpstreamMessageCount": dm_type.STRING
    },
    defaults: {
        "MICErrors": "",
        "DownstreamMessageCount": "",
        "RangingTime": "",
        "UpstreamMessageCount": ""
    }
};

// Schema for Device.XPON.ONU.{i}.EthernetUNI.{i}.Stats.
export const EthernetUNI_Stats = {
    path: "Device.XPON.ONU.{i}.EthernetUNI.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.STRING,
        "BytesReceived": dm_type.STRING,
        "PacketsSent": dm_type.STRING,
        "PacketsReceived": dm_type.STRING,
        "ErrorsSent": dm_type.STRING,
        "ErrorsReceived": dm_type.STRING,
        "UnicastPacketsSent": dm_type.STRING,
        "DiscardPacketsSent": dm_type.STRING,
        "DiscardPacketsReceived": dm_type.STRING,
        "MulticastPacketsSent": dm_type.STRING,
        "UnicastPacketsReceived": dm_type.STRING,
        "MulticastPacketsReceived": dm_type.STRING,
        "BroadcastPacketsSent": dm_type.STRING,
        "BroadcastPacketsReceived": dm_type.STRING,
        "UnknownProtoPacketsReceived": dm_type.STRING
    },
    defaults: {
        "BytesSent": "",
        "BytesReceived": "",
        "PacketsSent": "",
        "PacketsReceived": "",
        "ErrorsSent": "",
        "ErrorsReceived": "",
        "UnicastPacketsSent": "",
        "DiscardPacketsSent": "",
        "DiscardPacketsReceived": "",
        "MulticastPacketsSent": "",
        "UnicastPacketsReceived": "",
        "MulticastPacketsReceived": "",
        "BroadcastPacketsSent": "",
        "BroadcastPacketsReceived": "",
        "UnknownProtoPacketsReceived": ""
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.PerformanceThresholds.
export const TC_PerformanceThresholds = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.PerformanceThresholds.",
    schema: {
        "SignalFail": dm_type.UINT,
        "SignalDegrade": dm_type.UINT
    },
    defaults: {
        "SignalFail": "0",
        "SignalDegrade": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.PM.OMCI.
export const PM_OMCI = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.PM.OMCI.",
    schema: {
        "BaselineMessagesReceived": dm_type.STRING,
        "ExtendedMessagesReceived": dm_type.STRING,
        "MICErrors": dm_type.STRING
    },
    defaults: {
        "BaselineMessagesReceived": "",
        "ExtendedMessagesReceived": "",
        "MICErrors": ""
    }
};

// Schema for Device.XPON.
export const XPON = {
    path: "Device.XPON.",
    schema: {
        "ONUNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "ONUNumberOfEntries": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.ANI.{i}.TC.ONUActivation.
export const TC_ONUActivation = {
    path: "Device.XPON.ONU.{i}.ANI.{i}.TC.ONUActivation.",
    schema: {
        "ONUState": dm_type.STRING,
        "VendorID": dm_type.STRING,
        "SerialNumber": dm_type.STRING,
        "ONUID": dm_type.UINT
    },
    defaults: {
        "ONUState": "",
        "VendorID": "",
        "SerialNumber": "",
        "ONUID": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.
export const ONU = {
    path: "Device.XPON.ONU.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Name": dm_type.STRING,
        "Version": dm_type.STRING,
        "EquipmentID": dm_type.STRING,
        "SoftwareImageNumberOfEntries": dm_type.UINT,
        "EthernetUNINumberOfEntries": dm_type.UINT,
        "ANINumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Name": "",
        "Version": "",
        "EquipmentID": "",
        "SoftwareImageNumberOfEntries": "0",
        "EthernetUNINumberOfEntries": "0",
        "ANINumberOfEntries": "0"
    }
};

// Schema for Device.XPON.ONU.{i}.EthernetUNI.{i}.
export const ONU_EthernetUNI = {
    path: "Device.XPON.ONU.{i}.EthernetUNI.{i}.",
    schema: {
        "Enable": dm_type.BOOL,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING | dm_type.WRITABLE,
        "Upstream": dm_type.BOOL,
        "ANIs": dm_type.STRING,
        "InterdomainID": dm_type.STRING,
        "InterdomainName": dm_type.STRING
    },
    defaults: {
        "Status": "",
        "Alias": "",
        "Name": "",
        "LastChange": "0",
        "LowerLayers": "",
        "ANIs": "",
        "InterdomainID": "",
        "InterdomainName": ""
    }
};
