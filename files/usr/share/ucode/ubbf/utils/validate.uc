'use strict';

// Checks a value against what the schema says about the parameter it is
// being written to. The facts come from param_schema(), so they are the
// merge of the generated constraints table and any per-domain override.

const INT_TYPES = {
	DM_INT: true,
	DM_UINT: true,
	DM_LONG: true,
	DM_ULONG: true
};

const BOOLS = {
	'0': true, '1': true, 'true': true, 'false': true
};

/**
 * Reports whether a string is a base-10 integer, optionally signed.
 *
 * int() is not enough on its own: it stops at the first non-digit, so
 * "12abc" reads as 12 and a bad value would be accepted.
 *
 * @param {string} s - Candidate value
 * @returns {boolean} True when every character belongs to the number
 */
function is_integer(s) {
	let len = length(s);
	if (!len)
		return false;

	let i = (substr(s, 0, 1) == '-') ? 1 : 0;
	if (i >= len)
		return false;

	for (; i < len; i++) {
		let c = ord(s, i);
		if (c < 48 || c > 57)
			return false;
	}

	return true;
}

/**
 * Reports whether a number lies in any of a set of ranges. A null bound
 * is open.
 *
 * @param {array} ranges - `[[min, max], ...]`
 * @param {number} n - Candidate value
 * @returns {boolean}
 */
function in_ranges(ranges, n) {
	for (let r in ranges)
		if ((r[0] == null || n >= r[0]) && (r[1] == null || n <= r[1]))
			return true;
	return false;
}

/**
 * Validates one value, or one item of a list, against the integer range,
 * the enumeration and the string lengths.
 *
 * @param {object} info - param_schema() result for the target parameter
 * @param {string} s - Value or list item
 * @returns {string|null} A short reason when the value is unacceptable
 */
function item_check(info, s) {
	if (INT_TYPES[info.type]) {
		if (!is_integer(s))
			return 'not an integer';

		let n = +s;
		if (info.min != null && n < info.min)
			return sprintf('below the minimum of %d', info.min);
		if (info.max != null && n > info.max)
			return sprintf('above the maximum of %d', info.max);
		if (info.ranges && !in_ranges(info.ranges, n))
			return sprintf('outside the ranges %J', info.ranges);
	}

	if (info.enum && index(info.enum, s) < 0)
		return sprintf('not one of %s', join(', ', info.enum));

	if (info.type == 'DM_STRING') {
		let len = length(s);
		if (info.min_length != null && len < info.min_length)
			return sprintf('shorter than %d characters', info.min_length);
		if (info.max_length != null && len > info.max_length)
			return sprintf('longer than %d characters', info.max_length);
		if (info.lengths && !in_ranges(info.lengths, len))
			return sprintf('length %d outside %J', len, info.lengths);
	}

	return null;
}

/**
 * Validates a comma-separated list: the list lengths apply to the whole
 * value, the enumeration and the string lengths to each item.
 *
 * @param {object} info - param_schema() result for the target parameter
 * @param {string} s - Value as written
 * @returns {string|null} A short reason when the value is unacceptable
 */
function list_check(info, s) {
	let len = length(s);
	if (info.list_min_length != null && len < info.list_min_length)
		return sprintf('shorter than %d characters', info.list_min_length);
	if (info.list_max_length != null && len > info.list_max_length)
		return sprintf('longer than %d characters', info.list_max_length);

	if (s == '')
		return null;

	for (let item in split(s, ',')) {
		let why = item_check(info, trim(item));
		if (why)
			return sprintf('%s: %s', trim(item), why);
	}

	return null;
}

/**
 * Validates a value against a parameter's schema facts.
 *
 * @param {object} info - param_schema() result for the target parameter
 * @param {*} value - Value as written, before any coercion
 * @returns {string|null} A short reason when the value is unacceptable,
 *                        null when it is fine or nothing is known about it
 */
export function value_check(info, value) {
	if (!info)
		return null;

	let s = (type(value) == 'string') ? value : sprintf('%s', value);

	if (info.type == 'DM_BOOL' && !BOOLS[s])
		return 'not a boolean';

	if (info.list)
		return list_check(info, s);

	return item_check(info, s);
};

/**
 * Validates the path of a configuration file passed in by a ubus caller.
 *
 * @param {*} path - Candidate path
 * @returns {string|null} A short reason when the path is unacceptable,
 *                        null when it is fine
 */
export function config_path_check(path) {
	if (type(path) != 'string' || path == '' || substr(path, 0, 1) != '/')
		return 'file path must be absolute';

	for (let part in split(path, '/'))
		if (part == '.' || part == '..')
			return 'file path must not contain . or ..';

	return null;
};
