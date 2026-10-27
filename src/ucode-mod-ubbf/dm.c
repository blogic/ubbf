/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The `ubbf.dm` resource: registration, transactions, the config and its
 * digest, and the method table.
 */

#include <syslog.h>

#include "dm-priv.h"
#include "bindings.h"

/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/**
 * Creates and initialises a new `ubbf.dm` resource. The resource
 * framework releases the slots (model, operations, config, workspace,
 * runtime, hash) with the resource.
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
	dm->res_obj = obj;

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
 * Stores the patterns that the model leaves out for the active protocol or
 * TR-181 version. A get handler that returns a child object below one of
 * them loses it without a log entry, since the omission is intended.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: array of patterns)
 * @return       boolean true on success, false on bad arguments
 */
static uc_value_t *
uc_dm_register_hidden(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *patterns = uc_fn_arg(0);
	uc_value_t *hidden;

	if (!dm || ucv_type(patterns) != UC_ARRAY)
		return ucv_boolean_new(false);

	hidden = ucv_object_new(vm);

	for (size_t i = 0; i < ucv_array_length(patterns); i++) {
		uc_value_t *pattern = ucv_array_get(patterns, i);

		if (ucv_type(pattern) == UC_STRING)
			ucv_object_add(hidden, ucv_string_get(pattern),
				       ucv_boolean_new(true));
	}

	ucv_resource_value_set(dm->res_obj, DM_SLOT_HIDDEN, hidden);

	return ucv_boolean_new(true);
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
	uc_value_t *parsed;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_boolean_new(false);

	parsed = json_file_load(vm, ucv_string_get(path_val));
	if (!parsed)
		return ucv_boolean_new(false);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_CONFIG, parsed);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_RUNTIME,
			       value_deep_clone(vm, parsed));

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

	return ucv_get(dm_target_get(dm));
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

	clone = value_deep_clone(vm, config);
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
			       value_deep_clone(vm, config));

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

/* ---- dm.config_load --------------------------------------------------- */

/**
 * Loads config.json as the live config and seeds the instance map from
 * its `_instances` pins. The digest is set over the canonical content of
 * what was read, so that config_persist() writes again only when the
 * content changes; a pin that no row needs any more counts as a change.
 * Hashing the raw file bytes instead would make every load look changed.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: file path)
 * @return       true when the config was loaded
 */
static uc_value_t *
uc_dm_config_load(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path = uc_fn_arg(0);
	uc_value_t *config, *pins;
	char *content;

	if (!dm || ucv_type(path) != UC_STRING)
		return ucv_boolean_new(false);

	config = json_file_load(vm, ucv_string_get(path));
	if (!config)
		return ucv_boolean_new(false);

	pins = config_pins_take(vm, config);
	if (!pins)
		pins = ucv_object_new(vm);

	ucv_resource_value_set(dm->res_obj, DM_SLOT_CONFIG, config);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_RUNTIME, value_deep_clone(vm, config));

	content = config_content(vm, config, pins);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_HASH, sha256_new(content));
	free(content);
	ucv_put(pins);

	return ucv_boolean_new(true);
}

/* ---- dm.config_persist ------------------------------------------------ */

/**
 * Writes the live config with its pins. The runtime copy is written each
 * time; the persistent file only when the digest of the content differs
 * from the stored one. After a persistent write the digest is updated and
 * the runtime tree reloaded.
 *
 * The persistent write is atomic: a process killed between an
 * open(O_TRUNC) and the write would leave an empty config.json, which the
 * agent cannot start from.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: persistent path, runtime
 *               copy path, file mode, default 0600)
 * @return       true when the persistent file was rewritten, false when
 *               the content is unchanged, null when its write failed or
 *               no config is loaded
 */
static uc_value_t *
uc_dm_config_persist(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path = uc_fn_arg(0);
	uc_value_t *runtime_path = uc_fn_arg(1);
	uc_value_t *mode_val = uc_fn_arg(2);
	mode_t mode = ucv_type(mode_val) == UC_INTEGER ? (mode_t)(ucv_int64_get(mode_val) & 07777) : 0600;
	uc_value_t *config, *hash, *old;
	char *content;
	size_t len;

	if (!dm || ucv_type(path) != UC_STRING || ucv_type(runtime_path) != UC_STRING)
		return NULL;

	config = dm_target_get(dm);
	if (ucv_type(config) != UC_OBJECT)
		return NULL;

	content = config_content(vm, config, NULL);
	len = strlen(content);
	file_write_atomic(ucv_string_get(runtime_path), content, len, mode);

	hash = sha256_new(content);
	old = ucv_resource_value_get(dm->res_obj, DM_SLOT_HASH);
	if (ucv_is_equal(hash, old)) {
		ucv_put(hash);
		free(content);
		return ucv_boolean_new(false);
	}

	if (!file_write_atomic(ucv_string_get(path), content, len, mode)) {
		ubbf_log(LOG_ERR, "config_persist: failed to write %s", ucv_string_get(path));
		ucv_put(hash);
		free(content);
		return NULL;
	}

	free(content);
	ucv_resource_value_set(dm->res_obj, DM_SLOT_HASH, hash);

	config = ucv_resource_value_get(dm->res_obj, DM_SLOT_CONFIG);
	if (config)
		ucv_resource_value_set(dm->res_obj, DM_SLOT_RUNTIME, value_deep_clone(vm, config));

	return ucv_boolean_new(true);
}

/* ---- dm.save ---------------------------------------------------------- */

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

	return ucv_get(dm_runtime_get(dm));
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

/* ---- dm methods table ------------------------------------------------- */

static const uc_function_list_t dm_methods[] = {
	{ "register",                    uc_dm_register },
	{ "register_operations",         uc_dm_register_operations },
	{ "register_hidden",             uc_dm_register_hidden },
	{ "load",                        uc_dm_load },
	{ "config",                      uc_dm_config },
	{ "trans_start",                 uc_dm_trans_start },
	{ "trans_commit",                uc_dm_trans_commit },
	{ "trans_abort",                 uc_dm_trans_abort },
	{ "params_get",                  uc_dm_params_get },
	{ "params_set",                  uc_dm_params_set },
	{ "object_add",                  uc_dm_object_add },
	{ "object_del",                  uc_dm_object_del },
	{ "runtime_reload",              uc_dm_runtime_reload },
	{ "runtime",                     uc_dm_runtime },
	{ "digest",                      uc_dm_digest },
	{ "get_digest",                  uc_dm_digest },
	{ "set_digest",                  uc_dm_set_digest },
	{ "config_load",                 uc_dm_config_load },
	{ "config_persist",              uc_dm_config_persist },
	{ "wildcard_expand",             uc_dm_wildcard_expand },
	{ "names_compute",               uc_dm_names_compute },
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
	uc_type_declare(vm, "ubbf.dm", dm_methods, NULL);
}
