/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <limits.h>

#include "ubbf.h"

/* ---- instance utilities ------------------------------------------------ */

/**
 * Reports whether a key string is a valid TR-181 instance number.
 *
 * Instance numbers are positive base-10 integers that fit an int, with no
 * surrounding whitespace, sign or fractional part.
 *
 * @param key  key string to test (may be NULL)
 * @return     true when the key is a valid instance identifier
 */
bool
key_is_instance(const char *key)
{
	char *endp;
	long val;

	/* strtol() accepts leading whitespace and a sign */
	if (!key || *key < '0' || *key > '9')
		return false;

	errno = 0;
	val = strtol(key, &endp, 10);
	return (*endp == '\0' && errno == 0 && val >= 1 && val <= INT_MAX);
}

/**
 * Tests whether a value can serve as a TR-181 instance key.
 *
 * Integers are accepted when >= 1; strings must satisfy `key_is_instance`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       boolean indicating instance-key validity
 */
uc_value_t *
uc_ubbf_is_instance_key(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *key_val = uc_fn_arg(0);
	const char *key;

	if (ucv_type(key_val) == UC_INTEGER)
		return ucv_boolean_new(ucv_int64_get(key_val) >= 1);

	if (ucv_type(key_val) != UC_STRING)
		return ucv_boolean_new(false);

	key = ucv_string_get(key_val);
	return ucv_boolean_new(key_is_instance(key));
}

/**
 * Counts how many keys of an object are valid TR-181 instance numbers.
 *
 * @param obj  object to scan; non-objects yield 0
 * @return     number of instance-numbered children
 */
int
count_instance_keys(uc_value_t *obj)
{
	int count = 0;

	if (ucv_type(obj) != UC_OBJECT)
		return 0;

	ucv_object_foreach(obj, key, val) {
		(void)val;
		if (key_is_instance(key))
			count++;
	}

	return count;
}

/**
 * Returns the number of TR-181 instance keys on an object.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: container object)
 * @return       integer count of instance-numbered children
 */
uc_value_t *
uc_ubbf_count_instances(uc_vm_t *vm, size_t nargs)
{
	return ucv_int64_new(count_instance_keys(uc_fn_arg(0)));
}

/**
 * Picks the next free TR-181 instance number for a container.
 *
 * Returns the lowest positive integer not already present as an
 * instance key.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: container object)
 * @return       next available instance number, starting at 1
 */
uc_value_t *
uc_ubbf_find_next_instance(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *obj = uc_fn_arg(0);
	char key_buf[24];
	long expected;

	if (ucv_type(obj) != UC_OBJECT)
		return ucv_int64_new(1);

	/* generated keys are canonical decimal, so a direct lookup per
	 * candidate finds the lowest gap without a bounded scan buffer */
	for (expected = 1;; expected++) {
		snprintf(key_buf, sizeof(key_buf), "%ld", expected);
		if (!ucv_object_get(obj, key_buf, NULL))
			return ucv_int64_new(expected);
	}
}

/* ---- instance collection (recursive) ----------------------------------- */

/**
 * Recursively appends every TR-181 instance path under a base path.
 *
 * Walks `data` end-to-end and, for each instance-numbered key encountered,
 * pushes the fully qualified `base_path.key` string into `vm_arr`. Always
 * descends into object children regardless of whether the immediate child is
 * instance-keyed: nested `{i}` tables under intermediate non-`{i}` containers
 * (e.g. `Device.LLDP.Discovery.Device.{i}.DeviceInformation.VendorSpecific.{i}`)
 * are only reachable that way. Built paths use a 1024-byte stack buffer;
 * truncation is currently silent.
 *
 * @param vm_arr    output array that receives instance path strings
 * @param base_path path prefix prepended to each emitted key
 * @param data      object to walk; non-objects are skipped
 * @param vm        ucode VM context
 */
void
do_find_nested_instances(uc_value_t *vm_arr, const char *base_path,
			 uc_value_t *data, uc_vm_t *vm)
{
	if (ucv_type(data) != UC_OBJECT)
		return;

	ucv_object_foreach(data, key, child) {
		char path_buf[1024];

		if (ucv_type(child) != UC_OBJECT)
			continue;

		snprintf(path_buf, sizeof(path_buf), "%s.%s", base_path, key);

		if (key_is_instance(key))
			ucv_array_push(vm_arr, ucv_string_new(path_buf));

		do_find_nested_instances(vm_arr, path_buf, child, vm);
	}
}

/**
 * Recursively collects every concrete path matching a `{i}` pattern.
 *
 * For literal pattern segments the function descends into the matching
 * child; for `{i}` segments it iterates over every TR-181 instance key.
 * When the pattern still has remaining literal segments but the data tree
 * has no matching node, and there are no more `{i}` placeholders left to
 * expand, the resulting "singleton path" (pattern segments appended to
 * `current_path`) is still emitted so callers can hydrate the entry from
 * schema defaults later.
 *
 * Path strings are built into a 512-byte stack buffer; truncation is
 * silent.
 *
 * @param result        output array that receives matching path strings
 * @param pattern_parts pattern segments as a string array
 * @param data          current data subtree being walked
 * @param parts_idx     index into `pattern_parts` for the current step
 * @param current_path  path prefix accumulated so far
 * @param vm            ucode VM context
 */
void
do_collect_instances(uc_value_t *result, uc_value_t *pattern_parts,
		     uc_value_t *data, size_t parts_idx,
		     const char *current_path, uc_vm_t *vm)
{
	size_t plen = ucv_array_length(pattern_parts);
	char child_path[512];
	uc_value_t *part_val;
	const char *part;

	if (parts_idx >= plen) {
		ucv_array_push(result, ucv_string_new(current_path));
		return;
	}

	part_val = ucv_array_get(pattern_parts, parts_idx);
	part = ucv_string_get(part_val);
	if (!part)
		return;

	if (strcmp(part, "{i}") == 0) {
		if (ucv_type(data) != UC_OBJECT)
			return;

		ucv_object_foreach(data, key, child) {
			if (!key_is_instance(key))
				continue;

			if (current_path[0])
				snprintf(child_path, sizeof(child_path), "%s.%s",
					 current_path, key);
			else
				snprintf(child_path, sizeof(child_path), "%s", key);

			do_collect_instances(result, pattern_parts, child,
					    parts_idx + 1, child_path, vm);
		}
		return;
	}

	if (ucv_type(data) != UC_OBJECT) {
		/* check if remaining pattern has more instances */
		bool has_more = false;

		for (size_t i = parts_idx; i < plen; i++) {
			uc_value_t *p = ucv_array_get(pattern_parts, i);
			if (ucv_type(p) == UC_STRING && strcmp(ucv_string_get(p), "{i}") == 0) {
				has_more = true;
				break;
			}
		}

		if (!has_more) {
			char singleton_path[512];
			size_t off = 0;

			if (current_path[0])
				off = snprintf(singleton_path, sizeof(singleton_path),
					       "%s", current_path);

			for (size_t i = parts_idx; i < plen && off < sizeof(singleton_path) - 1; i++) {
				uc_value_t *rp = ucv_array_get(pattern_parts, i);
				const char *rs = ucv_string_get(rp);

				if (rs)
					off += snprintf(singleton_path + off,
							sizeof(singleton_path) - off,
							"%s%s", off > 0 ? "." : "", rs);
			}

			ucv_array_push(result, ucv_string_new(singleton_path));
		}
		return;
	}

	uc_value_t *child = ucv_object_get(data, part, NULL);

	if (!child) {
		bool has_more = false;

		for (size_t i = parts_idx; i < plen; i++) {
			uc_value_t *p = ucv_array_get(pattern_parts, i);
			if (ucv_type(p) == UC_STRING && strcmp(ucv_string_get(p), "{i}") == 0) {
				has_more = true;
				break;
			}
		}

		if (!has_more) {
			char singleton_path[512];
			size_t off = 0;

			if (current_path[0])
				off = snprintf(singleton_path, sizeof(singleton_path),
					       "%s", current_path);

			for (size_t i = parts_idx; i < plen && off < sizeof(singleton_path) - 1; i++) {
				uc_value_t *rp = ucv_array_get(pattern_parts, i);
				const char *rs = ucv_string_get(rp);

				if (rs)
					off += snprintf(singleton_path + off,
							sizeof(singleton_path) - off,
							"%s%s", off > 0 ? "." : "", rs);
			}

			ucv_array_push(result, ucv_string_new(singleton_path));
		}
		return;
	}

	if (current_path[0])
		snprintf(child_path, sizeof(child_path), "%s.%s", current_path, part);
	else
		snprintf(child_path, sizeof(child_path), "%s", part);

	do_collect_instances(result, pattern_parts, child,
			     parts_idx + 1, child_path, vm);
}

/**
 * Returns every concrete path matching a TR-181 pattern under a data tree.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: pattern parts, data,
 *               start index, current path string)
 * @return       array of matching path strings
 */
uc_value_t *
uc_ubbf_collect_instances_for_pattern(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pattern_parts = uc_fn_arg(0);
	uc_value_t *data = uc_fn_arg(1);
	uc_value_t *idx_val = uc_fn_arg(2);
	uc_value_t *path_val = uc_fn_arg(3);
	uc_value_t *result;
	size_t idx;
	const char *current_path;

	if (ucv_type(pattern_parts) != UC_ARRAY)
		return ucv_array_new(vm);

	idx = (ucv_type(idx_val) == UC_INTEGER) ? (size_t)ucv_int64_get(idx_val) : 0;
	current_path = (ucv_type(path_val) == UC_STRING) ? ucv_string_get(path_val) : "";

	result = ucv_array_new(vm);
	do_collect_instances(result, pattern_parts, data, idx, current_path, vm);

	return result;
}

/**
 * Updates the `<TableName>NumberOfEntries` parameter on a parent object.
 *
 * Counts the instance-numbered keys in `container` and writes the result
 * as a string into `parent[<table_name>NumberOfEntries]`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: parent object, table
 *               name string, container object)
 * @return       true on success, null on bad arguments
 */
uc_value_t *
uc_ubbf_entries_count_update(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *parent = uc_fn_arg(0);
	uc_value_t *table_name_val = uc_fn_arg(1);
	uc_value_t *container = uc_fn_arg(2);
	const char *table_name;
	char key_buf[128];
	char val_buf[16];
	int count;

	if (ucv_type(parent) != UC_OBJECT ||
	    ucv_type(table_name_val) != UC_STRING)
		return NULL;

	table_name = ucv_string_get(table_name_val);
	count = count_instance_keys(container);

	snprintf(key_buf, sizeof(key_buf), "%sNumberOfEntries", table_name);

	snprintf(val_buf, sizeof(val_buf), "%d", count);
	ucv_object_add(parent, key_buf, ucv_string_new(val_buf));

	return ucv_boolean_new(true);
}

/* ---- enumerate helpers ------------------------------------------------- */

/**
 * Builds a TR-181-style instance object by mapping over an array.
 *
 * For each item in `items`, calls `converter(item, index)` and stores the
 * result under the 1-based instance key. Items whose converter throws are
 * skipped silently.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: items array, converter fn)
 * @return       object with string-keyed instance entries
 */
uc_value_t *
uc_ubbf_enumerate_instances(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *items = uc_fn_arg(0);
	uc_value_t *converter = uc_fn_arg(1);
	uc_value_t *result;
	size_t len;

	if (ucv_type(items) != UC_ARRAY)
		return ucv_object_new(vm);

	if (!converter || !ucv_is_callable(converter))
		return ucv_object_new(vm);

	result = ucv_object_new(vm);
	len = ucv_array_length(items);

	for (size_t i = 0; i < len; i++) {
		uc_value_t *item = ucv_array_get(items, i);
		char key[24];

		uc_vm_stack_push(vm, ucv_get(converter));
		uc_vm_stack_push(vm, ucv_get(item));
		uc_vm_stack_push(vm, ucv_int64_new(i));

		if (uc_vm_call(vm, false, 2) == EXCEPTION_NONE) {
			uc_value_t *converted = uc_vm_stack_pop(vm);

			snprintf(key, sizeof(key), "%zu", i + 1);
			ucv_object_add(result, key, converted);
		}
	}

	return result;
}

/**
 * Looks up an array element by 1-based TR-181 instance number.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: array, instance number)
 * @return       array element, or null when out of range
 */
uc_value_t *
uc_ubbf_get_by_instance(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *items = uc_fn_arg(0);
	uc_value_t *inst_val = uc_fn_arg(1);
	int64_t idx;

	if (ucv_type(items) != UC_ARRAY || ucv_type(inst_val) != UC_INTEGER)
		return NULL;

	idx = ucv_int64_get(inst_val) - 1;
	if (idx < 0 || (size_t)idx >= ucv_array_length(items))
		return NULL;

	return ucv_get(ucv_array_get(items, (size_t)idx));
}
