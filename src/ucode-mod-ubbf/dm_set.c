/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Writes through the data model: params_set, object_add and object_del.
 */

#include <limits.h>
#include <inttypes.h>

#include "dm-priv.h"

/* params_set answers -1 for a path the model does not describe and this for
 * one whose instance was never created, which the callers map onto their
 * protocol's "no such object" rather than "bad path". Set handlers only ever
 * answer -1, so the two cannot be confused. */
#define DM_SET_NO_INSTANCE	(-2)
/* And this for a row that a get handler makes and nothing stores. */
#define DM_SET_RUNTIME_ROW	(-3)
/* And this for a value the parameter's type or schema rule does not allow. */
#define DM_SET_INVALID_VALUE	(-4)

/* ---- dm.params_set ---------------------------------------------------- */

/**
 * Reports whether a path segment can stand at a `{i}` of a pattern: an
 * instance number, or a key that the stored tree holds at that place.
 * USP allows instance identifiers that are not numbers, and presets
 * shipped at boot use names such as Medium or IPV6_Medium. The tree
 * membership still refuses an unsubstituted `${var}`.
 *
 * @param node  the stored node that holds the instances, or NULL
 * @param seg   the path segment
 * @return      true when the segment names an instance
 */
static bool
instance_segment_ok(uc_value_t *node, const char *seg)
{
	return key_is_instance(seg) || ucv_object_get(node, seg, NULL);
}

/**
 * Validates that each path segment is consistent with some registered
 * model pattern at that position. A segment is acceptable when some
 * pattern has the same literal token at that position, or when some
 * pattern has `{i}` at that position and instance_segment_ok() accepts
 * the segment.
 *
 * Guards against callers that feed non-numeric junk (e.g. an
 * unsubstituted `${var}` from a test harness) into a slot that the
 * model expects to be an instance number. Without this check the
 * segment would be stored verbatim as an object key, creating a
 * phantom instance that survives config reloads.
 *
 * @param model  registered model object (pattern string -> descriptor)
 * @param parts  path segments
 * @param cnt    number of segments to validate (>=1)
 * @return       true when every segment fits some pattern, else false
 */
static bool
path_instance_segments_valid(uc_value_t *model, uc_value_t *target,
			     char **parts, int cnt)
{
	if (cnt <= 0)
		return false;

	uc_value_t *node = target;

	for (int i = 0; i < cnt; i++) {
		bool ok = false;

		ucv_object_foreach(model, pattern, entry) {
			(void)entry;
			char *pat_buf = xstrdup(pattern);
			char *pp[PATH_PARTS_MAX];
			int pc = path_split(pat_buf, pp, PATH_PARTS_MAX, 0);

			if (i >= pc) {
				free(pat_buf);
				continue;
			}

			ok = strcmp(pp[i], "{i}") ? !strcmp(pp[i], parts[i])
						  : instance_segment_ok(node, parts[i]);

			free(pat_buf);
			if (ok)
				break;
		}

		if (!ok)
			return false;

		node = ucv_object_get(node, parts[i], NULL);
	}

	return true;
}

/**
 * Reports whether a path names an instance row that was never created.
 *
 * config_parent_resolve() creates every missing level as it walks, so a
 * write addressed to an instance nobody added would materialise it with no
 * schema defaults and no NumberOfEntries update. key_is_instance() is a
 * digit test alone, so the path validator cannot catch that.
 *
 * Only an instance whose container is present in the stored tree counts as
 * missing: a subtree the config does not track at all is synthesised by a
 * get handler, and its rows are not ours to judge. object_add checks the
 * parents of the row it creates with this.
 *
 * With a model, an instance of a `runtime_instances` table does not count
 * either: path_runtime_instance_absent() decides on it, because the stored
 * table holds only the rows written so far.
 *
 * @param model  registered model object, or NULL
 * @param target root of the stored configuration
 * @param parts  path segments
 * @param cnt    number of segments to examine
 * @return       true when a segment names an absent instance
 */
static bool
path_instance_missing(uc_value_t *model, uc_value_t *target, char **parts, int cnt)
{
	uc_value_t *node = target;

	for (int i = 0; i < cnt; i++) {
		uc_value_t *child = NULL;

		if (ucv_type(node) == UC_OBJECT)
			child = ucv_object_get(node, parts[i], NULL);

		if (!child && key_is_instance(parts[i]) &&
		    ucv_type(node) == UC_OBJECT)
			return !model || !ucv_is_truish(ucv_object_get(
				model_entry_for_parts(model, parts, i + 1),
				"runtime_instances", NULL));

		node = child;
	}

	return false;
}

/**
 * Reports whether the CPE maintains the rows of a table itself.
 *
 * Such a table is not addable or has a row limit of 0, by its model entry or
 * by its schema, and its get handler makes the rows.
 *
 * @param entry  model entry of the `{i}` pattern of the table
 * @return       true when a controller cannot create rows in it
 */
static bool
model_entry_cpe_maintained(uc_value_t *entry)
{
	if (!ucv_is_callable(ucv_object_get(entry, "get", NULL)))
		return false;

	return !schema_entry_addable(entry);
}

/**
 * Asks the get handler of a table whether it makes a row at run time.
 *
 * @param vm      ucode VM context
 * @param row     model entry of the table
 * @param target  root of the stored configuration
 * @param parts   path segments
 * @param cnt     number of segments up to and including the instance
 * @return        true when the handler returns the row
 */
static bool
runtime_row_live(uc_vm_t *vm, uc_value_t *row, uc_value_t *target,
		 char **parts, int cnt)
{
	uc_value_t *get_fn = ucv_object_get(row, "get", NULL);
	uc_value_t *node = target, *parent = NULL, *result;

	if (!ucv_is_callable(get_fn))
		return false;

	for (int i = 0; i < cnt - 1 && ucv_type(node) == UC_OBJECT; i++) {
		node = ucv_object_get(node, parts[i], NULL);
		if (key_is_instance(parts[i]))
			parent = node;
	}

	result = get_handler_call(vm, get_fn, strtoll(parts[cnt - 1], NULL, 10),
				  NULL, parent, target,
				  instances_from_parts(vm, parts, cnt));
	ucv_put(result);

	return result != NULL;
}

/**
 * Reports whether a write, or an add below a row, names a row of a
 * `runtime_instances` table that the stored configuration does not hold.
 *
 * Such a table mixes stored rows with rows a get handler adds, and a
 * controller can write only the stored ones. The table container may be
 * absent from the stored tree too, which path_instance_missing() leaves
 * alone; without this check the write would store the row, and a stored
 * row stops the enumeration of the runtime rows. A table that also has
 * `writable_rows` takes a write into a row its get handler makes, which
 * the write then stores, and an add of a row below such a row.
 *
 * @param vm     ucode VM context
 * @param model  registered model object
 * @param target root of the stored configuration
 * @param parts  path segments
 * @param cnt    number of segments of the written object
 * @return       true when the write must be refused
 */
static bool
path_runtime_instance_absent(uc_vm_t *vm, uc_value_t *model, uc_value_t *target,
			     char **parts, int cnt)
{
	uc_value_t *node = target;

	for (int i = 0; i < cnt; i++) {
		uc_value_t *child = NULL;

		if (ucv_type(node) == UC_OBJECT)
			child = ucv_object_get(node, parts[i], NULL);

		if (!child && key_is_instance(parts[i])) {
			uc_value_t *row = model_entry_for_parts(model, parts, i + 1);

			if (!ucv_is_truish(ucv_object_get(row, "runtime_instances", NULL)))
				return false;

			if (!ucv_is_truish(ucv_object_get(row, "writable_rows", NULL)))
				return true;

			return !runtime_row_live(vm, row, target, parts, i + 1);
		}

		node = child;
	}

	return false;
}

/**
 * Reports whether a write would store a row of a table the CPE maintains.
 *
 * The configuration holds no rows of such a table; the enumerate mode of
 * its get handler makes them. A value stored under a row makes it a stored
 * row, and subtree_dispatch() then stops enumerating the live rows, so the
 * table shrinks to that one row. Only a set handler of the written object
 * can take such a write, or a table with `writable_rows`, whose handler
 * shows stored and live rows side by side; path_runtime_instance_absent()
 * has then checked that the row is live.
 *
 * @param model  registered model object
 * @param target root of the stored configuration
 * @param parts  path segments
 * @param cnt    number of segments of the written object
 * @return       true when the write must be refused
 */
static bool
path_runtime_row_write(uc_value_t *model, uc_value_t *target,
		       char **parts, int cnt)
{
	uc_value_t *node = target;

	for (int i = 0; i < cnt; i++) {
		uc_value_t *child = NULL;

		if (ucv_type(node) == UC_OBJECT)
			child = ucv_object_get(node, parts[i], NULL);

		if (!child && key_is_instance(parts[i])) {
			uc_value_t *row = model_entry_for_parts(model, parts, i + 1);
			uc_value_t *obj = model_entry_for_parts(model, parts, cnt);

			if (!model_entry_cpe_maintained(row) ||
			    ucv_is_truish(ucv_object_get(row, "writable_rows", NULL)))
				return false;

			return !ucv_is_callable(ucv_object_get(obj, "set", NULL));
		}

		node = child;
	}

	return false;
}

/**
 * Walks a path to the parent of the leaf segment, creating intermediate
 * objects as needed. The returned pointer is borrowed from the target tree.
 *
 * @param vm     ucode VM context
 * @param target root object to mutate
 * @param parts  path segments
 * @param cnt    number of segments (must be >= 1)
 * @return       the object that holds the leaf segment as a child
 */
static uc_value_t *
config_parent_resolve(uc_vm_t *vm, uc_value_t *target, char **parts, int cnt)
{
	return tree_node_make(vm, target, parts, cnt - 1);
}

/**
 * Invokes the model `set` handler that matches a parameter path.
 *
 * Walks the model looking for a pattern whose depth matches the parent
 * object path; when found, builds the handler context (path, param,
 * value, instance, config, root) and invokes the handler. The first
 * match wins.
 *
 * Handlers may return a negative integer to reject the write; callers
 * use this to revert the stored value. A null/undefined return, or any
 * non-negative integer, is treated as acceptance. A handler that throws
 * refuses the write with -1; the exception is logged.
 *
 * @param vm          ucode VM context
 * @param model       registered model object
 * @param target      writable target tree (workspace or live config)
 * @param path        original parameter path (for context.path)
 * @param path_parts  pre-split path segments
 * @param path_cnt    number of path segments (>=1)
 * @param value       new value being set
 * @return            0 on accept (or no matching handler), the handler's
 *                    negative return value on reject
 */
static int
set_handler_invoke(uc_vm_t *vm, uc_value_t *model, uc_value_t *target,
		   const char *path, char **path_parts, int path_cnt,
		   uc_value_t *value)
{
	int obj_cnt = path_cnt - 1;

	ucv_object_foreach(model, pattern, entry) {
		char *pat_buf, *pp[PATH_PARTS_MAX];
		int64_t last_inst;
		bool matched, has_inst;
		int pc;

		uc_value_t *set_fn = ucv_object_get(entry, "set", NULL);
		if (!set_fn || !ucv_is_callable(set_fn))
			continue;

		pat_buf = xstrdup(pattern);
		pc = path_split(pat_buf, pp, PATH_PARTS_MAX, 0);
		matched = pc == obj_cnt &&
			  pattern_parts_match(pp, path_parts, pc, true, &last_inst);
		has_inst = matched && pattern_inst_before(pp, pc) >= 0;
		free(pat_buf);

		if (!matched)
			continue;

		uc_value_t *config_node = tree_node_get(target, path_parts, pc);

		uc_value_t *ctx = ucv_object_new(vm);
		ucv_object_add(ctx, "path", ucv_string_new(path));
		ucv_object_add(ctx, "param",
			       ucv_string_new(path_parts[path_cnt - 1]));
		ucv_object_add(ctx, "value", ucv_get(value));
		ucv_object_add(ctx, "instance",
			       has_inst ? ucv_int64_new(last_inst) : NULL);
		ucv_object_add(ctx, "config",
			       config_node ? ucv_get(config_node) : NULL);
		ucv_object_add(ctx, "root", ucv_get(target));

		uc_value_t *rv = callback_invoke(vm, set_fn, 1, ctx);
		int rc = 0;
		if (exception_log_clear(vm, path))
			rc = -1;
		else if (rv && ucv_type(rv) == UC_INTEGER &&
			 ucv_int64_get(rv) < 0)
			rc = (int)ucv_int64_get(rv);
		ucv_put(rv);
		ucv_put(ctx);
		return rc;
	}

	return 0;
}

/**
 * Checks every value of a map of parameter writes against the type and the
 * schema rule of its parameter, and logs each refused value.
 *
 * @param vm      ucode VM context
 * @param model   registered model object
 * @param target  configuration tree, for the alias lookup
 * @param params  map of parameter path to value
 * @return        true when the schema allows every value
 */
static bool
params_values_ok(uc_vm_t *vm, uc_value_t *model, uc_value_t *target,
		 uc_value_t *params)
{
	bool ok = true;

	ucv_object_foreach(params, path, value) {
		char *path_buf = xstrdup(path), *path_parts[PATH_PARTS_MAX], why[128];
		char alias_slots[32][16];
		int path_cnt = path_split(path_buf, path_parts, PATH_PARTS_MAX, 0);

		/* uc_dm_params_set() refuses an invalid path itself */
		if (path_cnt > 0 &&
		    path_resolve_aliases(target, path_parts, path_cnt,
					 &alias_slots[0][0], sizeof(alias_slots[0]),
					 (int)(sizeof(alias_slots) / sizeof(alias_slots[0]))) &&
		    !schema_entry_value_ok(vm, model_entry_for_parts(model, path_parts, path_cnt - 1),
					   path_parts[path_cnt - 1], value, why, sizeof(why))) {
			fprintf(stderr, "ubbf.dm.params_set: rejecting %s: %s\n", path, why);
			ok = false;
		}

		free(path_buf);
	}

	return ok;
}

/**
 * Applies a map of parameter writes against the dm.
 *
 * For each `path: value` pair, stores the value into the target tree and
 * invokes the registered set handler when one is registered.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: params object)
 * @return       0 when every write is accepted; otherwise the first
 *               failure (-1 for an invalid path or bad arguments,
 *               else the rejecting handler's negative return value), or
 *               DM_SET_INVALID_VALUE before any write when the schema does
 *               not allow one of the values
 */
uc_value_t *
uc_dm_params_set(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *params = uc_fn_arg(0);
	uc_value_t *model, *target;
	int err = 0;

	if (!dm || ucv_type(params) != UC_OBJECT)
		return ucv_int64_new(-1);

	model = dm_model_get(dm);
	target = dm_target_get(dm);
	if (!model || !target)
		return ucv_int64_new(-1);

	if (!params_values_ok(vm, model, target, params))
		return ucv_int64_new(DM_SET_INVALID_VALUE);

	ucv_object_foreach(params, path, value) {
		char *path_buf, *path_parts[PATH_PARTS_MAX];
		char alias_slots[32][16];
		int path_cnt = 0;
		path_buf = xstrdup(path);
		path_cnt = path_split(path_buf, path_parts, PATH_PARTS_MAX, 0);

		if (path_cnt == 0) {
			free(path_buf);
			continue;
		}

		if (path_cnt < 0 ||
		    !path_resolve_aliases(target, path_parts, path_cnt,
					  &alias_slots[0][0], sizeof(alias_slots[0]),
					  (int)(sizeof(alias_slots) / sizeof(alias_slots[0]))) ||
		    !path_instance_segments_valid(model, target, path_parts,
						  path_cnt - 1)) {
			fprintf(stderr, "ubbf.dm.params_set: rejecting invalid path %s\n",
				path);
			if (!err)
				err = -1;
			free(path_buf);
			continue;
		}

		if (path_instance_missing(model, target, path_parts, path_cnt - 1) ||
		    path_runtime_instance_absent(vm, model, target, path_parts, path_cnt - 1)) {
			fprintf(stderr, "ubbf.dm.params_set: no such instance for %s\n",
				path);
			if (!err)
				err = DM_SET_NO_INSTANCE;
			free(path_buf);
			continue;
		}

		if (path_runtime_row_write(model, target, path_parts, path_cnt - 1)) {
			fprintf(stderr, "ubbf.dm.params_set: %s is in a row the "
				"device makes, nothing stores it\n", path);
			if (!err)
				err = DM_SET_RUNTIME_ROW;
			free(path_buf);
			continue;
		}

		uc_value_t *parent = config_parent_resolve(vm, target,
							   path_parts,
							   path_cnt);
		const char *leaf = path_parts[path_cnt - 1];

		/* Snapshot any previous leaf value so a rejecting set
		 * handler can be reverted without reaching trans_commit
		 * (and thus the renderer) with a stored-but-invalid
		 * write. ucv_object_get returns a borrowed pointer; take
		 * our own reference because ucv_object_add releases the
		 * existing slot when overwriting. */
		uc_value_t *prev = ucv_object_get(parent, leaf, NULL);
		bool had_prev = prev != NULL;
		if (had_prev)
			ucv_get(prev);

		ucv_object_add(parent, leaf, ucv_get(value));

		int rc = set_handler_invoke(vm, model, target, path,
					    path_parts, path_cnt, value);

		if (rc < 0) {
			if (had_prev)
				ucv_object_add(parent, leaf, prev);
			else
				ucv_object_delete(parent, leaf);
			if (!err)
				err = rc;
		} else if (had_prev) {
			ucv_put(prev);
		}

		free(path_buf);
	}

	return ucv_int64_new(err);
}

/* ---- dm.object_add ---------------------------------------------------- */

/**
 * Takes the instance number of a new row from the instance map, for a table
 * whose runtime rows share the numbers with its stored rows.
 *
 * The map gets the table path, with the instance numbers that alias
 * resolution put in place, and one above the highest stored row. A number
 * that a stored row holds is not taken.
 *
 * @param vm         ucode VM context
 * @param parts      resolved segments of the table path
 * @param cnt        number of segments
 * @param container  stored table
 * @return           the number, or 0 to fall back to instance_next_free() for a
 *                   table the map does not number
 */
static int
numbered_inst(uc_vm_t *vm, char **parts, int cnt, uc_value_t *container)
{
	char *path, key[16];
	int64_t top = 0, n;

	ucv_object_foreach(container, k, v) {
		(void)v;
		if (key_is_instance(k) && strtoll(k, NULL, 10) > top)
			top = strtoll(k, NULL, 10);
	}

	path = path_join(parts, 0, cnt);
	n = instance_map_add_number(vm, path, top + 1);
	free(path);

	if (n < 1 || n > INT_MAX)
		return 0;

	snprintf(key, sizeof(key), "%" PRId64, n);
	if (ucv_object_get(container, key, NULL))
		return 0;

	return (int)n;
}

/**
 * Reports whether a pattern is the row pattern of a table path: one
 * segment longer, ending in `{i}`, and agreeing with the path on the other
 * segments. A `{i}` takes what instance_segment_ok() accepts.
 *
 * @param pattern  model pattern
 * @param target   root of the stored configuration
 * @param parts    segments of the table path
 * @param cnt      number of segments
 * @return         true when the pattern fits
 */
static bool
table_pattern_fits(const char *pattern, uc_value_t *target, char **parts, int cnt)
{
	char *buf = xstrdup(pattern), *pat_parts[PATH_PARTS_MAX];
	int pat_cnt = path_split(buf, pat_parts, PATH_PARTS_MAX, 0);
	bool ok = pat_cnt == cnt + 1 && !strcmp(pat_parts[cnt], "{i}");
	uc_value_t *walk = target;

	for (int i = 0; ok && i < cnt; i++) {
		ok = strcmp(pat_parts[i], "{i}") ? !strcmp(pat_parts[i], parts[i])
						 : instance_segment_ok(walk, parts[i]);
		walk = ucv_object_get(walk, parts[i], NULL);
	}

	free(buf);

	return ok;
}

/**
 * Finds the model entry of the rows of a table.
 *
 * The direct lookup of `<path>.{i}` misses nested patterns such as
 * Device.Firewall.Chain.{i}.Rule.{i} when the path holds instance numbers
 * or named instance keys, so the first pattern that table_pattern_fits()
 * accepts stands in for it.
 *
 * @param model   registered model object
 * @param target  root of the stored configuration
 * @param parts   segments of the table path
 * @param cnt     number of segments
 * @return        the entry, or NULL when the model has no such table
 */
static uc_value_t *
table_entry_find(uc_value_t *model, uc_value_t *target, char **parts, int cnt)
{
	char *path = path_join(parts, 0, cnt);
	uc_value_t *entry = table_row_entry(model, path);

	free(path);

	if (entry)
		return entry;

	ucv_object_foreach(model, mpat, mentry) {
		if (table_pattern_fits(mpat, target, parts, cnt))
			return mentry;
	}

	return NULL;
}

/**
 * Adds a new instance to a TR-181 multi-instance container.
 *
 * Navigates (creating as needed) to the container, allocates the next
 * free instance number, applies schema defaults, generates an Alias when
 * the schema defines one as an empty string, and updates the parent's
 * `<TableName>NumberOfEntries` field. The pattern path used for default
 * lookup is the supplied path with `.{i}` appended.
 *
 * A table that the instance map numbers takes the next number of the map,
 * because its runtime rows share the numbers with its stored rows; see
 * numbered_inst(). Another table takes the lowest number that no stored row
 * holds.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: container path)
 * @return       new instance number, or 0 when the path is invalid or
 *               the row limit of the table is reached
 */
uc_value_t *
uc_dm_object_add(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *model, *target;
	const char *path;
	char *buf, *parts[PATH_PARTS_MAX], *alias_str;
	char alias_slots[32][16];
	int cnt = 0;
	uc_value_t *container, *model_entry, *defaults;
	uc_value_t *alias;
	int64_t max;
	int new_inst;
	char inst_str[16];

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(0);

	model = dm_model_get(dm);
	target = dm_target_get(dm);
	if (!model || !target)
		return ucv_int64_new(0);

	path = ucv_string_get(path_val);
	buf = xstrdup(path);
	cnt = path_split(buf, parts, PATH_PARTS_MAX, 0);

	if (cnt == 0) {
		free(buf);
		return ucv_int64_new(0);
	}

	if (cnt < 0 ||
	    !path_resolve_aliases(target, parts, cnt,
				  &alias_slots[0][0], sizeof(alias_slots[0]),
				  (int)(sizeof(alias_slots) / sizeof(alias_slots[0]))) ||
	    !path_instance_segments_valid(model, target, parts, cnt)) {
		fprintf(stderr, "ubbf.dm.object_add: rejecting invalid container path %s\n",
			path);
		free(buf);
		return ucv_int64_new(0);
	}

	if (path_instance_missing(model, target, parts, cnt) ||
	    path_runtime_instance_absent(vm, model, target, parts, cnt)) {
		fprintf(stderr, "ubbf.dm.object_add: rejecting %s, a parent instance does not exist\n",
			path);
		free(buf);
		return ucv_int64_new(0);
	}

	container = tree_node_make(vm, target, parts, cnt);

	model_entry = table_entry_find(model, target, parts, cnt);

	/* A path the model describes no table for is not a place to put a row.
	 * The callers gate on object_writable() first, so reaching here means
	 * something bypassed them; the empty containers the walk above created
	 * go away with the transaction this failure aborts. */
	if (!model_entry) {
		fprintf(stderr, "ubbf.dm.object_add: no table at %s\n", path);
		free(buf);
		return ucv_int64_new(0);
	}

	if (!schema_entry_addable(model_entry)) {
		fprintf(stderr, "ubbf.dm.object_add: %s is maintained by the CPE\n",
			path);
		free(buf);
		return ucv_int64_new(0);
	}

	if (schema_entry_max_instances(model_entry, &max) &&
	    instance_keys_count(container) >= max) {
		free(buf);
		return ucv_int64_new(0);
	}

	new_inst = numbered_inst(vm, parts, cnt, container);
	if (!new_inst)
		new_inst = (int)instance_next_free(container);

	/* apply schema defaults */
	uc_value_t *new_obj = ucv_object_new(vm);
	defaults = schema_entry_defaults(vm, model_entry);
	ucv_object_foreach(defaults, key, val) {
		uint32_t type;

		if (schema_entry_member(model_entry, key, &type))
			ucv_object_add(new_obj, key, ucv_get(val));
	}
	ucv_put(defaults);

	/* TR-181 asks for a "cpe-" prefix on an Alias that the agent assigns.
	 * The table name starts with an upper-case letter, which keeps the
	 * value apart from the Alias of a firewall hook, "cpe-" and a
	 * lower-case name: firewall_reconcile deletes such a row when no hook
	 * claims it. */
	alias = ucv_object_get(new_obj, "Alias", NULL);
	if (alias && ucv_type(alias) == UC_STRING &&
	    ucv_string_length(alias) == 0) {
		xasprintf(&alias_str, "cpe-%s%d", parts[cnt - 1], new_inst);
		ucv_object_add(new_obj, "Alias", ucv_string_new(alias_str));
		free(alias_str);
	}

	snprintf(inst_str, sizeof(inst_str), "%d", new_inst);
	ucv_object_add(container, inst_str, new_obj);

	entries_count_set(tree_node_get(target, parts, cnt - 1), parts[cnt - 1], container);

	free(buf);
	return ucv_int64_new(new_inst);
}

/* ---- dm.object_del ---------------------------------------------------- */

/**
 * Removes a TR-181 instance from its multi-instance container.
 *
 * Validates that the trailing path segment is a positive integer and
 * updates the parent's `<TableName>NumberOfEntries` after deletion.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: instance path)
 * @return       0 on success, 1 when the path or instance does not
 *               exist, -1 on error
 */
uc_value_t *
uc_dm_object_del(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *target;
	const char *path;
	char *buf, *parts[PATH_PARTS_MAX], *endp;
	char alias_slots[32][16];
	int cnt = 0;
	long v;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(-1);

	target = dm_target_get(dm);
	if (!target)
		return ucv_int64_new(-1);

	path = ucv_string_get(path_val);
	buf = xstrdup(path);
	cnt = path_split(buf, parts, PATH_PARTS_MAX, 0);

	if (cnt < 2 ||
	    !path_resolve_aliases(target, parts, cnt,
				  &alias_slots[0][0], sizeof(alias_slots[0]),
				  (int)(sizeof(alias_slots) / sizeof(alias_slots[0])))) {
		free(buf);
		return ucv_int64_new(1);
	}

	/* validate instance key */
	v = strtol(parts[cnt - 1], &endp, 10);
	if (*endp || endp == parts[cnt - 1] || v < 1) {
		free(buf);
		return ucv_int64_new(1);
	}

	uc_value_t *parent = tree_node_get(target, parts, cnt - 2);
	uc_value_t *table = ucv_object_get(parent, parts[cnt - 2], NULL);

	if (!ucv_object_get(table, parts[cnt - 1], NULL)) {
		free(buf);
		return ucv_int64_new(1);
	}

	ucv_object_delete(table, parts[cnt - 1]);
	entries_count_set(parent, parts[cnt - 2], table);

	free(buf);
	return ucv_int64_new(0);
}
