/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Parameter and object names: names_compute, names and path_known.
 */

#include "dm-priv.h"

/* ---- dm.names_compute -------------------------------------------------- */

/**
 * Sets the derived `Name` of the rows whose model entry has a `name`
 * callback and that have no Name yet. A computed name can feed another
 * entry's callback, so the walk repeats until a pass changes nothing.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       null; an exception of a callback stays raised
 */
uc_value_t *
uc_dm_names_compute(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *model, *data, *parts, *paths, *inst, *name;
	bool changed = true;

	if (!dm)
		return NULL;

	model = dm_model_get(dm);
	data = dm_target_get(dm);

	while (changed) {
		changed = false;

		ucv_object_foreach(model, pattern, entry) {
			uc_value_t *fn = ucv_object_get(entry, "name", NULL);

			if (!ucv_is_callable(fn))
				continue;

			parts = path_parts_new(vm, pattern);
			if (!parts)
				continue;

			paths = ucv_array_new(vm);
			instances_collect(paths, parts, data, 0, "", vm);
			ucv_put(parts);

			for (size_t i = 0; i < ucv_array_length(paths); i++) {
				uc_value_t *p = ucv_array_get(paths, i);

				inst = navigate_by_path(vm, data, ucv_string_get(p));
				if (ucv_type(inst) != UC_OBJECT ||
				    ucv_is_truish(ucv_object_get(inst, "Name", NULL)))
					continue;

				name = callback_invoke(vm, fn, 2, inst, data);
				if (vm->exception.type != EXCEPTION_NONE) {
					ucv_put(paths);
					return NULL;
				}

				if (ucv_is_truish(name)) {
					ucv_object_add(inst, "Name", name);
					changed = true;
				} else {
					ucv_put(name);
				}
			}

			ucv_put(paths);
		}
	}

	return NULL;
}

/* ---- dm.names ---------------------------------------------------------- */

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
	uint32_t type;

	if (!schema_entry_member(ucv_object_get(model, pattern, NULL), name, &type))
		return false;

	return (type & DM_WRITABLE) != 0;
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
	uc_value_t *entry = table_row_entry(model, pattern);

	if (!entry)
		return false;

	/* A table the CPE maintains itself is readable but not addable, and
	 * GetParameterNames reports that as Writable=false. */
	return schema_entry_addable(entry);
}

/**
 * Reports whether a path names something the registered model describes.
 *
 * The test is model membership, not tree membership: TR-069 A.3.2.2 and
 * A.3.2.3 fault 9005 for a name the data model does not define, while an
 * object that is supported but currently empty is a valid, empty answer.
 * subtree_dispatch() cannot make that distinction because it returns an empty
 * object for both.
 *
 * @param model  registered model object
 * @param path   resolved path; a trailing dot asks about an object
 * @return       DM_PATH_NONE, DM_PATH_OBJECT or DM_PATH_PARAM
 */
static int
path_resolves(uc_value_t *model, const char *path)
{
	size_t len = strlen(path);
	char *pattern, *leaf;
	uc_value_t *parent;
	uint32_t type;
	int kind;

	if (!len || !model)
		return DM_PATH_NONE;

	pattern = path_to_pattern(path);
	if (!pattern)
		return DM_PATH_NONE;

	/* An object addressed without its trailing dot still names an object. */
	kind = ucv_object_get(model, pattern, NULL) ? DM_PATH_OBJECT : DM_PATH_NONE;

	leaf = strrchr(pattern, '.');
	if (path[len - 1] != '.' && leaf) {
		*leaf++ = '\0';
		parent = ucv_object_get(model, pattern, NULL);
		if (schema_entry_member(parent, leaf, &type))
			kind = DM_PATH_PARAM;
	}

	free(pattern);

	return kind;
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
 * Reports whether an object pattern is a table.
 *
 * @param model    registered model object
 * @param pattern  schema pattern of the object
 * @return         true when the model describes instances below it
 */
static bool
model_is_table(uc_value_t *model, const char *pattern)
{
	return table_row_entry(model, pattern) != NULL;
}

/**
 * Indexes the model by parent pattern.
 *
 * @param vm     ucode VM context
 * @param model  registered model object
 * @return       new object mapping a pattern to the array of its child
 *               object names; instance levels are left out
 */
static uc_value_t *
model_children_index(uc_vm_t *vm, uc_value_t *model)
{
	uc_value_t *index = ucv_object_new(vm);
	char *parent;

	ucv_object_foreach(model, pattern, entry) {
		const char *dot = pattern ? strrchr(pattern, '.') : NULL;
		size_t len = dot ? (size_t)(dot - pattern) : 0;
		uc_value_t *list;

		if (!dot || ucv_type(entry) != UC_OBJECT)
			continue;

		if (!strcmp(dot + 1, "{i}"))
			continue;

		parent = xalloc(len + 1);
		memcpy(parent, pattern, len);

		list = ucv_object_get(index, parent, NULL);
		if (!list) {
			list = ucv_array_new(vm);
			ucv_object_add(index, parent, list);
		}

		ucv_array_push(list, ucv_string_new(dot + 1));
		free(parent);
	}

	return index;
}

/**
 * Adds the names the model defines below a node and the hydrated tree lacks.
 *
 * The tree holds only what the stored configuration and the get handlers
 * produced: a table without rows and an object with neither have no node.
 * GetParameterNames answers from the supported data model (TR-069 A.3.2.3),
 * so a controller must see them to know it can add a row.
 *
 * @param vm        ucode VM context
 * @param model     registered model object
 * @param children  index from model_children_index()
 * @param node      hydrated node, or NULL for an object the tree lacks
 * @param prefix    resolved path of the node, including its trailing dot
 * @param pattern   schema pattern of the node, without a trailing dot
 * @param depth     remaining recursion budget
 * @param out       destination array
 */
static void
names_model_add(uc_vm_t *vm, uc_value_t *model, uc_value_t *children,
		uc_value_t *node, const char *prefix, const char *pattern,
		int depth, uc_value_t *out)
{
	uc_value_t *params, *list, *item;
	char *full, *sub;
	const char *name;
	bool found;

	if (depth <= 0 || model_is_table(model, pattern))
		return;

	params = schema_entry_params(vm, ucv_object_get(model, pattern, NULL));

	for (size_t i = 0; i < ucv_array_length(params); i++) {
		item = ucv_array_get(params, i);
		name = ucv_string_get(item);

		ucv_object_get(node, name, &found);
		if (found)
			continue;

		xasprintf(&full, "%s%s", prefix, name);
		names_collect(vm, out, full,
			      model_param_writable(model, pattern, name));
		free(full);
	}

	ucv_put(params);

	list = ucv_object_get(children, pattern, NULL);

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		item = ucv_array_get(list, i);
		name = ucv_string_get(item);

		ucv_object_get(node, name, &found);
		if (found)
			continue;

		xasprintf(&sub, "%s.%s", pattern, name);
		xasprintf(&full, "%s%s.", prefix, name);

		names_collect(vm, out, full, model_object_addable(model, sub));
		names_model_add(vm, model, children, NULL, full, sub,
				depth - 1, out);

		free(sub);
		free(full);
	}
}

/**
 * Walks a hydrated subtree emitting a name per object and parameter.
 *
 * The schema pattern is carried down instead of being rebuilt from each
 * resolved path: every child of an object shares its parent's pattern, so
 * deriving it per row would repeat a split and a join for every parameter in
 * the model.
 *
 * @param vm        ucode VM context
 * @param model     registered model object
 * @param children  index from model_children_index()
 * @param node      subtree node being walked
 * @param prefix    resolved path of the node, including its trailing dot
 * @param pattern   schema pattern of the node, without a trailing dot
 * @param depth     remaining recursion budget
 * @param out       destination array
 */
static void
names_walk(uc_vm_t *vm, uc_value_t *model, uc_value_t *children,
	   uc_value_t *node, const char *prefix, const char *pattern,
	   int depth, uc_value_t *out)
{
	char *full, *sub;

	if (depth <= 0)
		return;

	ucv_object_foreach(node, key, val) {
		/* Keys opening with a dot are the tree's own metadata. */
		if (!key || key[0] == '.')
			continue;

		if (ucv_type(val) != UC_OBJECT) {
			xasprintf(&full, "%s%s", prefix, key);
			names_collect(vm, out, full,
				      model_param_writable(model, pattern, key));
			free(full);
			continue;
		}

		xasprintf(&sub, "%s.%s", pattern, key_is_instance(key) ? "{i}" : key);
		xasprintf(&full, "%s%s.", prefix, key);

		names_collect(vm, out, full,
			      model_object_addable(model, sub));

		names_walk(vm, model, children, val, full, sub, depth - 1, out);

		free(sub);
		free(full);
	}

	names_model_add(vm, model, children, node, prefix, pattern, depth, out);
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
uc_value_t *
uc_dm_names(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);
	uc_value_t *next_val = uc_fn_arg(1);
	uc_value_t *subtree, *model, *children, *out;
	const char *path;
	char *pattern;
	size_t len;

	if (!dm || ucv_type(path_val) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_val);
	len = strlen(path);

	if (!len || path[len - 1] != '.')
		return NULL;

	model = dm_model_get(dm);
	if (path_resolves(model, path) != DM_PATH_OBJECT)
		return NULL;

	subtree = subtree_dispatch(vm, dm, path, NULL);
	if (ucv_type(subtree) != UC_OBJECT) {
		ucv_put(subtree);
		return NULL;
	}

	pattern = path_to_pattern(path);
	if (!pattern) {
		ucv_put(subtree);
		return NULL;
	}

	out = ucv_array_new(vm);
	children = model_children_index(vm, model);

	/* A.3.2.3: with NextLevel the answer is the next-level children alone,
	 * and the queried object itself belongs only to the full walk. */
	if (ucv_is_truish(next_val)) {
		names_walk(vm, model, children, subtree, path, pattern, 1, out);
	}
	else {
		names_collect(vm, out, path, model_object_addable(model, pattern));
		names_walk(vm, model, children, subtree, path, pattern, 32, out);
	}

	ucv_put(children);
	ucv_put(subtree);
	free(pattern);

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
uc_value_t *
uc_dm_path_known(uc_vm_t *vm, size_t nargs)
{
	ubbf_dm_t *dm = uc_fn_thisval("ubbf.dm");
	uc_value_t *path_val = uc_fn_arg(0);

	if (!dm || ucv_type(path_val) != UC_STRING)
		return ucv_int64_new(DM_PATH_NONE);

	return ucv_int64_new(path_resolves(dm_model_get(dm),
					   ucv_string_get(path_val)));
}
