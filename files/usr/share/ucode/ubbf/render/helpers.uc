'use strict';

/**
 * Sets a value in the device render state.
 *
 * @param {object} render_state - Render state object
 * @param {string} name - Device name
 * @param {string} key - Property key
 * @param {any} value - Value to set
 */
export function device_state_set(render_state, name, key, value) {
	render_state.device ??= {};
	render_state.device[name] ??= { name };
	render_state.device[name][key] = value;
};

/**
 * Adds a value to a list in the device render state.
 *
 * @param {object} render_state - Render state object
 * @param {string} name - Device name
 * @param {string} key - Property key for the list
 * @param {any} value - Value to add to list
 */
export function device_state_list_add(render_state, name, key, value) {
	render_state.device ??= {};
	render_state.device[name] ??= { name };
	render_state.device[name][key] ??= [];
	push(render_state.device[name][key], value);
};
