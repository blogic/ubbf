/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The access rules of the web UI roles: /etc/ubbf/acl/<role>.json lists
 * the data model paths a role may read and write, the JSON-RPC methods it
 * may call and the diagnostics it may start.
 *
 * A rule section maps a path pattern to a rule. A pattern matches a path
 * that is at least as long and agrees on every segment, `*` taking any
 * segment; the longest matching pattern wins. A path or pattern with more
 * than PATH_PARTS_MAX segments matches nothing. A rule is `true` (the whole
 * subtree), an array of property names, or `{ properties, filter }`, where
 * the filter is property values that the instance at the first `*` must
 * hold.
 */

#include "ubbf.h"
#include "bindings.h"

#include <errno.h>

#define ACL_DIR		"/etc/ubbf/acl"
#define ACL_CACHE_REG	"ubbf.acl.cache"
#define ACL_ROLE_MAX	32

/**
 * Whether a list holds a string, as ucode's `index(list, s) >= 0`; for a
 * string list this is a substring search.
 */
static bool
list_has(uc_value_t *list, const char *s)
{
	uc_value_t *item;

	if (ucv_type(list) == UC_STRING)
		return strstr(ucv_string_get(list), s) != NULL;

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		item = ucv_array_get(list, i);
		if (ucv_type(item) == UC_STRING && !strcmp(ucv_string_get(item), s))
			return true;
	}

	return false;
}

struct segs {
	char *buf;
	char *part[PATH_PARTS_MAX];
	size_t cnt;
};

/*
 * Splits a path at each dot, keeping empty segments as split() does, so
 * that the rules match as they did in ucode. The caller frees s->buf also
 * when the split fails.
 */
static bool
segs_split(struct segs *s, const char *path)
{
	int cnt;

	s->buf = xstrdup(path);
	cnt = path_split(s->buf, s->part, ARRAY_SIZE(s->part), PATH_SPLIT_KEEP_EMPTY);
	s->cnt = cnt < 0 ? 0 : (size_t)cnt;

	return cnt >= 0;
}

static bool
pattern_match(struct segs *path, const char *pattern, size_t *len)
{
	struct segs pat;
	bool match;

	match = segs_split(&pat, pattern) && path->cnt >= pat.cnt;

	for (size_t i = 0; match && i < pat.cnt; i++)
		match = !strcmp(pat.part[i], "*") || !strcmp(pat.part[i], path->part[i]);

	*len = pat.cnt;
	free(pat.buf);

	return match;
}

struct rule_match {
	const char *pattern;
	uc_value_t *rule;
	size_t len;
};

static bool
rule_find(uc_value_t *section, const char *path, struct rule_match *m)
{
	struct segs segs;
	size_t len;

	m->pattern = NULL;
	m->len = 0;

	if (ucv_type(section) != UC_OBJECT)
		return false;

	if (!segs_split(&segs, path)) {
		free(segs.buf);
		return false;
	}

	ucv_object_foreach(section, pattern, rule) {
		if (!pattern_match(&segs, pattern, &len) || len <= m->len)
			continue;

		m->pattern = pattern;
		m->rule = rule;
		m->len = len;
	}

	free(segs.buf);

	return m->pattern != NULL;
}

/**
 * The instance of a path at the first `*` of a pattern, read from a tree;
 * NULL when the tree does not hold it.
 */
static uc_value_t *
instance_data_get(uc_value_t *tree, const char *path, const char *pattern)
{
	uc_value_t *cur = tree, *rv = NULL;
	struct segs p, pat;
	bool found, p_ok, pat_ok;
	size_t i;

	p_ok = segs_split(&p, path);
	pat_ok = segs_split(&pat, pattern);
	if (!p_ok || !pat_ok)
		goto out;

	for (i = 0; i < pat.cnt && strcmp(pat.part[i], "*"); i++) {
		if (ucv_type(cur) != UC_OBJECT || i >= p.cnt)
			goto out;

		cur = ucv_object_get(cur, p.part[i], &found);
		if (!found)
			goto out;
	}

	if (i < pat.cnt && i < p.cnt && ucv_type(cur) == UC_OBJECT)
		rv = ucv_object_get(cur, p.part[i], NULL);

out:
	free(p.buf);
	free(pat.buf);

	return rv;
}

static bool
filter_check(uc_value_t *inst, uc_value_t *filter)
{
	if (ucv_type(filter) != UC_OBJECT)
		return true;

	ucv_object_foreach(filter, prop, expected) {
		uc_value_t *actual = ucv_type(inst) == UC_OBJECT
			? ucv_object_get(inst, prop, NULL) : NULL;

		if (!loose_equal(actual, expected))
			return false;
	}

	return true;
}

/**
 * The segment of a path right after a pattern, the property that a rule
 * with a property list judges; NULL when the path does not go beyond the
 * pattern or the segment is empty (a key that starts with a dot).
 */
static const char *
property_after(struct segs *path, size_t pattern_len)
{
	if (path->cnt <= pattern_len || !*path->part[pattern_len])
		return NULL;

	return path->part[pattern_len];
}

static bool
acl_check(uc_value_t *section, const char *path, uc_value_t *tree, bool whole_object)
{
	uc_value_t *props, *filter;
	struct rule_match m;
	struct segs segs;
	const char *prop;
	bool ok = false;

	if (!rule_find(section, path, &m))
		return false;

	if (loose_equal(m.rule, ucv_boolean_new(true)))
		return true;

	if (!segs_split(&segs, path)) {
		free(segs.buf);
		return false;
	}

	prop = property_after(&segs, m.len);

	if (ucv_type(m.rule) == UC_ARRAY) {
		ok = prop ? list_has(m.rule, prop) : whole_object;
	} else if (ucv_type(m.rule) == UC_OBJECT) {
		props = ucv_object_get(m.rule, "properties", NULL);
		filter = ucv_object_get(m.rule, "filter", NULL);

		if (ucv_is_truish(props)) {
			ok = !(ucv_is_truish(filter) && ucv_is_truish(tree) &&
			       !filter_check(instance_data_get(tree, path, m.pattern), filter));
			if (ok)
				ok = prop ? list_has(props, prop) : whole_object;
		}
	}

	free(segs.buf);

	return ok;
}

static bool
acl_can_read(uc_value_t *acl, const char *path, uc_value_t *tree)
{
	uc_value_t *read = ucv_object_get(acl, "read", NULL);

	return ucv_is_truish(read) && acl_check(read, path, tree, true);
}

static uc_value_t *
acl_load(uc_vm_t *vm, const char *path)
{
	uc_value_t *cache = registry_get(vm, ACL_CACHE_REG, UC_OBJECT);
	uc_value_t *entry, *acl, *id_val;
	char id[64];

	file_id(path, id, sizeof(id));
	if (!id[0])
		return NULL;

	entry = ucv_object_get(cache, path, NULL);
	id_val = ucv_object_get(entry, "id", NULL);
	if (ucv_type(id_val) == UC_STRING && !strcmp(ucv_string_get(id_val), id))
		return ucv_get(ucv_object_get(entry, "acl", NULL));

	acl = json_file_load(vm, path);
	if (!acl)
		return NULL;

	entry = ucv_object_new(vm);
	ucv_object_add(entry, "id", ucv_string_new(id));
	ucv_object_add(entry, "acl", ucv_get(acl));
	ucv_object_add(cache, path, entry);

	return acl;
}

/**
 * Loads the ACL of a web UI role, /etc/ubbf/acl/<role>.json. The name
 * becomes part of a file path, so only a plain role name is accepted. The
 * caller checks that the role is an enabled Device.Users.Role.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: RoleName of the session)
 * @return       the ACL, or null when there is none
 */
uc_value_t *
uc_ubbf_acl_role_load(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *role = uc_fn_arg(0);
	uc_value_t *acl;
	const char *s;
	char *path;

	if (ucv_type(role) != UC_STRING)
		return NULL;

	s = ucv_string_get(role);
	if (*s < 'a' || *s > 'z' || strlen(s) > ACL_ROLE_MAX ||
	    s[strspn(s, "abcdefghijklmnopqrstuvwxyz0123456789_-")])
		return NULL;

	xasprintf(&path, "%s/%s.json", ACL_DIR, s);
	acl = acl_load(vm, path);
	free(path);

	return acl;
}

static uc_value_t *
list_check(uc_vm_t *vm, size_t nargs, const char *key)
{
	uc_value_t *list = ucv_object_get(uc_fn_arg(0), key, NULL);
	uc_value_t *name = uc_fn_arg(1);

	return ucv_boolean_new(ucv_type(list) == UC_ARRAY && ucv_type(name) == UC_STRING &&
			       list_has(list, ucv_string_get(name)));
}

/**
 * Checks if the ACL permits a web UI diagnostic.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: ACL, diagnostic name such
 *               as IPPing)
 * @return       true when the name is listed in `diagnostics`
 */
uc_value_t *
uc_ubbf_acl_can_diagnose(uc_vm_t *vm, size_t nargs)
{
	return list_check(vm, nargs, "diagnostics");
}

/**
 * Checks if the ACL permits writing a data model path. A rule with a
 * property list grants the listed properties only, not the object.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: ACL, path, optional tree
 *               for the instance filters)
 * @return       true when the write is permitted
 */
uc_value_t *
uc_ubbf_acl_can_write(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *write = ucv_object_get(uc_fn_arg(0), "write", NULL);
	uc_value_t *path = uc_fn_arg(1);

	return ucv_boolean_new(ucv_is_truish(write) && ucv_type(path) == UC_STRING &&
			       acl_check(write, ucv_string_get(path), uc_fn_arg(2), false));
}

/**
 * Checks if the ACL permits adding an instance under an object path: the
 * write rule for any instance of the table, `<path>.*`, must grant the
 * whole instance (`true`), the right a delete of the instance needs. A
 * rule that lists properties, filters instances or names one instance
 * lets a role change rows, not create them.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: ACL, parent object path)
 * @return       true when the add is permitted
 */
uc_value_t *
uc_ubbf_acl_can_add(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *write = ucv_object_get(uc_fn_arg(0), "write", NULL);
	uc_value_t *path = uc_fn_arg(1);
	struct rule_match m;
	char *table;
	bool ok;

	if (ucv_type(path) != UC_STRING)
		return ucv_boolean_new(false);

	xasprintf(&table, "%s.*", ucv_string_get(path));
	ok = rule_find(write, table, &m) && ucv_type(m.rule) == UC_BOOLEAN &&
	     ucv_boolean_get(m.rule);
	free(table);

	return ucv_boolean_new(ok);
}

static bool
object_nonempty(uc_value_t *v)
{
	return ucv_type(v) == UC_OBJECT && ucv_object_length(v) > 0;
}

static bool
has_instance_keys(uc_value_t *obj)
{
	ucv_object_foreach(obj, key, val) {
		(void)val;
		if (key_is_instance(key))
			return true;
	}

	return false;
}

/**
 * Filters a tree by the read rules. An object with instance keys is a
 * table: each instance is checked on its own, with the filter of its
 * rule. A leaf stays when acl_can_read() permits its path.
 */
static uc_value_t *
filter_object(uc_vm_t *vm, uc_value_t *acl, uc_value_t *obj, const char *path,
	      uc_value_t *root)
{
	uc_value_t *read = ucv_object_get(acl, "read", NULL);
	uc_value_t *result, *rows, *filtered;
	struct rule_match m;
	char *child_path, *inst_path;
	bool include;

	if (ucv_type(obj) != UC_OBJECT)
		return ucv_get(obj);

	result = ucv_object_new(vm);

	ucv_object_foreach(obj, key, child) {
		if (*path)
			xasprintf(&child_path, "%s.%s", path, key);
		else
			child_path = xstrdup(key);

		if (ucv_type(child) != UC_OBJECT) {
			if (acl_can_read(acl, child_path, root))
				ucv_object_add(result, key, ucv_get(child));
			free(child_path);
			continue;
		}

		if (!has_instance_keys(child)) {
			filtered = filter_object(vm, acl, child, child_path, root);
			if (object_nonempty(filtered))
				ucv_object_add(result, key, filtered);
			else
				ucv_put(filtered);
			free(child_path);
			continue;
		}

		rows = ucv_object_new(vm);
		ucv_object_foreach(child, inst_key, inst) {
			if (!key_is_instance(inst_key))
				continue;

			xasprintf(&inst_path, "%s.%s", child_path, inst_key);
			include = rule_find(read, inst_path, &m) &&
				  (ucv_type(m.rule) != UC_OBJECT ||
				   !ucv_is_truish(ucv_object_get(m.rule, "filter", NULL)) ||
				   filter_check(inst, ucv_object_get(m.rule, "filter", NULL)));

			if (include) {
				filtered = filter_object(vm, acl, inst, inst_path, root);
				if (object_nonempty(filtered))
					ucv_object_add(rows, inst_key, filtered);
				else
					ucv_put(filtered);
			}

			free(inst_path);
		}

		if (ucv_object_length(rows))
			ucv_object_add(result, key, rows);
		else
			ucv_put(rows);

		free(child_path);
	}

	return result;
}

/**
 * Filters a data tree by the read rules of an ACL.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: ACL, tree, base path of
 *               the tree)
 * @return       the tree with only the permitted properties; an empty
 *               object when the base path has more than
 *               `PATH_PARTS_MAX` segments
 */
uc_value_t *
uc_ubbf_acl_filter_tree(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *acl = uc_fn_arg(0);
	uc_value_t *tree = uc_fn_arg(1);
	uc_value_t *base = uc_fn_arg(2);
	uc_value_t *root, *cur, *next, *rv;
	const char *base_path = ucv_type(base) == UC_STRING ? ucv_string_get(base) : "";
	struct segs segs;

	if (!ucv_is_truish(acl) || !ucv_is_truish(tree))
		return ucv_object_new(vm);

	if (!*base_path)
		return filter_object(vm, acl, tree, base_path, tree);

	/* the instance filters address the tree from the root of the model */
	if (!segs_split(&segs, base_path)) {
		free(segs.buf);
		return ucv_object_new(vm);
	}

	root = cur = ucv_object_new(vm);
	for (size_t i = 0; i + 1 < segs.cnt; i++) {
		next = ucv_object_new(vm);
		ucv_object_add(cur, segs.part[i], next);
		cur = next;
	}
	ucv_object_add(cur, segs.part[segs.cnt - 1], ucv_get(tree));
	free(segs.buf);

	rv = filter_object(vm, acl, tree, base_path, root);
	ucv_put(root);

	return rv;
}

