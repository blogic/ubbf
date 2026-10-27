'use strict';

// Stable instance numbers for tables whose rows the CPE builds from the
// devices present (cages, USB devices, modems, hosts). TR-369 R-ARC.8: an
// instance number does not change until its object is deleted, so a row
// keeps its number while other rows come and go, and a number is not given
// to another device. The map keeps a key per device, for example a cage
// name, and the next free number of each table.
//
// The map lives in /tmp only: a reboot ends a row that no configuration
// points at, so it may come back with another number. The rows that the
// configuration stores or names keep their numbers through pins, which
// config.json carries in its `_instances` section (instance_pins()).
//
// Each entry holds its number and when a read last saw its key. A key
// that no read saw for EXPIRE_S leaves the map, so a table of clients that
// come and go does not grow until the next reboot; the next free number
// stays, so the number is not given to another row. Pinned keys stay.

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf.utils.logging';

const MAP_DIR = '/tmp/ubbf';
const MAP_PATH = MAP_DIR + '/instance-map.json';
const CONFIG_PATH = '/etc/ubbf/config.json';

// last_seen is refreshed only when it is older than SEEN_STEP_S, so that a
// read does not write the map each time. The clock is monotonic: the map
// lives only until the next reboot.
const EXPIRE_S = 86400;
const SEEN_STEP_S = EXPIRE_S / 8;

let maps;
let maps_id;

function file_id(st) {
	return st ? sprintf('%d:%d:%d', st.ino, st.mtime, st.size) : null;
}

function json_read(path) {
	try {
		let data = json(fs.readfile(path) ?? '{}');
		return (type(data) == 'object') ? data : {};
	} catch (e) {
		return {};
	}
}

function maps_store() {
	fs.mkdir(MAP_DIR, 0755);
	if (!ubbf.write_file_atomic(MAP_PATH, sprintf('%.J\n', maps)))
		log_err('instance map: failed to write %s', MAP_PATH);
	maps_id = file_id(fs.stat(MAP_PATH));
}

let pins_seed;

// The agent numbers the rows, and the render and ubbf-device read the
// numbers, so a process reads the file again when another one wrote it.
// After a reboot the first process to come seeds the map from the pins of
// config.json, so that a render before the agent starts finds them.
function maps_load() {
	let id = file_id(fs.stat(MAP_PATH));
	if (maps && id == maps_id)
		return maps;

	maps = id ? json_read(MAP_PATH) : {};
	maps_id = id;

	if (!id)
		pins_seed(json_read(CONFIG_PATH)._instances);

	return maps;
}

function table_map(table) {
	return (maps_load()[table] ??= { next: 1, keys: {} });
}

function number_take(map, floor) {
	let n = max(map.next, floor ?? 1);
	map.next = n + 1;
	return n;
}

function uptime() {
	return clock(true)[0];
}

function keys_see(map, keys, floor, now) {
	let changed = false;

	for (let key in keys) {
		let entry = map.keys[key];
		if (entry == null) {
			map.keys[key] = { n: number_take(map, floor), last_seen: now };
			changed = true;
		} else if (entry.last_seen == null || now - entry.last_seen >= SEEN_STEP_S) {
			entry.last_seen = now;
			changed = true;
		}
	}

	return changed;
}

function pinned_keys(table) {
	let pinned = {};
	for (let n, key in json_read(CONFIG_PATH)._instances?.[table] ?? {})
		pinned[key] = true;
	return pinned;
}

// A retired key (#n) keeps its number reserved for good.
function keys_expire(table, map, now) {
	let stale = filter(keys(map.keys), (key) => substr(key, 0, 1) != '#' &&
		now - (map.keys[key].last_seen ?? now) > EXPIRE_S);
	if (!length(stale))
		return false;

	let pinned = pinned_keys(table);
	for (let key in stale) {
		if (pinned[key])
			map.keys[key].last_seen = now;
		else
			delete map.keys[key];
	}
	return true;
}

/**
 * Returns the instance number of each key, giving new keys the next free
 * numbers in the order of `keys`. A first call thus numbers the rows as
 * their position did. The keys of absent rows that no read saw for a day
 * leave the map, so `keys` must hold every row present.
 *
 * @param {string} table - Table path with the numbers of its parent rows,
 *                         for example Device.USB.USBHosts.Host.2.Device
 * @param {array} keys - Stable keys of the rows present
 * @param {number} [floor] - Lowest number a new key may take: one above
 *                           the highest stored row, so that the rows the
 *                           CPE finds follow the stored ones
 * @returns {object} Key to instance number
 */
export function instance_numbers(table, keys, floor) {
	let map = table_map(table);
	let now = uptime();
	let changed = keys_see(map, keys, floor, now);

	if (keys_expire(table, map, now))
		changed = true;

	if (changed)
		maps_store();

	let numbers = {};
	for (let key in keys)
		numbers[key] = map.keys[key].n;
	return numbers;
};

/**
 * Returns the instance number of one row, for a caller that does not know
 * the other rows present; it removes no key.
 *
 * @param {string} table - Table path
 * @param {string} key - Stable key of the row
 * @returns {number} The instance number
 */
export function instance_number(table, key) {
	let map = table_map(table);
	if (keys_see(map, [ key ], null, uptime()))
		maps_store();
	return map.keys[key].n;
};

/**
 * Takes the next free number of a table for a row that a controller adds,
 * so that no row the CPE finds gets it later.
 *
 * @param {string} table - Table path
 * @param {number} [floor] - One above the highest stored row
 * @returns {number} The instance number
 */
export function instance_next(table, floor) {
	let n = number_take(table_map(table), floor);
	maps_store();
	return n;
};

/**
 * Reports whether the map numbers a table.
 *
 * @param {string} table - Table path
 * @returns {boolean} True when the map holds the table
 */
export function instance_table_known(table) {
	return maps_load()[table] != null;
};

/**
 * Drops the keys of rows that are gone, for a table whose keys never come
 * back, such as random session ids. The next free number stays, so a
 * number is not given to another row.
 *
 * @param {string} table - Table path
 * @param {array} present - Stable keys of the rows present
 */
export function instance_prune(table, present) {
	let map = maps_load()[table];
	let changed = false;

	for (let key in keys(map?.keys ?? {})) {
		if (index(present, key) >= 0)
			continue;
		delete map.keys[key];
		changed = true;
	}

	if (changed)
		maps_store();
};

/**
 * Returns the key of the row with an instance number.
 *
 * @param {string} table - Table path
 * @param {array} keys - Stable keys of the rows present
 * @param {*} instance - Instance number
 * @param {number} [floor] - As for instance_numbers()
 * @returns {string|null} The key, or null when no present row has it
 */
export function instance_key(table, keys, instance, floor) {
	let n = ubbf.to_int(instance);
	for (let key, number in instance_numbers(table, keys, floor))
		if (number == n)
			return key;
	return null;
};

/**
 * Returns the key that the map holds for an instance number, without
 * numbering new keys.
 *
 * @param {string} table - Table path
 * @param {*} instance - Instance number
 * @returns {string|null} The key, or null when the map has none
 */
export function instance_lookup(table, instance) {
	let n = ubbf.to_int(instance);
	for (let key, entry in maps_load()[table]?.keys ?? {})
		if (entry.n == n)
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
 * @param {number} [floor] - As for instance_numbers()
 * @returns {object} Instance number to row
 */
export function instance_rows(table, keys, fn, floor) {
	let rows = {};
	for (let key, number in instance_numbers(table, keys, floor))
		rows[sprintf('%d', number)] = fn(key, number);
	return rows;
};

/**
 * Numbers the items of a table whose keys never come back, such as the
 * row ids of a daemon: the keys of the items that are gone leave the map.
 *
 * @param {string} table - Table path
 * @param {array} items - Items present
 * @param {function} key_fn - Returns the key of an item as a string
 * @param {number} [floor] - As for instance_numbers()
 * @returns {object} Instance number to item
 */
export function instance_items(table, items, key_fn, floor) {
	let ids = map(items, key_fn);
	let numbers = instance_numbers(table, ids, floor);
	instance_prune(table, ids);

	let rows = {};
	for (let i, item in items)
		rows[sprintf('%d', numbers[ids[i]])] = item;
	return rows;
};

/**
 * Returns one above the highest instance number of a stored table, the
 * floor of the numbers that the CPE gives the rows it finds.
 *
 * @param {object|null} rows - Stored table, instance number to row
 * @returns {number} The floor, 1 for an empty table
 */
export function instance_floor(rows) {
	let top = 0;
	for (let key in keys(rows ?? {}))
		if (ubbf.is_instance_key(key))
			top = max(top, +key);
	return top + 1;
};

/**
 * Gives each entry of a record store (faults, reboots) an `id`, the
 * instance number of its row, so that a removal or a rotation moves no
 * other row. An entry without one gets the next number in list order;
 * the writer and the readers of a store thus give the same numbers.
 *
 * @param {array} entries - Entries of the store, changed in place
 * @param {number} [next] - Next id the store keeps, null when it keeps none
 * @returns {number} The next free id
 */
export function instance_ids(entries, next) {
	let top = 0;
	for (let e in entries ?? [])
		if (type(e?.id) == 'int')
			top = max(top, e.id);

	next = max(next ?? 1, top + 1);
	for (let e in entries ?? [])
		if (type(e) == 'object' && type(e.id) != 'int')
			e.id = next++;
	return next;
};

/**
 * Builds the rows of a record store keyed by the ids of instance_ids().
 *
 * @param {array} entries - Entries with ids
 * @param {function} fn - Called with an entry, returns the row
 * @returns {object} Instance number to row
 */
export function instance_id_rows(entries, fn) {
	let rows = {};
	for (let e in entries ?? [])
		rows[sprintf('%d', e.id)] = fn(e);
	return rows;
};

function stack_claim(stored, items, taken, rows, claim_fn) {
	let numbers = sort(filter(keys(stored ?? {}), (k) => ubbf.is_instance_key(k)), (a, b) => +a - +b);
	for (let n in numbers) {
		if (rows[n] != null)
			continue;
		for (let i, item in items) {
			if (taken[i] || !claim_fn(stored[n], item))
				continue;
			taken[i] = true;
			rows[n] = item;
			break;
		}
	}
}

/**
 * Numbers the live items of a table that also stores rows, for a table
 * whose items need no number of their own across a reboot: a stored row
 * keeps its number and takes the item it claims, and the other items
 * follow the highest stored row in the order given.
 *
 * @param {object|null} stored - Stored table, instance number to row
 * @param {array} items - Live items
 * @param {function} exact_fn - (row, item): the row names the item, for
 *                              example by its address
 * @param {function} [loose_fn] - (row, item): the row takes the item when
 *                                no row names it, for example a DHCP row
 * @returns {object} Instance number to item; a stored row without an item
 *                   is absent
 */
export function instance_stack(stored, items, exact_fn, loose_fn) {
	let taken = [];
	let rows = {};

	stack_claim(stored, items, taken, rows, exact_fn);
	if (loose_fn)
		stack_claim(stored, items, taken, rows, loose_fn);

	let n = instance_floor(stored);
	for (let i, item in items)
		if (!taken[i])
			rows[sprintf('%d', n++)] = item;

	return rows;
};

function tree_node(root, table) {
	let node = root;
	for (let part in split(table, '.')) {
		if (type(node) != 'object')
			return null;
		node = node[part];
	}
	return node;
}

function pin_add(pins, reverse, table, n) {
	let key = reverse[table]?.[n];
	if (key == null)
		return;
	(pins[table] ??= {})[n] = key;
}

function references_pin(pins, reverse, value) {
	if (type(value) == 'object' || type(value) == 'array') {
		for (let k, v in value)
			references_pin(pins, reverse, v);
		return;
	}

	if (type(value) != 'string' || index(value, 'Device.') < 0)
		return;

	for (let m in match(value, /Device\.[A-Za-z0-9_.]+/g)) {
		let parts = split(rtrim(m[0], '.'), '.');
		for (let i = 1; i < length(parts); i++)
			if (ubbf.is_instance_key(parts[i]))
				pin_add(pins, reverse, join('.', slice(parts, 0, i)), parts[i]);
	}
}

function pins_sorted(pins) {
	let sorted = {};
	for (let table in sort(keys(pins))) {
		let numbers = sort(keys(pins[table]), (a, b) => +a - +b);
		sorted[table] = {};
		for (let n in numbers)
			sorted[table][n] = pins[table][n];
	}
	return sorted;
}

/**
 * Computes the pins of a configuration: the numbers of the mapped rows
 * that it stores, and those of the mapped rows that a stored string names
 * (`Device.<table>.<n>`, also inside a comma list). A pin keeps its key
 * from the live map; a row that nothing names has no pin. The same
 * configuration gives the same pins, in a stable order.
 *
 * @param {object} config - Configuration tree with Device
 * @returns {object} Table path to { instance number: key }
 */
export function instance_pins(config) {
	let reverse = {};
	for (let table, map in maps_load()) {
		reverse[table] = {};
		for (let key, entry in map.keys)
			reverse[table][sprintf('%d', entry.n)] = key;
	}

	let pins = {};
	for (let table in reverse)
		for (let n in keys(tree_node(config, table) ?? {}))
			if (ubbf.is_instance_key(n))
				pin_add(pins, reverse, table, n);

	references_pin(pins, reverse, config?.Device);

	return pins_sorted(pins);
};

/**
 * Seeds the map from the pins of config.json at start-up: a pinned key
 * takes its number back, and a number stays reserved while its row is
 * absent. A pin yields to a key that holds the number already.
 *
 * @param {object|null} pins - As instance_pins() returns
 */
export function instance_pins_load(pins) {
	let changed = false;
	let now = uptime();

	for (let table, numbers in pins ?? {}) {
		if (type(numbers) != 'object')
			continue;

		let map = table_map(table);
		let used = {};
		for (let key, entry in map.keys)
			used[entry.n] = key;

		for (let n, key in numbers) {
			n = ubbf.to_int(n);
			if (type(key) != 'string' || n == null || n < 1 || used[n] != null)
				continue;
			if (map.keys[key] != null)
				delete used[map.keys[key].n];
			map.keys[key] = { n, last_seen: now };
			used[n] = key;
			map.next = max(map.next, n + 1);
			changed = true;
		}
	}

	if (changed)
		maps_store();
};

pins_seed = instance_pins_load;

/**
 * Returns the numbers that the map holds for keys, without numbering new
 * keys, for a process other than the agent: only the agent gives numbers.
 *
 * @param {string} table - Table path
 * @param {array} keys - Stable keys of the rows present
 * @returns {object} Key to instance number, for the keys the map holds
 */
export function instance_numbers_known(table, keys) {
	let map = maps_load()[table]?.keys ?? {};
	let numbers = {};
	for (let key in keys)
		if (map[key] != null)
			numbers[key] = map[key].n;
	return numbers;
};

/**
 * Keeps the number of a row that is gone for good under a key that no row
 * can have, so that a new row with the key of the old one gets a new
 * number, and a stored reference to the old number keeps it reserved.
 *
 * @param {string} table - Table path
 * @param {string} key - Key of the row
 */
export function instance_retire(table, key) {
	let map = maps_load()[table];
	let n = map?.keys?.[key]?.n;
	if (n == null)
		return;

	delete map.keys[key];
	map.keys[sprintf('#%d', n)] = { n };
	maps_store();
};

// The numbering that a process other than the agent passes to code that it
// shares with the agent, such as modules/security/certificates.uc.
export const instance_map_readonly = {
	instance_numbers: instance_numbers_known,
	instance_retire: () => null
};
