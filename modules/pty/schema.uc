'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.
//
// StartSession() is a USP command; CWMP has no command for it.

schemas.UPTY = {
    path: 'Device.X_UBBF.UPTY.',
    schema: {
        'Enable': dm_type.BOOL | dm_type.WRITABLE,
        'Status': dm_type.STRING,
        'LastError': dm_type.STRING,
        'StartSession()': {
            type: 'sync',
            input: ['Token', 'URL', 'AllowInsecure', 'CACert'],
            output: ['Status', 'Message']
        }
    },
    defaults: {
        'Enable': 'true',
        'Status': 'Unavailable',
        'LastError': ''
    },
    constraints: {
        'Status': { enum: [ 'Disabled', 'Unavailable', 'Idle', 'Connecting', 'Connected', 'Active' ] }
    }
};
