'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.
//
// Device.X_UBBF.Testbed.Slot is the testbed slot the device sits in, 0 where
// it sits in none. The testbed sets it, because a device cannot know its own
// slot: agents of several slots share the lab network behind their WAN.
// Where no value is set, the slot comes from the factory data, if it holds
// one (factory.uc). Test agents read it from the `testbed` UCI package
// render.uc writes.

const model = ubbf_module.model;

let schemas = {};
include('schema.uc', { schemas });

let testbed = {};
include('factory.uc', { testbed });

/**
 * Get handler for Device.X_UBBF.Testbed.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Testbed object: the slot set, else the factory slot,
 *     else 0
 */
function testbed_get(ctx) {
	return {
		Slot: ctx.config?.Slot ?? testbed.factory_slot() ?? '0'
	};
}

model['Device.X_UBBF.Testbed'] = {
	schema: schemas.Testbed,
	get: testbed_get
};
