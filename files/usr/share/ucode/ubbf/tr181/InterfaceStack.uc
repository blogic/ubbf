'use strict';

import * as schemas from 'ubbf.schemas.InterfaceStack';
import * as ubbf from 'ubbf';

let dm_ref = null;

/**
 * Late-binds the dm handle so alias_get can resolve runtime-computed
 * aliases (e.g. Device.Optical.Interface.{i}.Alias) that exist only
 * in the with-state tree, not in stored config. Called once at boot
 * from datamodel.uc after the dm is created and the model is
 * registered; importing dm directly would form a cycle since
 * datamodel.uc imports this module.
 *
 * @param {object} dm - The datamodel handle from ubbf.create()
 */
export function bind_dm(dm) {
	dm_ref = dm;
};

/**
 * Gets the Alias property for a data model path.
 *
 * Reads from the live (with-state) data model so dynamically-discovered
 * instances surface their runtime Alias. Falls back to '' when the dm
 * handle is not yet bound or the lookup misses.
 *
 * @param {string} path - Data model path
 * @returns {string} Alias value or empty string
 */
function alias_get(path) {
	let node = dm_ref?.get_subtree_with_state(path);
	return node?.Alias ?? '';
}

/**
 * Parses LowerLayers string and adds relationships to results.
 *
 * @param {string} layers_str - Comma-separated LowerLayers value
 * @param {string} higher_path - Path of the higher layer object
 * @param {array} results - Array to collect relationships into
 */
function lowerlayers_parse(layers_str, higher_path, results) {
	for (let layer in ubbf.csv_to_list(layers_str))
		push(results, { higher: higher_path, lower: layer });
}

/**
 * Recursively collects LowerLayers relationships from configuration.
 *
 * @param {object} node - Current node in configuration tree
 * @param {string} path_prefix - Current path prefix
 * @param {array} results - Array to collect relationships into
 */
function lowerlayers_collect(node, path_prefix, results) {
	if (type(node) != 'object')
		return;

	for (let key in node) {
		let child = node[key];
		let child_path = path_prefix ? path_prefix + '.' + key : key;

		// LowerLayers is a comma-separated reference list, not a sub-tree; parse it directly and skip the recursive descent below.
		if (key == 'LowerLayers' && type(child) == 'string' && child != '') {
			lowerlayers_parse(child, path_prefix, results);
			continue;
		}

		if (type(child) == 'object')
			lowerlayers_collect(child, child_path, results);
	}
}

/**
 * Converts a relationship to TR-181 InterfaceStack object.
 *
 * @param {object} rel - Relationship with higher/lower paths
 * @param {number} index - Instance index (1-based)
 * @returns {object} InterfaceStack entry
 */
function relationship_to_object(rel, index) {
	return {
		Alias: sprintf('cpe-Stack%d', index),
		HigherLayer: rel.higher,
		LowerLayer: rel.lower,
		HigherAlias: alias_get(rel.higher),
		LowerAlias: alias_get(rel.lower)
	};
}

/**
 * Get handler for Device.InterfaceStack.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single stack entry or enumerated stack entries
 */
function interfacestack_get(ctx) {
	let root = ctx.root;
	if (!root)
		return null;

	let relationships = [];
	lowerlayers_collect(root.Device, 'Device', relationships);

	let to_object = (rel, idx) => relationship_to_object(rel, idx + 1);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(relationships, to_object);

	let rel = ubbf.get_by_instance(relationships, ctx.instance);
	if (!rel)
		return null;

	return to_object(rel, ctx.instance - 1);
}

/**
 * @param {object} root - Root configuration data
 * @returns {number} Number of InterfaceStack entries
 */
export function interfacestack_count(root) {
	if (!root)
		return 0;

	let relationships = [];
	lowerlayers_collect(root.Device, 'Device', relationships);
	return length(relationships);
};

export const model = {
	'Device.InterfaceStack': {
	},

	'Device.InterfaceStack.{i}': {
		schema: schemas.InterfaceStack,
		get: interfacestack_get
	}
};
