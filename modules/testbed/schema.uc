'use strict';

// Schema definitions for the Device.X_UBBF.Testbed domain.
//
// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// No defaults: dm_get.c merges them into the config the get handler reads, so a
// default Slot would hide the factory slot (factory.uc). The handler returns
// 0 where neither is present.
schemas.Testbed = {
	path: 'Device.X_UBBF.Testbed.',
	schema: {
		'Slot': dm_type.UINT | dm_type.WRITABLE
	}
};
