/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/* ---- tree operations --------------------------------------------------- */

/**
 * Recursively deep-clones a ucode value.
 *
 * Objects and arrays are duplicated structurally; primitive values are
 * shared via reference count increment. The function does not detect
 * cycles, so circular structures will recurse until stack exhaustion.
 *
 * @param vm   ucode VM context
 * @param val  value to clone (may be NULL)
 * @return     new value owning a fresh reference, or NULL if `val` was NULL
 */
uc_value_t *
deep_clone_value(uc_vm_t *vm, uc_value_t *val)
{
	if (!val)
		return NULL;

	switch (ucv_type(val)) {
	case UC_OBJECT: {
		uc_value_t *clone = ucv_object_new(vm);

		ucv_object_foreach(val, key, child)
			ucv_object_add(clone, key, deep_clone_value(vm, child));

		return clone;
	}

	case UC_ARRAY: {
		size_t len = ucv_array_length(val);
		uc_value_t *clone = ucv_array_new_length(vm, len);

		for (size_t i = 0; i < len; i++)
			ucv_array_push(clone, deep_clone_value(vm, ucv_array_get(val, i)));

		return clone;
	}

	default:
		return ucv_get(val);
	}
}

/**
 * Walks an object by path-parts, creating intermediate objects as needed.
 *
 * Each missing or non-object child along the path is replaced with a new
 * empty object. Returns the resolved leaf object.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: data object, parts array)
 * @return       resolved object, or null on bad arguments
 */
uc_value_t *
uc_ubbf_navigate_or_create(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data = uc_fn_arg(0);
	uc_value_t *parts = uc_fn_arg(1);
	uc_value_t *current;
	size_t i, plen;

	if (ucv_type(data) != UC_OBJECT || ucv_type(parts) != UC_ARRAY)
		return NULL;

	current = data;
	plen = ucv_array_length(parts);

	for (i = 0; i < plen; i++) {
		uc_value_t *part = ucv_array_get(parts, i);
		const char *key = ucv_string_get(part);
		uc_value_t *child;

		if (!key)
			return NULL;

		child = ucv_object_get(current, key, NULL);
		if (!child || ucv_type(child) != UC_OBJECT) {
			child = ucv_object_new(vm);
			ucv_object_add(current, key, child);
		}
		current = child;
	}

	return ucv_get(current);
}

/* ---- data model helper functions --------------------------------------- */

/**
 * Resolves a value in a nested object by a dotted TR-181 path string.
 *
 * The path is split with `path_split()` (so leading and trailing dots are
 * tolerated) and then each segment is looked up as an object key. Returns
 * a borrowed reference into the input tree.
 *
 * @param vm    ucode VM context
 * @param data  root object to navigate
 * @param path  dotted path string
 * @return      resolved value (borrowed), or NULL on missing or bad arguments
 */
uc_value_t *
navigate_by_path(uc_vm_t *vm, uc_value_t *data, const char *path)
{
	char *buf, *parts[64];
	int cnt, i;
	uc_value_t *current;

	if (!path || !*path || ucv_type(data) != UC_OBJECT)
		return NULL;

	buf = xstrdup(path);
	cnt = path_split(buf, parts, 64);

	current = data;
	for (i = 0; i < cnt; i++) {
		if (ucv_type(current) != UC_OBJECT) {
			free(buf);
			return NULL;
		}
		current = ucv_object_get(current, parts[i], NULL);
		if (!current) {
			free(buf);
			return NULL;
		}
	}

	free(buf);
	return current;
}

/**
 * Retrieves the value at a TR-181 path within a configuration tree.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       value at the path, or null when missing
 */
uc_value_t *
uc_ubbf_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *result;

	if (ucv_type(path_val) != UC_STRING)
		return NULL;

	result = navigate_by_path(vm, config, ucv_string_get(path_val));

	return result ? ucv_get(result) : NULL;
}

/**
 * Returns the instances of a TR-181 multi-instance object as an array.
 *
 * Each returned entry is the instance config decorated with `.instance`
 * (the key) and `.path` (the fully qualified path). Note that the
 * decoration mutates the underlying config object in place.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       array of instance objects, possibly empty
 */
uc_value_t *
uc_ubbf_instances(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *data, *arr;
	const char *path;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	path = ucv_string_get(path_val);
	data = navigate_by_path(vm, config, path);

	if (ucv_type(data) != UC_OBJECT)
		return ucv_array_new(vm);

	arr = ucv_array_new(vm);

	ucv_object_foreach(data, key, inst_config) {
		char path_buf[512];

		if (ucv_type(inst_config) != UC_OBJECT)
			continue;

		ucv_object_add(inst_config, ".instance", ucv_string_new(key));
		snprintf(path_buf, sizeof(path_buf), "%s.%s", path, key);
		ucv_object_add(inst_config, ".path", ucv_string_new(path_buf));
		ucv_array_push(arr, ucv_get(inst_config));
	}

	return arr;
}

/**
 * Reports whether a value at a TR-181 path is truthy.
 *
 * Booleans pass through; strings are truthy when equal to `"true"` or `"1"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config object, path string)
 * @return       boolean truthiness of the resolved value
 */
uc_value_t *
uc_ubbf_enabled(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	uc_value_t *value;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	value = navigate_by_path(vm, config, ucv_string_get(path_val));
	if (!value)
		return ucv_boolean_new(false);

	if (ucv_type(value) == UC_BOOLEAN)
		return ucv_boolean_new(ucv_boolean_get(value));

	if (ucv_type(value) == UC_STRING) {
		const char *s = ucv_string_get(value);
		return ucv_boolean_new(strcmp(s, "true") == 0 || strcmp(s, "1") == 0);
	}

	return ucv_boolean_new(false);
}

/**
 * Resolves a TR-181 interface reference to its system interface name.
 *
 * Navigates `config` to the referenced object and returns its `Name` field.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config, reference path)
 * @return       Name string, or null when the reference is missing
 */
uc_value_t *
uc_ubbf_interface_to_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *ref_val = uc_fn_arg(1);
	uc_value_t *data, *name;

	if (ucv_type(ref_val) != UC_STRING)
		return NULL;

	data = navigate_by_path(vm, config, ucv_string_get(ref_val));
	if (ucv_type(data) != UC_OBJECT)
		return NULL;

	name = ucv_object_get(data, "Name", NULL);
	return name ? ucv_get(name) : NULL;
}

/**
 * Resolves the first entry of a TR-181 LowerLayers CSV to a system name.
 *
 * Strips leading whitespace from the first comma-separated reference,
 * navigates `config`, and returns the referenced object's `Name`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config, LowerLayers string)
 * @return       Name string, or null when no reference resolves
 */
uc_value_t *
uc_ubbf_lower_layer_resolve(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);
	uc_value_t *layers_val = uc_fn_arg(1);
	const char *layers;
	char *buf, *comma, *ref;
	uc_value_t *data, *name;

	if (ucv_type(layers_val) != UC_STRING)
		return NULL;

	layers = ucv_string_get(layers_val);
	if (!layers || !*layers)
		return NULL;

	buf = xstrdup(layers);
	comma = strchr(buf, ',');
	if (comma)
		*comma = '\0';

	ref = buf;
	while (*ref == ' ')
		ref++;

	data = navigate_by_path(vm, config, ref);
	free(buf);

	if (ucv_type(data) != UC_OBJECT)
		return NULL;

	name = ucv_object_get(data, "Name", NULL);
	return name ? ucv_get(name) : NULL;
}
