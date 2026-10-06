'use strict';

// Auto-generated schema definitions for the SFPs and Optical domains
// Generated from TR-181 specifications
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Alarms.
schemas.Transceiver_Alarms = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Alarms.",
    schema: {
        "TemperatureHigh": dm_type.BOOL,
        "TemperatureLow": dm_type.BOOL,
        "VccHigh": dm_type.BOOL,
        "VccLow": dm_type.BOOL,
        "TxBiasHigh": dm_type.BOOL,
        "TxBiasLow": dm_type.BOOL,
        "TxPowerHigh": dm_type.BOOL,
        "TxPowerLow": dm_type.BOOL,
        "RxPowerHigh": dm_type.BOOL,
        "RxPowerLow": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Status.
schemas.Transceiver_Status = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Status.",
    schema: {
        "Temperature": dm_type.INT,
        "Vcc": dm_type.UINT,
        "TxBias": dm_type.UINT,
        "TxPower": dm_type.INT,
        "RxPower": dm_type.INT,
        "TxDisableState": dm_type.BOOL,
        "SoftTxDisableSelect": dm_type.BOOL,
        "RS1State": dm_type.BOOL,
        "RateSelectState": dm_type.BOOL,
        "SoftRateSelectSelect": dm_type.BOOL,
        "TXFaultState": dm_type.BOOL,
        "RxLOSState": dm_type.BOOL,
        "DataReadyBarState": dm_type.BOOL
    },
    defaults: {
        "Temperature": "0",
        "Vcc": "0",
        "TxBias": "0",
        "TxPower": "0",
        "RxPower": "0"
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.
schemas.Mgmt_SFF8472 = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": ""
    },
    addable: false
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Thresholds.
schemas.Transceiver_Thresholds = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Thresholds.",
    schema: {
        "HighTempAlarm": dm_type.INT,
        "HighTempWarning": dm_type.INT,
        "LowTempWarning": dm_type.INT,
        "LowTempAlarm": dm_type.INT,
        "HighVccAlarm": dm_type.UINT,
        "HighVccWarning": dm_type.UINT,
        "LowVccWarning": dm_type.UINT,
        "LowVccAlarm": dm_type.UINT,
        "HighTxBiasAlarm": dm_type.UINT,
        "HighTxBiasWarning": dm_type.UINT,
        "LowTxBiasWarning": dm_type.UINT,
        "LowTxBiasAlarm": dm_type.UINT,
        "HighTxPowerAlarm": dm_type.INT,
        "HighTxPowerWarning": dm_type.INT,
        "LowTxPowerWarning": dm_type.INT,
        "LowTxPowerAlarm": dm_type.INT,
        "HighRxPowerAlarm": dm_type.INT,
        "HighRxPowerWarning": dm_type.INT,
        "LowRxPowerWarning": dm_type.INT,
        "LowRxPowerAlarm": dm_type.INT
    },
    defaults: {
        "HighTempAlarm": "0",
        "HighTempWarning": "0",
        "LowTempWarning": "0",
        "LowTempAlarm": "0",
        "HighVccAlarm": "0",
        "HighVccWarning": "0",
        "LowVccWarning": "0",
        "LowVccAlarm": "0",
        "HighTxBiasAlarm": "0",
        "HighTxBiasWarning": "0",
        "LowTxBiasWarning": "0",
        "LowTxBiasAlarm": "0",
        "HighTxPowerAlarm": "0",
        "HighTxPowerWarning": "0",
        "LowTxPowerWarning": "0",
        "LowTxPowerAlarm": "0",
        "HighRxPowerAlarm": "0",
        "HighRxPowerWarning": "0",
        "LowRxPowerWarning": "0",
        "LowRxPowerAlarm": "0"
    }
};

// Schema for Device.SFPs.SFPCage.{i}.
schemas.SFPCage = {
    path: "Device.SFPs.SFPCage.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "SFPPresent": dm_type.BOOL,
        "SFF8024Identifier": dm_type.UINT,
        "MgmtInterface": dm_type.STRING,
        "SFPType": dm_type.STRING,
        "SFPReference": dm_type.STRING,
        "IsAllowed": dm_type.BOOL
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "SFF8024Identifier": "0",
        "MgmtInterface": "",
        "SFPType": "",
        "SFPReference": "",
        "IsAllowed": "true"
    },
    since: {
        "IsAllowed": "2.21"
    },
    addable: false
};

// Schema for Device.SFPs.Mgmt.
schemas.Mgmt = {
    path: "Device.SFPs.Mgmt.",
    schema: {
        "SFF8472NumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SFF8472NumberOfEntries": "0"
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.
schemas.SFF8472_Transceiver = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.",
    schema: {
        "Connector": dm_type.HEXBIN,
        "Transceiver": dm_type.HEXBIN,
        "Encoding": dm_type.UINT,
        "BRNominal": dm_type.INT,
        "RateIdentifier": dm_type.HEXBIN,
        "VendorName": dm_type.STRING,
        "VendorOUI": dm_type.HEXBIN,
        "VendorPN": dm_type.STRING,
        "VendorRev": dm_type.STRING,
        "BRMax": dm_type.UINT,
        "BRMin": dm_type.UINT,
        "VendorSN": dm_type.STRING,
        "DateCode": dm_type.STRING,
        "LengthSMFkm": dm_type.UINT,
        "LengthSMF": dm_type.UINT,
        "LengthOM2": dm_type.UINT,
        "LengthOM1": dm_type.UINT,
        "LengthOM3": dm_type.UINT,
        "Wavelength": dm_type.UINT,
        "VerCompliance": dm_type.HEXBIN,
        "OptCooledTrans": dm_type.BOOL,
        "OptPowerlvl": dm_type.BOOL,
        "OptLinearRcvr": dm_type.BOOL,
        "OptRateSelect": dm_type.BOOL,
        "OptTxDisable": dm_type.BOOL,
        "OptTxFault": dm_type.BOOL,
        "OptInvertedLOS": dm_type.BOOL,
        "OptLOS": dm_type.BOOL,
        "DMCtypeImplemented": dm_type.BOOL,
        "DMCtypeInternalCal": dm_type.BOOL,
        "DMCtypeExternalCal": dm_type.BOOL,
        "DMCtypeRxAvgPwr": dm_type.BOOL,
        "EOCalarmsImplemented": dm_type.BOOL,
        "EOCSoftTxDisable": dm_type.BOOL,
        "EOCSoftTxFault": dm_type.BOOL,
        "EOCSoftRxLOS": dm_type.BOOL,
        "EOCSoftRateSelect": dm_type.BOOL,
        "SFF8079AppSelect": dm_type.BOOL,
        "SFF8431SoftRateSelect": dm_type.BOOL,
        "EMCSPowerLvlOp": dm_type.BOOL,
        "EMCSPowerLvlSelect": dm_type.BOOL
    },
    defaults: {
        "Encoding": "0",
        "BRNominal": "0",
        "VendorName": "",
        "VendorPN": "",
        "VendorRev": "",
        "BRMax": "0",
        "BRMin": "0",
        "VendorSN": "",
        "DateCode": "",
        "LengthSMFkm": "0",
        "LengthSMF": "0",
        "LengthOM2": "0",
        "LengthOM1": "0",
        "LengthOM3": "0",
        "Wavelength": "0"
    }
};

// Schema for Device.SFPs.
schemas.SFPs = {
    path: "Device.SFPs.",
    schema: {
        "SFPCageNumberOfEntries": dm_type.UINT,
        "SupportedSFPTypes": dm_type.STRING
    },
    defaults: {
        "SFPCageNumberOfEntries": "0",
        "SupportedSFPTypes": ""
    },
    since: {
        "SupportedSFPTypes": "2.21"
    },
    constraints: {
        "SupportedSFPTypes": { list: true }
    }
};

// Schema for Device.SFPs.AllowedSFPs. (TR-181 2.21)
schemas.AllowedSFPs = {
    path: "Device.SFPs.AllowedSFPs.",
    schema: {
        "AllowedSFPNumberOfEntries": dm_type.UINT,
        "AllowAllSFPs": dm_type.BOOL | dm_type.WRITABLE
    },
    defaults: {
        "AllowedSFPNumberOfEntries": "0",
        "AllowAllSFPs": "true"
    }
};

// Schema for Device.SFPs.AllowedSFPs.AllowedSFP.{i}. (TR-181 2.21). SFPType
// takes the values of SupportedSFPTypes. Fingerprint is not served: the spec
// leaves its format to the CPE, and none is agreed yet.
schemas.AllowedSFP = {
    path: "Device.SFPs.AllowedSFPs.AllowedSFP.{i}.",
    schema: {
        "Alias": dm_type.STRING | dm_type.WRITABLE,
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "SFPType": dm_type.STRING | dm_type.WRITABLE,
        "VendorName": dm_type.STRING | dm_type.WRITABLE,
        "VendorOUI": dm_type.HEXBIN | dm_type.WRITABLE,
        "VendorPN": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Alias": "",
        "Enable": "false",
        "SFPType": "",
        "VendorName": "",
        "VendorOUI": "",
        "VendorPN": ""
    },
    constraints: {
        "Alias": { max_length: 64 },
        "SFPType": { enum: [ "", "Optical Ethernet", "Electrical Ethernet" ] },
        "VendorName": { max_length: 16 },
        // TR-181 says 3 bytes; empty is the criterion that matches any vendor
        "VendorOUI": { lengths: [ [ 0, 0 ], [ 3, 3 ] ] },
        "VendorPN": { max_length: 16 }
    }
};

// Schema for Device.SFPs.SFPProperties. (TR-181 2.21)
schemas.SFPProperties = {
    path: "Device.SFPs.SFPProperties.",
    schema: {
        "SFPNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SFPNumberOfEntries": "0"
    }
};

// Schema for Device.SFPs.SFPProperties.SFP.{i}. (TR-181 2.21)
schemas.SFPProperties_SFP = {
    path: "Device.SFPs.SFPProperties.SFP.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "VendorName": dm_type.STRING | dm_type.WRITABLE,
        "VendorOUI": dm_type.HEXBIN | dm_type.WRITABLE,
        "VendorPN": dm_type.STRING | dm_type.WRITABLE,
        "SFPType": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Enable": "true",
        "VendorName": "",
        "VendorOUI": "",
        "VendorPN": "",
        "SFPType": ""
    },
    constraints: {
        "VendorName": { max_length: 16 },
        "VendorOUI": { lengths: [ [ 0, 0 ], [ 3, 3 ] ] },
        "VendorPN": { max_length: 16 },
        "SFPType": { enum: [ "", "Optical Ethernet", "Electrical Ethernet" ] }
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Warnings.
schemas.Transceiver_Warnings = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Warnings.",
    schema: {
        "TemperatureHigh": dm_type.BOOL,
        "TemperatureLow": dm_type.BOOL,
        "VccHigh": dm_type.BOOL,
        "VccLow": dm_type.BOOL,
        "TxBiasHigh": dm_type.BOOL,
        "TxBiasLow": dm_type.BOOL,
        "TxPowerHigh": dm_type.BOOL,
        "TxPowerLow": dm_type.BOOL,
        "RxPowerHigh": dm_type.BOOL,
        "RxPowerLow": dm_type.BOOL
    },
    defaults: {}
};

// Schema for Device.Optical.Interface.{i}.Stats.
schemas.Optical_Interface_Stats = {
    path: "Device.Optical.Interface.{i}.Stats.",
    schema: {
        "BytesSent": dm_type.ULONG,
        "BytesReceived": dm_type.ULONG,
        "PacketsSent": dm_type.ULONG,
        "PacketsReceived": dm_type.ULONG,
        "ErrorsSent": dm_type.UINT,
        "ErrorsReceived": dm_type.UINT,
        "DiscardPacketsSent": dm_type.UINT,
        "DiscardPacketsReceived": dm_type.UINT,
        "Reset()": { type: 'sync', input: [] }
    },
    defaults: {
        "BytesSent": "18446744073709551615",
        "BytesReceived": "18446744073709551615",
        "PacketsSent": "18446744073709551615",
        "PacketsReceived": "18446744073709551615",
        "ErrorsSent": "4294967295",
        "ErrorsReceived": "4294967295",
        "DiscardPacketsSent": "4294967295",
        "DiscardPacketsReceived": "4294967295"
    }
};

// Schema for Device.Optical.Interface.{i}.
schemas.Optical_Interface = {
    path: "Device.Optical.Interface.{i}.",
    schema: {
        "Enable": dm_type.BOOL | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Description": dm_type.STRING | dm_type.WRITABLE,
        "LastChange": dm_type.UINT,
        "LowerLayers": dm_type.STRING,
        "Upstream": dm_type.BOOL,
        "MaxBitRate": dm_type.INT,
        "SFPReferenceList": dm_type.STRING,
        "OpticalSignalLevel": dm_type.INT,
        "TransmitOpticalLevel": dm_type.INT
    },
    defaults: {
        "Enable": "true",
        "Status": "Unknown",
        "Alias": "",
        "Name": "",
        "Description": "",
        "LastChange": "0",
        "LowerLayers": "",
        "MaxBitRate": "0",
        "SFPReferenceList": "",
        "OpticalSignalLevel": "0",
        "TransmitOpticalLevel": "0"
    },
    since: {
        "Description": "2.21"
    },
    // LowerLayers and MaxBitRate are read-only here (TR-181: readWrite): an
    // optical interface is the lowest layer, and its speed follows the SFP.
    constraints: {
        "Status": { enum: [ "Up", "Down", "Unknown", "Dormant", "NotPresent", "LowerLayerDown", "Error", "NotAllowed" ] },
        "Description": { max_length: 256 },
        "LowerLayers": { list: true, list_max_length: 1024 }
    },
    addable: false
};

// Schema for Device.Optical.
schemas.Optical = {
    path: "Device.Optical.",
    schema: {
        "InterfaceNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "InterfaceNumberOfEntries": "0"
    }
};
