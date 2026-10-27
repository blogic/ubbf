/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Private interface of the dm*.c files.
 */

#ifndef UBBF_DM_PRIV_H
#define UBBF_DM_PRIV_H

#include "ubbf.h"

enum {
	DM_SLOT_MODEL,
	DM_SLOT_OPERATIONS,
	DM_SLOT_CONFIG,
	DM_SLOT_WORKSPACE,
	DM_SLOT_RUNTIME,
	DM_SLOT_HASH,
	DM_SLOT_HIDDEN,
	DM_SLOT_MAX
};

/* res_obj points back to the resource that embeds the struct, so it
 * holds no reference: a counted one would keep the resource alive. */
typedef struct {
	uc_vm_t *vm;
	uc_value_t *res_obj;
} ubbf_dm_t;

/**
 * Returns the writable target tree (workspace if active, else live config).
 *
 * @param dm  dm instance
 * @return    borrowed reference to the active write target
 */
static inline uc_value_t *
dm_target_get(ubbf_dm_t *dm)
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
dm_runtime_get(ubbf_dm_t *dm)
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
dm_model_get(ubbf_dm_t *dm)
{
	return ucv_resource_value_get(dm->res_obj, DM_SLOT_MODEL);
}

/* dm_model.c */
int pattern_inst_before(char **pattern, int before);
uc_value_t *model_entry_for_parts(uc_value_t *model, char **parts, int cnt);
uc_value_t *table_row_entry(uc_value_t *model, const char *pattern);
char *path_to_pattern(const char *path);

/* dm_get.c */
uc_value_t *uc_dm_params_get(uc_vm_t *vm, size_t nargs);
uc_value_t *instances_from_parts(uc_vm_t *vm, char **parts, int cnt);
uc_value_t *get_handler_call(uc_vm_t *vm, uc_value_t *handler, int64_t instance,
			     uc_value_t *config, uc_value_t *parent,
			     uc_value_t *runtime, uc_value_t *instances);
uc_value_t *subtree_dispatch(uc_vm_t *vm, ubbf_dm_t *dm, const char *path,
			     uc_value_t *anc_cache);
uc_value_t *uc_dm_get_subtree_with_state(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_wildcard_expand(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_refresh_instances(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_get_subtree(uc_vm_t *vm, size_t nargs);

/* dm_set.c */
uc_value_t *uc_dm_params_set(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_object_add(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_object_del(uc_vm_t *vm, size_t nargs);

/* dm_names.c */
uc_value_t *uc_dm_names_compute(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_names(uc_vm_t *vm, size_t nargs);
uc_value_t *uc_dm_path_known(uc_vm_t *vm, size_t nargs);

#endif /* UBBF_DM_PRIV_H */
