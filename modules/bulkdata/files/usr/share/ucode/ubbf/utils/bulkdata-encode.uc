'use strict';

import * as ubbf from 'ubbf';

/**
 * JSON value of a parameter (TR-369 A.7.2.5): numbers for the integer
 * types, a boolean for boolean, else the string.
 *
 * @param {object} e - Parameter with `type` (DM_*) and `value` (string)
 * @returns {*} JSON value
 */
export function json_value(e) {
	if (match(e.type, /^DM_U?(INT|LONG)$/)) {
		// int() stops at int64; json() also holds an unsignedLong above it,
		// and clips a value past uint64, which the round trip catches
		if (match(e.value, /^-?(0|[1-9][0-9]*)$/)) {
			let n = json(e.value);
			return (sprintf('%s', n) == e.value) ? n : e.value;
		}

		let n = int(e.value);
		return (n == n) ? n : e.value;
	}

	if (e.type == 'DM_BOOL')
		return ubbf.to_bool(e.value);

	return e.value;
};
