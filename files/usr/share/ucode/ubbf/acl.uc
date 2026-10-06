'use strict';

import { readfile } from 'fs';
import * as ubbf from 'ubbf';

let acl_cache = {};

/**
 * Matches a path against a pattern with wildcard support.
 *
 * The pattern need not cover the full path: any path that is at least as long
 * as the pattern and matches every pattern segment (with `*` accepting any
 * single segment) is considered a match. Trailing path segments beyond the
 * pattern length are ignored.
 *
 * @param {string} path - The concrete path to match
 * @param {string} pattern - The pattern (supports `*` per-segment wildcard)
 * @returns {boolean} True if the path matches the pattern
 */
function pattern_match(path, pattern) {
	let path_parts = split(path, '.');
	let pattern_parts = split(pattern, '.');

	if (length(path_parts) < length(pattern_parts))
		return false;

	for (let i = 0; i < length(pattern_parts); i++) {
		if (pattern_parts[i] == '*')
			continue;
		if (pattern_parts[i] != path_parts[i])
			return false;
	}

	return true;
}

/**
 * Gets instance data from the tree at the wildcard position.
 *
 * @param {object} tree - The data tree
 * @param {array} path_parts - Parts of the path
 * @param {array} pattern_parts - Parts of the pattern
 * @returns {object|null} Instance data at the wildcard position, or null
 */
function get_instance_data(tree, path_parts, pattern_parts) {
	let current = tree;
	let instance_idx = -1;

	for (let i = 0; i < length(pattern_parts); i++) {
		if (pattern_parts[i] == '*') {
			instance_idx = i;
			break;
		}
		if (type(current) != 'object' || !(path_parts[i] in current))
			return null;
		current = current[path_parts[i]];
	}

	if (instance_idx < 0 || instance_idx >= length(path_parts))
		return null;

	let instance_key = path_parts[instance_idx];
	if (type(current) != 'object' || !(instance_key in current))
		return null;

	return current[instance_key];
}

/**
 * Checks if instance data matches the filter criteria.
 *
 * @param {object} instance_data - The instance data to check
 * @param {object} filter - Filter criteria (property-value pairs)
 * @returns {boolean} True if the instance matches all filter criteria
 */
function check_filter(instance_data, filter) {
	if (!filter || type(filter) != 'object')
		return true;

	for (let prop, expected in filter) {
		let actual = instance_data?.[prop];
		if (actual != expected)
			return false;
	}

	return true;
}

/**
 * Finds the best matching ACL rule for a given path.
 *
 * @param {object} acl_section - The ACL section (read or write)
 * @param {string} path - The data model path
 * @returns {object|null} Matching rule info with pattern and rule, or null
 */
function find_matching_rule(acl_section, path) {
	if (type(acl_section) != 'object')
		return null;

	let best_match = null;
	let best_len = 0;

	for (let pattern in acl_section) {
		if (!pattern_match(path, pattern))
			continue;

		let pattern_len = length(split(pattern, '.'));
		if (pattern_len > best_len) {
			best_match = { pattern, rule: acl_section[pattern] };
			best_len = pattern_len;
		}
	}

	return best_match;
}

/**
 * Extracts the property name from a path that extends beyond a pattern.
 *
 * @param {string} path - The full path
 * @param {string} pattern - The pattern path
 * @returns {string|null} The property name, or null if path doesn't extend pattern
 */
function extract_property_from_path(path, pattern) {
	let path_parts = split(path, '.');
	let pattern_parts = split(pattern, '.');

	if (length(path_parts) <= length(pattern_parts))
		return null;

	return path_parts[length(pattern_parts)];
}

/**
 * Loads an ACL file, with caching.
 *
 * @param {string} path - Path to the ACL JSON file
 * @returns {object|null} Parsed ACL object, or null on failure
 */
export function acl_load(path) {
	if (path in acl_cache)
		return acl_cache[path];

	let content = readfile(path);
	if (!content)
		return null;

	let acl = json(content);
	acl_cache[path] = acl;
	return acl;
};

/**
 * Checks if the ACL permits reading the given data model path.
 *
 * @param {object} acl - The ACL object
 * @param {string} dm_path - The data model path
 * @param {object} tree - Optional data tree for filter evaluation
 * @returns {boolean} True if read is permitted
 */
export function acl_can_read(acl, dm_path, tree) {
	if (!acl?.read)
		return false;

	let match = find_matching_rule(acl.read, dm_path);
	if (!match)
		return false;

	let rule = match.rule;

	if (rule == true)
		return true;

	if (type(rule) == 'array') {
		let prop = extract_property_from_path(dm_path, match.pattern);
		if (!prop)
			return true;
		return index(rule, prop) >= 0;
	}

	if (type(rule) == 'object' && rule.properties) {
		if (rule.filter && tree) {
			let path_parts = split(dm_path, '.');
			let pattern_parts = split(match.pattern, '.');
			let instance_data = get_instance_data(tree, path_parts, pattern_parts);
			if (!check_filter(instance_data, rule.filter))
				return false;
		}

		let prop = extract_property_from_path(dm_path, match.pattern);
		if (!prop)
			return true;
		return index(rule.properties, prop) >= 0;
	}

	return false;
};

/**
 * Checks if the ACL permits adding an instance under an object path.
 *
 * An add is permitted when some write rule reaches deeper than the parent path
 * and agrees with it segment by segment, wildcards included: such a rule
 * describes what may be written inside the instance that would be created.
 *
 * @param {object} acl - The ACL object
 * @param {string} dm_path - The parent object path
 * @returns {boolean} True if the add is permitted
 */
export function acl_can_add(acl, dm_path) {
	if (!acl?.write)
		return false;

	let parent_parts = split(dm_path, '.');

	for (let pattern in acl.write) {
		let pattern_parts = split(pattern, '.');
		if (length(pattern_parts) <= length(parent_parts))
			continue;

		let matches = true;
		for (let i = 0; i < length(parent_parts); i++) {
			if (pattern_parts[i] != '*' && pattern_parts[i] != parent_parts[i]) {
				matches = false;
				break;
			}
		}

		if (matches)
			return true;
	}

	return false;
};

/**
 * Checks if the ACL permits writing to the given data model path.
 *
 * @param {object} acl - The ACL object
 * @param {string} dm_path - The data model path
 * @param {object} tree - Optional data tree for filter evaluation
 * @returns {boolean} True if write is permitted
 */
export function acl_can_write(acl, dm_path, tree) {
	if (!acl?.write)
		return false;

	let match = find_matching_rule(acl.write, dm_path);
	if (!match)
		return false;

	let rule = match.rule;

	if (rule == true)
		return true;

	if (type(rule) == 'array') {
		let prop = extract_property_from_path(dm_path, match.pattern);
		if (!prop)
			return false;
		return index(rule, prop) >= 0;
	}

	if (type(rule) == 'object' && rule.properties) {
		if (rule.filter && tree) {
			let path_parts = split(dm_path, '.');
			let pattern_parts = split(match.pattern, '.');
			let instance_data = get_instance_data(tree, path_parts, pattern_parts);
			if (!check_filter(instance_data, rule.filter))
				return false;
		}

		let prop = extract_property_from_path(dm_path, match.pattern);
		if (!prop)
			return false;
		return index(rule.properties, prop) >= 0;
	}

	return false;
};

/**
 * Recursively filters an object tree based on ACL read permissions.
 *
 * Treats a child as a multi-instance container when any of its keys parse as
 * an integer (TR-181 instance numbers); each numeric instance is then checked
 * individually against the ACL, including any instance-level `filter`
 * conditions. Non-instance subtrees are recursed without instance handling.
 * Leaf values are kept only when `acl_can_read` permits the corresponding
 * data model path.
 *
 * @param {object} acl - The ACL object
 * @param {object} obj - The object to filter
 * @param {string} current_path - The current data model path
 * @param {object} root_tree - The root tree for filter evaluation
 * @returns {object} Filtered object with only permitted properties
 */
function filter_object(acl, obj, current_path, root_tree) {
	if (type(obj) != 'object')
		return obj;

	let result = {};

	for (let key in obj) {
		let child_path = current_path ? current_path + '.' + key : key;
		let child = obj[key];

		if (type(child) == 'object') {
			let has_instances = false;
			for (let k in child) {
				if (ubbf.is_instance_key(k)) {
					has_instances = true;
					break;
				}
			}

			if (has_instances) {
				let filtered_instances = {};
				for (let inst_key in child) {
					if (!ubbf.is_instance_key(inst_key))
						continue;

					let inst_path = child_path + '.' + inst_key;
					let inst_data = child[inst_key];

					let match = find_matching_rule(acl.read, inst_path);
					let should_include = false;

					if (match) {
						let rule = match.rule;
						if (type(rule) == 'object' && rule.filter)
							should_include = check_filter(inst_data, rule.filter);
						else
							should_include = true;
					}

					if (should_include) {
						let filtered_inst = filter_object(acl, inst_data, inst_path, root_tree);
						if (filtered_inst != null && length(keys(filtered_inst)) > 0)
							filtered_instances[inst_key] = filtered_inst;
					}
				}

				if (length(keys(filtered_instances)) > 0)
					result[key] = filtered_instances;
			} else {
				let filtered_child = filter_object(acl, child, child_path, root_tree);
				if (filtered_child != null && length(keys(filtered_child)) > 0)
					result[key] = filtered_child;
			}
		} else {
			if (acl_can_read(acl, child_path, root_tree))
				result[key] = child;
		}
	}

	return result;
}

/**
 * Filters an entire data tree based on ACL read permissions.
 *
 * @param {object} acl - The ACL object
 * @param {object} tree - The data tree to filter
 * @param {string} base_path - The base data model path
 * @returns {object} Filtered tree with only permitted properties
 */
export function acl_filter_tree(acl, tree, base_path) {
	if (!acl || !tree)
		return {};

	let root_tree = tree;
	if (base_path && base_path != '') {
		let parts = split(base_path, '.');
		root_tree = {};
		let current = root_tree;
		for (let i = 0; i < length(parts) - 1; i++) {
			current[parts[i]] = {};
			current = current[parts[i]];
		}
		current[parts[length(parts) - 1]] = tree;
	}

	return filter_object(acl, tree, base_path ?? '', root_tree);
};

/**
 * Clears the ACL cache, forcing files to be reloaded on next access.
 */
export function acl_clear_cache() {
	acl_cache = {};
};
