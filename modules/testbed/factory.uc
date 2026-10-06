'use strict';

// Included by handler.uc and render.uc with `{ testbed }` as the scope.
// `provision` is the factory store that survives a reset, as for the
// wireless country in default_config. The package is optional, so the
// module is loaded at runtime.

/**
 * Reads the testbed slot from the provisioning partition.
 *
 * A device that knows its slot from the factory carries it from its first
 * boot and across a reset to a baseline, before any testbed write.
 *
 * @returns {string|null} Slot as a decimal string, or null when there is none
 */
testbed.factory_slot = function() {
	let provision;

	try {
		provision = import('provision');
	} catch (e) {
		return null;
	}

	let ctx = provision.open();
	if (!ctx)
		return null;

	ctx.init();

	let slot = ctx.get('testbed.slot');
	if (type(slot) == 'string' && match(slot, /^[0-9]+$/))
		slot = int(slot);
	if (type(slot) != 'int' || slot < 1)
		return null;

	return '' + slot;
};
