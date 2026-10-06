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
 * @returns {object} Schema with objects and events
 */
export function extract(model) {
	let schema = { objects: {}, events: {} };

	for (let path in model) {
		let obj = model[path];
		let params = {};

		if (obj.schema && obj.schema.schema) {
			for (let param_name in obj.schema.schema) {
				let param_def = obj.schema.schema[param_name];

				if (type(param_def) == 'object' && param_def.type == 'event') {
					let event_path = path + '.' + param_name;
					schema.events[event_path] = param_def.input ?? [];
					continue;
				}

				params[param_name] = param_def;
			}
		}

		schema.objects[path] = params;
	}

	return schema;
};

/**
 * Combines the generated constraints for one object with its curated ones.
 *
 * The merge is per parameter, not per object: a curated entry usually states
 * one extra fact, such as `secured`, and must not discard the lengths or the
 * enumeration the spec dump supplied for that same parameter.
 *
 * @param {object} generated - Generated table for this object pattern
 * @param {object} curated - Table written beside the schema, if any
 * @returns {object} Parameter name to merged facts
 */
function constraints_merge(generated, curated) {
	let out = {};

	for (let name, facts in (generated ?? {}))
		out[name] = { ...facts };

	for (let name, facts in (curated ?? {}))
		out[name] = { ...(out[name] ?? {}), ...facts };

	return out;
}

/**
 * Extracts human-readable schema information from a model.
 *
 * @param {object} model - The full model definition
 * @returns {object} Human-readable schema with decoded types
 */
export function extract_readable(model, generated) {
	type_names_init();

	let schema = { objects: {} };

	for (let path in model) {
		let obj = model[path];
		let params = {};
		let constraints = constraints_merge((generated ?? {})[path],
						    obj.schema?.constraints);

		if (obj.schema && obj.schema.schema) {
			for (let param_name in obj.schema.schema) {
				let value = obj.schema.schema[param_name];
				if (type(value) == 'object') {
					params[param_name] = {
						command: true,
						type: value.type,
						input: value.input,
						output: value.output
					};
					continue;
				}

				// The decoded type and writability win, so a
				// constraints entry can add facts but never
				// contradict the schema value it annotates.
				params[param_name] = {
					...(constraints[param_name] ?? {}),
					...type_decode(value)
				};
			}
		}

		schema.objects[path] = params;
	}

	return schema;
};

/**
 * Merges vendor-specific attributes into a base schema.
 *
 * @param {object} schema - Base schema with path, schema, and defaults
 * @param {object} vendor_attr - Vendor attributes with schema and defaults to merge
 * @returns {object} Combined schema with merged properties
 */
export function vendor_schema(schema, vendor_attr) {
	return {
		path: schema.path,
		schema: { ...schema.schema, ...vendor_attr.schema },
		defaults: { ...schema.defaults, ...vendor_attr.defaults },
		constraints: { ...(schema.constraints ?? {}),
			       ...(vendor_attr.constraints ?? {}) }
	};
};
