'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Schema for Device.Ethernet.WoL.
schemas.WoL = {
    path: "Device.Ethernet.WoL.",
    schema: {
        "SendMagicPacket()": { type: 'sync', input: ['MACAddress', 'Password'] }
    },
    defaults: {
    }
};
