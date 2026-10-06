'use strict';

import { readfile, writefile, unlink, popen } from 'fs';
import * as digest from 'digest';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf.utils.logging';

const CONFIG_PATH = '/etc/ubbf/config.json';
const BACKUP_SUFFIX = '.bak';

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

	return ubbf.write_file_atomic(path, sprintf('%.J\n', data)) ? true : null;
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

/**
 * Applies a configuration file using ubbf-apply.
 *
 * @param {string} path - Path to config file (defaults to CONFIG_PATH)
 * @returns {object} Result with success status and output
 */
export function config_apply(path) {
	path ??= CONFIG_PATH;

	let cmd = sprintf('/usr/libexec/ubbf/apply "%s" 2>&1', path);
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

/**
 * Safely applies a configuration with validation and rollback on failure.
 *
 * @param {string} source_path - Path to new config file
 * @param {string} target_path - Target path (defaults to CONFIG_PATH)
 * @returns {object} Result with success status and error if applicable
 */
export function config_apply_safe(source_path, target_path) {
	target_path ??= CONFIG_PATH;
	let backup_path = target_path + BACKUP_SUFFIX;

	let original = readfile(target_path);
	if (!original)
		return { success: false, error: 'Cannot read current config' };

	let validation = config_validate(source_path);
	if (!validation.success)
		return { success: false, error: sprintf('Validation failed: %s', validation.output) };

	if (writefile(backup_path, original) == null)
		return { success: false, error: 'Cannot create backup' };

	let new_content = readfile(source_path);
	if (!new_content) {
		unlink(backup_path);
		return { success: false, error: 'Cannot read source config' };
	}

	if (writefile(target_path, new_content) == null) {
		unlink(backup_path);
		return { success: false, error: 'Cannot write config' };
	}

	let result = config_apply(target_path);
	if (!result.success) {
		if (writefile(target_path, original) == null) {
			log_err('config_apply_safe: apply failed AND rollback failed, backup at %s', backup_path);
			return { success: false, error: sprintf('Apply failed, rollback failed: %s', result.output) };
		}
		unlink(backup_path);
		return { success: false, error: sprintf('Apply failed, rolled back: %s', result.output) };
	}

	unlink(backup_path);
	return { success: true, error: null };
};
