'use strict';

import * as fs from 'fs';
import * as digest from 'digest';
import * as ubbf from 'ubbf';

const STATE_PATH = '/tmp/ubbf/uci-last-changed.json';

function state_load(path) {
	let raw = fs.readfile(path);
	if (!raw)
		return {};
	try {
		let parsed = json(raw);
		return (type(parsed) == 'object') ? parsed : {};
	} catch (e) {
		return {};
	}
}

/**
 * Hashes every regular file in shadow_dir and updates state_path with
 * a {md5, lastchanged} entry per file. The lastchanged ISO 8601
 * timestamp advances only when the file's md5 differs from the value
 * stored in the previous state, so a render that produces the same
 * UCI bytes does not bump the timestamp.
 *
 * Failures are non-fatal: callers should treat the state file as a
 * best-effort cache and fall back when entries are missing.
 *
 * @param {string} shadow_dir - directory holding the rendered UCI files
 * @param {string} state_path - JSON state file path
 */
export function update_after_apply(shadow_dir, state_path) {
	let entries = fs.lsdir(shadow_dir);
	if (!entries)
		return;

	let state = state_load(state_path);
	let now = ubbf.iso8601_format();

	for (let name in entries) {
		let full = shadow_dir + '/' + name;
		let st = fs.stat(full);
		if (!st || st.type != 'file')
			continue;

		let content = fs.readfile(full);
		if (content == null)
			continue;

		let md5 = digest.md5(content);
		if (state[name]?.md5 == md5)
			continue;

		state[name] = { md5: md5, lastchanged: now };
	}

	fs.writefile(state_path, sprintf('%.J', state));
};

/**
 * Returns the ISO 8601 timestamp at which the rendered UCI for the
 * named config last changed, or null when the state file is missing,
 * unreadable, or has no entry for this name (e.g. before the first
 * apply has run after boot).
 *
 * @param {string} name - UCI config name (e.g. "firewall")
 * @returns {string|null}
 */
export function last_changed_get(name) {
	let state = state_load(STATE_PATH);
	return state[name]?.lastchanged;
};
