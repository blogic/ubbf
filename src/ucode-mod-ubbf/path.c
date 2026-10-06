/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Splits a dotted path in place into segment pointers.
 *
 * Trims leading and trailing dots, then replaces each interior `.` with a
 * NUL terminator and stores a pointer to each resulting segment in `parts`.
 * The input buffer is modified in place; segment pointers remain valid only
 * for the lifetime of `buf`.
 *
 * @param buf        mutable path buffer (modified in place)
 * @param parts      output array of segment pointers
 * @param max_parts  capacity of `parts`; surplus segments are dropped
 * @return           number of segments written into `parts`
 */
int
path_split(char *buf, char **parts, int max_parts)
{
	int count = 0;
	char *p, *next;

	while (*buf == '.')
		buf++;

	char *end = buf + strlen(buf) - 1;
	while (end > buf && *end == '.')
		*end-- = '\0';

	for (p = buf; count < max_parts && p && *p; count++) {
		next = strchr(p, '.');
		if (next)
			*next++ = '\0';
		parts[count] = p;
		p = next;
	}

	return count;
}

/**
 * Resolves alias- or name-keyed segments in a split path to instance numbers.
 *
 * USP allows multi-instance object tables to be addressed either by the
 * volatile numeric instance key (`Chain.1`) or by a stable string key
 * (`Chain.Medium` or the bracketed `Chain.[Medium]`). TR-181 tables that
 * declare `Alias` as a non-volatile unique key are always addressable by
 * alias; some tables additionally accept `Name` as a secondary string key
 * (Firewall.Level, Firewall.Chain).
 *
 * This helper walks `parts[]` against the live `config` tree. At each
 * position where the current segment does not directly exist as a child
 * of the current container but matches some child's `Alias` (or `Name`)
 * value, the segment pointer is rewritten in-place to point at the
 * numeric instance key of the matched child. Rewrites come out of
 * `slot_buf`, a caller-provided scratch buffer laid out as
 * `slot_max * slot_stride` bytes; each resolved segment consumes one
 * slot.
 *
 * Segments that are already numeric, already literal-matching, or
 * unresolvable are left untouched: this is a best-effort rewrite that
 * lets downstream validators (`path_instance_segments_valid`) continue
 * to police correctness. The function returns false only when the
 * scratch buffer is exhausted or a slot is too small for the resolved
 * key; in either case `parts[]` may be partially mutated and callers
 * should treat the lookup as failed.
 *
 * Bracketed USP form `[Alias]` is accepted: when a segment starts with
 * `[` and ends with `]`, the brackets are stripped before lookup and the
 * stripped form is used for alias matching (it is never used as a
 * direct-key probe because TR-181 instance and object names cannot
 * contain brackets).
 *
 * @param config       live tree to resolve against (target for writes,
 *                     runtime for reads); may be NULL (no-op)
 * @param parts        split path segments; updated in place
 * @param cnt          number of segments in `parts`
 * @param slot_buf     scratch buffer for rewrites (caller-provided)
 * @param slot_stride  size of each slot in bytes (must include NUL)
 * @param slot_max     number of slots available in `slot_buf`
 * @return             true on normal completion (including unresolved
 *                     segments), false when scratch space is exhausted
 */
bool
path_resolve_aliases(uc_value_t *config, char **parts, int cnt,
		     char *slot_buf, size_t slot_stride, int slot_max)
{
	uc_value_t *node;
	int slot_n = 0;

	if (!config || ucv_type(config) != UC_OBJECT || cnt <= 0)
		return true;

	node = config;

	for (int i = 0; i < cnt; i++) {
		const char *seg = parts[i];
		const char *lookup = seg;
		char stripped[128];
		size_t seg_len = strlen(seg);
		bool bracketed = false;
		uc_value_t *direct;
		const char *matched_key = NULL;

		if (seg_len >= 2 && seg[0] == '[' && seg[seg_len - 1] == ']') {
			size_t inner_len = seg_len - 2;

			if (inner_len >= sizeof(stripped))
				return false;
			memcpy(stripped, seg + 1, inner_len);
			stripped[inner_len] = '\0';
			lookup = stripped;
			bracketed = true;
		}

		if (ucv_type(node) != UC_OBJECT) {
			node = NULL;
			continue;
		}

		direct = bracketed ? NULL : ucv_object_get(node, lookup, NULL);

		if (!direct) {
			ucv_object_foreach(node, key, val) {
				uc_value_t *alias, *name;

				if (ucv_type(val) != UC_OBJECT)
					continue;

				alias = ucv_object_get(val, "Alias", NULL);
				if (alias && ucv_type(alias) == UC_STRING &&
				    !strcmp(ucv_string_get(alias), lookup)) {
					matched_key = key;
					break;
				}

				name = ucv_object_get(val, "Name", NULL);
				if (name && ucv_type(name) == UC_STRING &&
				    !strcmp(ucv_string_get(name), lookup)) {
					matched_key = key;
					break;
				}
			}
		}

		if (matched_key) {
			size_t klen = strlen(matched_key);

			if (slot_n >= slot_max)
				return false;
			if (klen + 1 > slot_stride)
				return false;

			char *slot = slot_buf + (size_t)slot_n * slot_stride;

			memcpy(slot, matched_key, klen + 1);
			parts[i] = slot;
			slot_n++;
			node = ucv_object_get(node, matched_key, NULL);
		} else {
			node = direct;
		}
	}

	return true;
}

/**
 * Splits a dotted TR-181 path string into an array of segment strings.
 *
 * Leading and trailing dots are trimmed before splitting; an empty result
 * is returned for empty or all-dot input.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: the path string)
 * @return       array of segment strings, or empty array on bad input
 */
uc_value_t *
uc_ubbf_path_to_parts(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	const char *path, *p, *end;
	uc_value_t *arr;
	size_t len;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	path = ucv_string_get(path_val);
	len = ucv_string_length(path_val);

	while (len > 0 && path[0] == '.')
		path++, len--;
	while (len > 0 && path[len - 1] == '.')
		len--;

	if (len == 0)
		return ucv_array_new(vm);

	end = path + len;
	arr = ucv_array_new(vm);

	for (p = path; p < end; ) {
		const char *dot = memchr(p, '.', end - p);
		size_t part_len = dot ? (size_t)(dot - p) : (size_t)(end - p);

		ucv_array_push(arr, ucv_string_new_length(p, part_len));
		p += part_len + 1;
	}

	return arr;
}

/**
 * Navigates a nested object by an array of key segments.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: data object, parts array)
 * @return       value at the resolved path, or null if any segment is missing
 */
uc_value_t *
uc_ubbf_navigate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data = uc_fn_arg(0);
	uc_value_t *parts = uc_fn_arg(1);
	uc_value_t *current;
	size_t i, plen;

	if (ucv_type(parts) != UC_ARRAY)
		return NULL;

	current = data;
	plen = ucv_array_length(parts);

	for (i = 0; i < plen; i++) {
		uc_value_t *part;
		const char *key;

		if (ucv_type(current) != UC_OBJECT)
			return NULL;

		part = ucv_array_get(parts, i);
		key = ucv_string_get(part);
		if (!key)
			return NULL;

		current = ucv_object_get(current, key, NULL);
		if (!current)
			return NULL;
	}

	return ucv_get(current);
}

/**
 * Matches a path against a TR-181 pattern containing `{i}` placeholders.
 *
 * The path may be longer than the pattern; only the first `pattern_len`
 * segments are compared. `{i}` segments accept any positive integer string
 * and are captured into the returned array in order.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, pattern)
 * @return       array of captured instance numbers when matched, else null
 */
uc_value_t *
uc_ubbf_match_pattern(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *pattern_val = uc_fn_arg(1);
	const char *path_str, *pat_str;
	uc_value_t *instances;
	char *path_buf, *pat_buf;
	char *path_parts[64], *pat_parts[64];
	int path_cnt = 0, pat_cnt = 0;
	int i;

	if (ucv_type(path_val) != UC_STRING || ucv_type(pattern_val) != UC_STRING)
		return NULL;

	path_str = ucv_string_get(path_val);
	pat_str = ucv_string_get(pattern_val);

	path_buf = strdup(path_str);
	pat_buf = strdup(pat_str);

	path_cnt = path_split(path_buf, path_parts, 64);
	pat_cnt = path_split(pat_buf, pat_parts, 64);

	if (path_cnt < pat_cnt) {
		free(path_buf);
		free(pat_buf);
		return NULL;
	}

	instances = ucv_array_new(vm);

	for (i = 0; i < pat_cnt; i++) {
		if (strcmp(pat_parts[i], "{i}") == 0) {
			char *endp;
			long val = strtol(path_parts[i], &endp, 10);

			if (*endp != '\0' || endp == path_parts[i]) {
				ucv_put(instances);
				free(path_buf);
				free(pat_buf);
				return NULL;
			}
			ucv_array_push(instances, ucv_int64_new(val));
		} else if (strcmp(pat_parts[i], path_parts[i]) != 0) {
			ucv_put(instances);
			free(path_buf);
			free(pat_buf);
			return NULL;
		}
	}

	free(path_buf);
	free(pat_buf);
	return instances;
}

/**
 * Tests whether a TR-181 pattern can match the given prefix path.
 *
 * Returns true when the pattern is at least as deep as the path and every
 * non-`{i}` pattern segment equals the corresponding path segment. The
 * special inputs empty path and `Device` always match.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: pattern, path)
 * @return       boolean indicating whether the pattern matches the path
 */
uc_value_t *
uc_ubbf_pattern_matches_path(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pattern_val = uc_fn_arg(0);
	uc_value_t *path_val = uc_fn_arg(1);
	const char *pat_str, *path_str;
	char *pat_buf, *path_buf;
	char *pat_parts[64], *path_parts[64];
	int pat_cnt = 0, path_cnt = 0;
	size_t path_len;
	int i;

	if (ucv_type(pattern_val) != UC_STRING || ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	path_str = ucv_string_get(path_val);
	path_len = strlen(path_str);

	if (path_len == 0 || strcmp(path_str, "Device") == 0)
		return ucv_boolean_new(true);

	pat_str = ucv_string_get(pattern_val);

	pat_buf = strdup(pat_str);
	path_buf = strdup(path_str);

	pat_cnt = path_split(pat_buf, pat_parts, 64);
	path_cnt = path_split(path_buf, path_parts, 64);

	if (pat_cnt < path_cnt) {
		free(pat_buf);
		free(path_buf);
		return ucv_boolean_new(false);
	}

	for (i = 0; i < path_cnt; i++) {
		if (strcmp(pat_parts[i], "{i}") == 0)
			continue;
		if (strcmp(pat_parts[i], path_parts[i]) != 0) {
			free(pat_buf);
			free(path_buf);
			return ucv_boolean_new(false);
		}
	}

	free(pat_buf);
	free(path_buf);
	return ucv_boolean_new(true);
}

/**
 * Extracts the trailing instance number from a TR-181 object path.
 *
 * Validates that `path` equals `prefix + "." + <positive decimal>` with no
 * trailing segments and returns the integer. A single trailing dot is
 * accepted so the helper matches both `Device.X.Y.3` and `Device.X.Y.3.`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, prefix)
 * @return       positive integer instance, or null on mismatch
 */
uc_value_t *
uc_ubbf_tr181_ref_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *prefix_val = uc_fn_arg(1);
	const char *path, *prefix;
	size_t plen, prelen;
	char *endp;
	long long inst;

	if (ucv_type(path_val) != UC_STRING || ucv_type(prefix_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	prefix = ucv_string_get(prefix_val);
	plen = ucv_string_length(path_val);
	prelen = ucv_string_length(prefix_val);

	if (plen < prelen + 2)
		return NULL;
	if (strncmp(path, prefix, prelen) != 0)
		return NULL;
	if (path[prelen] != '.')
		return NULL;

	inst = strtoll(path + prelen + 1, &endp, 10);
	if (endp == path + prelen + 1)
		return NULL;
	if (*endp != '\0' && !(*endp == '.' && endp[1] == '\0'))
		return NULL;
	if (inst < 1)
		return NULL;

	return ucv_int64_new(inst);
}

/**
 * Extracts the `config` member of a handler context object.
 *
 * Returns an empty object when the context is missing the field or when
 * the field is not an object, so callers can chain property access without
 * a null check.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: ctx object)
 * @return       config object or an empty object
 */
uc_value_t *
uc_ubbf_ctx_config(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ctx = uc_fn_arg(0);
	uc_value_t *config;

	if (ucv_type(ctx) != UC_OBJECT)
		return ucv_object_new(vm);

	config = ucv_object_get(ctx, "config", NULL);

	return (config && ucv_type(config) == UC_OBJECT) ? ucv_get(config) : ucv_object_new(vm);
}

/**
 * Extracts the `parent` member of a handler context, falling back to `config`.
 *
 * Returns an empty object when neither field resolves to an object, so
 * callers can dereference safely.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: ctx object)
 * @return       parent object, config object, or an empty object
 */
uc_value_t *
uc_ubbf_ctx_parent(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ctx = uc_fn_arg(0);
	uc_value_t *val;

	if (ucv_type(ctx) != UC_OBJECT)
		return ucv_object_new(vm);

	val = ucv_object_get(ctx, "parent", NULL);
	if (val && ucv_type(val) == UC_OBJECT)
		return ucv_get(val);

	val = ucv_object_get(ctx, "config", NULL);

	return (val && ucv_type(val) == UC_OBJECT) ? ucv_get(val) : ucv_object_new(vm);
}
