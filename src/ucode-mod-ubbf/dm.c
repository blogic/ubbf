/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/* params_set answers -1 for a path the model does not describe and this for
 * one whose instance was never created, which the callers map onto their
 * protocol's "no such object" rather than "bad path". Set handlers only ever
 * answer -1, so the two cannot be confused. */
#define DM_SET_NO_INSTANCE	(-2)

/* ---- datamodel resource ------------------------------------------------ */

enum {
	DM_SLOT_MODEL,
	DM_SLOT_OPERATIONS,
	DM_SLOT_CONFIG,
	DM_SLOT_WORKSPACE,
	DM_SLOT_HOOKS,
	DM_SLOT_RUNTIME,
	DM_SLOT_HASH,
	DM_SLOT_MAX
};

typedef struct {
	uc_vm_t *vm;
	uc_value_t *res_obj;
} ubbf_dm_t;

/**
 * Resource destructor for a `ubbf.dm` instance.
 *
 * Drops the self-reference taken in `uc_ubbf_create()`. Resource slots
 * (model, operations, config, workspace, hooks, runtime, hash) are
 * released by the resource framework.
 *
 * @param ptr  pointer to the embedded `ubbf_dm_t` payload
 */
static void
dm_free(void *ptr)
{
	ubbf_dm_t *dm = ptr;

	ucv_put(dm->res_obj);
}

/**
 * Creates and initialises a new `ubbf.dm` resource.
 *
 * The instance keeps an internal back reference to its own resource
 * object (`res_obj`) so resource-slot accessors work; the reference is
 * released in `dm_free()`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       new resource object, or NULL on allocation failure
 */
uc_value_t *
uc_ubbf_create(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm;
	uc_value_t *obj;

	obj = ucv_resource_create_ex(vm, "ubbf.dm", (void **)&dm,
				     DM_SLOT_MAX, sizeof(ubbf_dm_t));
	if (!obj)
		return NULL;

	dm->vm = vm;
	dm->res_obj = ucv_get(obj);

	return obj;
}

/**
 * Stores the data-model registration object on the dm instance.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: model object keyed by pattern)
 * @return       boolean true on success, false on bad arguments
 */
static uc_value_t *
uc_dm_register(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *model = uc_fn_arg(0);

	if (!dm || ucv_type(model) != UC_OBJECT)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_MODEL, ucv_get(model));

	return ucv_boolean_new(true);
}

/**
 * Stores the operations registration object on the dm instance.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: operations object keyed by path)
 * @return       boolean true on success, false on bad arguments
 */
static uc_value_t *
uc_dm_register_operations(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *ops = uc_fn_arg(0);

	if (!dm || ucv_type(ops) != UC_OBJECT)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_OPERATIONS, ucv_get(ops));

	return ucv_boolean_new(true);
}

/**
 * Stores the hook callback object on the dm instance.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: hooks object)
 * @return       boolean true on success, false on bad arguments
 */
static uc_value_t *
uc_dm_set_hooks(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *hooks = uc_fn_arg(0);

	if (!dm || ucv_type(hooks) != UC_OBJECT)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_HOOKS, ucv_get(hooks));

	return ucv_boolean_new(true);
}

/**
 * Parses a JSON byte buffer into a ucode value.
 *
 * Takes ownership of `buf` and frees it on every exit path. The
 * returned value (or NULL on parse failure) is caller-owned.
 *
 * @param vm   ucode VM context
 * @param buf  malloc'd JSON buffer (consumed by this function)
 * @param len  length of `buf` in bytes
 * @return     parsed ucode value, or NULL on tokeniser or parse failure
 */
static uc_value_t *
json_buf_parse(uc_vm_t *vm, char *buf, long len)
{
	struct json_tokener *tok = json_tokener_new();
	struct json_object *jobj;
	uc_value_t *parsed;

	if (!tok) {
		free(buf);
		return NULL;
	}

	jobj = json_tokener_parse_ex(tok, buf, len);
	free(buf);

	if (!jobj) {
		json_tokener_free(tok);
		return NULL;
	}

	parsed = ucv_from_json(vm, jobj);
	json_object_put(jobj);
	json_tokener_free(tok);

	return parsed;
}

/**
 * Loads a JSON config file into the dm instance.
 *
 * Replaces both the live config and the runtime tree (cloned from the
 * fresh config) on success.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: file path)
 * @return       boolean true when loaded, false on any I/O or parse error
 */
static uc_value_t *
uc_dm_load(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	const char *path;
	FILE *fp;
	char *buf;
	long len;
	uc_value_t *parsed;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	path = ucv_string_get(path_val);
	fp = fopen(path, "r");
	if (!fp)
		return ucv_boolean_new(false);

	fseek(fp, 0, SEEK_END);
	len = ftell(fp);
	fseek(fp, 0, SEEK_SET);

	if (len <= 0) {
		fclose(fp);
		return ucv_boolean_new(false);
	}

	buf = malloc(len + 1);
	if (!buf) {
		fclose(fp);
		return ucv_boolean_new(false);
	}

	if ((long)fread(buf, 1, len, fp) != len) {
		free(buf);
		fclose(fp);
		return ucv_boolean_new(false);
	}

	buf[len] = '\0';
	fclose(fp);

	parsed = json_buf_parse(vm, buf, len);

	if (!parsed)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_CONFIG, parsed);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_RUNTIME,
			       deep_clone_value(vm, parsed));

	return ucv_boolean_new(true);
}

/**
 * Returns the current configuration tree.
 *
 * When a transaction workspace exists it is returned in preference to
 * the persisted config so handlers see uncommitted edits.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       config or workspace object, or null on error
 */
static uc_value_t *
uc_dm_config(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");

	if (!dm)
		return NULL;

	uc_value_t *ws = ucv_resource_value_get(dm->res_obj, DM_SLOT_WORKSPACE);
	if (ws)
		return ucv_get(ws);

	return ucv_get(ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG));
}

/**
 * Begins a transaction by snapshotting the live config into a workspace.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       0 on success, -1 on error
 */
static uc_value_t *
uc_dm_trans_start(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *config, *clone;

	if (!dm)
		return ucv_int64_new(-1);

	config = ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
	if (!config)
		return ucv_int64_new(-1);

	clone = deep_clone_value(vm, config);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_WORKSPACE, clone);

	return ucv_int64_new(0);
}

/**
 * Discards the active transaction workspace.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       0 on success, -1 on error
 */
static uc_value_t *
uc_dm_trans_abort(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");

	if (!dm)
		return ucv_int64_new(-1);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_WORKSPACE, NULL);

	return ucv_int64_new(0);
}

/**
 * Promotes the transaction workspace to the live config.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       1 when committed with changes, 0 when no workspace, -1 on error
 */
static uc_value_t *
uc_dm_trans_commit(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *workspace;

	if (!dm)
		return ucv_int64_new(-1);

	workspace = ucv_resource_value_get(dm->res_obj, DM_SLOT_WORKSPACE);
	if (!workspace)
		return ucv_int64_new(0);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_CONFIG, ucv_get(workspace));
	ucv_resource_value_set(dm->res_obj, DM_SLOT_WORKSPACE, NULL);

	return ucv_int64_new(1);
}

/**
 * Resolves a TR-181 path within the transaction workspace or live config.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path string)
 * @return       value at the path, or null when missing
 */
static uc_value_t *
uc_dm_lookup(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	const char *path;
	uc_value_t *config, *current;
	char *buf, *parts[64];
	int cnt;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	config = ucv_resource_value_get(dm->res_obj, DM_SLOT_WORKSPACE);
	if (!config)
		config = ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
	if (!config)
		return NULL;

	buf = strdup(path);
	current = config;
	cnt = path_split(buf, parts, 64);

	for (int i = 0; i < cnt; i++) {
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

	return ucv_get(current);
}

/* ---- handler dispatch -------------------------------------------------- */

/**
 * Finds the longest-pattern model entry whose `get` handler matches `path`.
 *
 * Iterates the entire registered model. For each pattern with a callable
 * `get` handler, attempts pattern-vs-path matching honouring `{i}` captures.
 * The match with the most pattern segments wins; on tie the earlier
 * iteration order prevails.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path string)
 * @return       result object `{ handler, instance?, remaining[], pattern }`,
 *               or null when no get handler matches
 */
static uc_value_t *
uc_dm_find_get_handler(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *model;
	const char *path;
	uc_value_t *best_result = NULL;
	int best_len = 0;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	model = ucv_resource_value_get(dm->res_obj, DM_SLOT_MODEL);
	if (!model)
		return NULL;

	ucv_object_foreach(model, pattern, entry) {
		uc_value_t *get_fn;
		char *pat_buf, *path_buf;
		char *pat_parts[64], *ppath_parts[64];
		int pat_cnt = 0, path_cnt = 0;
		uc_value_t *instances;
		int i;
		bool matched = true;

		if (ucv_type(entry) != UC_OBJECT)
			continue;

		get_fn = ucv_object_get(entry, "get", NULL);
		if (!get_fn || !ucv_is_callable(get_fn))
			continue;

		pat_buf = strdup(pattern);
		path_buf = strdup(path);

		pat_cnt = path_split(pat_buf, pat_parts, 64);
		path_cnt = path_split(path_buf, ppath_parts, 64);

		if (path_cnt < pat_cnt) {
			free(pat_buf);
			free(path_buf);
			continue;
		}

		instances = ucv_array_new(vm);

		for (i = 0; i < pat_cnt; i++) {
			if (strcmp(pat_parts[i], "{i}") == 0) {
				char *endp;
				long val = strtol(ppath_parts[i], &endp, 10);

				if (*endp != '\0' || endp == ppath_parts[i]) {
					matched = false;
					break;
				}
				ucv_array_push(instances, ucv_int64_new(val));
			} else if (strcmp(pat_parts[i], ppath_parts[i]) != 0) {
				matched = false;
				break;
			}
		}

		if (!matched) {
			ucv_put(instances);
			free(pat_buf);
			free(path_buf);
			continue;
		}

		if (pat_cnt > best_len) {
			uc_value_t *remaining = ucv_array_new(vm);

			for (i = pat_cnt; i < path_cnt; i++)
				ucv_array_push(remaining, ucv_string_new(ppath_parts[i]));

			ucv_put(best_result);
			best_result = ucv_object_new(vm);

			ucv_object_add(best_result, "handler", ucv_get(get_fn));

			size_t inst_len = ucv_array_length(instances);
			if (inst_len > 0)
				ucv_object_add(best_result, "instance",
					       ucv_get(ucv_array_get(instances, inst_len - 1)));

			ucv_object_add(best_result, "remaining", remaining);
			ucv_object_add(best_result, "pattern", ucv_string_new(pattern));

			best_len = pat_cnt;
		}

		ucv_put(instances);
		free(pat_buf);
		free(path_buf);
	}

	return best_result;
}

/**
 * Finds the model entry whose `set` handler matches the parameter path.
 *
 * Pattern depth must equal the path depth minus one (the trailing
 * segment is the parameter name). Returns the first matching entry.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: parameter path string)
 * @return       result object `{ handler, instance?, pattern }`, or null when none matches
 */
static uc_value_t *
uc_dm_find_set_handler(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *model;
	const char *path;
	char *path_buf;
	char *path_parts[64];
	int path_cnt = 0;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	model = ucv_resource_value_get(dm->res_obj, DM_SLOT_MODEL);
	if (!model)
		return NULL;

	path_buf = strdup(path);
	path_cnt = path_split(path_buf, path_parts, 64);

	if (path_cnt < 2) {
		free(path_buf);
		return NULL;
	}

	int obj_cnt = path_cnt - 1;

	ucv_object_foreach(model, pattern, entry) {
		uc_value_t *set_fn;
		char *pat_buf;
		char *pat_parts[64];
		int pat_cnt = 0;
		bool matched = true;
		uc_value_t *instances;
		int i;

		if (ucv_type(entry) != UC_OBJECT)
			continue;

		set_fn = ucv_object_get(entry, "set", NULL);
		if (!set_fn || !ucv_is_callable(set_fn))
			continue;

		pat_buf = strdup(pattern);
		pat_cnt = path_split(pat_buf, pat_parts, 64);

		if (pat_cnt != obj_cnt) {
			free(pat_buf);
			continue;
		}

		instances = ucv_array_new(vm);

		for (i = 0; i < pat_cnt; i++) {
			if (strcmp(pat_parts[i], "{i}") == 0) {
				char *endp;
				long val = strtol(path_parts[i], &endp, 10);

				if (*endp != '\0' || endp == path_parts[i]) {
					matched = false;
					break;
				}
				ucv_array_push(instances, ucv_int64_new(val));
			} else if (strcmp(pat_parts[i], path_parts[i]) != 0) {
				matched = false;
				break;
			}
		}

		if (matched) {
			uc_value_t *result = ucv_object_new(vm);
			size_t inst_len = ucv_array_length(instances);

			ucv_object_add(result, "handler", ucv_get(set_fn));

			if (inst_len > 0)
				ucv_object_add(result, "instance",
					       ucv_get(ucv_array_get(instances, inst_len - 1)));

			ucv_object_add(result, "pattern", ucv_string_new(pattern));

			ucv_put(instances);
			free(pat_buf);
			free(path_buf);
			return result;
		}

		ucv_put(instances);
		free(pat_buf);
	}

	free(path_buf);
	return NULL;
}

/* ---- internal helpers for dm dispatch ---------------------------------- */

/**
 * Picks the next free TR-181 instance number for a container object.
 *
 * Returns the lowest positive integer not present as an instance key,
 * scanning at most 256 existing keys. Internal counterpart of the
 * exported `uc_ubbf_find_next_instance`.
 *
 * @param obj  container object to inspect
 * @return     next available instance number, starting at 1
 */
static int
find_next_inst(uc_value_t *obj)
{
	int instances[256], count = 0, expected, i, j;

	if (ucv_type(obj) != UC_OBJECT)
		return 1;

	ucv_object_foreach(obj, key, val) {
		char *endp;
		long v;

		(void)val;
		v = strtol(key, &endp, 10);
		if (*endp == '\0' && endp != key && v >= 1 && count < 256)
			instances[count++] = (int)v;
	}

	if (count == 0)
		return 1;

	for (i = 1; i < count; i++) {
		int tmp = instances[i];
		for (j = i - 1; j >= 0 && instances[j] > tmp; j--)
			instances[j + 1] = instances[j];
		instances[j + 1] = tmp;
	}

	expected = 1;
	for (i = 0; i < count; i++) {
		if (instances[i] != expected)
			return expected;
		expected++;
	}

	return expected;
}

/**
 * Returns the writable target tree (workspace if active, else live config).
 *
 * @param dm  dm instance
 * @return    borrowed reference to the active write target
 */
static inline uc_value_t *
dm_get_target(ubbf_dm_t *dm)
{
	uc_value_t *ws = ucv_resource_value_get(dm->res_obj, DM_SLOT_WORKSPACE);

	return ws ? ws : ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
}

/**
 * Returns the read-only runtime tree (config plus runtime-resolved values).
 *
 * @param dm  dm instance
 * @return    borrowed reference to the runtime tree
 */
static inline uc_value_t *
dm_get_runtime(ubbf_dm_t *dm)
{
	return ucv_resource_value_get(dm->res_obj, DM_SLOT_RUNTIME);
}

/**
 * Returns the registered data-model object.
 *
 * @param dm  dm instance
 * @return    borrowed reference to the model object
 */
static inline uc_value_t *
dm_get_model(ubbf_dm_t *dm)
{
	return ucv_resource_value_get(dm->res_obj, DM_SLOT_MODEL);
}

/**
 * Invokes a ucode callable with a variable number of arguments.
 *
 * Pushes the function and `nargs` arguments onto the VM stack and calls
 * with `uc_vm_call`; on exception returns NULL. The returned value is
 * the popped stack result (caller-owned).
 *
 * @param vm     ucode VM context
 * @param fn     callable value to invoke
 * @param nargs  number of variadic arguments to pass
 * @return       popped return value, or NULL on exception or non-callable
 */
static uc_value_t *
invoke_callback(uc_vm_t *vm, uc_value_t *fn, int nargs, ...)
{
	va_list ap;

	if (!fn || !ucv_is_callable(fn))
		return NULL;

	uc_vm_stack_push(vm, ucv_get(fn));

	va_start(ap, nargs);
	for (int i = 0; i < nargs; i++)
		uc_vm_stack_push(vm, ucv_get(va_arg(ap, uc_value_t *)));
	va_end(ap);

	if (uc_vm_call(vm, false, nargs) != EXCEPTION_NONE)
		return NULL;

	return uc_vm_stack_pop(vm);
}

/**
 * Coerces a TR-181 Enable value to a C bool.
 *
 * Mirrors utils.c:uc_ubbf_to_bool: booleans pass through, strings yield
 * true only for `"true"` or `"1"`, everything else is false.
 *
 * @param val  value to test (may be NULL)
 * @return     boolean conversion result
 */
static bool
enable_truthy(uc_value_t *val)
{
	if (ucv_type(val) == UC_BOOLEAN)
		return ucv_boolean_get(val);

	if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		return strcmp(s, "true") == 0 || strcmp(s, "1") == 0;
	}

	return false;
}

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
		       ucv_string_new(enable_truthy(en) ? "Enabled" : "Disabled"));
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
	char *pat_buf, *pat_parts[64];
	int pat_cnt = 0;
	int64_t last_inst = 0;
	bool has_inst = false;

	uc_value_t *fn = ucv_object_get(entry, handler_key, NULL);
	bool callable = fn && ucv_is_callable(fn);
	bool flag_only = false;

	if (!callable && strcmp(handler_key, "get") == 0)
		flag_only = enable_truthy(
			ucv_object_get(entry, "enable_status_derive", NULL));

	if (!callable && !flag_only)
		return false;

	pat_buf = strdup(pattern);
	pat_cnt = path_split(pat_buf, pat_parts, 64);

	if (path_cnt < pat_cnt) {
		free(pat_buf);
		return false;
	}

	for (int i = 0; i < pat_cnt; i++) {
		if (strcmp(pat_parts[i], "{i}") == 0) {
			char *endp;
			long val = strtol(path_parts[i], &endp, 10);

			if (*endp != '\0' || endp == path_parts[i]) {
				free(pat_buf);
				return false;
			}
			last_inst = val;
			has_inst = true;
		} else if (strcmp(pat_parts[i], path_parts[i]) != 0) {
			free(pat_buf);
			return false;
		}
	}

	free(pat_buf);

	if (pat_cnt > best->pattern_len) {
		best->handler = callable ? fn : NULL;
		best->instance = has_inst ? last_inst : 0;
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
merge_schema_defaults(uc_vm_t *vm, uc_value_t *config_node, uc_value_t *defaults)
{
	if (!defaults || ucv_type(defaults) != UC_OBJECT || !config_node)
		return;

	ucv_object_foreach(defaults, key, val) {
		if (!ucv_object_get(config_node, key, NULL))
			ucv_object_add(config_node, key, ucv_get(val));
	}
}

/* ---- dm.params_get ---------------------------------------------------- */

/* Forward declaration: the shared subtree dispatcher lives further down in
 * this file, alongside its only other caller `uc_dm_get_subtree_with_state`.
 * params_get below routes every requested path through it so the two entry
 * points walk the same handler-merge logic instead of two separate dispatch
 * loops that have to be kept in sync. */
static uc_value_t *
dispatch_subtree(uc_vm_t *vm, ubbf_dm_t *dm, const char *path,
		 uc_value_t *anc_cache);

/**
 * Resolves parameter values for a path map.
 *
 * Mutates the input `paths` object in place: each key is replaced with the
 * resolved value. For every requested path the parent object is hydrated via
 * `dispatch_subtree` (the same dispatcher backing `dm.get_subtree_with_state`
 * / `bbf-dm.show`), and the leaf segment is read out of the result. A
 * per-call subtree cache keyed by parent path keeps obuspa's batched
 * params_get O(handlers per parent) instead of O(N · handlers).
 *
 * Falling back to the runtime tree directly and then to schema defaults
 * preserves behaviour for static parameters whose object exists in
 * persisted config but whose value was never explicitly set.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: paths object)
 * @return       0 on success, -1 on error
 */
static uc_value_t *
uc_dm_params_get(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *paths = uc_fn_arg(0);
	uc_value_t *model, *runtime;
	uc_value_t *subtree_cache, *anc_cache;

	if (!dm || ucv_type(paths) != UC_OBJECT)
		return ucv_int64_new(-1);

	model = dm_get_model(dm);
	runtime = dm_get_runtime(dm);
	if (!model || !runtime)
		return ucv_int64_new(-1);

	subtree_cache = ucv_object_new(vm);
	anc_cache = ucv_object_new(vm);

	ucv_object_foreach(paths, path, old_val) {
		char *path_buf, *path_parts[64];
		char alias_slots[32][16];
		int path_cnt = 0;
		uc_value_t *value = NULL;

		(void)old_val;

		path_buf = strdup(path);
		path_cnt = path_split(path_buf, path_parts, 64);

		if (path_cnt == 0) {
			free(path_buf);
			continue;
		}

		path_resolve_aliases(runtime, path_parts, path_cnt,
				     &alias_slots[0][0], sizeof(alias_slots[0]),
				     (int)(sizeof(alias_slots) / sizeof(alias_slots[0])));

		/* Hydrate the parent object via the shared subtree dispatcher
		 * (same logic that backs dm.get_subtree_with_state and
		 * bbf-dm.show), then read the leaf out of it. The cache keeps
		 * an obuspa params_get batch O(handlers per parent) instead of
		 * O(N · handlers) when several leaves share a parent. */
		if (path_cnt >= 2) {
			char base_path[512];
			size_t base_off = 0;

			for (int i = 0; i < path_cnt - 1 && base_off < sizeof(base_path) - 1; i++)
				base_off += snprintf(base_path + base_off,
						     sizeof(base_path) - base_off,
						     "%s%s", i ? "." : "", path_parts[i]);

			uc_value_t *subtree = ucv_object_get(subtree_cache, base_path, NULL);
			if (!subtree) {
				subtree = dispatch_subtree(vm, dm, base_path, anc_cache);
				if (subtree)
					ucv_object_add(subtree_cache, base_path, subtree);
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
		if (!value && path_cnt >= 2) {
			char obj_path[512];
			size_t off = 0;

			for (int i = 0; i < path_cnt - 1 && off < sizeof(obj_path) - 1; i++)
				off += snprintf(obj_path + off, sizeof(obj_path) - off,
						"%s%s", i ? "." : "", path_parts[i]);

			if (navigate_by_path(vm, runtime, obj_path)) {
				ucv_object_foreach(model, pattern, entry) {
					uc_value_t *schema, *defs, *dv;
					char *pb;
					char *pps[64];
					int pc = 0;
					bool m = true;

					if (ucv_type(entry) != UC_OBJECT)
						continue;
					schema = ucv_object_get(entry, "schema", NULL);
					if (!schema)
						continue;
					defs = ucv_object_get(schema, "defaults", NULL);
					if (!defs || !ucv_object_get(defs, path_parts[path_cnt - 1], NULL))
						continue;

					pb = strdup(pattern);
					pc = path_split(pb, pps, 64);

					if (pc != path_cnt - 1) {
						free(pb);
						continue;
					}

					for (int i = 0; i < pc; i++) {
						if (strcmp(pps[i], "{i}") == 0)
							continue;
						if (strcmp(pps[i], path_parts[i]) != 0) {
							m = false;
							break;
						}
					}

					free(pb);
					if (!m)
						continue;

					dv = ucv_object_get(defs, path_parts[path_cnt - 1], NULL);
					if (dv)
						value = dv;
					break;
				}
			}
		}

		free(path_buf);

		if (value)
			ucv_object_add(paths, path, ucv_get(value));
	}

	ucv_put(subtree_cache);
	ucv_put(anc_cache);
	return ucv_int64_new(0);
}

/* ---- dm.params_set ---------------------------------------------------- */

/**
 * Validates that each path segment is consistent with some registered
 * model pattern at that position. A segment is acceptable when some
 * pattern has the same literal token at that position, or when some
 * pattern has `{i}` at that position and the segment is a valid
 * instance key (per `key_is_instance`).
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
			char *pat_buf = strdup(pattern);
			char *pp[64];
			int pc = path_split(pat_buf, pp, 64);

			if (i >= pc) {
				free(pat_buf);
				continue;
			}

			if (strcmp(pp[i], "{i}") == 0) {
				if (key_is_instance(parts[i])) {
					ok = true;
				} else if (ucv_type(node) == UC_OBJECT &&
					   ucv_object_get(node, parts[i], NULL)) {
					/* non-numeric instance identifier
					 * that already exists as a direct
					 * child in the live tree, accepted
					 * as a named instance. USP allows
					 * non-numeric instance identifiers
					 * and presets shipped at boot may
					 * use human-readable keys (Medium,
					 * IPV6_Medium, ...). Requiring tree
					 * membership still rejects stray
					 * `${var}` junk that was never
					 * substituted. */
					ok = true;
				}
			} else if (strcmp(pp[i], parts[i]) == 0) {
				ok = true;
			}

			free(pat_buf);
			if (ok)
				break;
		}

		if (!ok)
			return false;

		if (ucv_type(node) == UC_OBJECT)
			node = ucv_object_get(node, parts[i], NULL);
		else
			node = NULL;
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
 * get handler, and its rows are not ours to judge. object_add deliberately
 * does not consult this, because creating the row is its purpose.
 *
 * @param target root of the stored configuration
 * @param parts  path segments
 * @param cnt    number of segments to examine
 * @return       true when a segment names an absent instance
 */
static bool
path_instance_missing(uc_value_t *target, char **parts, int cnt)
{
	uc_value_t *node = target;

	for (int i = 0; i < cnt; i++) {
		uc_value_t *child = NULL;

		if (ucv_type(node) == UC_OBJECT)
			child = ucv_object_get(node, parts[i], NULL);

		if (!child && key_is_instance(parts[i]) &&
		    ucv_type(node) == UC_OBJECT)
			return true;

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
	uc_value_t *cur = target;

	for (int i = 0; i < cnt - 1; i++) {
		uc_value_t *child = ucv_object_get(cur, parts[i], NULL);

		if (!child || ucv_type(child) != UC_OBJECT) {
			child = ucv_object_new(vm);
			ucv_object_add(cur, parts[i], child);
		}
		cur = child;
	}

	return cur;
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
 * non-negative integer, is treated as acceptance.
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
		char *pat_buf, *pp[64];
		int pc = 0;
		bool matched = true;
		int64_t last_inst = 0;
		bool has_inst = false;

		uc_value_t *set_fn = ucv_object_get(entry, "set", NULL);
		if (!set_fn || !ucv_is_callable(set_fn))
			continue;

		pat_buf = strdup(pattern);
		pc = path_split(pat_buf, pp, 64);

		if (pc != obj_cnt) {
			free(pat_buf);
			continue;
		}

		for (int i = 0; i < pc; i++) {
			if (strcmp(pp[i], "{i}") == 0) {
				char *endp;
				long v = strtol(path_parts[i], &endp, 10);
				if (*endp || endp == path_parts[i]) {
					matched = false;
					break;
				}
				last_inst = v;
				has_inst = true;
			} else if (strcmp(pp[i], path_parts[i]) != 0) {
				matched = false;
				break;
			}
		}

		free(pat_buf);
		if (!matched)
			continue;

		uc_value_t *inst_parts_arr = ucv_array_new(vm);
		for (int i = 0; i < pc; i++)
			ucv_array_push(inst_parts_arr, ucv_string_new(path_parts[i]));

		uc_value_t *config_node = NULL;
		uc_value_t *cn = target;
		for (int i = 0; i < pc; i++) {
			cn = ucv_object_get(cn, path_parts[i], NULL);
			if (!cn)
				break;
		}
		config_node = cn;

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

		uc_value_t *rv = invoke_callback(vm, set_fn, 1, ctx);
		int rc = 0;
		if (rv && ucv_type(rv) == UC_INTEGER &&
		    ucv_int64_get(rv) < 0)
			rc = (int)ucv_int64_get(rv);
		ucv_put(rv);
		ucv_put(ctx);
		ucv_put(inst_parts_arr);
		return rc;
	}

	return 0;
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
 *               failure (-1 for an invalid path or bad arguments, else
 *               the rejecting handler's negative return value)
 */
static uc_value_t *
uc_dm_params_set(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *params = uc_fn_arg(0);
	uc_value_t *model, *target;
	int err = 0;

	if (!dm || ucv_type(params) != UC_OBJECT)
		return ucv_int64_new(-1);

	model = dm_get_model(dm);
	target = dm_get_target(dm);
	if (!model || !target)
		return ucv_int64_new(-1);

	ucv_object_foreach(params, path, value) {
		char *path_buf, *path_parts[64];
		char alias_slots[32][16];
		int path_cnt = 0;
		path_buf = strdup(path);
		path_cnt = path_split(path_buf, path_parts, 64);

		if (path_cnt == 0) {
			free(path_buf);
			continue;
		}

		path_resolve_aliases(target, path_parts, path_cnt,
				     &alias_slots[0][0], sizeof(alias_slots[0]),
				     (int)(sizeof(alias_slots) / sizeof(alias_slots[0])));

		if (!path_instance_segments_valid(model, target, path_parts,
						  path_cnt - 1)) {
			fprintf(stderr, "ubbf.dm.params_set: rejecting invalid path %s\n",
				path);
			if (!err)
				err = -1;
			free(path_buf);
			continue;
		}

		if (path_instance_missing(target, path_parts, path_cnt - 1)) {
			fprintf(stderr, "ubbf.dm.params_set: no such instance for %s\n",
				path);
			if (!err)
				err = DM_SET_NO_INSTANCE;
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
 * Adds a new instance to a TR-181 multi-instance container.
 *
 * Navigates (creating as needed) to the container, allocates the next
 * free instance number, applies schema defaults, generates an Alias when
 * the schema defines one as an empty string, and updates the parent's
 * `<TableName>NumberOfEntries` field. The pattern path used for default
 * lookup is the supplied path with `.{i}` appended.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: container path)
 * @return       new instance number, or 0 when the path is invalid or
 *               `maxInstances` is reached
 */
static uc_value_t *
uc_dm_object_add(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *model, *target;
	const char *path;
	char *buf, *parts[64];
	char alias_slots[32][16];
	int cnt = 0;
	uc_value_t *container, *model_entry, *schema, *defaults;
	uc_value_t *alias, *addable, *max_val;
	int new_inst;
	char inst_str[16], pattern_path[512], alias_buf[128];
	size_t off;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(0);

	model = dm_get_model(dm);
	target = dm_get_target(dm);
	if (!model || !target)
		return ucv_int64_new(0);

	path = ucv_string_get(path_val);
	buf = strdup(path);
	cnt = path_split(buf, parts, 64);

	if (cnt == 0) {
		free(buf);
		return ucv_int64_new(0);
	}

	path_resolve_aliases(target, parts, cnt,
			     &alias_slots[0][0], sizeof(alias_slots[0]),
			     (int)(sizeof(alias_slots) / sizeof(alias_slots[0])));

	if (!path_instance_segments_valid(model, target, parts, cnt)) {
		fprintf(stderr, "ubbf.dm.object_add: rejecting invalid container path %s\n",
			path);
		free(buf);
		return ucv_int64_new(0);
	}

	/* navigate or create container */
	container = target;
	for (int i = 0; i < cnt; i++) {
		uc_value_t *child = ucv_object_get(container, parts[i], NULL);
		if (!child || ucv_type(child) != UC_OBJECT) {
			child = ucv_object_new(vm);
			ucv_object_add(container, parts[i], child);
		}
		container = child;
	}

	/* build pattern path (path + .{i}) for the direct-lookup fast path */
	off = 0;
	for (int i = 0; i < cnt && off < sizeof(pattern_path) - 5; i++)
		off += snprintf(pattern_path + off, sizeof(pattern_path) - off,
				"%s%s", i ? "." : "", parts[i]);
	snprintf(pattern_path + off, sizeof(pattern_path) - off, ".{i}");

	model_entry = ucv_object_get(model, pattern_path, NULL);

	/* direct string lookup misses nested patterns like
	 * Device.Firewall.Chain.{i}.Rule.{i} when the container path
	 * contains resolved instance numbers or named instance keys.
	 * Fall back to pattern matching: locate a model pattern whose
	 * shape matches parts[] plus a trailing {i}. Named instance
	 * keys (non-numeric children present in the tree) are accepted
	 * at {i} positions, matching the validator's relaxed rule. */
	if (!model_entry) {
		ucv_object_foreach(model, mpat, mentry) {
			char *mpb = strdup(mpat);
			char *mpp[64];
			int mpc = path_split(mpb, mpp, 64);
			bool ok = (mpc == cnt + 1) &&
				  (strcmp(mpp[mpc - 1], "{i}") == 0);
			uc_value_t *walk = target;

			for (int i = 0; ok && i < cnt; i++) {
				if (strcmp(mpp[i], "{i}") == 0) {
					if (!key_is_instance(parts[i]) &&
					    !(ucv_type(walk) == UC_OBJECT &&
					      ucv_object_get(walk, parts[i], NULL)))
						ok = false;
				} else if (strcmp(mpp[i], parts[i]) != 0) {
					ok = false;
				}
				if (ok && ucv_type(walk) == UC_OBJECT)
					walk = ucv_object_get(walk, parts[i], NULL);
			}

			free(mpb);
			if (ok) {
				model_entry = mentry;
				break;
			}
		}
	}

	/* A path the model describes no table for is not a place to put a row.
	 * The callers gate on object_writable() first, so reaching here means
	 * something bypassed them; the empty containers the walk above created
	 * go away with the transaction this failure aborts. */
	if (!model_entry) {
		fprintf(stderr, "ubbf.dm.object_add: no table at %s\n", path);
		free(buf);
		return ucv_int64_new(0);
	}

	addable = ucv_object_get(model_entry, "addable", NULL);
	if (addable && !ucv_is_truish(addable)) {
		fprintf(stderr, "ubbf.dm.object_add: %s is maintained by the CPE\n",
			path);
		free(buf);
		return ucv_int64_new(0);
	}

	max_val = ucv_object_get(model_entry, "maxInstances", NULL);
	if (max_val && ucv_type(max_val) == UC_INTEGER &&
	    count_instance_keys(container) >= ucv_int64_get(max_val)) {
		free(buf);
		return ucv_int64_new(0);
	}

	new_inst = (int)find_next_inst(container);

	/* apply schema defaults */
	uc_value_t *new_obj = ucv_object_new(vm);
	schema = model_entry ? ucv_object_get(model_entry, "schema", NULL) : NULL;
	defaults = schema ? ucv_object_get(schema, "defaults", NULL) : NULL;
	if (defaults && ucv_type(defaults) == UC_OBJECT) {
		uc_value_t *schema_def = schema ? ucv_object_get(schema, "schema", NULL) : NULL;

		ucv_object_foreach(defaults, key, val) {
			if (!schema_def || ucv_object_get(schema_def, key, NULL))
				ucv_object_add(new_obj, key, ucv_get(val));
		}
	}

	/* Generate a default Alias for the new instance. The "cpe-" prefix is
	 * reserved for entries managed by firewall_reconcile (it deletes any
	 * unclaimed cpe-* row in Firewall.{Service,InterfaceSetting,Policy}),
	 * so user-Add-created instances must use a different namespace or they
	 * vanish on the next trans_commit. Use "<Table><N>" (e.g. "Service12"). */
	alias = ucv_object_get(new_obj, "Alias", NULL);
	if (alias && ucv_type(alias) == UC_STRING &&
	    ucv_string_length(alias) == 0) {
		snprintf(alias_buf, sizeof(alias_buf), "%s%d",
			 parts[cnt - 1], new_inst);
		ucv_object_add(new_obj, "Alias", ucv_string_new(alias_buf));
	}

	snprintf(inst_str, sizeof(inst_str), "%d", new_inst);
	ucv_object_add(container, inst_str, new_obj);

	/* update NumberOfEntries on parent */
	if (cnt >= 1) {
		uc_value_t *parent = target;
		for (int i = 0; i < cnt - 1; i++)
			parent = ucv_object_get(parent, parts[i], NULL);
		if (parent) {
			char noe_key[128];
			snprintf(noe_key, sizeof(noe_key), "%sNumberOfEntries", parts[cnt - 1]);
			char noe_val[16];
			snprintf(noe_val, sizeof(noe_val), "%d", count_instance_keys(container));
			ucv_object_add(parent, noe_key, ucv_string_new(noe_val));
		}
	}

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
static uc_value_t *
uc_dm_object_del(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *target;
	const char *path;
	char *buf, *parts[64], *endp;
	char alias_slots[32][16];
	char noe_key[128], noe_val[16];
	int cnt = 0;
	long v;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(-1);

	target = dm_get_target(dm);
	if (!target)
		return ucv_int64_new(-1);

	path = ucv_string_get(path_val);
	buf = strdup(path);
	cnt = path_split(buf, parts, 64);

	path_resolve_aliases(target, parts, cnt,
			     &alias_slots[0][0], sizeof(alias_slots[0]),
			     (int)(sizeof(alias_slots) / sizeof(alias_slots[0])));

	if (cnt < 2) {
		free(buf);
		return ucv_int64_new(1);
	}

	/* validate instance key */
	v = strtol(parts[cnt - 1], &endp, 10);
	if (*endp || endp == parts[cnt - 1] || v < 1) {
		free(buf);
		return ucv_int64_new(1);
	}

	uc_value_t *parent = target;
	for (int i = 0; i < cnt - 2; i++) {
		parent = ucv_object_get(parent, parts[i], NULL);
		if (!parent || ucv_type(parent) != UC_OBJECT) {
			free(buf);
			return ucv_int64_new(1);
		}
	}

	uc_value_t *table = ucv_object_get(parent, parts[cnt - 2], NULL);
	if (!table || ucv_type(table) != UC_OBJECT ||
	    !ucv_object_get(table, parts[cnt - 1], NULL)) {
		free(buf);
		return ucv_int64_new(1);
	}

	ucv_object_delete(table, parts[cnt - 1]);

	snprintf(noe_key, sizeof(noe_key), "%sNumberOfEntries", parts[cnt - 2]);
	snprintf(noe_val, sizeof(noe_val), "%d", count_instance_keys(table));
	ucv_object_add(parent, noe_key, ucv_string_new(noe_val));

	free(buf);
	return ucv_int64_new(0);
}

/* ---- dm.runtime_reload ------------------------------------------------ */

/**
 * Replaces the runtime tree with a fresh deep clone of the live config.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       boolean true on success, false when no config is loaded
 */
static uc_value_t *
uc_dm_runtime_reload(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");

	if (!dm)
		return ucv_boolean_new(false);

	uc_value_t *config = ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
	if (!config)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_RUNTIME,
			       deep_clone_value(vm, config));

	return ucv_boolean_new(true);
}

/* ---- dm.digest -------------------------------------------------------- */

/**
 * Returns the cached config digest stored on the dm.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       digest value, or null when none has been set
 */
static uc_value_t *
uc_dm_digest(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");

	if (!dm)
		return NULL;

	return ucv_get(ucv_resource_value_get(dm->res_obj, DM_SLOT_HASH));
}

/* ---- dm.set_digest ---------------------------------------------------- */

/**
 * Stores a digest value alongside the dm config.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: hash value)
 * @return       boolean true on success, null on missing dm
 */
static uc_value_t *
uc_dm_set_digest(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *hash = uc_fn_arg(0);

	if (!dm)
		return NULL;

	ucv_resource_value_set(dm->res_obj, DM_SLOT_HASH, ucv_get(hash));

	return ucv_boolean_new(true);
}

/* ---- dm.save ---------------------------------------------------------- */

/**
 * Serialises the live config to a JSON file at the supplied path.
 *
 * Uses tab indentation. Trailing newline is appended.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: target file path)
 * @return       boolean true on success, false on any I/O error
 */
static uc_value_t *
uc_dm_save(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *config;
	char *json_str;
	FILE *fp;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	config = ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
	if (!config)
		return ucv_boolean_new(false);

	json_str = ucv_to_jsonstring_formatted(vm, config, '\t', 1);
	if (!json_str)
		return ucv_boolean_new(false);

	fp = fopen(ucv_string_get(path_val), "w");
	if (!fp) {
		free(json_str);
		return ucv_boolean_new(false);
	}

	fputs(json_str, fp);
	fputc('\n', fp);
	fclose(fp);
	free(json_str);

	return ucv_boolean_new(true);
}

/* ---- dm.runtime ------------------------------------------------------- */

/**
 * Returns the runtime tree (config plus runtime-resolved values).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       runtime tree, or null when none is loaded
 */
static uc_value_t *
uc_dm_runtime(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");

	if (!dm)
		return NULL;

	return ucv_get(dm_get_runtime(dm));
}

/* ---- dm.set_config (direct assignment, for apply_config) -------------- */

/**
 * Replaces the live config wholesale with a supplied object.
 *
 * Used by `apply_config()` to install a config loaded from disk without
 * going through the transaction workspace.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: new config object)
 * @return       boolean true on success, false on bad arguments
 */
static uc_value_t *
uc_dm_set_config(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *new_config = uc_fn_arg(0);

	if (!dm || ucv_type(new_config) != UC_OBJECT)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_CONFIG, ucv_get(new_config));

	return ucv_boolean_new(true);
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
merge_runtime_instances_c(uc_vm_t *vm, uc_value_t *base,
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
			const char *k = ucv_string_get(pv);
			uc_value_t *child = ucv_object_get(cur, k, NULL);

			if (!child || ucv_type(child) != UC_OBJECT) {
				child = ucv_object_new(vm);
				ucv_object_add(cur, k, child);
			}
			cur = child;
		}

		uc_value_t *last_pv = ucv_array_get(full_parts, plen - 1);
		const char *last_k = ucv_string_get(last_pv);

		if (ucv_type(inst_val) == UC_OBJECT) {
			uc_value_t *target = ucv_object_get(cur, last_k, NULL);

			if (!target || ucv_type(target) != UC_OBJECT) {
				target = ucv_object_new(vm);
				ucv_object_add(cur, last_k, target);
			}
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
instance_matches_base_c(char **inst_parts, int inst_cnt,
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
 * Invokes a `get` handler with a freshly built context object.
 *
 * Constructs `{ instance, config, parent, root }` and discards any
 * non-object return so callers can rely on the result being either NULL
 * or a TR-181 object.
 *
 * @param vm       ucode VM context
 * @param handler  callable get handler
 * @param instance current instance number, or 0 if not applicable
 * @param config   per-instance config (may be NULL)
 * @param parent   parent-instance config (may be NULL)
 * @param runtime  runtime tree root
 * @return         handler result object, or NULL on failure
 */
static uc_value_t *
call_get_handler(uc_vm_t *vm, uc_value_t *handler, int64_t instance,
		 uc_value_t *config, uc_value_t *parent, uc_value_t *runtime)
{
	uc_value_t *ctx = ucv_object_new(vm);

	ucv_object_add(ctx, "instance", instance ? ucv_int64_new(instance) : NULL);
	ucv_object_add(ctx, "config", config ? ucv_get(config) : NULL);
	ucv_object_add(ctx, "parent", parent ? ucv_get(parent) : NULL);
	ucv_object_add(ctx, "root", runtime ? ucv_get(runtime) : NULL);

	uc_value_t *result = invoke_callback(vm, handler, 1, ctx);
	ucv_put(ctx);

	if (!result || ucv_type(result) != UC_OBJECT) {
		ucv_put(result);
		return NULL;
	}

	return result;
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
	char parent_pat[512], rel[512], key[128], count[16];
	uc_value_t *entry, *schema, *params, *counts;
	size_t off = 0;

	if (last_i < 2 || pp_cnt - 1 < base_cnt)
		return;

	for (int i = 0; i < last_i - 1 && off < sizeof(parent_pat) - 1; i++)
		off += snprintf(parent_pat + off, sizeof(parent_pat) - off,
				"%s%s", i ? "." : "", pat_parts[i]);

	entry = ucv_object_get(model, parent_pat, NULL);
	schema = entry ? ucv_object_get(entry, "schema", NULL) : NULL;
	params = schema ? ucv_object_get(schema, "schema", NULL) : NULL;
	if (ucv_type(params) != UC_OBJECT)
		return;

	snprintf(key, sizeof(key), "%sNumberOfEntries", pat_parts[last_i - 1]);
	if (!ucv_object_get(params, key, NULL))
		return;

	off = 0;
	rel[0] = '\0';
	for (int i = base_cnt; i < pp_cnt - 1 && off < sizeof(rel) - 1; i++)
		off += snprintf(rel + off, sizeof(rel) - off,
				"%s%s", i > base_cnt ? "." : "", pp_parts[i]);

	counts = ucv_object_get(pending, rel, NULL);
	if (!counts) {
		counts = ucv_object_new(vm);
		ucv_object_add(pending, rel, counts);
	}

	snprintf(count, sizeof(count), "%d", count_instance_keys(rows));
	ucv_object_add(counts, key, ucv_string_new(count));
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
			char table[128], count[16];
			size_t key_len = strlen(key);
			uc_value_t *rows = NULL;

			if (key_len > suffix_len && key_len - suffix_len < sizeof(table)) {
				memcpy(table, key, key_len - suffix_len);
				table[key_len - suffix_len] = '\0';
				rows = ucv_object_get(parent, table, NULL);
			}

			if (ucv_type(rows) == UC_OBJECT) {
				snprintf(count, sizeof(count), "%d", count_instance_keys(rows));
				ucv_object_add(parent, key, ucv_string_new(count));
			} else {
				ucv_object_add(parent, key, ucv_get(val));
			}
		}
	}
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
 *                   the dispatch_subtree calls of one params_get batch so a
 *                   shared ancestor handler runs once instead of per leaf.
 *                   Pass NULL for a standalone single-subtree dispatch.
 * @return           hydrated subtree object, possibly empty on bad input
 */
static uc_value_t *
dispatch_subtree(uc_vm_t *vm, ubbf_dm_t *dm, const char *path,
		 uc_value_t *anc_cache)
{
	uc_value_t *model, *runtime;
	char *base_buf, *base_parts_arr[64];
	int base_cnt = 0;

	if (!dm || !path)
		return ucv_object_new(vm);

	model = dm_get_model(dm);
	runtime = dm_get_runtime(dm);
	if (!model || !runtime)
		return ucv_object_new(vm);

	uc_value_t *subtree = navigate_by_path(vm, runtime, path);
	uc_value_t *base = subtree ? deep_clone_value(vm, subtree) : ucv_object_new(vm);
	uc_value_t *pending = ucv_object_new(vm);

	base_buf = strdup(path);
	base_cnt = path_split(base_buf, base_parts_arr, 64);

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
			char *a_buf = strdup(a_pattern);
			char *a_parts[64];
			int a_cnt = path_split(a_buf, a_parts, 64);
			free(a_buf);
			if (a_cnt >= base_cnt)
				continue;
			match_handler(path, base_cnt, base_parts_arr,
				      a_pattern, a_entry, "get", &ancestor);
		}

		if (ancestor.handler && ancestor.pattern_len < base_cnt) {
			char anc_path[512];
			size_t ap_off = 0;
			for (int i = 0; i < ancestor.pattern_len &&
				 ap_off < sizeof(anc_path) - 1; i++)
				ap_off += snprintf(anc_path + ap_off,
						   sizeof(anc_path) - ap_off,
						   "%s%s", i ? "." : "",
						   base_parts_arr[i]);

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
				uc_value_t *a_schema = ucv_object_get(ancestor.entry, "schema", NULL);
				uc_value_t *a_defs = a_schema ? ucv_object_get(a_schema, "defaults", NULL) : NULL;
				uc_value_t *a_merged = NULL;
				if (a_cfg && a_defs) {
					a_merged = deep_clone_value(vm, a_cfg);
					merge_schema_defaults(vm, a_merged, a_defs);
				} else if (a_cfg) {
					a_merged = ucv_get(a_cfg);
				} else if (a_defs) {
					a_merged = deep_clone_value(vm, a_defs);
				}

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
					char *pb = strdup(ancestor.pattern_key);
					char *pp[64];
					int pc = path_split(pb, pp, 64);
					int last_i = -1, prev_i = -1;
					for (int i = pc - 1; i >= 0; i--) {
						if (strcmp(pp[i], "{i}") == 0) {
							last_i = i;
							break;
						}
					}
					if (last_i > 0) {
						for (int i = last_i - 1; i >= 0; i--) {
							if (strcmp(pp[i], "{i}") == 0) {
								prev_i = i;
								break;
							}
						}
					}
					if (prev_i >= 0) {
						uc_value_t *pcur = runtime;
						for (int i = 0; i <= prev_i && pcur; i++)
							pcur = ucv_object_get(pcur, base_parts_arr[i], NULL);
						anc_parent = pcur;
					}
					free(pb);
				}

				a_result = call_get_handler(vm, ancestor.handler,
							    ancestor.instance,
							    a_merged, anc_parent, runtime);
				ucv_put(a_merged);

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
					ucv_object_add(base, sk, deep_clone_value(vm, sv));
			}

			ucv_put(a_result);
		}
	}

	ucv_object_foreach(model, pattern, entry) {
		uc_value_t *get_fn;
		char *pat_buf, *pat_parts[64];
		int pat_cnt = 0;
		bool matches_path = true;

		if (ucv_type(entry) != UC_OBJECT)
			continue;

		get_fn = ucv_object_get(entry, "get", NULL);
		if (!get_fn || !ucv_is_callable(get_fn))
			get_fn = NULL;

		bool has_flag = enable_truthy(
			ucv_object_get(entry, "enable_status_derive", NULL));

		if (!get_fn && !has_flag)
			continue;

		/* pattern_matches_path check */
		pat_buf = strdup(pattern);
		pat_cnt = path_split(pat_buf, pat_parts, 64);

		if (pat_cnt < base_cnt)
			matches_path = false;
		else {
			for (int i = 0; i < base_cnt; i++) {
				if (strcmp(pat_parts[i], "{i}") == 0)
					continue;
				if (strcmp(pat_parts[i], base_parts_arr[i]) != 0) {
					matches_path = false;
					break;
				}
			}
		}

		if (!matches_path) {
			free(pat_buf);
			continue;
		}

		/* collect existing instances */
		uc_value_t *pat_arr = ucv_array_new(vm);
		for (int i = 0; i < pat_cnt; i++)
			ucv_array_push(pat_arr, ucv_string_new(pat_parts[i]));

		uc_value_t *inst_paths = ucv_array_new(vm);
		do_collect_instances(inst_paths, pat_arr, runtime, 0, "", vm);

		bool matched_an_instance = false;

		if (ucv_array_length(inst_paths) > 0) {
			/* merge existing instances */
			for (size_t pi = 0; pi < ucv_array_length(inst_paths); pi++) {
				uc_value_t *ip_val = ucv_array_get(inst_paths, pi);
				const char *inst_path = ucv_string_get(ip_val);
				char *ip_buf = strdup(inst_path);
				char *ip_parts[64];
				int ip_cnt = 0;

				ip_cnt = path_split(ip_buf, ip_parts, 64);

				if (!instance_matches_base_c(ip_parts, ip_cnt, base_parts_arr, base_cnt)) {
					free(ip_buf);
					continue;
				}
				matched_an_instance = true;

				uc_value_t *config_node = navigate_by_path(vm, runtime, inst_path);

				uc_value_t *schema_obj = ucv_object_get(entry, "schema", NULL);
				uc_value_t *defs = schema_obj ? ucv_object_get(schema_obj, "defaults", NULL) : NULL;
				uc_value_t *merged = NULL;
				if (config_node && defs) {
					merged = deep_clone_value(vm, config_node);
					merge_schema_defaults(vm, merged, defs);
				} else if (config_node) {
					merged = ucv_get(config_node);
				} else if (defs) {
					merged = deep_clone_value(vm, defs);
				}

				uc_value_t *ip_arr = ucv_array_new(vm);
				for (int i = 0; i < ip_cnt; i++)
					ucv_array_push(ip_arr, ucv_string_new(ip_parts[i]));

				uc_value_t *parent_config = NULL;
				{
					/* find last {i} in pattern */
					int last_i = -1;
					for (int i = pat_cnt - 1; i >= 0; i--) {
						if (strcmp(pat_parts[i], "{i}") == 0) {
							last_i = i;
							break;
						}
					}
					if (last_i >= 0 && (size_t)(last_i + 1) < (size_t)pat_cnt) {
						uc_value_t *pcur = runtime;
						for (int i = 0; i <= last_i && pcur; i++)
							pcur = ucv_object_get(pcur, ip_parts[i], NULL);
						parent_config = pcur;
					} else if (last_i > 0) {
						int prev_i = -1;
						for (int i = last_i - 1; i >= 0; i--) {
							if (strcmp(pat_parts[i], "{i}") == 0) {
								prev_i = i;
								break;
							}
						}
						if (prev_i >= 0) {
							uc_value_t *pcur = runtime;
							for (int i = 0; i <= prev_i && pcur; i++)
								pcur = ucv_object_get(pcur, ip_parts[i], NULL);
							parent_config = pcur;
						}
					}
				}

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
					result = call_get_handler(vm, get_fn, inst_num,
								  merged, parent_config, runtime);
				if (has_flag)
					status_overlay(vm, &result, merged);
				ucv_put(merged);
				if (result) {
					uc_value_t *rel = ucv_array_new(vm);
					for (int i = base_cnt; i < ip_cnt; i++)
						ucv_array_push(rel, ucv_string_new(ip_parts[i]));

					uc_value_t *cur = base;
					size_t rlen = ucv_array_length(rel);
					for (size_t i = 0; i < rlen; i++) {
						uc_value_t *rv = ucv_array_get(rel, i);
						const char *rk = ucv_string_get(rv);
						uc_value_t *child = ucv_object_get(cur, rk, NULL);
						if (!child || ucv_type(child) != UC_OBJECT) {
							child = ucv_object_new(vm);
							ucv_object_add(cur, rk, child);
						}
						cur = child;
					}
					ucv_object_foreach(result, rk, rv)
						ucv_object_add(cur, rk, ucv_get(rv));

					ucv_put(rel);
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
		if (!matched_an_instance && get_fn && strstr(pattern, "{i}")) {
			/* runtime discovery for patterns with no existing instances */
			int last_i = -1;
			for (int i = pat_cnt - 1; i >= 0; i--) {
				if (strcmp(pat_parts[i], "{i}") == 0) {
					last_i = i;
					break;
				}
			}

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
				int prev_i = -1;
				for (int i = last_i - 1; i >= 0; i--) {
					if (strcmp(pat_parts[i], "{i}") == 0) {
						prev_i = i;
						break;
					}
				}
				if (prev_i >= 0) {
					uc_value_t *pcur = runtime;
					for (int i = 0; i <= prev_i && pcur; i++)
						pcur = ucv_object_get(pcur, base_parts_arr[i], NULL);
					parent_config = pcur;
				}

				char *endp;
				int64_t inst_num = strtoll(base_parts_arr[last_i], &endp, 10);
				if (*endp != '\0' || endp == base_parts_arr[last_i])
					inst_num = 0;

				char base_path_str[512];
				size_t bp_off = 0;
				for (int i = 0; i < base_cnt && bp_off < sizeof(base_path_str) - 1; i++)
					bp_off += snprintf(base_path_str + bp_off,
							   sizeof(base_path_str) - bp_off,
							   "%s%s", i ? "." : "", base_parts_arr[i]);

				uc_value_t *config_node = navigate_by_path(vm, runtime, base_path_str);
				uc_value_t *schema_obj = ucv_object_get(entry, "schema", NULL);
				uc_value_t *defs = schema_obj ? ucv_object_get(schema_obj, "defaults", NULL) : NULL;
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
					merged = deep_clone_value(vm, config_node);
					merge_schema_defaults(vm, merged, defs);
				} else if (config_node) {
					merged = ucv_get(config_node);
				}

				uc_value_t *result = call_get_handler(vm, get_fn, inst_num,
								      merged, parent_config, runtime);
				if (has_flag)
					status_overlay(vm, &result, merged);
				ucv_put(merged);
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
				do_collect_instances(parent_insts, parent_pat, runtime, 0, "", vm);

				for (size_t pi = 0; pi < ucv_array_length(parent_insts); pi++) {
					uc_value_t *pp_val = ucv_array_get(parent_insts, pi);
					const char *pp_str = ucv_string_get(pp_val);
					uc_value_t *parent_data = navigate_by_path(vm, runtime, pp_str);

					uc_value_t *result = call_get_handler(vm, get_fn, 0,
									      NULL, parent_data, runtime);
					if (!result) continue;

					char *pp_buf = strdup(pp_str);
					char *pp_parts[64];
					int pp_cnt = path_split(pp_buf, pp_parts, 64);

					uc_value_t *rel = ucv_array_new(vm);
					for (int i = base_cnt; i < pp_cnt; i++)
						ucv_array_push(rel, ucv_string_new(pp_parts[i]));

					merge_runtime_instances_c(vm, base, rel, result);
					entries_count_record(vm, pending, model, pat_parts, last_i,
							     pp_parts, pp_cnt, base_cnt, result);

					ucv_put(rel);
					ucv_put(result);
					free(pp_buf);
				}

				ucv_put(parent_insts);
				ucv_put(parent_pat);
			} else {
				/* enumerate_at_root -- single {i} depth */
				int i_count = 0;
				for (int i = 0; i < pat_cnt; i++)
					if (strcmp(pat_parts[i], "{i}") == 0) i_count++;

				if (i_count <= 1 && last_i >= 0) {
					uc_value_t *result = call_get_handler(vm, get_fn, 0,
									      NULL, NULL, runtime);
					if (result) {
						int container_idx = last_i - 1;
						if (container_idx >= 0) {
							uc_value_t *rel = ucv_array_new(vm);
							for (int i = base_cnt; i <= container_idx; i++)
								ucv_array_push(rel, ucv_string_new(pat_parts[i]));

							merge_runtime_instances_c(vm, base, rel, result);
							ucv_put(rel);
						}
						ucv_put(result);
					}
				}
			}
		}

		ucv_put(inst_paths);
		ucv_put(pat_arr);
		free(pat_buf);
	}

	entries_count_apply(vm, base, pending);
	ucv_put(pending);
	free(base_buf);
	return base;
}

/**
 * Ucode-callable wrapper around `dispatch_subtree`.
 *
 * Exposes the shared dispatcher as `dm.get_subtree_with_state(path)` for
 * `bbf-dm.show`, `bbf-dm.get` (trailing-dot paths), `webui-show` and
 * `dm.refresh_instances`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: base path string)
 * @return       hydrated subtree object, possibly empty on bad input
 */
static uc_value_t *
uc_dm_get_subtree_with_state(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);

	if (ucv_type(path_val) != UC_STRING)
		return ucv_object_new(vm);

	return dispatch_subtree(vm, dm, ucv_string_get(path_val), NULL);
}

/* ---- dm.names ---------------------------------------------------------- */

#define DM_WRITABLE_BIT	0x80000000

#define DM_PATH_NONE	0
#define DM_PATH_OBJECT	1
#define DM_PATH_PARAM	2

/**
 * Looks a leaf up in the registered model and reports whether it is writable.
 *
 * The model is keyed by schema pattern, so the caller passes the pattern of
 * the object holding the leaf rather than the leaf's own resolved path.
 *
 * @param model    registered model object
 * @param pattern  schema pattern of the parent object
 * @param name     leaf name
 * @return         true when the schema marks the parameter writable
 */
static bool
model_param_writable(uc_value_t *model, const char *pattern, const char *name)
{
	uc_value_t *entry, *schema, *params, *info;

	entry = ucv_object_get(model, pattern, NULL);
	schema = entry ? ucv_object_get(entry, "schema", NULL) : NULL;
	params = schema ? ucv_object_get(schema, "schema", NULL) : NULL;
	info = params ? ucv_object_get(params, name, NULL) : NULL;

	if (ucv_type(info) != UC_INTEGER)
		return false;

	return (ucv_int64_get(info) & DM_WRITABLE_BIT) != 0;
}

/**
 * Reports whether instances may be added under an object pattern.
 *
 * @param model    registered model object
 * @param pattern  schema pattern of the object
 * @return         true when the model describes instances below it
 */
static bool
model_object_addable(uc_value_t *model, const char *pattern)
{
	char buf[512];
	uc_value_t *entry, *addable;

	if (snprintf(buf, sizeof(buf), "%s.{i}", pattern) >= (int)sizeof(buf))
		return false;

	entry = ucv_object_get(model, buf, NULL);
	if (!entry)
		return false;

	/* A table the CPE maintains itself is readable but not addable, and
	 * GetParameterNames reports that as Writable=false. */
	addable = ucv_object_get(entry, "addable", NULL);

	return !addable || ucv_is_truish(addable);
}

/**
 * Folds a resolved path into its schema pattern.
 *
 * @param path     resolved path, with or without a trailing dot
 * @param out      destination buffer
 * @param out_len  size of the destination buffer
 * @return         true when the pattern fits
 */
static bool
path_to_pattern(const char *path, char *out, size_t out_len)
{
	char buf[512], seg[512];
	size_t len = strlen(path);

	if (len >= sizeof(buf))
		return false;

	memcpy(buf, path, len + 1);
	if (len && buf[len - 1] == '.')
		buf[len - 1] = '\0';

	out[0] = '\0';
	for (char *tok = strtok(buf, "."); tok; tok = strtok(NULL, ".")) {
		const char *part = key_is_instance(tok) ? "{i}" : tok;

		if ((size_t)snprintf(seg, sizeof(seg), "%s%s%s", out,
				     out[0] ? "." : "", part) >= out_len)
			return false;

		memcpy(out, seg, strlen(seg) + 1);
	}

	return out[0] != '\0';
}

/**
 * Reports whether a path names something the registered model describes.
 *
 * The test is model membership, not tree membership: TR-069 A.3.2.2 and
 * A.3.2.3 fault 9005 for a name the data model does not define, while an
 * object that is supported but currently empty is a valid, empty answer.
 * dispatch_subtree() cannot make that distinction because it returns an empty
 * object for both.
 *
 * @param model  registered model object
 * @param path   resolved path; a trailing dot asks about an object
 * @return       DM_PATH_NONE, DM_PATH_OBJECT or DM_PATH_PARAM
 */
static int
path_resolves(uc_value_t *model, const char *path)
{
	char pattern[512], parent[512];
	size_t len = strlen(path);
	const char *leaf;

	if (!len || !model)
		return DM_PATH_NONE;

	if (!path_to_pattern(path, pattern, sizeof(pattern)))
		return DM_PATH_NONE;

	if (path[len - 1] == '.')
		return ucv_object_get(model, pattern, NULL) ? DM_PATH_OBJECT
							    : DM_PATH_NONE;

	leaf = strrchr(pattern, '.');
	if (!leaf)
		return DM_PATH_NONE;

	if ((size_t)(leaf - pattern) >= sizeof(parent))
		return DM_PATH_NONE;

	memcpy(parent, pattern, leaf - pattern);
	parent[leaf - pattern] = '\0';
	leaf++;

	uc_value_t *entry = ucv_object_get(model, parent, NULL);
	uc_value_t *schema = entry ? ucv_object_get(entry, "schema", NULL) : NULL;
	uc_value_t *params = schema ? ucv_object_get(schema, "schema", NULL) : NULL;

	if (params && ucv_object_get(params, leaf, NULL))
		return DM_PATH_PARAM;

	/* An object addressed without its trailing dot still names an object. */
	return ucv_object_get(model, pattern, NULL) ? DM_PATH_OBJECT
						    : DM_PATH_NONE;
}

static void
names_collect(uc_vm_t *vm, uc_value_t *out, const char *path, bool writable)
{
	uc_value_t *entry = ucv_object_new(vm);

	ucv_object_add(entry, "path", ucv_string_new(path));
	ucv_object_add(entry, "writable", ucv_boolean_new(writable));
	ucv_array_push(out, entry);
}

/**
 * Walks a hydrated subtree emitting a name per object and parameter.
 *
 * The schema pattern is carried down instead of being rebuilt from each
 * resolved path: every child of an object shares its parent's pattern, so
 * deriving it per row would repeat a split and a join for every parameter in
 * the model.
 *
 * @param vm       ucode VM context
 * @param model    registered model object
 * @param node     subtree node being walked
 * @param prefix   resolved path of the node, including its trailing dot
 * @param pattern  schema pattern of the node, without a trailing dot
 * @param depth    remaining recursion budget
 * @param out      destination array
 */
static void
names_walk(uc_vm_t *vm, uc_value_t *model, uc_value_t *node,
	   const char *prefix, const char *pattern, int depth,
	   uc_value_t *out)
{
	char full[512], sub[512];

	if (depth <= 0)
		return;

	ucv_object_foreach(node, key, val) {
		/* Keys opening with a dot are the tree's own metadata. */
		if (!key || key[0] == '.')
			continue;

		if (snprintf(full, sizeof(full), "%s%s", prefix, key) >=
		    (int)sizeof(full))
			continue;

		if (ucv_type(val) != UC_OBJECT) {
			names_collect(vm, out, full,
				      model_param_writable(model, pattern, key));
			continue;
		}

		if (snprintf(sub, sizeof(sub), "%s.%s", pattern,
			     key_is_instance(key) ? "{i}" : key) >=
		    (int)sizeof(sub))
			continue;

		if (snprintf(full, sizeof(full), "%s%s.", prefix, key) >=
		    (int)sizeof(full))
			continue;

		names_collect(vm, out, full,
			      model_object_addable(model, sub));

		names_walk(vm, model, val, full, sub, depth - 1, out);
	}
}

/**
 * Builds the GetParameterNames answer for a path.
 *
 * Hydrating the subtree runs the get handlers, which is what materialises the
 * runtime instances, so the walk cannot be served from the persisted tree
 * alone. What it avoids is handing the whole tree back to the VM to be walked
 * a second time.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, next_level)
 * @return       array of `{ path, writable }`, or null on a path that does not
 *               resolve
 */
static uc_value_t *
uc_dm_names(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *next_val = uc_fn_arg(1);
	uc_value_t *subtree, *model, *out;
	const char *path;
	char base[512], pattern[512], child[512];
	size_t len;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	len = strlen(path);

	if (!len || path[len - 1] != '.' || len >= sizeof(base))
		return NULL;

	model = dm_get_model(dm);
	if (path_resolves(model, path) != DM_PATH_OBJECT)
		return NULL;

	subtree = dispatch_subtree(vm, dm, path, NULL);
	if (ucv_type(subtree) != UC_OBJECT) {
		ucv_put(subtree);
		return NULL;
	}

	out = ucv_array_new(vm);

	if (!path_to_pattern(path, pattern, sizeof(pattern))) {
		ucv_put(subtree);
		ucv_put(out);
		return NULL;
	}

	/* A.3.2.3: with NextLevel the answer is the next-level children alone,
	 * and the queried object itself belongs only to the full walk. */
	if (ucv_is_truish(next_val)) {
		ucv_object_foreach(subtree, key, val) {
			if (!key || key[0] == '.')
				continue;

			if (snprintf(child, sizeof(child), "%s%s", path, key) >=
			    (int)sizeof(child))
				continue;

			if (ucv_type(val) != UC_OBJECT) {
				names_collect(vm, out, child,
					      model_param_writable(model, pattern, key));
				continue;
			}

			if (snprintf(base, sizeof(base), "%s.%s", pattern,
				     key_is_instance(key) ? "{i}" : key) >=
			    (int)sizeof(base))
				continue;

			if (snprintf(child, sizeof(child), "%s%s.", path, key) >=
			    (int)sizeof(child))
				continue;

			names_collect(vm, out, child,
				      model_object_addable(model, base));
		}
	}
	else {
		names_collect(vm, out, path, model_object_addable(model, pattern));
		names_walk(vm, model, subtree, path, pattern, 32, out);
	}

	ucv_put(subtree);

	return out;
}

/**
 * dm.path_known(path)
 *
 * Reports whether the registered model describes a path: 0 when it does not,
 * 1 for an object, 2 for a parameter. Callers use it to tell an unsupported
 * name from a supported but empty object, which the subtree dispatch cannot
 * express because it answers both with an empty object.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: path string)
 * @return       integer path kind
 */
static uc_value_t *
uc_dm_path_known(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(DM_PATH_NONE);

	return ucv_int64_new(path_resolves(dm_get_model(dm),
					   ucv_string_get(path_val)));
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
 * @return       array of instance path strings
 */
static uc_value_t *
uc_dm_refresh_instances(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *subtree, *arr;
	const char *path;
	char *trimmed, *s, *e;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_array_new(vm);

	path = ucv_string_get(path_val);
	trimmed = strdup(path);
	s = trimmed;
	while (*s == '.') s++;
	e = s + strlen(s) - 1;
	while (e > s && *e == '.') *e-- = '\0';

	subtree = uc_dm_get_subtree_with_state(vm, nargs);

	arr = ucv_array_new(vm);
	do_find_nested_instances(arr, s, subtree, vm);
	ucv_put(subtree);
	free(trimmed);

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
static uc_value_t *
uc_dm_get_subtree(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *runtime, *result;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_object_new(vm);

	runtime = dm_get_runtime(dm);
	if (!runtime)
		return ucv_object_new(vm);

	result = navigate_by_path(vm, runtime, ucv_string_get(path_val));

	return result ? ucv_get(result) : ucv_object_new(vm);
}

/* ---- dm methods table ------------------------------------------------- */

static const uc_function_list_t dm_methods[] = {
	{ "register",                    uc_dm_register },
	{ "register_operations",         uc_dm_register_operations },
	{ "set_hooks",                   uc_dm_set_hooks },
	{ "load",                        uc_dm_load },
	{ "config",                      uc_dm_config },
	{ "lookup",                      uc_dm_lookup },
	{ "trans_start",                 uc_dm_trans_start },
	{ "trans_commit",                uc_dm_trans_commit },
	{ "trans_abort",                 uc_dm_trans_abort },
	{ "find_get_handler",            uc_dm_find_get_handler },
	{ "find_set_handler",            uc_dm_find_set_handler },
	{ "params_get",                  uc_dm_params_get },
	{ "params_set",                  uc_dm_params_set },
	{ "object_add",                  uc_dm_object_add },
	{ "object_del",                  uc_dm_object_del },
	{ "runtime_reload",              uc_dm_runtime_reload },
	{ "runtime",                     uc_dm_runtime },
	{ "digest",                      uc_dm_digest },
	{ "get_digest",                  uc_dm_digest },
	{ "set_digest",                  uc_dm_set_digest },
	{ "save",                        uc_dm_save },
	{ "set_config",                  uc_dm_set_config },
	{ "get_subtree",                 uc_dm_get_subtree },
	{ "get_subtree_with_state",      uc_dm_get_subtree_with_state },
	{ "names",                       uc_dm_names },
	{ "path_known",                  uc_dm_path_known },
	{ "refresh_instances",           uc_dm_refresh_instances },
};

/**
 * Registers the `ubbf.dm` resource type with the VM.
 *
 * Called once at module init to make the type available before any
 * `ubbf.create()` invocation.
 *
 * @param vm  ucode VM context
 */
void dm_register_type(uc_vm_t *vm)
{
	uc_type_declare(vm, "ubbf.dm", dm_methods, dm_free);
}
