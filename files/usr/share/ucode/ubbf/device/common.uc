'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { readfile } from 'fs';
import { log_warn } from 'ubbf.utils.logging';
import { instance_ids } from 'ubbf.utils.instance-map';

const DEFAULT_MAX_ENTRIES = 100;

let cached_firmware_version;

/**
 * Returns the current firmware version string from ubus system.board.
 * Cached after first call.
 *
 * @returns {string} Firmware revision or 'unknown'
 */
export function firmware_version_get() {
	if (!cached_firmware_version) {
		let board = ubus.call({ object: 'system', method: 'board', data: {} });
		cached_firmware_version = board?.release?.revision ?? 'unknown';
	}

	return cached_firmware_version;
};

/**
 * Returns the free space in KiB on the filesystem hosting path, or -1 on error.
 *
 * @param {string} path - Filesystem path to inspect
 * @returns {number} Free KiB, or -1 on error
 */
export function storage_free_kib(path) {
	let info = ubbf.statvfs_info(path);
	return info?.avail_kib ?? -1;
};

/**
 * Normalises a parsed faults file into the { meta, faults } shape, with an
 * id on each fault and the next id in meta.next_id. Older formats stored a
 * bare array of faults.
 *
 * @param {*} parsed - Raw parsed JSON value
 * @returns {object} Object with meta and faults fields
 */
export function faults_state_normalise(parsed) {
	let state = { meta: {}, faults: [] };
	if (type(parsed) == 'array')
		state.faults = parsed;
	else if (type(parsed) == 'object')
		state = { meta: parsed.meta ?? {}, faults: parsed.faults ?? [] };

	state.meta.next_id = instance_ids(state.faults, state.meta.next_id);
	return state;
};

/**
 * Finds the entry with an id in a record store.
 *
 * @param {array} entries - Entries with ids (instance_ids())
 * @param {*} id - Instance number of the row
 * @returns {object|null} The entry, null when none has the id
 */
export function entries_find(entries, id) {
	for (let e in entries)
		if (e?.id == id)
			return e;
	return null;
};

/**
 * Removes the entry with an id from a record store.
 *
 * @param {array} entries - Entries with ids (instance_ids())
 * @param {*} id - Instance number of the row
 * @returns {boolean} True when an entry had the id
 */
export function entries_remove(entries, id) {
	for (let i, e in entries) {
		if (e?.id != id)
			continue;
		splice(entries, i, 1);
		return true;
	}
	return false;
};

/**
 * Applies storage/rotate/max-entries limits to a faults state and returns
 * whether a new entry can be stored. Mutates state.faults to rotate old
 * entries out when rotation is enabled.
 *
 * @param {object} state - Faults state ({ meta, faults })
 * @param {string} storage_path - Filesystem path for storage checks
 * @returns {boolean} true if a new entry may be appended
 */
export function fault_entry_should_store(state, storage_path) {
	let max_entries = state.meta.max_entries ?? DEFAULT_MAX_ENTRIES;
	if (max_entries == 0)
		return false;

	let min_free = state.meta.min_free_space ?? 0;
	if (min_free > 0 && storage_free_kib(storage_path) < min_free)
		return false;

	let rotate = state.meta.rotate ?? true;
	while (length(state.faults) >= max_entries) {
		if (!rotate)
			return false;
		shift(state.faults);
	}

	return true;
};

/**
 * Loads and parses a JSON state file, tolerating a missing or corrupt
 * file by returning the fallback. These files are best-effort history;
 * resetting beats crash-looping the daemon on a truncated file.
 *
 * @param {string} path - File to read
 * @param {*} fallback - Value returned when the file is absent or corrupt
 * @returns {*} Parsed content, or the fallback
 */
export function json_state_load(path, fallback) {
	let data = readfile(path);
	if (!data)
		return fallback;

	try {
		return json(data);
	} catch (e) {
		log_warn('%s: corrupt state file, resetting: %s', path, e);
		return fallback;
	}
};

/**
 * Persists a JSON state file atomically so a crash mid-write cannot
 * leave a truncated file behind.
 *
 * @param {string} path - Destination file
 * @param {*} state - Value to serialise
 * @returns {boolean} true on success
 */
export function json_state_save(path, state) {
	return ubbf.write_file_atomic(path, sprintf('%.J\n', state));
};
