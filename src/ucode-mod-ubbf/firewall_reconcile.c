/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The firewall reconcile: the `firewall` hooks of the model entries claim
 * Device.Firewall.Service, InterfaceSetting and Policy rows, which the
 * reconcile adds, adopts or removes, and every Firewall.Level gets a Chain
 * of its own.
 */

#include <inttypes.h>

#include "ubbf.h"
#include "bindings.h"

struct fw_table {
	const char *name;
	const char *schema;
	bool (*matches)(uc_value_t *existing, uc_value_t *claim);
};

static bool
field_equal(uc_value_t *a, uc_value_t *b, const char *key, const char *absent)
{
	uc_value_t *va = ucv_object_get(a, key, NULL);
	uc_value_t *vb = ucv_object_get(b, key, NULL);
	uc_value_t *def = absent ? ucv_string_new(absent) : NULL;
	bool eq = loose_equal(va ? va : def, vb ? vb : def);

	ucv_put(def);

	return eq;
}

static bool
service_matches(uc_value_t *existing, uc_value_t *claim)
{
	return field_equal(existing, claim, "Interface", NULL) &&
	       field_equal(existing, claim, "Protocol", NULL) &&
	       field_equal(existing, claim, "DestPort", NULL) &&
	       field_equal(existing, claim, "IPVersion", "-1") &&
	       field_equal(existing, claim, "SourcePrefixes", "");
}

static bool
interface_setting_matches(uc_value_t *existing, uc_value_t *claim)
{
	return field_equal(existing, claim, "Interface", NULL);
}

static bool
policy_matches(uc_value_t *existing, uc_value_t *claim)
{
	return field_equal(existing, claim, "SourceInterface", NULL) &&
	       field_equal(existing, claim, "DestinationInterface", NULL);
}

static const struct fw_table fw_tables[] = {
	{ "Service", "Firewall.Service", service_matches },
	{ "InterfaceSetting", "Firewall.InterfaceSetting", interface_setting_matches },
	{ "Policy", "Firewall.Policy", policy_matches },
};

/**
 * Reports whether an Alias comes from a firewall hook: "cpe-" and a
 * lower-case letter, such as cpe-ssh-22. The default Alias of a row that a
 * controller adds is "cpe-" and the table name, which starts with an
 * upper-case letter (uc_dm_object_add() in dm_set.c), so such a row stays.
 */
static bool
alias_is_hook(uc_value_t *alias)
{
	const char *s;

	if (ucv_type(alias) != UC_STRING)
		return false;

	s = ucv_string_get(alias);

	return !strncmp(s, "cpe-", 4) && s[4] >= 'a' && s[4] <= 'z';
}

static const struct fw_table *
fw_table_find(uc_value_t *type)
{
	if (ucv_type(type) != UC_STRING)
		return NULL;

	for (size_t i = 0; i < ARRAY_SIZE(fw_tables); i++)
		if (!strcmp(ucv_string_get(type), fw_tables[i].name))
			return &fw_tables[i];

	return NULL;
}

/**
 * Adds the descriptors that one hook call returned to the claims of their
 * tables. A descriptor needs a known `type` and an `alias`.
 */
static void
descriptors_add(uc_value_t *claims, uc_value_t *descriptors)
{
	const struct fw_table *table;
	uc_value_t *desc;

	if (ucv_type(descriptors) != UC_ARRAY)
		return;

	for (size_t i = 0; i < ucv_array_length(descriptors); i++) {
		desc = ucv_array_get(descriptors, i);
		table = fw_table_find(ucv_object_get(desc, "type", NULL));

		if (!table || !ucv_is_truish(ucv_object_get(desc, "alias", NULL)))
			continue;

		ucv_array_push(ucv_object_get(claims, table->name, NULL), ucv_get(desc));
	}
}

/**
 * Calls the `firewall` hook of a model entry for each of its instances.
 * A singleton absent from the config still carries its schema defaults,
 * so its hook runs with an empty object.
 *
 * @return  false when a hook raised an exception
 */
static bool
entry_claims_collect(uc_vm_t *vm, uc_value_t *claims, const char *pattern,
		     uc_value_t *hook, uc_value_t *data)
{
	uc_value_t *parts = path_parts_new(vm, pattern);
	uc_value_t *paths = ucv_array_new(vm);
	uc_value_t *path, *inst, *descriptors;
	bool ok = true;

	if (parts)
		instances_collect(paths, parts, data, 0, "", vm);

	for (size_t i = 0; ok && i < ucv_array_length(paths); i++) {
		path = ucv_array_get(paths, i);
		inst = navigate_by_path(vm, data, ucv_string_get(path));
		inst = inst ? ucv_get(inst) : ucv_object_new(vm);

		descriptors = callback_invoke(vm, hook, 3, inst, data, path);
		ok = vm->exception.type == EXCEPTION_NONE;
		if (ok)
			descriptors_add(claims, descriptors);

		ucv_put(descriptors);
		ucv_put(inst);
	}

	ucv_put(paths);
	ucv_put(parts);

	return ok;
}

static uc_value_t *
claims_collect(uc_vm_t *vm, uc_value_t *model, uc_value_t *data)
{
	uc_value_t *claims = ucv_object_new(vm);
	uc_value_t *hook;

	for (size_t i = 0; i < ARRAY_SIZE(fw_tables); i++)
		ucv_object_add(claims, fw_tables[i].name, ucv_array_new(vm));

	ucv_object_foreach(model, pattern, entry) {
		hook = ucv_object_get(entry, "firewall", NULL);
		if (!ucv_is_callable(hook))
			continue;

		if (!entry_claims_collect(vm, claims, pattern, hook, data)) {
			ucv_put(claims);
			return NULL;
		}
	}

	return claims;
}

static void
defaults_fill(uc_value_t *row, uc_value_t *defaults)
{
	bool found;

	ucv_object_foreach(defaults, key, val) {
		ucv_object_get(row, key, &found);
		if (!found)
			ucv_object_add(row, key, ucv_get(val));
	}
}

static uc_value_t *
row_new(uc_vm_t *vm, uc_value_t *defaults)
{
	uc_value_t *row = ucv_object_new(vm);

	ucv_object_foreach(defaults, key, val)
		ucv_object_add(row, key, ucv_get(val));

	return row;
}

/**
 * Finds the first row of a table that covers a claim.
 *
 * @return  the instance key of the row, or NULL
 */
static const char *
claim_row_find(const struct fw_table *table, uc_value_t *container, uc_value_t *claim)
{
	ucv_object_foreach(container, key, row) {
		if (ucv_type(row) != UC_OBJECT || !key_is_instance(key))
			continue;

		if (table->matches(row, claim))
			return key;
	}

	return NULL;
}

static void
claim_row_add(uc_vm_t *vm, uc_value_t *container, uc_value_t *claim,
	      uc_value_t *defaults, uc_value_t *live)
{
	uc_value_t *row = row_new(vm, defaults);
	char key[24];

	ucv_object_add(row, "Alias", ucv_get(ucv_object_get(claim, "alias", NULL)));
	ucv_object_add(row, "Enable", ucv_string_new("true"));

	ucv_object_foreach(claim, attr, val) {
		if (!strcmp(attr, "type") || !strcmp(attr, "alias"))
			continue;
		ucv_object_add(row, attr, ucv_get(val));
	}

	snprintf(key, sizeof(key), "%" PRId64, instance_next_free(container));
	ucv_object_add(container, key, row);
	ucv_object_add(live, key, ucv_boolean_new(true));
}

/**
 * Reconciles one Device.Firewall table against its claims. Claims match
 * rows by content, so the sweep of stale rows keys on the rows that the
 * claims took: hook aliases are not unique (two services can share one
 * alias), and an alias-keyed sweep would both keep orphaned rows and
 * delete rows whose alias scheme changed.
 */
static void
table_reconcile(uc_vm_t *vm, uc_value_t *firewall, const struct fw_table *table,
		uc_value_t *claims)
{
	uc_value_t *container = object_child_make(vm, firewall, table->name);
	uc_value_t *defaults = schema_defaults_new(vm, table->schema);
	uc_value_t *live = ucv_object_new(vm);
	uc_value_t *stale = ucv_array_new(vm);
	uc_value_t *claim, *row;
	const char *key;

	for (size_t i = 0; i < ucv_array_length(claims); i++) {
		claim = ucv_array_get(claims, i);
		key = claim_row_find(table, container, claim);

		if (!key) {
			claim_row_add(vm, container, claim, defaults, live);
			continue;
		}

		row = ucv_object_get(container, key, NULL);
		defaults_fill(row, defaults);
		if (alias_is_hook(ucv_object_get(row, "Alias", NULL)))
			ucv_object_add(row, "Alias", ucv_get(ucv_object_get(claim, "alias", NULL)));
		ucv_object_add(live, key, ucv_boolean_new(true));
	}

	ucv_object_foreach(container, k, v) {
		if (ucv_type(v) != UC_OBJECT || !key_is_instance(k) ||
		    !alias_is_hook(ucv_object_get(v, "Alias", NULL)) ||
		    ucv_object_get(live, k, NULL))
			continue;

		ucv_array_push(stale, ucv_string_new(k));
	}

	for (size_t i = 0; i < ucv_array_length(stale); i++) {
		row = ucv_array_get(stale, i);
		ucv_object_delete(container, ucv_string_get(row));
	}

	entries_count_set(firewall, table->name, container);

	ucv_put(stale);
	ucv_put(live);
	ucv_put(defaults);
}

static bool
level_chain_valid(uc_vm_t *vm, uc_value_t *data, uc_value_t *chain)
{
	char *path;
	size_t len;
	bool valid;

	if (ucv_type(chain) != UC_STRING || !ucv_string_length(chain))
		return false;

	len = ucv_string_length(chain);
	path = xstrdup(ucv_string_get(chain));
	while (len && path[len - 1] == '.')
		path[--len] = '\0';

	valid = ucv_is_truish(navigate_by_path(vm, data, path));
	free(path);

	return valid;
}

/**
 * Gives every Level a Chain of its own. TR-181 has the device create the
 * Chain that the read-only Level.Chain references when the Level is
 * created; a Level whose Chain was deleted gets a new, empty one, so the
 * active Level always has a chain to render.
 */
static void
level_chains_reconcile(uc_vm_t *vm, uc_value_t *firewall, uc_value_t *data)
{
	uc_value_t *levels = ucv_object_get(firewall, "Level", NULL);
	uc_value_t *chains, *defaults, *chain, *name;
	char key[24], *text;

	if (ucv_type(levels) != UC_OBJECT)
		return;

	chains = object_child_make(vm, firewall, "Chain");
	defaults = schema_defaults_new(vm, "Firewall.Chain");

	ucv_object_foreach(levels, lkey, level) {
		if (ucv_type(level) != UC_OBJECT || !key_is_instance(lkey) ||
		    level_chain_valid(vm, data, ucv_object_get(level, "Chain", NULL)))
			continue;

		chain = row_new(vm, defaults);
		ucv_object_add(chain, "Enable", ucv_string_new("true"));

		xasprintf(&text, "cpe-Level%s", lkey);
		ucv_object_add(chain, "Alias", ucv_string_new(text));
		free(text);

		name = ucv_object_get(level, "Name", NULL);
		if (ucv_is_truish(name)) {
			ucv_object_add(chain, "Name", ucv_get(name));
		} else {
			xasprintf(&text, "Level%s", lkey);
			ucv_object_add(chain, "Name", ucv_string_new(text));
			free(text);
		}

		snprintf(key, sizeof(key), "%" PRId64, instance_next_free(chains));
		ucv_object_add(chains, key, chain);

		xasprintf(&text, "Device.Firewall.Chain.%s", key);
		ucv_object_add(level, "Chain", ucv_string_new(text));
		free(text);
	}

	entries_count_set(firewall, "Chain", chains);
	ucv_put(defaults);
}

/**
 * Runs the firewall reconcile on a config tree: the claims of the
 * `firewall` hooks against Device.Firewall.Service, InterfaceSetting and
 * Policy, then a Chain for each Level. An exception of a hook stops the
 * reconcile before any table changes and stays raised.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: model, config root,
 *               which is changed in place)
 * @return       null
 */
uc_value_t *
uc_ubbf_firewall_reconcile(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *model = uc_fn_arg(0);
	uc_value_t *data = uc_fn_arg(1);
	uc_value_t *claims, *firewall;

	if (ucv_type(data) != UC_OBJECT)
		return NULL;

	claims = claims_collect(vm, model, data);
	if (!claims)
		return NULL;

	firewall = object_child_make(vm, object_child_make(vm, data, "Device"), "Firewall");

	for (size_t i = 0; i < ARRAY_SIZE(fw_tables); i++)
		table_reconcile(vm, firewall, &fw_tables[i],
				ucv_object_get(claims, fw_tables[i].name, NULL));

	level_chains_reconcile(vm, firewall, data);

	ucv_put(claims);

	return NULL;
}
