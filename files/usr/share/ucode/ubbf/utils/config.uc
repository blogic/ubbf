'use strict';

import { readfile, popen } from 'fs';
import * as digest from 'digest';
import * as ubbf from 'ubbf';

const CONFIG_PATH = '/etc/ubbf/config.json';

/**
 * Loads configuration from a JSON file.
 *
 * @param {string} path - Path to config file (defaults to CONFIG_PATH)
 * @returns {object|null} Object with data and hash, or null on failure
 */
export function config_load(path) {
	path ??= CONFIG_PATH;

	let content = readfile(path);
	if (!content)
		return null;

	let data = json(content);
	if (!data)
		return null;

	return {
		data: data,
		hash: digest.sha256(content)
	};
};

/**
 * Saves configuration data to a JSON file atomically.
 *
 * @param {string} path - Path to config file (defaults to CONFIG_PATH)
 * @param {object} data - Configuration data to save
 * @returns {boolean|null} True on success, null on failure
 */
export function config_save(path, data) {
	path ??= CONFIG_PATH;

	return ubbf.write_file_atomic(path, sprintf('%.J\n', data), 0600) ? true : null;
};

/**
 * Validates a configuration file using ubbf-apply dry-run.
 *
 * @param {string} path - Path to config file (defaults to CONFIG_PATH)
 * @returns {object} Result with success status and output
 */
export function config_validate(path) {
	path ??= CONFIG_PATH;

	let cmd = sprintf('/usr/libexec/ubbf/apply --dry-run "%s" 2>&1', path);
	let p = popen(cmd, 'r');
	if (!p)
		return { success: false, output: 'Failed to execute ubbf-apply' };

	let output = p.read('all');
	let exitcode = p.close();

	return {
		success: (exitcode == 0),
		output: output
	};
};

// The data model keeps the live config in memory, so a whole-file restore has
// to go through it. It imports every TR-181 handler, so a handler cannot
// import it back without a cycle; it registers its restore here instead.
let restore_hook;

/**
 * Registers the function that replaces the live config with a file.
 *
 * @param {function} fn - Called with the file path and the `done` callback,
 *                        returns the result object or null when queued
 */
export function config_restore_hook_set(fn) {
	restore_hook = fn;
};

/**
 * Replaces the live config with a config file through the data model.
 *
 * The file is read at once. While a USP transaction is open the restore
 * waits for it to end, and `done` gets the result.
 *
 * @param {string} path - Path to the new config file
 * @param {function} done - Called with the result of a queued restore
 * @returns {object|null} null when the restore is queued, else
 *                        `{ success, error?, rolled_back? }`
 */
export function config_restore(path, done) {
	if (!restore_hook)
		return { success: false, error: 'No data model to restore into' };

	return restore_hook(path, done);
};
