'use strict';

// Auto-generated schema definitions for SFPs domain
// Generated from TR-181 specifications

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Alarms.
export const Transceiver_Alarms = {
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
export const Transceiver_Status = {
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
export const Mgmt_SFF8472 = {
    path: "Device.SFPs.Mgmt.SFF8472.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": ""
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Thresholds.
export const Transceiver_Thresholds = {
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
export const SFPCage = {
    path: "Device.SFPs.SFPCage.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "SFPPresent": dm_type.BOOL,
        "SFF8024Identifier": dm_type.UINT,
        "MgmtInterface": dm_type.STRING,
        "SFPType": dm_type.STRING,
        "SFPReference": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "SFF8024Identifier": "0",
        "MgmtInterface": "",
        "SFPType": "",
        "SFPReference": ""
    }
};

// Schema for Device.SFPs.Mgmt.
export const Mgmt = {
    path: "Device.SFPs.Mgmt.",
    schema: {
        "SFF8472NumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SFF8472NumberOfEntries": "0"
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.
export const SFF8472_Transceiver = {
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
export const SFPs = {
    path: "Device.SFPs.",
    schema: {
        "SFPCageNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "SFPCageNumberOfEntries": "0"
    }
};

// Schema for Device.SFPs.Mgmt.SFF8472.{i}.Transceiver.Warnings.
export const Transceiver_Warnings = {
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
