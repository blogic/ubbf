'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf';

const FS_READ = [
	'access', 'basename', 'dirname', 'error', 'glob', 'lsdir', 'lstat',
	'readfile', 'readlink', 'realpath', 'stat'
];

/**
 * Refuses a call that would change the device during a render.
 *
 * @param {string} name - Name of the refused function
 * @returns {function} Function that raises when called
 */
function render_refuse(name) {
	return () => die(`${name}() changes the device: a render records it as an effect`);
}

/**
 * Returns the fs functions a render may call.
 *
 * `popen()` stays for templates that read a command's output; it accepts
 * the read mode only.
 *
 * @returns {object} Read-only subset of the fs module
 */
function fs_readonly() {
	let ro = {};
	for (let name in FS_READ)
		ro[name] = fs[name];

	ro.popen = (command, mode) => {
		if (mode != null && mode != 'r')
			die(`popen() mode '${mode}' changes the device: a render reads only`);
		return fs.popen(command, 'r');
	};

	return ro;
}

/**
 * Returns the ubbf module without its file writer.
 *
 * @returns {object} The ubbf module functions except write_file_atomic
 */
function ubbf_readonly() {
	let ro = {};
	for (let name, value in ubbf)
		if (name != 'write_file_atomic')
			ro[name] = value;
	return ro;
}

/**
 * Returns the scope entries that keep a render free of side effects.
 *
 * A render runs for `apply --dry-run` too, so a template records every
 * change to the device in `effects`, and apply runs the list after the
 * UCI commit. The direct ways to change the device raise.
 *
 * @param {array} effects - List the effect_* functions append to
 * @returns {object} Scope entries for fs, ubbf, system and the effect_* functions
 */
export function render_scope_effects(effects) {
	return {
		fs: fs_readonly(),
		ubbf: ubbf_readonly(),
		system: render_refuse('system'),

		effect_file_write: (path, content) =>
			push(effects, { action: 'file_write', path, content }),
		effect_file_replace: (path, content) =>
			push(effects, { action: 'file_replace', path, content }),
		effect_file_remove: (path) =>
			push(effects, { action: 'file_remove', path }),
		effect_dir_create: (path) =>
			push(effects, { action: 'dir_create', path }),
		effect_ubus_call: (object, method, data) =>
			push(effects, { action: 'ubus_call', object, method, data: data ?? {} }),
		effect_command: (command) =>
			push(effects, { action: 'command', command })
	};
};

// A missing file to remove and an existing directory to create are the
// states the templates ask for, so those two results count as success.
const effect_runners = {
	file_write: (e) => fs.writefile(e.path, e.content) != null,
	file_replace: (e) => ubbf.write_file_atomic(e.path, e.content),
	file_remove: (e) => fs.unlink(e.path) || !fs.lstat(e.path),
	dir_create: (e) => fs.mkdir(e.path, 0755) || fs.stat(e.path)?.type == 'directory',
	ubus_call: (e) => {
		ubus.call({ object: e.object, method: e.method, data: e.data });
		return true;
	},
	command: (e) => {
		system(e.command);
		return true;
	}
};

/**
 * Runs the effects a render recorded, in the order recorded.
 *
 * @param {array} effects - Effects from generate()
 * @returns {number} Number of effects that failed
 */
export function effects_run(effects) {
	let failed = 0;

	for (let e in effects ?? []) {
		let runner = effect_runners[e?.action];
		if (!runner) {
			log_err('render effect: unknown action %s', e?.action);
			failed++;
			continue;
		}
		if (!runner(e)) {
			log_err('render effect: %s %s failed', e.action, e.path ?? '');
			failed++;
		}
	}

	return failed;
};
