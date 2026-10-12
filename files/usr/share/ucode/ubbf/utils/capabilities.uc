'use strict';

import { readfile } from 'fs';
import { cache_call, log_exception } from 'ubbf';

const CAPABILITIES_PATH = '/tmp/ubbf/capabilities.json';

/**
 * Reads the radios of the capabilities file (uncached).
 *
 * @returns {array} Capability radios, empty when the file is missing or malformed
 */
function capability_radios_fetch() {
	let raw = readfile(CAPABILITIES_PATH);
	if (!raw)
		return [];

	let capabilities;
	try {
		capabilities = json(raw);
	} catch (e) {
		log_exception(CAPABILITIES_PATH, e);
		return [];
	}

	return type(capabilities?.radios) == 'array' ? capabilities.radios : [];
}

/**
 * Reads the radios of the capabilities file (cached).
 *
 * @returns {array} Capability radios
 */
export function capability_radios_get() {
	return cache_call(capability_radios_fetch);
};
