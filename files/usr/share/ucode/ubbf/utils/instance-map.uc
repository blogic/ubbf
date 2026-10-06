'use strict';

// Stable instance numbers for tables whose rows the CPE builds from the
// devices present (cages, USB devices, modems, hosts). TR-369 R-ARC.8: an
// instance number does not change until its object is deleted, so a row
// keeps its number while other rows come and go, and a number is not given
// to another device. The map keeps a key per device, for example a cage
// name, and the next free number of each table.

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf.utils.logging';

const MAP_PATH = '/etc/ubbf/instance-map.json';
const VOLATILE_PATH = '/tmp/ubbf/instance-map.json';

let maps = {};

function map_load(path) {
	if (maps[path])
		return maps[path];

	let data;
	try {
		data = json(fs.readfile(path) ?? '{}');
	} catch (e) {
		data = null;
	}

	maps[path] = (type(data) == 'object') ? data : {};
	return maps[path];
}

/**
 * Returns the instance number of each key, giving new keys the next free
 * numbers in the order of `keys`. A first call thus numbers the rows as
 * their position did.
 *
 * @param {string} table - Table path, for example Device.Optical.Interface
 * @param {array} keys - Stable keys of the rows present
 * @param {boolean} volatile - Keep the map in /tmp, for tables with many
 *                             short-lived rows that a reboot clears anyway
 * @returns {object} Key to instance number
 */
export function instance_numbers(table, keys, volatile) {
	let path = volatile ? VOLATILE_PATH : MAP_PATH;
	let all = map_load(path);
	let map = (all[table] ??= { next: 1, keys: {} });
	let changed = false;

	for (let key in keys) {
		if (map.keys[key] != null)
			continue;
		map.keys[key] = map.next++;
		changed = true;
	}

	if (changed) {
		if (volatile)
			fs.mkdir('/tmp/ubbf', 0755);
		if (!ubbf.write_file_atomic(path, sprintf('%.J\n', all)))
			log_err('instance map: failed to write %s', path);
	}

	let numbers = {};
	for (let key in keys)
		numbers[key] = map.keys[key];
	return numbers;
};

/**
 * Adopts the numbers that stored rows already give their keys, for a map
 * that does not hold them yet; a number another key holds is not taken.
 *
 * @param {string} table - Table path
 * @param {object} numbers - Key to instance number
 * @param {boolean} volatile - As for instance_numbers()
 */
export function instance_seed(table, numbers, volatile) {
	let path = volatile ? VOLATILE_PATH : MAP_PATH;
	let all = map_load(path);
	let map = (all[table] ??= { next: 1, keys: {} });
	let used = {};
	let changed = false;

	for (let key, n in map.keys)
		used[n] = true;

	for (let key, n in numbers) {
		n = ubbf.to_int(n);
		if (key == '' || n == null || n < 1 || map.keys[key] != null || used[n])
			continue;
		map.keys[key] = n;
		used[n] = true;
		map.next = max(map.next, n + 1);
		changed = true;
	}

	if (changed && !ubbf.write_file_atomic(path, sprintf('%.J\n', all)))
		log_err('instance map: failed to write %s', path);
};

/**
 * Drops the keys of rows that are gone, for a table whose keys never come
 * back, such as random session ids. The next free number stays, so a
 * number is not given to another row.
 *
 * @param {string} table - Table path
 * @param {array} present - Stable keys of the rows present
 * @param {boolean} volatile - As for instance_numbers()
 */
export function instance_prune(table, present, volatile) {
	let path = volatile ? VOLATILE_PATH : MAP_PATH;
	let map = map_load(path)[table];
	let changed = false;

	for (let key in keys(map?.keys ?? {})) {
		if (index(present, key) >= 0)
			continue;
		delete map.keys[key];
		changed = true;
	}

	if (changed && !ubbf.write_file_atomic(path, sprintf('%.J\n', maps[path])))
		log_err('instance map: failed to write %s', path);
};

/**
 * Returns the key of the row with an instance number.
 *
 * @param {string} table - Table path
 * @param {array} keys - Stable keys of the rows present
 * @param {*} instance - Instance number
 * @param {boolean} volatile - As for instance_numbers()
 * @returns {string|null} The key, or null when no present row has it
 */
export function instance_key(table, keys, instance, volatile) {
	let n = ubbf.to_int(instance);
	for (let key, number in instance_numbers(table, keys, volatile))
		if (number == n)
			return key;
	return null;
};

/**
 * Builds the rows of a table keyed by their stable instance numbers.
 *
 * @param {string} table - Table path
 * @param {array} keys - Stable keys of the rows present
 * @param {function} fn - Called with the key and its instance number,
 *                        returns the row
 * @param {boolean} volatile - As for instance_numbers()
 * @returns {object} Instance number to row
 */
export function instance_rows(table, keys, fn, volatile) {
	let rows = {};
	for (let key, number in instance_numbers(table, keys, volatile))
		rows[sprintf('%d', number)] = fn(key, number);
	return rows;
};
