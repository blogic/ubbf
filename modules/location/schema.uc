'use strict';

// Schema for Device.DeviceInfo.Location.{i}., hand-maintained against
// tr-181-2-19-0-deviceinfo.xml and tr-181-2-21-0-deviceinfo.xml.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so the definition is added to that object.
//
// A stored row is the location a controller configured (Source External);
// the defaults are the spec's object defaults for such a row. The GPS row
// is a runtime row of the handler.

schemas.Location = {
    path: "Device.DeviceInfo.Location.{i}.",
    schema: {
        "Source": dm_type.STRING,
        "AcquiredTime": dm_type.DATETIME,
        "ExternalSource": dm_type.STRING,
        "ExternalProtocol": dm_type.STRING,
        "DataObject": dm_type.STRING | dm_type.WRITABLE
    },
    defaults: {
        "Source": "External",
        "AcquiredTime": "0001-01-01T00:00:00Z",
        "ExternalSource": "",
        "ExternalProtocol": "CWMP",
        "DataObject": ""
    },
    constraints: {
        "Source": { enum: [ "GPS", "Barometer", "AGPS", "Manual", "External" ] },
        "ExternalProtocol": {
            enum: [ "", "CWMP", "USP", "OMA-DM", "SNMP", "UPnP", "HELD", "DHCPv4", "DHCPv6", "LLDP-MED", "MLP", "Other" ]
        },
        "DataObject": { max_length: 2048 }
    }
};
