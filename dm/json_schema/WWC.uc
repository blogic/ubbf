'use strict';

// Auto-generated schema definitions for WWC domain
// Generated from TR-181 specifications

// Schema for Device.WWC.URSP.{i}.TrafficDescriptor.{i}.
export const URSP_TrafficDescriptor = {
    path: "Device.WWC.URSP.{i}.TrafficDescriptor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Type": dm_type.UINT,
        "Value": dm_type.STRING,
        "RouteSelectionDescriptorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Type": "0",
        "Value": "",
        "RouteSelectionDescriptorNumberOfEntries": "0"
    }
};

// Schema for Device.WWC.URSP.{i}.TrafficDescriptor.{i}.RouteSelectionDescriptor.{i}.
export const TrafficDescriptor_RouteSelectionDescriptor = {
    path: "Device.WWC.URSP.{i}.TrafficDescriptor.{i}.RouteSelectionDescriptor.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Precedence": dm_type.UINT,
        "SSC": dm_type.UINT,
        "DNN": dm_type.STRING,
        "PDUSessionType": dm_type.STRING,
        "AccessType": dm_type.STRING
    },
    defaults: {
        "Alias": "",
        "Precedence": "0",
        "SSC": "0",
        "DNN": "",
        "PDUSessionType": "",
        "AccessType": ""
    }
};

// Schema for Device.WWC.AccessNetwork.{i}.
export const AccessNetwork = {
    path: "Device.WWC.AccessNetwork.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Name": dm_type.STRING,
        "Interface": dm_type.STRING | dm_type.WRITABLE,
        "RegistrationStatus": dm_type.STRING,
        "ConnectionStatus": dm_type.STRING,
        "AccessNetworkType": dm_type.STRING,
        "LastError": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Name": "",
        "Interface": "",
        "RegistrationStatus": "",
        "ConnectionStatus": "",
        "AccessNetworkType": "",
        "LastError": "0"
    }
};

// Schema for Device.WWC.
export const WWC = {
    path: "Device.WWC.",
    schema: {
        "HwCapabilities": dm_type.STRING,
        "SwCapabilities": dm_type.STRING,
        "Mode": dm_type.STRING | dm_type.WRITABLE,
        "Status": dm_type.STRING,
        "AccessNetworkNumberOfEntries": dm_type.UINT,
        "URSPNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "HwCapabilities": "",
        "SwCapabilities": "",
        "Mode": "Auto",
        "Status": "",
        "AccessNetworkNumberOfEntries": "0",
        "URSPNumberOfEntries": "0"
    }
};

// Schema for Device.WWC.URSP.{i}.
export const URSP = {
    path: "Device.WWC.URSP.{i}.",
    schema: {
        "Alias": dm_type.STRING,
        "Precedence": dm_type.UINT,
        "TrafficDescriptorNumberOfEntries": dm_type.UINT
    },
    defaults: {
        "Alias": "",
        "Precedence": "0",
        "TrafficDescriptorNumberOfEntries": "0"
    }
};

// Schema for Device.WWC.AccessNetwork.{i}.GUTI.
export const AccessNetwork_GUTI = {
    path: "Device.WWC.AccessNetwork.{i}.GUTI.",
    schema: {
        "PLMN": dm_type.UINT,
        "AMFId": dm_type.UINT,
        "TMSI": dm_type.UINT
    },
    defaults: {
        "PLMN": "0",
        "AMFId": "0",
        "TMSI": "0"
    }
};

// Schema for Device.WWC.URSP.{i}.TrafficDescriptor.{i}.RouteSelectionDescriptor.{i}.NetworkSlice.
export const RouteSelectionDescriptor_NetworkSlice = {
    path: "Device.WWC.URSP.{i}.TrafficDescriptor.{i}.RouteSelectionDescriptor.{i}.NetworkSlice.",
    schema: {
        "SliceServiceType": dm_type.STRING,
        "SliceDifferentiator": dm_type.UINT
    },
    defaults: {
        "SliceServiceType": "",
        "SliceDifferentiator": "0"
    }
};
