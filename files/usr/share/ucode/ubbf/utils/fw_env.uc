'use strict';

import * as fs from 'fs';
import { cmd_build } from 'ubbf';

/**
 * Reads a U-Boot environment variable.
 *
 * @param {string} name - Variable name
 * @returns {string|null} Variable value, or null if unset
 */
export function fw_printenv(name) {
	let p = fs.popen(cmd_build([ 'fw_printenv', '-n', name, { raw: '2>/dev/null' } ]), 'r');
	if (!p)
		return null;
	let val = trim(p.read('all') ?? '');
	p.close();
	return (val != '') ? val : null;
};

/**
 * Sets a U-Boot environment variable.
 *
 * @param {string} name - Variable name
 * @param {string} value - Variable value
 * @returns {boolean} True if fw_setenv succeeded
 */
export function fw_setenv(name, value) {
	return system(cmd_build([ 'fw_setenv', name, value ])) == 0;
};
