/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

/**
 * Splits a dotted path in place into segment pointers.
 *
 * By default one leading and one trailing dot are dropped, so
 * `Device.IP.` and `.Device.IP` give the segments of `Device.IP`. A path
 * that is empty after that has no segments. An empty segment, as in
 * `Device..IP` or `Device.IP..`, makes the path invalid.
 *
 * With `PATH_SPLIT_KEEP_EMPTY` every dot separates two segments and empty
 * segments stay, as with the ucode `split(path, ".")`: `Device.` gives
 * `Device` and an empty segment, and an empty path one empty segment.
 *
 * A path with more segments than `max_parts` is invalid in both modes.
 * After an invalid path, `buf` and `parts` hold partial results.
 *
 * @param buf        mutable path buffer (modified in place)
 * @param parts      output array of segment pointers into `buf`
 * @param max_parts  capacity of `parts`
 * @param flags      0 or `PATH_SPLIT_KEEP_EMPTY`
 * @return           number of segments, or -1 when the path is invalid
 */
int
path_split(char *buf, char **parts, int max_parts, unsigned int flags)
{
	bool keep_empty = flags & PATH_SPLIT_KEEP_EMPTY;
	char *p = buf, *next;
	int count = 0;
	size_t len;

	if (!keep_empty) {
		if (*p == '.')
			p++;

		len = strlen(p);
		if (len && p[len - 1] == '.')
			p[len - 1] = '\0';

		if (!*p)
			return 0;
	}

	for (; p; p = next) {
		next = strchr(p, '.');
		if (next)
			*next++ = '\0';

		if ((!*p && !keep_empty) || count >= max_parts)
			return -1;

		parts[count++] = p;
	}

	return count;
}

/**
 * Joins the segments `parts[from]` to `parts[to - 1]` with dots.
 *
 * @param parts  segments
 * @param from   index of the first segment
 * @param to     index after the last segment
 * @return       new string that the caller frees; empty when `from >= to`
 */
char *
path_join(char **parts, int from, int to)
{
	size_t len = 0, n;
	char *path, *p;

	for (int i = from; i < to; i++)
		len += strlen(parts[i]) + 1;

	path = p = xalloc(len + 1);

	for (int i = from; i < to; i++) {
		if (i > from)
			*p++ = '.';

		n = strlen(parts[i]);
		memcpy(p, parts[i], n);
		p += n;
	}

	return path;
}

/**
 * Splits a dotted path with `path_split()` into an array of strings.
 *
 * @param vm    ucode VM context
 * @param path  dotted path
 * @return      new array of the segments, or NULL when the path is invalid
 */
uc_value_t *
path_parts_new(uc_vm_t *vm, const char *path)
{
	char *buf = xstrdup(path), **parts;
	uc_value_t *arr = NULL;
	int max = 1, cnt;

	for (const char *p = path; *p; p++)
		max += (*p == '.');

	parts = xcalloc(max, sizeof(*parts));
	cnt = path_split(buf, parts, max, 0);

	if (cnt >= 0) {
		arr = ucv_array_new(vm);
		for (int i = 0; i < cnt; i++)
			ucv_array_push(arr, ucv_string_new(parts[i]));
	}

	free(parts);
	free(buf);

	return arr;
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
 * Splits a dotted TR-181 path string into an array of segment strings,
 * with the rules of `path_split()`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: the path string)
 * @return       array of segment strings, or empty array on bad input or
 *               an invalid path
 */
uc_value_t *
uc_ubbf_path_to_parts(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *arr;

	if (ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	arr = path_parts_new(vm, ucv_string_get(path_val));

	return arr ? arr : ucv_array_new(vm);
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
 * Compares the first `cnt` segments of a pattern with the segments of a
 * path. A `{i}` takes any segment; with `numeric` set only a decimal
 * number, as strtoll() reads it.
 *
 * @param pattern  pattern segments, at least `cnt`
 * @param parts    path segments, at least `cnt`
 * @param cnt      number of segments to compare
 * @param numeric  whether a `{i}` takes only a number
 * @param inst     receives the number at the last `{i}`, 0 without one;
 *                 may be NULL
 * @return         true when every segment agrees
 */
bool
pattern_parts_match(char **pattern, char **parts, int cnt, bool numeric,
		    int64_t *inst)
{
	int64_t num = 0;
	char *endp;

	for (int i = 0; i < cnt; i++) {
		if (strcmp(pattern[i], "{i}")) {
			if (strcmp(pattern[i], parts[i]))
				return false;
			continue;
		}

		if (!numeric)
			continue;

		num = strtoll(parts[i], &endp, 10);
		if (*endp || endp == parts[i])
			return false;
	}

	if (inst)
		*inst = num;

	return true;
}

/**
 * Tests whether a TR-181 pattern can match the given prefix path.
 *
 * Returns true when the pattern is at least as deep as the path and every
 * non-`{i}` pattern segment equals the corresponding path segment. The
 * special inputs empty path and `Device` always match; an invalid path or
 * pattern (see `path_split()`) matches nothing.
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
	char *pat_parts[PATH_PARTS_MAX], *path_parts[PATH_PARTS_MAX];
	int pat_cnt = 0, path_cnt = 0;
	size_t path_len;
	bool match;

	if (ucv_type(pattern_val) != UC_STRING || ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	path_str = ucv_string_get(path_val);
	path_len = strlen(path_str);

	if (path_len == 0 || strcmp(path_str, "Device") == 0)
		return ucv_boolean_new(true);

	pat_str = ucv_string_get(pattern_val);

	pat_buf = xstrdup(pat_str);
	path_buf = xstrdup(path_str);

	pat_cnt = path_split(pat_buf, pat_parts, PATH_PARTS_MAX, 0);
	path_cnt = path_split(path_buf, path_parts, PATH_PARTS_MAX, 0);
	match = path_cnt >= 0 && pat_cnt >= path_cnt &&
		pattern_parts_match(pat_parts, path_parts, path_cnt, false, NULL);

	free(pat_buf);
	free(path_buf);
	return ucv_boolean_new(match);
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
	int64_t inst;

	if (ucv_type(path_val) != UC_STRING || ucv_type(prefix_val) != UC_STRING)
		return NULL;

	inst = tr181_ref_instance(ucv_string_get(path_val), ucv_string_get(prefix_val));

	return inst > 0 ? ucv_int64_new(inst) : NULL;
}

/**
 * C API of tr181_ref_parse(): the instance number of a reference
 * `<prefix>.<n>` or `<prefix>.<n>.`.
 *
 * @param path    the reference
 * @param prefix  table path without the trailing dot
 * @return        the instance number, or -1 when the reference is not one
 *                to a row of the table
 */
int64_t
tr181_ref_instance(const char *path, const char *prefix)
{
	size_t prelen = strlen(prefix), len;
	const char *num;
	char key[24];

	if (strncmp(path, prefix, prelen) != 0 || path[prelen] != '.')
		return -1;

	num = path + prelen + 1;
	len = strcspn(num, ".");
	if (len >= sizeof(key) || (num[len] == '.' && num[len + 1] != '\0'))
		return -1;

	memcpy(key, num, len);
	key[len] = '\0';

	return key_is_instance(key) ? strtoll(key, NULL, 10) : -1;
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
