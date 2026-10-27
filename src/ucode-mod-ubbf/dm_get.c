/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Reads through the data model: params_get, the subtree dispatch that
 * merges the get handlers into the stored tree, wildcard expansion and the
 * instance refresh.
 */

#include "dm-priv.h"

/**
 * Writes a `Status` field derived from Enable onto a get result.
 *
 * Backs the `enable_status_derive: true` model-entry flag. Allocates
 * `*result` if NULL, then unconditionally overwrites any existing
 * `Status` key. Unconditional is required because a handler that spreads
 * `ctx.config` (e.g. `...ubbf.ctx_config(ctx)`) carries the schema-default
 * `"Status": ""` through its result; the flag's whole point is to own
 * that field. Handlers that need conditional Status must not set the flag.
 *
 * @param vm      ucode VM context
 * @param result  in/out result object (allocated if *result is NULL)
 * @param cfg     config object whose `Enable` drives the derivation
 */
static void
status_overlay(uc_vm_t *vm, uc_value_t **result, uc_value_t *cfg)
{
	if (!*result)
		*result = ucv_object_new(vm);

	uc_value_t *en = cfg ? ucv_object_get(cfg, "Enable", NULL) : NULL;
	ucv_object_delete(*result, "Status");
	ucv_object_add(*result, "Status",
		       ucv_string_new(value_to_bool(en) ? "Enabled" : "Disabled"));
}

/* internal: find best get handler, returns {handler, instance, remaining[], pattern} */
typedef struct {
	uc_value_t *handler;
	int64_t instance;
	int pattern_len;
	const char *pattern_key;
	uc_value_t *entry;
} handler_match_t;

/**
 * Tests whether one model entry matches a path and updates `best` if longer.
 *
 * Iterates the pattern segments, accepting `{i}` against numeric path
 * segments and otherwise requiring exact equality. When the pattern is
 * longer than any earlier match for this query, `best` is overwritten.
 *
 * @param path         original path string (used by caller for context only)
 * @param path_cnt     number of split path segments
 * @param path_parts   pre-split path segments
 * @param pattern      candidate pattern key
 * @param entry        model entry object that owns the handler
 * @param handler_key  field name of the handler to look up (e.g. `get`, `set`)
 * @param best         in/out longest-match record updated on improvement
 * @return             true when this match became the new best
 */
static bool
match_handler(const char *path, int path_cnt, char **path_parts,
	      const char *pattern, uc_value_t *entry, const char *handler_key,
	      handler_match_t *best)
{
	char *pat_buf, *pat_parts[PATH_PARTS_MAX];
	int64_t last_inst;
	bool matched;
	int pat_cnt;

	uc_value_t *fn = ucv_object_get(entry, handler_key, NULL);
	bool callable = fn && ucv_is_callable(fn);
	bool flag_only = false;

	if (!callable && strcmp(handler_key, "get") == 0)
		flag_only = value_to_bool(
			ucv_object_get(entry, "enable_status_derive", NULL));

	if (!callable && !flag_only)
		return false;

	pat_buf = xstrdup(pattern);
	pat_cnt = path_split(pat_buf, pat_parts, PATH_PARTS_MAX, 0);
	matched = pat_cnt >= 0 && path_cnt >= pat_cnt &&
		  pattern_parts_match(pat_parts, path_parts, pat_cnt, true, &last_inst);
	free(pat_buf);

	if (!matched)
		return false;

	if (pat_cnt > best->pattern_len) {
		best->handler = callable ? fn : NULL;
		best->instance = last_inst;
		best->pattern_len = pat_cnt;
		best->pattern_key = pattern;
		best->entry = entry;
		return true;
	}

	return false;
}

/**
 * Adds schema default values to a config node for keys that are absent.
 *
 * Existing keys are preserved; only missing keys receive their default.
 *
 * @param vm           ucode VM context
 * @param config_node  destination object (mutated in place)
 * @param defaults     defaults object to merge in
 */
static void
schema_defaults_merge(uc_vm_t *vm, uc_value_t *config_node, uc_value_t *defaults)
{
	if (!defaults || ucv_type(defaults) != UC_OBJECT || !config_node)
		return;

	ucv_object_foreach(defaults, key, val) {
		if (!ucv_object_get(config_node, key, NULL))
			ucv_object_add(config_node, key, ucv_get(val));
	}
}

/* ---- dm.params_get ---------------------------------------------------- */

/**
 * Reports whether a pattern has as many segments as a path and agrees with
 * it on each, `{i}` taking any segment.
 *
 * @param pattern  model pattern
 * @param parts    path segments
 * @param cnt      number of segments
 * @return         true when the pattern fits the path
 */
static bool
pattern_fits(const char *pattern, char **parts, int cnt)
{
	char *buf = xstrdup(pattern), *pat_parts[PATH_PARTS_MAX];
	int pat_cnt = path_split(buf, pat_parts, PATH_PARTS_MAX, 0);
	bool fits = pat_cnt == cnt &&
		    pattern_parts_match(pat_parts, parts, cnt, false, NULL);

	free(buf);

	return fits;
}

/**
 * Returns the schema default of a parameter from the first model entry
 * whose pattern fits the object of the parameter.
 *
 * @param vm     ucode VM context
 * @param model  registered model object
 * @param parts  segments of the parameter path
 * @param cnt    number of segments, at least 2
 * @return       new reference to the default, or NULL when there is none
 */
static uc_value_t *
param_default_get(uc_vm_t *vm, uc_value_t *model, char **parts, int cnt)
{
	uc_value_t *def;

	ucv_object_foreach(model, pattern, entry) {
		if (ucv_type(entry) != UC_OBJECT || !pattern_fits(pattern, parts, cnt - 1))
			continue;

		def = schema_entry_default(vm, entry, parts[cnt - 1]);
		if (def)
			return def;
	}

	return NULL;
}

/**
 * Resolves parameter values for a path map.
 *
 * Mutates the input `paths` object in place: each key is replaced with the
 * resolved value. For every requested path the parent object is hydrated via
 * `subtree_dispatch` (the same dispatcher backing `dm.get_subtree_with_state`
 * / `bbf-dm.show`), and the leaf segment is read out of the result. A
 * per-call subtree cache keyed by parent path keeps obuspa's batched
 * params_get O(handlers per parent) instead of O(N · handlers).
 *
 * Falling back to the runtime tree directly and then to schema defaults
 * preserves behaviour for static parameters whose object exists in
 * persisted config but whose value was never explicitly set.
 *
 * A path that path_split() refuses, or whose aliases path_resolve_aliases()
 * cannot resolve, keeps its value.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: paths object)
 * @return       0 on success, -1 on error
 */
uc_value_t *
uc_dm_params_get(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *paths = uc_fn_arg(0);
	uc_value_t *model, *runtime;
	uc_value_t *subtree_cache, *anc_cache;

	if (!dm || ucv_type(paths) != UC_OBJECT)
		return ucv_int64_new(-1);

	model = dm_model_get(dm);
	runtime = dm_runtime_get(dm);
	if (!model || !runtime)
		return ucv_int64_new(-1);

	subtree_cache = ucv_object_new(vm);
	anc_cache = ucv_object_new(vm);

	ucv_object_foreach(paths, path, old_val) {
		char *path_buf, *path_parts[PATH_PARTS_MAX], *obj_path = NULL;
		char alias_slots[32][16];
		int path_cnt = 0;
		uc_value_t *value = NULL, *fallback = NULL;

		(void)old_val;

		path_buf = xstrdup(path);
		path_cnt = path_split(path_buf, path_parts, PATH_PARTS_MAX, 0);

		if (path_cnt <= 0 ||
		    !path_resolve_aliases(runtime, path_parts, path_cnt,
					  &alias_slots[0][0], sizeof(alias_slots[0]),
					  (int)(sizeof(alias_slots) / sizeof(alias_slots[0])))) {
			free(path_buf);
			continue;
		}

		if (path_cnt >= 2)
			obj_path = path_join(path_parts, 0, path_cnt - 1);

		/* Hydrate the parent object via the shared subtree dispatcher
		 * (same logic that backs dm.get_subtree_with_state and
		 * bbf-dm.show), then read the leaf out of it. The cache keeps
		 * an obuspa params_get batch O(handlers per parent) instead of
		 * O(N · handlers) when several leaves share a parent. */
		if (obj_path) {
			uc_value_t *subtree = ucv_object_get(subtree_cache, obj_path, NULL);
			if (!subtree) {
				subtree = subtree_dispatch(vm, dm, obj_path, anc_cache);
				if (subtree)
					ucv_object_add(subtree_cache, obj_path, subtree);
			}

			if (subtree && ucv_type(subtree) == UC_OBJECT)
				value = ucv_object_get(subtree, path_parts[path_cnt - 1], NULL);
		}

		if (!value)
			value = navigate_by_path(vm, runtime, path);

		/* Final fallback: parent object exists in runtime but the
		 * specific leaf was never written and no handler synthesised
		 * it. Surface the schema default so callers see the documented
		 * value rather than null. */
		if (!value && obj_path && navigate_by_path(vm, runtime, obj_path))
			value = fallback = param_default_get(vm, model, path_parts, path_cnt);

		free(obj_path);
		free(path_buf);

		if (value)
			ucv_object_add(paths, path, ucv_get(value));

		ucv_put(fallback);
	}

	ucv_put(subtree_cache);
	ucv_put(anc_cache);
	return ucv_int64_new(0);
}

/* ---- dm.get_subtree_with_state ---------------------------------------- */

/**
 * Merges runtime-discovered instances into the response tree.
 *
 * For each instance-numbered key in `result`, navigates to
 * `base[rel_parts...][inst_key]`, creating intermediate objects as
 * needed, and shallow-merges the instance value into it.
 *
 * @param vm        ucode VM context
 * @param base      destination tree (mutated)
 * @param rel_parts path segments from `base` down to the instance container
 * @param result    object whose instance children are merged in
 */
static void
runtime_instances_merge(uc_vm_t *vm, uc_value_t *base,
			uc_value_t *rel_parts, uc_value_t *result)
{
	if (ucv_type(result) != UC_OBJECT)
		return;

	ucv_object_foreach(result, inst_key, inst_val) {
		if (!key_is_instance(inst_key))
			continue;

		uc_value_t *full_parts = ucv_array_new(vm);
		size_t rlen = ucv_array_length(rel_parts);

		for (size_t i = 0; i < rlen; i++)
			ucv_array_push(full_parts, ucv_get(ucv_array_get(rel_parts, i)));
		ucv_array_push(full_parts, ucv_string_new(inst_key));

		uc_value_t *cur = base;
		size_t plen = ucv_array_length(full_parts);

		for (size_t i = 0; i < plen - 1; i++) {
			uc_value_t *pv = ucv_array_get(full_parts, i);

			cur = object_child_make(vm, cur, ucv_string_get(pv));
		}

		uc_value_t *last_pv = ucv_array_get(full_parts, plen - 1);
		const char *last_k = ucv_string_get(last_pv);

		if (ucv_type(inst_val) == UC_OBJECT) {
			uc_value_t *target = object_child_make(vm, cur, last_k);

			ucv_object_foreach(inst_val, ik, iv)
				ucv_object_add(target, ik, ucv_get(iv));
		} else {
			ucv_object_add(cur, last_k, ucv_get(inst_val));
		}

		ucv_put(full_parts);
	}
}

/**
 * Tests whether an instance path falls inside a base path.
 *
 * Returns true when every base segment matches the corresponding
 * instance segment (up to the smaller of the two lengths).
 *
 * @param inst_parts instance path segments
 * @param inst_cnt   number of instance segments
 * @param base_parts base path segments
 * @param base_cnt   number of base segments
 * @return           true when the instance path is within base scope
 */
static bool
instance_base_matches(char **inst_parts, int inst_cnt,
		      char **base_parts, int base_cnt)
{
	for (int i = 0; i < base_cnt; i++) {
		if (i >= inst_cnt)
			return true;
		if (strcmp(base_parts[i], inst_parts[i]) != 0)
			return false;
	}

	return true;
}

/**
 * Collects the instance numbers of a path, outermost first, for the
 * `instances` member of a get context: a handler below a row learns from
 * it which row it serves, as an operation handler does.
 *
 * @param vm     ucode VM context
 * @param parts  path segments
 * @param cnt    number of segments to scan
 * @return       new array of integers
 */
uc_value_t *
instances_from_parts(uc_vm_t *vm, char **parts, int cnt)
{
	uc_value_t *arr = ucv_array_new(vm);

	for (int i = 0; i < cnt; i++)
		if (key_is_instance(parts[i]))
			ucv_array_push(arr, ucv_int64_new(strtoll(parts[i], NULL, 10)));

	return arr;
}

/**
 * Invokes a `get` handler with a freshly built context object.
 *
 * Constructs `{ instance, instances, config, parent, root }` and discards
 * any non-object return so callers can rely on the result being either
 * NULL or a TR-181 object.
 *
 * @param vm        ucode VM context
 * @param handler   callable get handler
 * @param instance  current instance number, or 0 if not applicable
 * @param config    per-instance config (may be NULL)
 * @param parent    parent-instance config (may be NULL)
 * @param runtime   runtime tree root
 * @param instances instance numbers of the path from instances_from_parts(),
 *                  owned by the context; in enumerate mode those of the
 *                  parent rows (may be NULL)
 * @return          handler result object, or NULL on failure; an
 *                  exception of the handler is logged and gives NULL
 */
uc_value_t *
get_handler_call(uc_vm_t *vm, uc_value_t *handler, int64_t instance,
		 uc_value_t *config, uc_value_t *parent, uc_value_t *runtime,
		 uc_value_t *instances)
{
	uc_value_t *ctx = ucv_object_new(vm);

	ucv_object_add(ctx, "instance", instance ? ucv_int64_new(instance) : NULL);
	ucv_object_add(ctx, "instances", instances ? instances : ucv_array_new(vm));
	ucv_object_add(ctx, "config", config ? ucv_get(config) : NULL);
	ucv_object_add(ctx, "parent", parent ? ucv_get(parent) : NULL);
	ucv_object_add(ctx, "root", runtime ? ucv_get(runtime) : NULL);

	uc_value_t *result = callback_invoke(vm, handler, 1, ctx);
	ucv_put(ctx);

	if (exception_log_clear(vm, "get handler") || ucv_type(result) != UC_OBJECT) {
		ucv_put(result);
		return NULL;
	}

	return result;
}

/**
 * Finds the model entry of a child object of a pattern.
 *
 * A table, `<pattern>.<key>.{i}`, is looked up first: its rows carry the
 * schema, while the container entry `<pattern>.<key>` usually has none.
 *
 * @param model          registered model object
 * @param pattern        pattern of the parent entry
 * @param key            child name
 * @param child_pattern  receives the pattern of the entry found, a new
 *                       string that the caller frees, or NULL
 * @param table          receives whether the entry is the row entry of a table
 * @return               the entry, or NULL when the model registers neither
 */
static uc_value_t *
child_entry(uc_value_t *model, const char *pattern, const char *key,
	    char **child_pattern, bool *table)
{
	uc_value_t *entry;

	xasprintf(child_pattern, "%s.%s.{i}", pattern, key);
	entry = ucv_object_get(model, *child_pattern, NULL);
	*table = entry != NULL;
	if (entry)
		return entry;

	free(*child_pattern);
	xasprintf(child_pattern, "%s.%s", pattern, key);
	entry = ucv_object_get(model, *child_pattern, NULL);
	if (entry)
		return entry;

	free(*child_pattern);
	*child_pattern = NULL;

	return NULL;
}

/**
 * Logs a key that result_project() removed, once per pattern and key.
 *
 * @param vm       ucode VM context
 * @param pattern  pattern of the model entry
 * @param key      removed key
 * @param what     what the key is missing from
 */
static void
undeclared_log(uc_vm_t *vm, const char *pattern, const char *key,
	       const char *what)
{
	uc_value_t *seen = registry_get(vm, "ubbf.dm.undeclared", UC_OBJECT);
	char *id;

	xasprintf(&id, "%s.%s", pattern, key);

	if (!ucv_object_get(seen, id, NULL)) {
		fprintf(stderr, "ubbf.dm: %s: get handler returned %s, which %s\n",
			pattern, key, what);
		ucv_object_add(seen, id, ucv_boolean_new(true));
	}

	free(id);
}

static void rows_project(uc_vm_t *vm, ubbf_dm_t *dm, const char *pattern,
			 uc_value_t *entry, uc_value_t *rows);

/**
 * Reports whether the model leaves out a child object on purpose, for the
 * active protocol or TR-181 version.
 *
 * @param dm       datamodel instance
 * @param pattern  pattern of the parent entry
 * @param key      key of the child object
 * @return         true when `uc_dm_register_hidden()` named its pattern
 */
static bool
child_hidden(ubbf_dm_t *dm, const char *pattern, const char *key)
{
	uc_value_t *hidden = ucv_resource_value_get(dm->res_obj, DM_SLOT_HIDDEN);
	char *table, *object;
	bool found;

	if (!hidden)
		return false;

	xasprintf(&table, "%s.%s.{i}", pattern, key);
	xasprintf(&object, "%s.%s", pattern, key);

	found = ucv_object_get(hidden, table, NULL) ||
		ucv_object_get(hidden, object, NULL);

	free(table);
	free(object);

	return found;
}

/**
 * Removes from a get handler result what the model does not have: a
 * parameter that the schema of the entry does not declare, such as a member
 * the TR-181 version of the image does not have, and a child object whose
 * pattern the model does not register, such as a table the version deletes.
 * A child object that stays is projected against its own entry, so a
 * handler that returns its children inline is filtered like one that does
 * not. Keys that start with a dot stay: they carry internal metadata such as
 * `.instance` that child handlers read from their parent.
 *
 * Each removed key is logged once per pattern, except a member that the
 * protocol or the version hides in a table schema, and a child object that
 * the model leaves out for the protocol or the version.
 *
 * @param vm       ucode VM context
 * @param dm       datamodel instance
 * @param pattern  pattern of the model entry
 * @param entry    model entry
 * @param result   handler result for one object
 */
static void
result_project(uc_vm_t *vm, ubbf_dm_t *dm, const char *pattern,
	       uc_value_t *entry, uc_value_t *result)
{
	uc_value_t *model = dm_model_get(dm);
	uc_value_t *params, *children, *child;
	char *child_pattern;
	uint32_t type;
	bool table;

	if (ucv_type(result) != UC_OBJECT || !ucv_object_get(entry, "schema", NULL))
		return;

	params = ucv_array_new(vm);
	children = ucv_array_new(vm);

	ucv_object_foreach(result, key, val) {
		if (key[0] == '.')
			continue;

		if (ucv_type(val) != UC_OBJECT) {
			if (!schema_entry_member(entry, key, &type))
				ucv_array_push(params, ucv_string_new(key));
			continue;
		}

		child = child_entry(model, pattern, key, &child_pattern, &table);
		if (!child)
			ucv_array_push(children, ucv_string_new(key));
		else if (table)
			rows_project(vm, dm, child_pattern, child, val);
		else
			result_project(vm, dm, child_pattern, child, val);

		free(child_pattern);
	}

	for (size_t i = 0; i < ucv_array_length(params); i++) {
		uc_value_t *name = ucv_array_get(params, i);

		ucv_object_delete(result, ucv_string_get(name));

		if (!schema_entry_hidden(entry, ucv_string_get(name)))
			undeclared_log(vm, pattern, ucv_string_get(name),
				       "the schema does not declare");
	}

	for (size_t i = 0; i < ucv_array_length(children); i++) {
		uc_value_t *name = ucv_array_get(children, i);

		if (!child_hidden(dm, pattern, ucv_string_get(name)))
			undeclared_log(vm, pattern, ucv_string_get(name),
				       "the model does not register");

		ucv_object_delete(result, ucv_string_get(name));
	}

	ucv_put(params);
	ucv_put(children);
}

/**
 * Applies `result_project()` to each row of an enumerate-mode result.
 *
 * @param vm       ucode VM context
 * @param dm       datamodel instance
 * @param pattern  pattern of the model entry
 * @param entry    model entry
 * @param rows     handler result, one key per row
 */
static void
rows_project(uc_vm_t *vm, ubbf_dm_t *dm, const char *pattern,
	     uc_value_t *entry, uc_value_t *rows)
{
	ucv_object_foreach(rows, key, row) {
		(void)key;
		result_project(vm, dm, pattern, entry, row);
	}
}

/**
 * Records the row count a runtime-enumerated table produced, for its parent.
 *
 * The parent object carries `<Table>NumberOfEntries`, but its handler runs
 * independently of the table's, nothing orders parent before child, and every
 * handler merge is an unconditional overwrite, schema default included. So the
 * count is parked under the parent's path relative to the response base and
 * written by `entries_count_apply()` once the model walk is over. Nothing is
 * recorded when the parent lies above the base or its schema does not declare
 * the key.
 *
 * @param vm         ucode VM context
 * @param pending    object mapping a relative parent path to its counts
 * @param model      registered model object
 * @param pat_parts  pattern segments of the table entry
 * @param last_i     index of the table's trailing `{i}` in `pat_parts`
 * @param pp_parts   segments of the concrete container path
 * @param pp_cnt     number of segments in `pp_parts`
 * @param base_cnt   number of segments in the response base path
 * @param rows       enumerate-mode handler result, one key per row
 */
static void
entries_count_record(uc_vm_t *vm, uc_value_t *pending, uc_value_t *model,
		     char **pat_parts, int last_i, char **pp_parts, int pp_cnt,
		     int base_cnt, uc_value_t *rows)
{
	char *parent_pat, *rel, *key, count[16];
	uc_value_t *entry, *counts;
	uint32_t type;

	if (last_i < 2 || pp_cnt - 1 < base_cnt)
		return;

	parent_pat = path_join(pat_parts, 0, last_i - 1);
	entry = ucv_object_get(model, parent_pat, NULL);
	free(parent_pat);

	xasprintf(&key, "%sNumberOfEntries", pat_parts[last_i - 1]);
	if (!schema_entry_member(entry, key, &type)) {
		free(key);
		return;
	}

	rel = path_join(pp_parts, base_cnt, pp_cnt - 1);
	counts = ucv_object_get(pending, rel, NULL);
	if (!counts) {
		counts = ucv_object_new(vm);
		ucv_object_add(pending, rel, counts);
	}
	free(rel);

	snprintf(count, sizeof(count), "%d", instance_keys_count(rows));
	ucv_object_add(counts, key, ucv_string_new(count));
	free(key);
}

/**
 * Writes the counts parked by `entries_count_record()` onto their parents.
 *
 * Always overwrites: after the merge a handler-computed "0" and a schema
 * default "0" are indistinguishable, and the row count is what TR-181
 * defines the parameter to be. The rows are counted where they ended up,
 * under the parent's table in the response, because a parent handler may
 * synthesise the table itself while the table's own handler discovers
 * nothing; the parked count stands in only when the response carries no
 * table object. A parent missing from the response is skipped.
 *
 * @param vm       ucode VM context
 * @param base     hydrated subtree (mutated)
 * @param pending  object mapping a relative parent path to its counts
 */
static void
entries_count_apply(uc_vm_t *vm, uc_value_t *base, uc_value_t *pending)
{
	static const char suffix[] = "NumberOfEntries";
	const size_t suffix_len = sizeof(suffix) - 1;

	ucv_object_foreach(pending, rel, counts) {
		uc_value_t *parent = *rel ? navigate_by_path(vm, base, rel) : base;

		if (ucv_type(parent) != UC_OBJECT)
			continue;

		ucv_object_foreach(counts, key, val) {
			size_t key_len = strlen(key);
			uc_value_t *rows = NULL;
			char *table = NULL;

			if (key_len > suffix_len) {
				table = xalloc(key_len - suffix_len + 1);
				memcpy(table, key, key_len - suffix_len);
				rows = ucv_object_get(parent, table, NULL);
			}

			if (ucv_type(rows) == UC_OBJECT)
				entries_count_set(parent, table, rows);
			else
				ucv_object_add(parent, key, ucv_get(val));

			free(table);
		}
	}
}

typedef struct {
	const char *pattern;
	uc_value_t *entry;
	int depth;
	size_t index;
} model_order_t;

static int
model_order_cmp(const void *a, const void *b)
{
	const model_order_t *x = a, *y = b;

	if (x->depth != y->depth)
		return x->depth - y->depth;

	return (x->index > y->index) - (x->index < y->index);
}

/**
 * Lists the model entries ordered by pattern depth, then registration order.
 *
 * A get handler result replaces the keys it returns, so a container handler
 * that returns its stored config must run before the handlers of its
 * descendants. Registration order does not guarantee that: `Device` is
 * registered after most of the domains below it.
 *
 * @param model  registered model object
 * @param count  receives the number of entries
 * @return       array to free(), or NULL when the model is empty
 */
static model_order_t *
model_order_build(uc_value_t *model, size_t *count)
{
	size_t n = ucv_object_length(model), i = 0;
	model_order_t *order;

	*count = 0;
	if (!n)
		return NULL;

	order = calloc(n, sizeof(*order));
	if (!order)
		return NULL;

	ucv_object_foreach(model, pattern, entry) {
		if (i >= n)
			break;

		order[i].pattern = pattern;
		order[i].entry = entry;
		order[i].depth = 1;
		order[i].index = i;

		for (const char *p = pattern; *p; p++)
			if (*p == '.')
				order[i].depth++;

		i++;
	}

	qsort(order, i, sizeof(*order), model_order_cmp);
	*count = i;

	return order;
}

/**
 * Collects the paths of an object below rows that are in a response tree.
 *
 * The rows of a table that the CPE maintains are not in the stored tree; a
 * get handler makes them earlier in the same walk, so they are only in the
 * response. Without their paths the walk would never call the handler of
 * an object below them, for example Device.LEDs.LED.{i}.CurrentCycleElement.
 *
 * @param vm          ucode VM context
 * @param out         array that receives the full object paths
 * @param pat_parts   pattern segments of the object
 * @param pat_cnt     number of pattern segments
 * @param base        response tree, rooted at the base path
 * @param base_parts  base path segments
 * @param base_cnt    number of base path segments, less than `pat_cnt`
 */
static void
response_instances_collect(uc_vm_t *vm, uc_value_t *out, char **pat_parts,
			   int pat_cnt, uc_value_t *base, char **base_parts,
			   int base_cnt)
{
	char *base_path = path_join(base_parts, 0, base_cnt);
	uc_value_t *rel = ucv_array_new(vm);

	for (int i = base_cnt; i < pat_cnt; i++)
		ucv_array_push(rel, ucv_string_new(pat_parts[i]));

	instances_collect(out, rel, base, 0, base_path, vm);
	ucv_put(rel);
	free(base_path);
}

/**
 * Returns the object of a response tree at a path below its base, creating
 * the missing objects on the way.
 *
 * @param vm        ucode VM context
 * @param base      response tree, rooted at the base path
 * @param parts     segments of the full path
 * @param cnt       number of segments in `parts`
 * @param base_cnt  number of base path segments, at most `cnt`
 * @return          the object at the path (borrowed)
 */
static uc_value_t *
base_node_get(uc_vm_t *vm, uc_value_t *base, char **parts, int cnt,
	      int base_cnt)
{
	return tree_node_make(vm, base, parts + base_cnt, cnt - base_cnt);
}

/**
 * Returns a subtree augmented with values produced by registered get handlers.
 *
 * Walks the model and, for every entry whose pattern matches under the base
 * path, hydrates each existing instance via its `get` handler and merges the
 * result back into the subtree. Patterns with no existing instances also
 * trigger runtime discovery so dynamic tables (e.g. ARP-derived hosts) are
 * populated, and the row count of such a table is written onto its parent's
 * `<Table>NumberOfEntries` after the walk when the parent schema declares it.
 *
 * Shared between `uc_dm_get_subtree_with_state` (called from ucode as
 * `dm.get_subtree_with_state`) and `uc_dm_params_get` (called per-leaf by
 * obuspa via the `params_get` USP callback). Keeping a single implementation
 * makes sure the two entry points always agree about which handlers fire,
 * which ancestor synthesised data is visible, and how schema defaults merge
 * into the response.
 *
 * @param vm         ucode VM context
 * @param dm         pointer to the ubbf data-model registration
 * @param path       TR-181 base path (no trailing dot required)
 * @param anc_cache  optional object memoising ancestor get-handler results
 *                   by ancestor instance path; pass the same object across
 *                   the subtree_dispatch calls of one params_get batch so a
 *                   shared ancestor handler runs once instead of per leaf.
 *                   Pass NULL for a standalone single-subtree dispatch.
 * @return           hydrated subtree object; empty on bad input or an
 *                   invalid path
 */
uc_value_t *
subtree_dispatch(uc_vm_t *vm, ubbf_dm_t *dm, const char *path,
		 uc_value_t *anc_cache)
{
	uc_value_t *model, *runtime;
	char *base_buf, *base_parts_arr[PATH_PARTS_MAX];
	int base_cnt = 0;

	if (!dm || !path)
		return ucv_object_new(vm);

	model = dm_model_get(dm);
	runtime = dm_runtime_get(dm);
	if (!model || !runtime)
		return ucv_object_new(vm);

	base_buf = xstrdup(path);
	base_cnt = path_split(base_buf, base_parts_arr, PATH_PARTS_MAX, 0);
	if (base_cnt < 0) {
		free(base_buf);
		return ucv_object_new(vm);
	}

	uc_value_t *subtree = navigate_by_path(vm, runtime, path);
	uc_value_t *base = subtree ? value_deep_clone(vm, subtree) : ucv_object_new(vm);
	uc_value_t *pending = ucv_object_new(vm);

	/*
	 * A subtree query rooted below an ancestor get-handler (for example
	 * `Device.IP.Interface.1.IPv6Address.` whose nearest ancestor handler is
	 * `Device.IP.Interface.{i}` / `interface_get`) must still evaluate that
	 * handler so its synthesised instances appear in `base`. The pattern
	 * iteration below only walks handlers at or deeper than `base_cnt`, so
	 * without this step the response is limited to whatever is persisted in
	 * the runtime tree, losing all rows the handler emits at request time.
	 */
	{
		handler_match_t ancestor = { 0 };
		ucv_object_foreach(model, a_pattern, a_entry) {
			if (ucv_type(a_entry) != UC_OBJECT)
				continue;
			/* The ancestor walk needs a callable handler so the
			 * synthesised subtree can be merged into base. Skip
			 * entries that match only via enable_status_derive:
			 * match_handler accepts those (so the longest-match
			 * picks them up for its own dispatch) but they have a
			 * NULL get_fn, and selecting one as ancestor yields
			 * `ancestor.handler == NULL`, which then skips the
			 * block. The textbook trip is
			 * Device.DNS.Client.Server.{i} (flag-only) shadowing
			 * Device.DNS.Client.Server (`dns_client_server_get`
			 * which emits dynamic Server.{i} rows). */
			uc_value_t *a_get = ucv_object_get(a_entry, "get", NULL);
			if (!a_get || !ucv_is_callable(a_get))
				continue;
			/* Also skip patterns at exactly base_cnt: those are
			 * leaf-level handlers, not ancestors. Otherwise the
			 * longest-match logic picks them up, the post-search
			 * `< base_cnt` guard rejects them, and a strictly-
			 * shorter ancestor that actually synthesises base's
			 * subtree (e.g. interface_get at pattern_len=4 versus
			 * ipv6_address_get at pattern_len=6 for an IPv6Address.2
			 * read) is shadowed and never invoked. */
			char *a_buf = xstrdup(a_pattern);
			char *a_parts[PATH_PARTS_MAX];
			int a_cnt = path_split(a_buf, a_parts, PATH_PARTS_MAX, 0);
			free(a_buf);
			if (a_cnt < 0 || a_cnt >= base_cnt)
				continue;
			match_handler(path, base_cnt, base_parts_arr,
				      a_pattern, a_entry, "get", &ancestor);
		}

		if (ancestor.handler && ancestor.pattern_len < base_cnt) {
			char *anc_path = path_join(base_parts_arr, 0, ancestor.pattern_len);
			uc_value_t *a_result = NULL;

			/* A batched params_get resolves every leaf of a subtree
			 * through this dispatcher, once per distinct leaf parent.
			 * Every Radio/BSS/STA path under
			 * Device.WiFi.DataElements.Network.Device.1 shares the
			 * same ancestor handler (device_get for Device.1), so
			 * without memoisation that handler rebuilds the entire
			 * device once per resolved parameter -- O(parameters x
			 * device size), i.e. quadratic. Reusing the ancestor
			 * handler result across leaves of one params_get batch
			 * keeps it O(devices), matching the single-dispatch cost
			 * of dm.get_subtree_with_state / bbf-dm.show. */
			if (anc_cache)
				a_result = ucv_get(ucv_object_get(anc_cache, anc_path, NULL));

			if (!a_result) {
				uc_value_t *a_cfg = navigate_by_path(vm, runtime, anc_path);
				uc_value_t *a_defs = schema_entry_defaults(vm, ancestor.entry);
				uc_value_t *a_merged = NULL;
				if (a_cfg && a_defs) {
					a_merged = value_deep_clone(vm, a_cfg);
					schema_defaults_merge(vm, a_merged, a_defs);
				} else if (a_cfg) {
					a_merged = ucv_get(a_cfg);
				} else if (a_defs) {
					a_merged = value_deep_clone(vm, a_defs);
				}
				ucv_put(a_defs);

				/* Match the existing-instances loop (dm.c parent_config
				 * computation) and the pat_cnt == base_cnt runtime-discovery
				 * branch: pass the previous-{i} ancestor's runtime config as
				 * parent. Handlers like pool_client_get read ctx.parent to
				 * locate their containing object (Pool.{i} for Client.{i})
				 * and synthesise null without it. Every read rooted below
				 * a dynamic instance (e.g. Pool.1.Client.1.IPv4Address.1.
				 * LeaseTimeRemaining) comes back empty otherwise. */
				uc_value_t *anc_parent = NULL;
				{
					char *pb = xstrdup(ancestor.pattern_key);
					char *pp[PATH_PARTS_MAX];
					int pc = path_split(pb, pp, PATH_PARTS_MAX, 0);
					int last_i = pattern_inst_before(pp, pc);
					int prev_i = last_i > 0 ? pattern_inst_before(pp, last_i) : -1;

					if (prev_i >= 0)
						anc_parent = tree_node_get(runtime, base_parts_arr, prev_i + 1);
					free(pb);
				}

				a_result = get_handler_call(vm, ancestor.handler,
							    ancestor.instance,
							    a_merged, anc_parent, runtime,
							    instances_from_parts(vm, base_parts_arr,
										 ancestor.pattern_len));
				ucv_put(a_merged);

				if (a_result)
					result_project(vm, dm, ancestor.pattern_key,
						       ancestor.entry, a_result);

				if (anc_cache && a_result)
					ucv_object_add(anc_cache, anc_path, ucv_get(a_result));
			}

			uc_value_t *sub = a_result;
			for (int i = ancestor.pattern_len; i < base_cnt && sub; i++) {
				if (ucv_type(sub) != UC_OBJECT) {
					sub = NULL;
					break;
				}
				sub = ucv_object_get(sub, base_parts_arr[i], NULL);
			}

			/* deep_clone, not ucv_get: a cached a_result is shared by
			 * every leaf under this ancestor, and the pattern loop
			 * below merges further data into base by descending into
			 * existing child objects. Sharing them would let one
			 * leaf's merge mutate the cached snapshot another leaf
			 * still reads. */
			if (sub && ucv_type(sub) == UC_OBJECT) {
				ucv_object_foreach(sub, sk, sv)
					ucv_object_add(base, sk, value_deep_clone(vm, sv));
			}

			ucv_put(a_result);
			free(anc_path);
		}
	}

	size_t order_cnt = 0;
	model_order_t *order = model_order_build(model, &order_cnt);

	for (size_t oi = 0; oi < order_cnt; oi++) {
		const char *pattern = order[oi].pattern;
		uc_value_t *entry = order[oi].entry;
		uc_value_t *get_fn;
		char *pat_buf, *pat_parts[PATH_PARTS_MAX];
		int pat_cnt = 0;
		bool matches_path;

		if (ucv_type(entry) != UC_OBJECT)
			continue;

		get_fn = ucv_object_get(entry, "get", NULL);
		if (!get_fn || !ucv_is_callable(get_fn))
			get_fn = NULL;

		bool has_flag = value_to_bool(
			ucv_object_get(entry, "enable_status_derive", NULL));

		/* An object without a handler still has its schema defaults:
		 * a single-instance object below a row, such as
		 * Device.BulkData.Profile.{i}.CSVEncoding, is stored only once
		 * a value is set, and reads empty before that otherwise. */
		bool defaults_only = !get_fn && !has_flag;

		if (defaults_only) {
			uc_value_t *defs = schema_entry_defaults(vm, entry);
			bool any = ucv_object_length(defs) > 0;

			ucv_put(defs);
			if (!any)
				continue;
		}

		/* pattern_matches_path check */
		pat_buf = xstrdup(pattern);
		pat_cnt = path_split(pat_buf, pat_parts, PATH_PARTS_MAX, 0);

		matches_path = pat_cnt >= base_cnt &&
			       pattern_parts_match(pat_parts, base_parts_arr, base_cnt, false, NULL);

		if (!matches_path) {
			free(pat_buf);
			continue;
		}

		/* collect existing instances */
		uc_value_t *pat_arr = ucv_array_new(vm);
		for (int i = 0; i < pat_cnt; i++)
			ucv_array_push(pat_arr, ucv_string_new(pat_parts[i]));

		uc_value_t *inst_paths = ucv_array_new(vm);
		instances_collect(inst_paths, pat_arr, runtime, 0, "", vm);

		if (!ucv_array_length(inst_paths) && pat_cnt > base_cnt &&
		    strcmp(pat_parts[pat_cnt - 1], "{i}") != 0)
			response_instances_collect(vm, inst_paths, pat_parts, pat_cnt,
						   base, base_parts_arr, base_cnt);

		bool matched_an_instance = false;

		if (ucv_array_length(inst_paths) > 0) {
			/* merge existing instances */
			for (size_t pi = 0; pi < ucv_array_length(inst_paths); pi++) {
				uc_value_t *ip_val = ucv_array_get(inst_paths, pi);
				const char *inst_path = ucv_string_get(ip_val);
				char *ip_buf = xstrdup(inst_path);
				char *ip_parts[PATH_PARTS_MAX];
				int ip_cnt = 0;

				ip_cnt = path_split(ip_buf, ip_parts, PATH_PARTS_MAX, 0);

				if (ip_cnt < 0 ||
				    !instance_base_matches(ip_parts, ip_cnt, base_parts_arr, base_cnt)) {
					free(ip_buf);
					continue;
				}
				matched_an_instance = true;

				if (defaults_only) {
					uc_value_t *defs = schema_entry_defaults(vm, entry);

					schema_defaults_merge(vm, base_node_get(vm, base, ip_parts,
										ip_cnt, base_cnt), defs);
					ucv_put(defs);
					free(ip_buf);
					continue;
				}

				uc_value_t *config_node = navigate_by_path(vm, runtime, inst_path);

				uc_value_t *defs = schema_entry_defaults(vm, entry);
				uc_value_t *merged = NULL;
				if (config_node && defs) {
					merged = value_deep_clone(vm, config_node);
					schema_defaults_merge(vm, merged, defs);
				} else if (config_node) {
					merged = ucv_get(config_node);
				} else if (defs) {
					merged = value_deep_clone(vm, defs);
				}
				ucv_put(defs);

				uc_value_t *ip_arr = ucv_array_new(vm);
				for (int i = 0; i < ip_cnt; i++)
					ucv_array_push(ip_arr, ucv_string_new(ip_parts[i]));

				/* the parent is the row of the last {i} for an object
				 * below it, else the row of the {i} before that */
				uc_value_t *parent_config = NULL;
				int last_inst_i = pattern_inst_before(pat_parts, pat_cnt);
				int parent_i = last_inst_i + 1 < pat_cnt ? last_inst_i
					     : pattern_inst_before(pat_parts, last_inst_i);

				if (last_inst_i >= 0 && parent_i >= 0)
					parent_config = tree_node_get(runtime, ip_parts, parent_i + 1);

				int64_t inst_num = 0;
				for (int i = ip_cnt - 1; i >= 0; i--) {
					char *endp;
					long v = strtol(ip_parts[i], &endp, 10);
					if (*endp == '\0' && endp != ip_parts[i]) {
						inst_num = v;
						break;
					}
				}

				uc_value_t *result = NULL;
				if (get_fn)
					result = get_handler_call(vm, get_fn, inst_num,
								  merged, parent_config, runtime,
								  instances_from_parts(vm, ip_parts, ip_cnt));
				if (has_flag)
					status_overlay(vm, &result, merged);
				ucv_put(merged);
				result_project(vm, dm, pattern, entry, result);
				if (result) {
					uc_value_t *cur = base_node_get(vm, base, ip_parts,
									ip_cnt, base_cnt);

					ucv_object_foreach(result, rk, rv)
						ucv_object_add(cur, rk, ucv_get(rv));

					ucv_put(result);
				}

				ucv_put(ip_arr);
				free(ip_buf);
			}
		}

		/* Runtime discovery + explicit-instance fallback. Fires when
		 * no persisted instance matched base, regardless of whether
		 * inst_paths was empty. The existing-instances loop above may
		 * have run and skipped every entry because none matched base
		 * (e.g. base = Device.DNS.Client.Server.3 against persisted
		 * Server.1 / Server.2). In that case the dynamic branch must
		 * still be allowed to synthesise base. */
		int last_i = pattern_inst_before(pat_parts, pat_cnt);

		/* A table flagged runtime_instances holds rows the handler
		 * synthesises next to the persisted ones (UPnP port mappings
		 * beside configured ones), so its enumeration also runs when
		 * persisted rows matched. A request for one persisted row is
		 * complete after the loop above. */
		bool base_is_instance = (pat_cnt == base_cnt && last_i >= 0 &&
					 key_is_instance(base_parts_arr[last_i]));
		bool runtime_instances = ucv_is_truish(ucv_object_get(entry, "runtime_instances", NULL));
		bool enumerate = !matched_an_instance || (runtime_instances && !base_is_instance);

		if (enumerate && get_fn && strstr(pattern, "{i}")) {
			/* runtime discovery for patterns with no existing instances */

			/* Pattern matches base exactly and the trailing {i} slot
			 * in base is a concrete instance number. Treat base as
			 * the fully qualified instance path and call the leaf
			 * handler with the same parent_config logic the existing-
			 * instances loop uses (parent = previous {i} ancestor's
			 * runtime config, instance = base's last {i}). Covers
			 * dynamic instances whose data is synthesised at request
			 * time and never lands in the runtime tree, e.g.
			 * Device.DHCPv4.Server.Pool.{i}.Client.{i} (`pool_client_get`)
			 * and IPv6Address.{i} reads via `params_get`. Without this
			 * the runtime-discovery branch below would call the
			 * handler in enumerate-mode with the wrong parent, the
			 * handler would return null, and the leaf would come back
			 * empty. */
			if (pat_cnt == base_cnt && last_i >= 0 &&
			    key_is_instance(base_parts_arr[last_i])) {
				uc_value_t *parent_config = NULL;
				int prev_i = pattern_inst_before(pat_parts, last_i);

				if (prev_i >= 0)
					parent_config = tree_node_get(runtime, base_parts_arr, prev_i + 1);

				char *endp;
				int64_t inst_num = strtoll(base_parts_arr[last_i], &endp, 10);
				if (*endp != '\0' || endp == base_parts_arr[last_i])
					inst_num = 0;

				char *base_path_str = path_join(base_parts_arr, 0, base_cnt);
				uc_value_t *config_node = navigate_by_path(vm, runtime, base_path_str);

				free(base_path_str);
				uc_value_t *defs = config_node ? schema_entry_defaults(vm, entry) : NULL;
				/* When the requested instance is dynamic (no runtime
				 * config) deliberately pass NULL config rather than
				 * falling back to schema defaults. Handlers fall into
				 * two camps: pool_client_get-shaped ones synthesise
				 * dynamic rows from ctx.parent + ctx.instance and
				 * ignore ctx.config; ipv6_address_get-shaped ones
				 * branch on ctx.config to decide what kind of address
				 * they emit, and feeding them the schema default tree
				 * (Origin: "Static", IPAddress: "", ...) makes them
				 * return a Static placeholder that overwrites the
				 * ancestor block's correctly synthesised data. The
				 * NULL signal tells those handlers "no config exists,
				 * stay quiet". */
				uc_value_t *merged = NULL;
				if (config_node && defs) {
					merged = value_deep_clone(vm, config_node);
					schema_defaults_merge(vm, merged, defs);
				} else if (config_node) {
					merged = ucv_get(config_node);
				}
				ucv_put(defs);

				uc_value_t *result = get_handler_call(vm, get_fn, inst_num,
								      merged, parent_config, runtime,
								      instances_from_parts(vm, base_parts_arr,
											   base_cnt));
				if (has_flag)
					status_overlay(vm, &result, merged);
				ucv_put(merged);
				result_project(vm, dm, pattern, entry, result);
				if (result) {
					ucv_object_foreach(result, rk, rv)
						ucv_object_add(base, rk, ucv_get(rv));
					ucv_put(result);
				}
			} else if (last_i > 0) {
				/* enumerate_with_parent */
				uc_value_t *parent_pat = ucv_array_new(vm);
				for (int i = 0; i < last_i; i++)
					ucv_array_push(parent_pat, ucv_string_new(pat_parts[i]));

				uc_value_t *parent_insts = ucv_array_new(vm);
				instances_collect(parent_insts, parent_pat, runtime, 0, "", vm);

				/* The parent of a table below a row is that row, as in
				 * the two branches above: the previous {i} ancestor,
				 * not the table container. */
				int prev_i = pattern_inst_before(pat_parts, last_i);

				for (size_t pi = 0; pi < ucv_array_length(parent_insts); pi++) {
					uc_value_t *pp_val = ucv_array_get(parent_insts, pi);
					const char *pp_str = ucv_string_get(pp_val);

					char *pp_buf = xstrdup(pp_str);
					char *pp_parts[PATH_PARTS_MAX];
					int pp_cnt = path_split(pp_buf, pp_parts, PATH_PARTS_MAX, 0);

					if (pp_cnt < 0) {
						free(pp_buf);
						continue;
					}

					uc_value_t *parent_data = prev_i >= 0
						? tree_node_get(runtime, pp_parts, prev_i < pp_cnt ? prev_i + 1 : pp_cnt)
						: navigate_by_path(vm, runtime, pp_str);

					uc_value_t *result = get_handler_call(vm, get_fn, 0,
									      NULL, parent_data, runtime,
									      instances_from_parts(vm, pp_parts,
												   pp_cnt));
					if (!result) {
						free(pp_buf);
						continue;
					}

					uc_value_t *rel = ucv_array_new(vm);
					for (int i = base_cnt; i < pp_cnt; i++)
						ucv_array_push(rel, ucv_string_new(pp_parts[i]));

					rows_project(vm, dm, pattern, entry, result);
					runtime_instances_merge(vm, base, rel, result);
					entries_count_record(vm, pending, model, pat_parts, last_i,
							     pp_parts, pp_cnt, base_cnt, result);

					ucv_put(rel);
					ucv_put(result);
					free(pp_buf);
				}

				ucv_put(parent_insts);
				ucv_put(parent_pat);
			}
		}

		ucv_put(inst_paths);
		ucv_put(pat_arr);
		free(pat_buf);
	}

	free(order);
	entries_count_apply(vm, base, pending);
	ucv_put(pending);
	free(base_buf);
	return base;
}

/**
 * Ucode-callable wrapper around `subtree_dispatch`.
 *
 * Exposes the shared dispatcher as `dm.get_subtree_with_state(path)` for
 * `bbf-dm.show`, `bbf-dm.get` (trailing-dot paths), `webui-show` and
 * `dm.refresh_instances`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: base path string)
 * @return       hydrated subtree object; empty on bad input or an invalid
 *               path
 */
uc_value_t *
uc_dm_get_subtree_with_state(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);

	if (ucv_type(path_val) != UC_STRING)
		return ucv_object_new(vm);

	return subtree_dispatch(vm, dm, ucv_string_get(path_val), NULL);
}

/* ---- dm.wildcard_expand ------------------------------------------------ */

static bool
digits_only(const char *s)
{
	return *s && !s[strspn(s, "0123456789")];
}

static void
wildcard_expand_into(uc_vm_t *vm, ubbf_dm_t *dm, uc_value_t *out, const char *path)
{
	const char *star = strchr(path, '*');
	uc_value_t *subtree;
	char *prefix, *next;

	if (!star) {
		ucv_array_push(out, ucv_string_new(path));
		return;
	}

	prefix = xalloc(star - path + 1);
	memcpy(prefix, path, star - path);
	subtree = subtree_dispatch(vm, dm, prefix, NULL);

	ucv_object_foreach(subtree, key, val) {
		(void)val;
		if (!digits_only(key))
			continue;

		xasprintf(&next, "%s%s%s", prefix, key, star + 1);
		wildcard_expand_into(vm, dm, out, next);
		free(next);
	}

	ucv_put(subtree);
	free(prefix);
}

/**
 * Expands each `*` instance wildcard of a path into one path per row of
 * the object before it; a later wildcard expands within each row.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path)
 * @return       paths without wildcards; empty when the object has no rows
 */
uc_value_t *
uc_dm_wildcard_expand(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path = uc_fn_arg(0);
	uc_value_t *out = ucv_array_new(vm);

	if (dm && ucv_type(path) == UC_STRING)
		wildcard_expand_into(vm, dm, out, ucv_string_get(path));

	return out;
}

/* ---- dm.refresh_instances --------------------------------------------- */

/**
 * Returns every fully qualified instance path under a TR-181 base path.
 *
 * Internally hydrates the subtree via `uc_dm_get_subtree_with_state` so
 * the returned list reflects runtime-discovered instances as well as
 * persisted ones.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: base path string)
 * @return       array of instance path strings, empty for an invalid path
 */
uc_value_t *
uc_dm_refresh_instances(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *subtree, *arr;
	char *buf, *parts[PATH_PARTS_MAX], *base;
	int cnt;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	buf = xstrdup(ucv_string_get(path_val));
	cnt = path_split(buf, parts, PATH_PARTS_MAX, 0);
	arr = ucv_array_new(vm);

	if (cnt >= 0) {
		base = path_join(parts, 0, cnt);
		subtree = uc_dm_get_subtree_with_state(vm, nargs);
		nested_instances_find(arr, base, subtree, vm);
		ucv_put(subtree);
		free(base);
	}

	free(buf);

	return arr;
}

/* ---- dm.get_subtree --------------------------------------------------- */

/**
 * Returns the runtime subtree at a TR-181 path without invoking get handlers.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: base path string)
 * @return       runtime subtree, or empty object on missing path
 */
uc_value_t *
uc_dm_get_subtree(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *runtime, *result;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_object_new(vm);

	runtime = dm_runtime_get(dm);
	if (!runtime)
		return ucv_object_new(vm);

	result = navigate_by_path(vm, runtime, ucv_string_get(path_val));

	return result ? ucv_get(result) : ucv_object_new(vm);
}
