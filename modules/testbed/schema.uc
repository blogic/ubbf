'use strict';

// Schema definitions for the Device.X_UBBF.Testbed domain.
//
// Included by handler.uc with { schemas } as the scope; there is nothing to
// export from an included file, so each definition is added to that object.

// No defaults: dm.c merges them into the config the get handler reads, so a
// default Slot would hide the factory slot (factory.uc). The handler returns
// 0 where neither is present.
schemas.Testbed = {
	path: 'Device.X_UBBF.Testbed.',
	schema: {
		'Slot': dm_type.UINT | dm_type.WRITABLE
	}
};
