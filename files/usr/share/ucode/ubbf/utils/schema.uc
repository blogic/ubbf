'use strict';

let TYPE_NAMES;

/**
 * Initialises the TYPE_NAMES mapping from dm_type values to names.
 */
function type_names_init() {
	if (TYPE_NAMES)
		return;

	TYPE_NAMES = {};
	for (let name, value in dm_type) {
		if (name == 'WRITABLE')
			continue;
		TYPE_NAMES[value] = 'DM_' + name;
	}
}

/**
 * Decodes a dm_type value into writable flag and type name.
 *
 * @param {number} value - dm_type value
 * @returns {object} Object with writable boolean and type string
 */
function type_decode(value) {
	let writable = (value & dm_type.WRITABLE) != 0;
	let type_bits = value & ~dm_type.WRITABLE;

	return {
		writable,
		type: TYPE_NAMES[type_bits] ?? 'DM_STRING'
	};
}

/**
 * Extracts schema information from a model for USP agent use.
 *
 * @param {object} model - The full model definition
 * @param {function} members_get - Returns the schema members of a model entry,
 *                                 given the entry and its object pattern
 * @returns {object} Schema with objects and events
 */
export function extract(model, members_get) {
	let schema = { objects: {}, events: {} };

	for (let path, entry in model) {
		let params = {};

		for (let param_name, param_def in (members_get(entry, path) ?? {})) {
			if (type(param_def) == 'object' && param_def.type == 'event') {
				let event_path = path + '.' + param_name;
				schema.events[event_path] = param_def.input ?? [];
				continue;
			}

			params[param_name] = param_def;
		}

		schema.objects[path] = params;
	}

	return schema;
};

/**
 * Describes one parameter of a model entry: its decoded type and writability
 * plus the constraints its schema states.
 *
 * @param {object} entry - Model entry of the object pattern
 * @param {string} name - Parameter name
 * @returns {object|null} Parameter facts, or null when the entry's schema
 *                        does not describe the parameter
 */
export function param_info(entry, name) {
	let value = entry?.schema?.schema?.[name];

	if (value == null)
		return null;

	if (type(value) == 'object')
		return {
			command: true,
			type: value.type,
			input: value.input,
			output: value.output
		};

	type_names_init();

	// The decoded type and writability win, so a constraints entry can add
	// facts but never contradict the schema value it annotates.
	return {
		...(entry.schema.constraints?.[name] ?? {}),
		...type_decode(value)
	};
};
