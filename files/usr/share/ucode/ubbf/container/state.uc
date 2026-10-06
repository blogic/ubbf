'use strict';

import * as fs from 'fs';

const STATE_DIR = '/tmp/containers';

let restart_timers = {};
let manually_stopped = {};

/**
 * Returns the pending uloop restart timer for a container, if any.
 *
 * @param {string} name - Container name
 * @returns {object|null} Pending uloop timer handle or null
 */
export function restart_timer_get(name) {
	return restart_timers[name];
};

/**
 * Stores a pending uloop restart timer for a container.
 *
 * @param {string} name - Container name
 * @param {object} timer - uloop timer handle returned by uloop.timer()
 */
export function restart_timer_set(name, timer) {
	restart_timers[name] = timer;
};

/**
 * Drops the pending uloop restart timer reference for a container.
 *
 * @param {string} name - Container name
 */
export function restart_timer_clear(name) {
	delete restart_timers[name];
};

/**
 * Marks a container as manually stopped so the autorestart monitor skips it.
 *
 * @param {string} name - Container name
 */
export function manually_stopped_set(name) {
	manually_stopped[name] = true;
};

/**
 * Clears the manually-stopped flag for a container, re-enabling autorestart.
 *
 * @param {string} name - Container name
 */
export function manually_stopped_clear(name) {
	delete manually_stopped[name];
};

/**
 * @param {string} name - Container name
 * @returns {boolean} True when the container is flagged as manually stopped
 */
export function is_manually_stopped(name) {
	return !!manually_stopped[name];
};

/**
 * Reads per-container runtime state from /tmp.
 *
 * @param {string} name - Container name
 * @returns {object} Runtime state (retry_count, last_restarted, running_since)
 */
export function runtime_state_read(name) {
	let path = sprintf('%s/%s.json', STATE_DIR, name);
	let content = fs.readfile(path);
	if (!content)
		return { retry_count: 0, last_restarted: null, running_since: null };

	return json(content) ?? { retry_count: 0, last_restarted: null, running_since: null };
};

/**
 * Writes per-container runtime state to /tmp.
 *
 * @param {string} name - Container name
 * @param {object} state - Runtime state to persist
 */
export function runtime_state_write(name, state) {
	fs.mkdir(STATE_DIR, 0755);
	fs.writefile(sprintf('%s/%s.json', STATE_DIR, name), sprintf('%.J\n', state));
};

/**
 * Removes per-container runtime state.
 *
 * @param {string} name - Container name
 */
export function runtime_state_remove(name) {
	fs.unlink(sprintf('%s/%s.json', STATE_DIR, name));
	restart_timer_clear(name);
	delete manually_stopped[name];
};
