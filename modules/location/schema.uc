'use strict';

// Schema for Device.DeviceInfo.Location.{i}., hand-maintained against
// tr-181-2-19-0-deviceinfo.xml.
//
// Included by handler.uc with { schemas } as the scope; there is nothing to
// export from an included file, so the definition is added to that object.
//
// DataObject is read-only here: TR-181 makes it writable only when
// ExternalProtocol is CWMP or USP, and this module produces GPS rows alone.
// The defaults describe that one row shape, not the spec's External/CWMP
// object default, which never applies while Add is refused.

schemas.Location = {
    path: "Device.DeviceInfo.Location.{i}.",
    schema: {
        "Source": dm_type.STRING,
        "AcquiredTime": dm_type.DATETIME,
        "ExternalSource": dm_type.STRING,
        "ExternalProtocol": dm_type.STRING,
        "DataObject": dm_type.STRING
    },
    defaults: {
        "Source": "GPS",
        "AcquiredTime": "0001-01-01T00:00:00Z",
        "ExternalSource": "",
        "ExternalProtocol": "",
        "DataObject": ""
    }
};
