/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include "schema-table.h"

#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <glob.h>
#include <inttypes.h>

#define SCHEMA_TABLE_GLOB	"/usr/lib/ubbf/schema-*.so"
#define SCHEMA_TABLE_CORE	"core"

enum {
	SCHEMA_PROTO_USP,
	SCHEMA_PROTO_CWMP,
	SCHEMA_PROTO_BOTH,
	SCHEMA_PROTO_ANY,
};

enum {
	SCHEMA_KIND_PARAM,
	SCHEMA_KIND_COMMAND,
};

/* One opened schema-*.so. The pointers lead into its read-only pages; the
 * library is never closed, so they stay valid for the life of the process. */
struct schema_table {
	char *name;
	const char *pool;
	const struct schema_object *objects;
	uint32_t object_count;
	const struct schema_member *members;
	const struct schema_default *defaults;
	const struct schema_rule *rules;
	const struct schema_range *ranges;
	const uint32_t *enums;
};

/* A schema object and the table whose pool its offsets point into. */
struct schema_ref {
	const struct schema_table *table;
	const struct schema_object *obj;
};

static struct schema_table *schema_tables;
static size_t schema_table_count;
static bool schema_tables_scanned;

static int schema_protocol = SCHEMA_PROTO_USP;

/* TR-181 minor number of the active version; 0 until datamodel.uc sets it,
 * which keeps every member, so a user of the tables that never selects a
 * version sees all of them. */
static unsigned int schema_minor;

/**
 * Finds an opened schema table by name.
 *
 * @param name  table name, not necessarily NUL-terminated
 * @param len   length of the name
 * @return      the table, or NULL when none of that name is open
 */
static const struct schema_table *
schema_table_find(const char *name, size_t len)
{
	for (size_t i = 0; i < schema_table_count; i++) {
		const char *n = schema_tables[i].name;

		if (strlen(n) == len && !strncmp(n, name, len))
			return &schema_tables[i];
	}

	return NULL;
}

/**
 * Looks up one symbol of a schema table library.
 *
 * @param dl    library handle
 * @param path  library path, for the error message
 * @param name  symbol name
 * @return      the symbol address, or NULL when the library lacks it
 */
static const void *
table_symbol(void *dl, const char *path, const char *name)
{
	const void *sym = dlsym(dl, name);

	if (!sym)
		fprintf(stderr, "ubbf: schema table %s has no %s\n", path, name);

	return sym;
}

/**
 * Opens one schema-*.so and adds its table under a name.
 *
 * @param path  library path
 * @param name  table name
 * @return      true when the table was added
 */
static bool
schema_table_open(const char *path, const char *name)
{
	const uint32_t *abi, *object_count;
	struct schema_table t = { 0 };
	void *dl = dlopen(path, RTLD_NOW | RTLD_LOCAL);

	if (!dl) {
		fprintf(stderr, "ubbf: schema table %s: %s\n", path, dlerror());
		return false;
	}

	abi = table_symbol(dl, path, "ubbf_schema_abi");
	if (abi && *abi != SCHEMA_TABLE_ABI)
		fprintf(stderr, "ubbf: schema table %s has ABI %u, ubbf.so reads %u\n",
			path, (unsigned int)*abi, (unsigned int)SCHEMA_TABLE_ABI);

	t.pool = table_symbol(dl, path, "ubbf_schema_pool");
	t.objects = table_symbol(dl, path, "ubbf_schema_objects");
	object_count = table_symbol(dl, path, "ubbf_schema_object_count");
	t.members = table_symbol(dl, path, "ubbf_schema_members");
	t.defaults = table_symbol(dl, path, "ubbf_schema_defaults");
	t.rules = table_symbol(dl, path, "ubbf_schema_rules");
	t.ranges = table_symbol(dl, path, "ubbf_schema_ranges");
	t.enums = table_symbol(dl, path, "ubbf_schema_enums");

	if (!abi || *abi != SCHEMA_TABLE_ABI || !t.pool || !t.objects ||
	    !object_count || !t.members || !t.defaults || !t.rules ||
	    !t.ranges || !t.enums) {
		dlclose(dl);
		return false;
	}

	t.name = xstrdup(name);
	t.object_count = *object_count;

	schema_tables = xrealloc(schema_tables,
				 (schema_table_count + 1) * sizeof(*schema_tables));
	schema_tables[schema_table_count++] = t;

	return true;
}

/**
 * Derives the table name from a library path: "core" from
 * ".../schema-core.so".
 *
 * @param path  library path
 * @return      newly allocated name, or NULL for a path of another form
 */
static char *
table_name_get(const char *path)
{
	const char *base = strrchr(path, '/');
	size_t len;

	base = base ? base + 1 : path;
	len = strlen(base);

	if (len <= strlen("schema-.so") || strncmp(base, "schema-", strlen("schema-")) ||
	    strcmp(base + len - strlen(".so"), ".so"))
		return NULL;

	return strndup(base + strlen("schema-"), len - strlen("schema-.so"));
}

/**
 * Opens the schema tables that a glob pattern matches, in name order.
 *
 * A table whose name is already open is skipped, so the first pattern that
 * provides a name wins.
 *
 * @param pattern  glob pattern of schema-*.so files
 * @param loaded   array that receives the names of the tables opened, or NULL
 */
static void
schema_tables_glob(const char *pattern, uc_value_t *loaded)
{
	glob_t gl;
	int rv = glob(pattern, 0, NULL, &gl);

	for (size_t i = 0; rv == 0 && i < gl.gl_pathc; i++) {
		char *name = table_name_get(gl.gl_pathv[i]);

		if (name && !schema_table_find(name, strlen(name)) &&
		    schema_table_open(gl.gl_pathv[i], name) && loaded)
			ucv_array_push(loaded, ucv_string_new(name));

		free(name);
	}

	globfree(&gl);
}

/**
 * Opens the installed schema tables on first use.
 */
static void
schema_tables_init(void)
{
	if (schema_tables_scanned)
		return;

	schema_tables_scanned = true;
	schema_tables_glob(SCHEMA_TABLE_GLOB, NULL);
}

/**
 * Returns the core table.
 *
 * @return  the table of the schemas/ directory, or NULL when ubbf runs
 *          without tables
 */
static const struct schema_table *
schema_core_table(void)
{
	schema_tables_init();

	return schema_table_find(SCHEMA_TABLE_CORE, strlen(SCHEMA_TABLE_CORE));
}

/**
 * Binary search over the sorted records of a table.
 *
 * @param pool     string pool of the table
 * @param records  first record
 * @param count    number of records
 * @param size     size of one record
 * @param key      name to find
 * @return         the record whose key equals `key`, or NULL
 */
static const void *
table_record_find(const char *pool, const void *records, uint32_t count,
		  size_t size, const char *key)
{
	uint32_t lo = 0, hi = count;

	while (lo < hi) {
		uint32_t mid = lo + (hi - lo) / 2;
		const void *rec = (const char *)records + mid * size;
		int cmp = strcmp(key, pool + *(const uint32_t *)rec);

		if (!cmp)
			return rec;

		if (cmp < 0)
			hi = mid;
		else
			lo = mid + 1;
	}

	return NULL;
}

/**
 * Looks up a schema object by name.
 *
 * A `<module>.<Key>` name lives in the table of that module, a
 * `<Module>.<Export>` name in the core table.
 *
 * @param id   schema name
 * @param ref  receives the object and its table
 * @return     true when a table has the name
 */
static bool
schema_object_find(const char *id, struct schema_ref *ref)
{
	const char *dot = strchr(id, '.');
	const struct schema_table *t;

	schema_tables_init();

	t = dot ? schema_table_find(id, dot - id) : NULL;
	if (!t)
		t = schema_core_table();
	if (!t)
		return false;

	ref->table = t;
	ref->obj = table_record_find(t->pool, t->objects, t->object_count,
				     sizeof(*t->objects), id);

	return ref->obj != NULL;
}

static const char *
ref_str(const struct schema_ref *ref, uint32_t off)
{
	return ref->table->pool + off;
}

static const struct schema_member *
ref_member(const struct schema_ref *ref, uint32_t i)
{
	return &ref->table->members[ref->obj->member_first + i];
}

static const struct schema_default *
ref_default(const struct schema_ref *ref, uint32_t i)
{
	return &ref->table->defaults[ref->obj->default_first + i];
}

/**
 * Reports whether a member exists in the active TR-181 version.
 *
 * Same rule as tag_visible() in utils/dm-version.uc.
 *
 * @param m  schema member
 * @return   true when no version is selected or the member exists in it
 */
static bool
member_version_ok(const struct schema_member *m)
{
	if (!schema_minor)
		return true;

	if (m->since && schema_minor < m->since)
		return false;

	return !m->until || schema_minor < m->until;
}

/**
 * Reports whether a member belongs to the active management protocol and
 * the active TR-181 version.
 *
 * Parameters serve both protocols; commands and events default to USP.
 *
 * @param m  schema member
 * @return   true when the member is part of the active data model
 */
static bool
member_visible(const struct schema_member *m)
{
	if (!member_version_ok(m))
		return false;

	return m->proto == SCHEMA_PROTO_ANY || m->proto == SCHEMA_PROTO_BOTH ||
	       m->proto == schema_protocol;
}

/**
 * Finds a visible member of a schema object by name.
 *
 * @param ref   schema object
 * @param name  member name
 * @return      the member, or NULL when absent, bound to the other protocol,
 *              or not in the active version
 */
static const struct schema_member *
object_member_find(const struct schema_ref *ref, const char *name)
{
	for (uint32_t i = 0; i < ref->obj->member_count; i++) {
		const struct schema_member *m = ref_member(ref, i);

		if (strcmp(ref_str(ref, m->name), name))
			continue;

		return member_visible(m) ? m : NULL;
	}

	return NULL;
}

/**
 * Reports whether the active protocol or version hides any member of an
 * object.
 *
 * A projected object also drops the defaults of the hidden members, so the
 * tree never materialises a key the schema no longer advertises.
 *
 * @param ref  schema object
 * @return     true when at least one member is hidden
 */
static bool
object_projected(const struct schema_ref *ref)
{
	for (uint32_t i = 0; i < ref->obj->member_count; i++)
		if (!member_visible(ref_member(ref, i)))
			return true;

	return false;
}

/**
 * Finds the default value of a member of a schema object.
 *
 * @param ref        schema object
 * @param name       member name
 * @param projected  result of `object_projected(ref)`
 * @return           the default string, or NULL when there is none
 */
static const char *
object_default_find(const struct schema_ref *ref, const char *name,
		    bool projected)
{
	for (uint32_t i = 0; i < ref->obj->default_count; i++) {
		const struct schema_default *d = ref_default(ref, i);

		if (strcmp(ref_str(ref, d->name), name))
			continue;

		if (projected && !object_member_find(ref, name))
			return NULL;

		return ref_str(ref, d->value);
	}

	return NULL;
}

/**
 * Builds the defaults object of a schema object.
 *
 * @param vm   ucode VM context
 * @param ref  schema object
 * @return     new object mapping member name to default string
 */
static uc_value_t *
object_defaults_new(uc_vm_t *vm, const struct schema_ref *ref)
{
	bool projected = object_projected(ref);
	uc_value_t *out = ucv_object_new(vm);

	for (uint32_t i = 0; i < ref->obj->default_count; i++) {
		const struct schema_default *d = ref_default(ref, i);
		const char *name = ref_str(ref, d->name);

		if (projected && !object_member_find(ref, name))
			continue;

		ucv_object_add(out, name, ucv_string_new(ref_str(ref, d->value)));
	}

	return out;
}

/**
 * Parses a JSON text from the string pool of a table.
 *
 * @param vm    ucode VM context
 * @param pool  string pool
 * @param off   pool offset of the text, or SCHEMA_NONE
 * @return      new value, or NULL for SCHEMA_NONE
 */
static uc_value_t *
json_value_parse(uc_vm_t *vm, const char *pool, uint32_t off)
{
	struct json_object *jso;
	uc_value_t *val;

	if (off == SCHEMA_NONE)
		return NULL;

	jso = json_tokener_parse(pool + off);
	if (!jso)
		return NULL;

	val = ucv_from_json(vm, jso);
	json_object_put(jso);

	return val;
}

/**
 * Names the type bits of a parameter the way the USP core spells them.
 *
 * @param type  parameter type bits, with or without the writable flag
 * @return      new string such as "DM_UINT"; "DM_STRING" for unknown bits
 */
static uc_value_t *
type_name_new(uint32_t type)
{
	char buf[32];
	uint32_t bits = type & ~DM_WRITABLE;

	for (size_t i = 0; i < dm_type_vals_count; i++) {
		if (dm_type_vals[i].value != bits || dm_type_vals[i].value == DM_WRITABLE)
			continue;

		snprintf(buf, sizeof(buf), "DM_%s", dm_type_vals[i].name);
		return ucv_string_new(buf);
	}

	return ucv_string_new("DM_STRING");
}

/**
 * Resolves the schema of a model entry.
 *
 * An entry names its schema as a string when a table describes it, and
 * carries the schema object itself otherwise; that object is handed back
 * through `legacy`.
 *
 * @param entry   model entry
 * @param legacy  receives the schema object of an entry without a table
 * @param ref     receives the table object
 * @return        true for a table object, false for an object schema or none
 */
static bool
entry_object(uc_value_t *entry, uc_value_t **legacy, struct schema_ref *ref)
{
	uc_value_t *schema = ucv_type(entry) == UC_OBJECT
		? ucv_object_get(entry, "schema", NULL) : NULL;

	*legacy = NULL;

	if (ucv_type(schema) == UC_STRING)
		return schema_object_find(ucv_string_get(schema), ref);

	if (ucv_type(schema) == UC_OBJECT)
		*legacy = schema;

	return false;
}

/**
 * Returns the defaults of a model entry's schema.
 *
 * @param vm     ucode VM context
 * @param entry  model entry
 * @return       new reference to the defaults object, or NULL when the entry
 *               has none
 */
uc_value_t *
schema_entry_defaults(uc_vm_t *vm, uc_value_t *entry)
{
	uc_value_t *legacy, *defaults;
	struct schema_ref ref;

	if (entry_object(entry, &legacy, &ref))
		return object_defaults_new(vm, &ref);

	defaults = legacy ? ucv_object_get(legacy, "defaults", NULL) : NULL;

	return ucv_type(defaults) == UC_OBJECT ? ucv_get(defaults) : NULL;
}

/**
 * Returns the default of one parameter of a model entry's schema.
 *
 * @param vm     ucode VM context
 * @param entry  model entry
 * @param name   parameter name
 * @return       new reference to the default, or NULL when there is none
 */
uc_value_t *
schema_entry_default(uc_vm_t *vm, uc_value_t *entry, const char *name)
{
	uc_value_t *legacy, *defaults;
	struct schema_ref ref;
	const char *def;

	if (entry_object(entry, &legacy, &ref)) {
		def = object_default_find(&ref, name, object_projected(&ref));
		return def ? ucv_string_new(def) : NULL;
	}

	defaults = legacy ? ucv_object_get(legacy, "defaults", NULL) : NULL;

	return ucv_get(ucv_object_get(defaults, name, NULL));
}

/**
 * Looks up a member of a model entry's schema.
 *
 * @param entry  model entry
 * @param name   member name
 * @param type   receives the type bits of a parameter, 0 for a command or
 *               an event
 * @return       true when the schema describes the member
 */
bool
schema_entry_member(uc_value_t *entry, const char *name, uint32_t *type)
{
	uc_value_t *legacy, *members, *val;
	const struct schema_member *m;
	struct schema_ref ref;

	if (entry_object(entry, &legacy, &ref)) {
		m = object_member_find(&ref, name);
		if (!m)
			return false;

		*type = m->type;
		return true;
	}

	members = legacy ? ucv_object_get(legacy, "schema", NULL) : NULL;
	val = ucv_object_get(members, name, NULL);
	if (!val)
		return false;

	*type = ucv_type(val) == UC_INTEGER ? (uint32_t)ucv_int64_get(val) : 0;
	return true;
}

/**
 * Reports whether a model entry's schema declares a member that the active
 * protocol or version hides.
 *
 * Only a table knows this: an object schema has its hidden members removed
 * by datamodel.uc.
 *
 * @param entry  model entry
 * @param name   member name
 * @return       true when the table has the member and does not show it
 */
bool
schema_entry_hidden(uc_value_t *entry, const char *name)
{
	uc_value_t *legacy;
	struct schema_ref ref;

	if (!entry_object(entry, &legacy, &ref))
		return false;

	for (uint32_t i = 0; i < ref.obj->member_count; i++) {
		const struct schema_member *m = ref_member(&ref, i);

		if (!strcmp(ref_str(&ref, m->name), name))
			return !member_visible(m);
	}

	return false;
}

/**
 * Lists the parameters of a model entry's schema.
 *
 * @param vm     ucode VM context
 * @param entry  model entry
 * @return       new array of the parameter names the active protocol sees;
 *               commands and events are left out
 */
uc_value_t *
schema_entry_params(uc_vm_t *vm, uc_value_t *entry)
{
	uc_value_t *legacy, *members, *out = ucv_array_new(vm);
	struct schema_ref ref;

	if (entry_object(entry, &legacy, &ref)) {
		for (uint32_t i = 0; i < ref.obj->member_count; i++) {
			const struct schema_member *m = ref_member(&ref, i);

			if (m->kind != SCHEMA_KIND_PARAM || !member_visible(m))
				continue;

			ucv_array_push(out, ucv_string_new(ref_str(&ref, m->name)));
		}

		return out;
	}

	members = legacy ? ucv_object_get(legacy, "schema", NULL) : NULL;
	if (ucv_type(members) != UC_OBJECT)
		return out;

	ucv_object_foreach(members, name, val)
		if (ucv_type(val) == UC_INTEGER)
			ucv_array_push(out, ucv_string_new(name));

	return out;
}

/* One rule in the shape the check reads, filled from a table record or from
 * the `constraints` of an object schema. An object schema has no pool, so its
 * enumeration stays a ucode array and its ranges live in `owned`. */
struct value_rule {
	struct schema_rule r;
	uint32_t type;
	const struct schema_range *ranges;
	const struct schema_range *lengths;
	const char *pool;
	const uint32_t *enums;
	uc_value_t *enum_list;
	struct schema_range *owned;
};

static void
rule_from_table(struct value_rule *vr, const struct schema_ref *ref,
		const struct schema_member *m)
{
	const struct schema_table *t = ref->table;

	vr->type = m->type;

	if (m->info == SCHEMA_NONE)
		return;

	vr->r = t->rules[m->info];
	vr->ranges = &t->ranges[vr->r.range_first];
	vr->lengths = &t->ranges[vr->r.length_first];
	vr->pool = t->pool;
	vr->enums = &t->enums[vr->r.enum_first];
}

static uint16_t
ranges_read(uc_value_t *list, struct schema_range *out)
{
	uint16_t n = 0;

	for (size_t i = 0; i < ucv_array_length(list) && n < UINT16_MAX; i++) {
		uc_value_t *lo = ucv_array_get(ucv_array_get(list, i), 0);
		uc_value_t *hi = ucv_array_get(ucv_array_get(list, i), 1);

		out[n].lo = ucv_type(lo) == UC_INTEGER ? ucv_int64_get(lo) : INT64_MIN;
		out[n].hi = ucv_type(hi) == UC_INTEGER ? ucv_int64_get(hi) : INT64_MAX;
		n++;
	}

	return n;
}

static void
rule_int_read(uc_value_t *facts, const char *key, uint16_t flag,
	      struct schema_rule *r, int64_t *out)
{
	uc_value_t *v = ucv_object_get(facts, key, NULL);

	if (ucv_type(v) != UC_INTEGER)
		return;

	*out = ucv_int64_get(v);
	r->flags |= flag;
}

static void
rule_length_read(uc_value_t *facts, const char *key, uint16_t flag,
		 struct schema_rule *r, uint32_t *out)
{
	int64_t n = 0;

	rule_int_read(facts, key, flag, r, &n);
	*out = n < 0 ? 0 : n > UINT32_MAX ? UINT32_MAX : (uint32_t)n;
}

static void
rule_from_object(struct value_rule *vr, uc_value_t *def, const char *name,
		 uint32_t type)
{
	uc_value_t *facts = ucv_object_get(ucv_object_get(def, "constraints", NULL), name, NULL);
	uc_value_t *ranges, *lengths, *list;
	struct schema_rule *r = &vr->r;

	vr->type = type;

	if (ucv_type(facts) != UC_OBJECT)
		return;

	rule_int_read(facts, "min", SCHEMA_RULE_MIN, r, &r->min);
	rule_int_read(facts, "max", SCHEMA_RULE_MAX, r, &r->max);
	rule_length_read(facts, "min_length", SCHEMA_RULE_MIN_LENGTH, r, &r->min_length);
	rule_length_read(facts, "max_length", SCHEMA_RULE_MAX_LENGTH, r, &r->max_length);
	rule_length_read(facts, "list_min_length", SCHEMA_RULE_LIST_MIN_LENGTH, r,
			 &r->list_min_length);
	rule_length_read(facts, "list_max_length", SCHEMA_RULE_LIST_MAX_LENGTH, r,
			 &r->list_max_length);

	if (ucv_is_truish(ucv_object_get(facts, "list", NULL)))
		r->flags |= SCHEMA_RULE_LIST;

	list = ucv_object_get(facts, "enum", NULL);
	if (ucv_type(list) == UC_ARRAY) {
		vr->enum_list = list;
		r->enum_count = ucv_array_length(list);
	}

	ranges = ucv_object_get(facts, "ranges", NULL);
	lengths = ucv_object_get(facts, "lengths", NULL);
	if (ucv_type(ranges) != UC_ARRAY)
		ranges = NULL;
	if (ucv_type(lengths) != UC_ARRAY)
		lengths = NULL;
	if (!ranges && !lengths)
		return;

	vr->owned = xalloc((ucv_array_length(ranges) + ucv_array_length(lengths) + 1) *
			   sizeof(*vr->owned));
	vr->ranges = vr->owned;
	r->range_count = ranges_read(ranges, vr->owned);
	vr->lengths = vr->owned + r->range_count;
	r->length_count = ranges_read(lengths, vr->owned + r->range_count);
}

/**
 * Reads the rule of a parameter of a model entry's schema.
 *
 * @param entry  model entry
 * @param name   parameter name
 * @param vr     receives the rule; free `vr->owned` after use
 * @return       false when the schema does not describe a visible parameter
 *               of that name
 */
static bool
entry_rule(uc_value_t *entry, const char *name, struct value_rule *vr)
{
	const struct schema_member *m;
	uc_value_t *legacy, *val;
	struct schema_ref ref;

	memset(vr, 0, sizeof(*vr));

	if (entry_object(entry, &legacy, &ref)) {
		m = object_member_find(&ref, name);
		if (!m || m->kind != SCHEMA_KIND_PARAM)
			return false;

		rule_from_table(vr, &ref, m);
		return true;
	}

	val = ucv_object_get(ucv_object_get(legacy, "schema", NULL), name, NULL);
	if (ucv_type(val) != UC_INTEGER)
		return false;

	rule_from_object(vr, legacy, name, (uint32_t)ucv_int64_get(val));
	return true;
}

static bool
ranges_hold(const struct schema_range *ranges, uint16_t count, int64_t n)
{
	for (uint16_t i = 0; i < count; i++)
		if (n >= ranges[i].lo && n <= ranges[i].hi)
			return true;

	return false;
}

static bool
enum_has(const struct value_rule *vr, const char *s)
{
	for (uint16_t i = 0; i < vr->r.enum_count; i++) {
		uc_value_t *item = vr->enum_list ? ucv_array_get(vr->enum_list, i) : NULL;
		const char *e = vr->enum_list ? ucv_string_get(item) : vr->pool + vr->enums[i];

		if (e && !strcmp(e, s))
			return true;
	}

	return false;
}

/**
 * Parses a base-10 integer, optionally signed, that fills the whole string.
 * A value past the int64_t range reads as its limit, which every rule bound
 * compares correctly against.
 */
static bool
integer_parse(const char *s, int64_t *n)
{
	const char *p = s + (*s == '-');

	if (!*p)
		return false;

	for (; *p; p++)
		if (!isdigit((unsigned char)*p))
			return false;

	*n = strtoll(s, NULL, 10);
	return true;
}

/**
 * Tells whether a parsed integer lies in the range of its TR-181 base type:
 * int and unsignedInt are 32 bits, long and unsignedLong 64 bits.
 */
static bool
integer_fits(uint32_t type, const char *s, int64_t n)
{
	switch (type) {
	case DM_INT:
		return n >= INT32_MIN && n <= INT32_MAX;
	case DM_UINT:
		return n >= 0 && n <= UINT32_MAX;
	case DM_LONG:
		errno = 0;
		strtoll(s, NULL, 10);
		return errno != ERANGE;
	case DM_ULONG:
		if (*s == '-')
			return false;
		errno = 0;
		strtoull(s, NULL, 10);
		return errno != ERANGE;
	default:
		return true;
	}
}

/**
 * Tells whether a value is a TR-181 hexBinary: an even number of hex digits.
 */
static bool
hexbinary_valid(const char *s)
{
	size_t len;

	for (len = 0; s[len]; len++)
		if (!isxdigit((unsigned char)s[len]))
			return false;

	return !(len % 2);
}

static bool
int_type(uint32_t type)
{
	switch (type & ~DM_WRITABLE) {
	case DM_INT:
	case DM_UINT:
	case DM_LONG:
	case DM_ULONG:
		return true;
	default:
		return false;
	}
}

/**
 * Checks one value, or one item of a list, against the number limits, the
 * enumeration and the string lengths.
 *
 * @return  NULL when the item is acceptable, else a short reason in `why`
 */
static const char *
item_check(const struct value_rule *vr, const char *s, char *why, size_t why_len)
{
	const struct schema_rule *r = &vr->r;
	uint32_t type = vr->type & ~DM_WRITABLE;
	size_t len = strlen(s);
	int64_t n;

	if (int_type(type)) {
		if (!integer_parse(s, &n))
			return "not an integer";
		/* an explicit range may go beyond the type, as unsignedInt(-1,576:)
		 * of Routing.Router.{i}.IPv4Forwarding.{i}.MTU does in TR-181 */
		if (!integer_fits(type, s, n) &&
		    !(r->range_count && ranges_hold(vr->ranges, r->range_count, n)))
			return "outside the range of its type";
		if ((r->flags & SCHEMA_RULE_MIN) && n < r->min)
			return snprintf(why, why_len, "below the minimum of %" PRId64, r->min), why;
		if ((r->flags & SCHEMA_RULE_MAX) && n > r->max)
			return snprintf(why, why_len, "above the maximum of %" PRId64, r->max), why;
		if (r->range_count && !ranges_hold(vr->ranges, r->range_count, n))
			return "outside the allowed ranges";
	}

	if (type == DM_HEXBIN && !hexbinary_valid(s))
		return "not an even number of hex digits";

	if (r->enum_count && !enum_has(vr, s))
		return "not an allowed value";

	if (type != DM_STRING && type != DM_HEXBIN)
		return NULL;

	/* TR-106 counts the size of a hexBinary in bytes */
	if (type == DM_HEXBIN)
		len /= 2;

	if ((r->flags & SCHEMA_RULE_MIN_LENGTH) && len < r->min_length)
		return snprintf(why, why_len, "shorter than %u", r->min_length), why;
	if ((r->flags & SCHEMA_RULE_MAX_LENGTH) && len > r->max_length)
		return snprintf(why, why_len, "longer than %u", r->max_length), why;
	if (r->length_count && !ranges_hold(vr->lengths, r->length_count, (int64_t)len))
		return "length outside the allowed lengths";

	return NULL;
}

/* The comma that ends a list item, or the end of the text; a comma inside
 * square brackets belongs to a nested list and ends nothing. */
static char *
list_item_end(char *s)
{
	int depth = 0;

	for (; *s; s++) {
		if (*s == '[')
			depth++;
		else if (*s == ']' && depth > 0)
			depth--;
		else if (*s == ',' && !depth)
			break;
	}

	return s;
}

/**
 * Checks a comma-separated list: the list lengths apply to the whole value,
 * the other rules to each item, with the blanks around it and the
 * brackets of a nested list removed.
 */
static const char *
list_check(const struct value_rule *vr, char *s, char *why, size_t why_len)
{
	const struct schema_rule *r = &vr->r;
	size_t len = strlen(s);
	char item_why[64];

	if ((r->flags & SCHEMA_RULE_LIST_MIN_LENGTH) && len < r->list_min_length)
		return snprintf(why, why_len, "shorter than %u characters", r->list_min_length), why;
	if ((r->flags & SCHEMA_RULE_LIST_MAX_LENGTH) && len > r->list_max_length)
		return snprintf(why, why_len, "longer than %u characters", r->list_max_length), why;

	if (!len)
		return NULL;

	for (char *item = s, *next; item; item = next) {
		const char *reason;
		char *end;

		next = list_item_end(item);
		if (*next)
			*next++ = '\0';
		else
			next = NULL;

		while (isspace((unsigned char)*item))
			item++;
		for (end = item + strlen(item); end > item && isspace((unsigned char)end[-1]); end--)
			;
		*end = '\0';

		/* TR-106 nested lists put each inner list in square brackets */
		if (*item == '[' && end > item + 1 && end[-1] == ']') {
			end[-1] = '\0';
			item++;
		}

		reason = item_check(vr, item, item_why, sizeof(item_why));
		if (reason)
			return snprintf(why, why_len, "%s: %s", item, reason), why;
	}

	return NULL;
}

static const char *
value_check(const struct value_rule *vr, char *s, char *why, size_t why_len)
{
	if ((vr->type & ~DM_WRITABLE) == DM_BOOL &&
	    strcmp(s, "0") && strcmp(s, "1") && strcmp(s, "true") && strcmp(s, "false"))
		return "not a boolean";

	if (vr->r.flags & SCHEMA_RULE_LIST)
		return list_check(vr, s, why, why_len);

	return item_check(vr, s, why, why_len);
}

/**
 * Checks a value written to a parameter of a model entry's schema against
 * the parameter's type and rule.
 *
 * @param vm       ucode VM context
 * @param entry    model entry of the object that holds the parameter
 * @param name     parameter name
 * @param value    value as written
 * @param why      receives a short reason for a refused value
 * @param why_len  size of `why`
 * @return         true when the value is acceptable or the schema does not
 *                 describe the parameter
 */
bool
schema_entry_value_ok(uc_vm_t *vm, uc_value_t *entry, const char *name,
		      uc_value_t *value, char *why, size_t why_len)
{
	struct value_rule vr;
	const char *reason;
	char *s;

	if (!entry_rule(entry, name, &vr))
		return true;

	s = ucv_to_string(vm, value);
	reason = value_check(&vr, s, why, why_len);

	if (reason && reason != why)
		snprintf(why, why_len, "%s", reason);

	free(s);
	free(vr.owned);

	return reason == NULL;
}

/**
 * Reads the `addable` flag of the table of a model entry. A key of the
 * entry wins over the schema: the handler that makes the rows is the
 * authority on its own table.
 *
 * @param entry  model entry of the `{i}` pattern of the table
 * @return       false when the entry or the schema says `addable: false`
 */
static bool
entry_addable_flag(uc_value_t *entry)
{
	uc_value_t *addable = ucv_object_get(entry, "addable", NULL);
	uc_value_t *legacy;
	struct schema_ref ref;

	if (addable)
		return ucv_is_truish(addable);

	if (entry_object(entry, &legacy, &ref))
		return ref.obj->addable;

	addable = ucv_object_get(legacy, "addable", NULL);

	return !addable || ucv_is_truish(addable);
}

/**
 * Reads the row limit of the table of a model entry. A `maxInstances` key of
 * the entry wins over the schema.
 *
 * @param entry  model entry of the `{i}` pattern of the table
 * @param max    receives the limit
 * @return       false when the table has no limit
 */
bool
schema_entry_max_instances(uc_value_t *entry, int64_t *max)
{
	uc_value_t *val = ucv_object_get(entry, "maxInstances", NULL);
	uc_value_t *legacy;
	struct schema_ref ref;

	if (ucv_type(val) == UC_INTEGER) {
		*max = ucv_int64_get(val);
		return true;
	}

	if (entry_object(entry, &legacy, &ref)) {
		if (ref.obj->max_instances == SCHEMA_NONE)
			return false;

		*max = ref.obj->max_instances;
		return true;
	}

	val = ucv_object_get(legacy, "max_instances", NULL);
	if (ucv_type(val) != UC_INTEGER)
		return false;

	*max = ucv_int64_get(val);
	return true;
}

/**
 * Reports whether a controller may add rows to the table of a model entry:
 * not when the entry or the schema says `addable: false`, and not when the
 * row limit is 0.
 *
 * @param entry  model entry of the `{i}` pattern of the table
 * @return       false for a table the CPE maintains itself
 */
bool
schema_entry_addable(uc_value_t *entry)
{
	int64_t max;

	if (!entry_addable_flag(entry))
		return false;

	return !schema_entry_max_instances(entry, &max) || max != 0;
}

/**
 * Reports whether a schemas/ module name is safe to splice into an import.
 *
 * @param name  module name
 * @param len   length of the name
 * @return      true for a non-empty name of letters, digits and underscores
 */
static bool
module_name_valid(const char *name, size_t len)
{
	if (!len)
		return false;

	for (size_t i = 0; i < len; i++)
		if (!isalnum((unsigned char)name[i]) && name[i] != '_')
			return false;

	return true;
}

/**
 * Loads a schemas/ module once per VM and returns its exports.
 *
 * A module with exports cannot be loaded by require(), so a small program
 * imports it the way schema-gen.uc does. A missing module raises the import
 * exception in the calling script.
 *
 * @param vm    ucode VM context
 * @param name  module name, such as "Bridging"
 * @param len   length of the name
 * @return      borrowed reference to the exports, or NULL
 */
static uc_value_t *
schema_module_load(uc_vm_t *vm, const char *name, size_t len)
{
	uc_value_t *cache = registry_get(vm, "ubbf.schema_modules", UC_OBJECT);
	uc_value_t *loadstring, *loaded, *code, *mod;
	char *key, *src;

	if (!module_name_valid(name, len))
		return NULL;

	key = xstrdup(name);
	key[len] = '\0';

	mod = ucv_object_get(cache, key, NULL);
	if (mod) {
		free(key);
		return mod;
	}

	loadstring = ucv_object_get(uc_vm_scope_get(vm), "loadstring", NULL);
	if (!ucv_is_callable(loadstring)) {
		free(key);
		return NULL;
	}

	xasprintf(&src, "import * as m from 'ubbf.schemas.%s'; return m;", key);
	code = ucv_string_new(src);
	free(src);

	loaded = callback_invoke(vm, loadstring, 1, code);
	ucv_put(code);
	mod = loaded ? callback_invoke(vm, loaded, 0) : NULL;
	ucv_put(loaded);

	if (vm->exception.type != EXCEPTION_NONE || !mod) {
		ucv_put(mod);
		free(key);
		return NULL;
	}

	ucv_object_add(cache, key, mod);
	free(key);

	return mod;
}

/**
 * Resolves a `<Module>.<Export>` name to the export of a schemas/ module.
 *
 * @param vm  ucode VM context
 * @param id  schema name
 * @return    new reference to the schema object, or NULL
 */
static uc_value_t *
schema_module_export(uc_vm_t *vm, uc_value_t *id)
{
	const char *name, *dot;
	uc_value_t *mod, *key, *def;

	if (ucv_type(id) != UC_STRING)
		return NULL;

	name = ucv_string_get(id);
	dot = strchr(name, '.');
	if (!dot)
		return NULL;

	mod = schema_module_load(vm, name, dot - name);
	if (!mod)
		return NULL;

	/* The import namespace holds upvalue references, which only
	 * ucv_key_get() resolves. */
	key = ucv_string_new(dot + 1);
	def = ucv_key_get(vm, mod, key);
	ucv_put(key);

	return def;
}

/**
 * Resolves the schema name passed as the first argument.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments
 * @param ref    receives the table object
 * @return       false for a missing or unknown name
 */
static bool
arg_object(uc_vm_t *vm, size_t nargs, struct schema_ref *ref)
{
	uc_value_t *id = uc_fn_arg(0);

	if (ucv_type(id) != UC_STRING)
		return false;

	return schema_object_find(ucv_string_get(id), ref);
}

static uc_value_t *
ranges_new(uc_vm_t *vm, const struct schema_range *ranges, uint16_t count)
{
	uc_value_t *out = ucv_array_new(vm);

	for (uint16_t i = 0; i < count; i++) {
		uc_value_t *pair = ucv_array_new(vm);

		ucv_array_push(pair, ranges[i].lo == INT64_MIN ? NULL : ucv_int64_new(ranges[i].lo));
		ucv_array_push(pair, ranges[i].hi == INT64_MAX ? NULL : ucv_int64_new(ranges[i].hi));
		ucv_array_push(out, pair);
	}

	return out;
}

/**
 * Adds the facts of a table rule to an object, with the keys of the
 * `constraints` table of a schemas/ export.
 */
static void
rule_facts_add(uc_vm_t *vm, uc_value_t *out, const struct schema_ref *ref,
	       const struct schema_rule *r)
{
	const struct schema_table *t = ref->table;

	if (r->flags & SCHEMA_RULE_MIN)
		ucv_object_add(out, "min", ucv_int64_new(r->min));
	if (r->flags & SCHEMA_RULE_MAX)
		ucv_object_add(out, "max", ucv_int64_new(r->max));
	if (r->flags & SCHEMA_RULE_MIN_LENGTH)
		ucv_object_add(out, "min_length", ucv_int64_new(r->min_length));
	if (r->flags & SCHEMA_RULE_MAX_LENGTH)
		ucv_object_add(out, "max_length", ucv_int64_new(r->max_length));
	if (r->flags & SCHEMA_RULE_LIST)
		ucv_object_add(out, "list", ucv_boolean_new(true));
	if (r->flags & SCHEMA_RULE_LIST_MIN_LENGTH)
		ucv_object_add(out, "list_min_length", ucv_int64_new(r->list_min_length));
	if (r->flags & SCHEMA_RULE_LIST_MAX_LENGTH)
		ucv_object_add(out, "list_max_length", ucv_int64_new(r->list_max_length));
	if (r->flags & SCHEMA_RULE_SECURED)
		ucv_object_add(out, "secured", ucv_boolean_new(true));
	if (r->range_count)
		ucv_object_add(out, "ranges", ranges_new(vm, &t->ranges[r->range_first], r->range_count));
	if (r->length_count)
		ucv_object_add(out, "lengths", ranges_new(vm, &t->ranges[r->length_first], r->length_count));

	if (r->enum_count) {
		uc_value_t *list = ucv_array_new(vm);

		for (uint16_t i = 0; i < r->enum_count; i++)
			ucv_array_push(list, ucv_string_new(t->pool + t->enums[r->enum_first + i]));

		ucv_object_add(out, "enum", list);
	}
}

/**
 * Reports whether a controller may add rows to a table, for a model entry
 * passed from ucode.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: model entry of the table)
 * @return       false for a table the CPE maintains itself
 */
uc_value_t *
uc_ubbf_schema_entry_addable(uc_vm_t *vm, size_t nargs)
{
	return ucv_boolean_new(schema_entry_addable(uc_fn_arg(0)));
}

/**
 * Builds the full schema object of a name, in the shape of a schemas/ export.
 *
 * Constraints are left out: `schema_param_info()` serves them per parameter.
 * Without the core table, the export of the schemas/ module itself is
 * returned, unprojected; datamodel.uc projects it like any object schema.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: schema name)
 * @return       `{ path, schema, defaults }`, or null for an unknown name
 */
uc_value_t *
uc_ubbf_schema_get(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out, *members;
	struct schema_ref ref;

	if (!arg_object(vm, nargs, &ref))
		return schema_core_table() ? NULL : schema_module_export(vm, uc_fn_arg(0));

	out = ucv_object_new(vm);
	members = ucv_object_new(vm);

	if (ref.obj->path != SCHEMA_NONE)
		ucv_object_add(out, "path", ucv_string_new(ref_str(&ref, ref.obj->path)));

	for (uint32_t i = 0; i < ref.obj->member_count; i++) {
		const struct schema_member *m = ref_member(&ref, i);

		if (!member_visible(m))
			continue;

		ucv_object_add(members, ref_str(&ref, m->name),
			       m->kind == SCHEMA_KIND_COMMAND
			       ? json_value_parse(vm, ref.table->pool, m->info)
			       : ucv_uint64_new(m->type));
	}

	ucv_object_add(out, "schema", members);
	ucv_object_add(out, "defaults", object_defaults_new(vm, &ref));

	return out;
}

/**
 * Builds the defaults object of a schema name, such as `Firewall.Service`:
 * from the schema table, or from the schema module when no table is
 * built in.
 *
 * @param vm    ucode VM context
 * @param name  schema name
 * @return      new defaults object, or NULL for an unknown name
 */
uc_value_t *
schema_defaults_new(uc_vm_t *vm, const char *name)
{
	uc_value_t *id, *def, *defaults;
	struct schema_ref ref;

	if (schema_object_find(name, &ref))
		return object_defaults_new(vm, &ref);

	if (schema_core_table())
		return NULL;

	id = ucv_string_new(name);
	def = schema_module_export(vm, id);
	defaults = ucv_get(ucv_object_get(def, "defaults", NULL));
	ucv_put(def);
	ucv_put(id);

	return defaults;
}

/**
 * Builds the defaults object of a schema name, see schema_defaults_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: schema name)
 * @return       new defaults object, or null for an unknown name
 */
uc_value_t *
uc_ubbf_schema_defaults(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);

	if (ucv_type(name) != UC_STRING)
		return NULL;

	return schema_defaults_new(vm, ucv_string_get(name));
}

static uc_value_t *
command_info_new(uc_vm_t *vm, uc_value_t *def)
{
	uc_value_t *out = ucv_object_new(vm);

	ucv_object_add(out, "command", ucv_boolean_new(true));
	ucv_object_add(out, "type", ucv_get(ucv_object_get(def, "type", NULL)));
	ucv_object_add(out, "input", ucv_get(ucv_object_get(def, "input", NULL)));
	ucv_object_add(out, "output", ucv_get(ucv_object_get(def, "output", NULL)));

	return out;
}

/**
 * Describes one member of an object schema, the form of a module without a
 * schema table: `{ schema: { name: type bits | command }, constraints }`.
 * The decoded type and writability win, so a constraints entry can add
 * facts but never contradict the type it annotates.
 */
static uc_value_t *
object_param_info_new(uc_vm_t *vm, uc_value_t *schema, const char *name)
{
	uc_value_t *members = ucv_object_get(schema, "schema", NULL);
	uc_value_t *value = ucv_object_get(members, name, NULL);
	uc_value_t *rules, *out;
	uint32_t type;

	if (ucv_type(value) == UC_OBJECT)
		return command_info_new(vm, value);

	if (ucv_type(value) != UC_INTEGER)
		return NULL;

	type = (uint32_t)ucv_int64_get(value);
	rules = ucv_object_get(ucv_object_get(schema, "constraints", NULL), name, NULL);
	out = ucv_object_new(vm);

	ucv_object_foreach(rules, key, rule)
		ucv_object_add(out, key, ucv_get(rule));

	ucv_object_add(out, "writable", ucv_boolean_new((type & DM_WRITABLE) != 0));
	ucv_object_add(out, "type", type_name_new(type));

	return out;
}

/**
 * Describes one member of a schema: its rule plus the decoded writability
 * and type of a parameter, or the definition of a command.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: schema name or object
 *               schema, member name)
 * @return       facts object, or null when the schema does not describe the
 *               member
 */
uc_value_t *
uc_ubbf_schema_param_info(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *schema = uc_fn_arg(0);
	uc_value_t *name = uc_fn_arg(1);
	const struct schema_member *m;
	uc_value_t *out, *def;
	struct schema_ref ref;

	if (ucv_type(name) != UC_STRING)
		return NULL;

	if (ucv_type(schema) == UC_OBJECT)
		return object_param_info_new(vm, schema, ucv_string_get(name));

	if (!arg_object(vm, nargs, &ref))
		return NULL;

	m = object_member_find(&ref, ucv_string_get(name));
	if (!m)
		return NULL;

	if (m->kind == SCHEMA_KIND_COMMAND) {
		def = json_value_parse(vm, ref.table->pool, m->info);
		out = command_info_new(vm, def);
		ucv_put(def);

		return out;
	}

	out = ucv_object_new(vm);

	if (m->info != SCHEMA_NONE)
		rule_facts_add(vm, out, &ref, &ref.table->rules[m->info]);

	ucv_object_add(out, "writable", ucv_boolean_new((m->type & DM_WRITABLE) != 0));
	ucv_object_add(out, "type", type_name_new(m->type));

	return out;
}

static void
members_extract(uc_vm_t *vm, uc_value_t *schema, const char *path,
		uc_value_t *members)
{
	uc_value_t *objects = ucv_object_get(schema, "objects", NULL);
	uc_value_t *events = ucv_object_get(schema, "events", NULL);
	uc_value_t *params = ucv_object_new(vm);
	uc_value_t *type, *input;
	char *event_path;

	ucv_object_foreach(members, name, def) {
		type = ucv_object_get(def, "type", NULL);
		if (ucv_type(def) != UC_OBJECT || ucv_type(type) != UC_STRING ||
		    strcmp(ucv_string_get(type), "event")) {
			ucv_object_add(params, name, ucv_get(def));
			continue;
		}

		input = ucv_object_get(def, "input", NULL);
		xasprintf(&event_path, "%s.%s", path, name);
		ucv_object_add(events, event_path, input ? ucv_get(input) : ucv_array_new(vm));
		free(event_path);
	}

	ucv_object_add(objects, path, params);
}

/**
 * Extracts the schema the USP core registers from a model: the parameters
 * and commands of each object pattern, and its events apart.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: model, function that
 *               returns the schema members of a model entry, given the
 *               entry and its object pattern)
 * @return       `{ objects, events }`, or null when the function throws
 */
uc_value_t *
uc_ubbf_schema_extract(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *model = uc_fn_arg(0);
	uc_value_t *members_get = uc_fn_arg(1);
	uc_value_t *schema = ucv_object_new(vm);
	uc_value_t *members, *pattern;

	ucv_object_add(schema, "objects", ucv_object_new(vm));
	ucv_object_add(schema, "events", ucv_object_new(vm));

	ucv_object_foreach(model, path, entry) {
		pattern = ucv_string_new(path);
		members = callback_invoke(vm, members_get, 2, entry, pattern);
		ucv_put(pattern);

		if (vm->exception.type != EXCEPTION_NONE) {
			ucv_put(schema);
			return NULL;
		}

		members_extract(vm, schema, path, members);
		ucv_put(members);
	}

	return schema;
}

/**
 * Lists the open schema tables.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       array of table names, such as "core" and "pcp"
 */
uc_value_t *
uc_ubbf_schema_tables(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *out = ucv_array_new(vm);

	schema_tables_init();

	for (size_t i = 0; i < schema_table_count; i++)
		ucv_array_push(out, ucv_string_new(schema_tables[i].name));

	return out;
}

/**
 * Opens the schema tables of another directory, such as a build tree. A
 * table whose name is already open is skipped.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: glob pattern of schema-*.so)
 * @return       array of the names of the tables opened, or null for a
 *               pattern that is not a string
 */
uc_value_t *
uc_ubbf_schema_tables_load(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pattern = uc_fn_arg(0);
	uc_value_t *loaded;

	if (ucv_type(pattern) != UC_STRING)
		return NULL;

	schema_tables_init();

	loaded = ucv_array_new(vm);
	schema_tables_glob(ucv_string_get(pattern), loaded);

	return loaded;
}

/**
 * Selects the management protocol whose commands and events are visible.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: "usp" or "cwmp")
 * @return       true when the protocol is known
 */
uc_value_t *
uc_ubbf_schema_protocol_set(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *proto = uc_fn_arg(0);
	const char *s;

	if (ucv_type(proto) != UC_STRING)
		return ucv_boolean_new(false);

	s = ucv_string_get(proto);

	if (!strcmp(s, "usp"))
		schema_protocol = SCHEMA_PROTO_USP;
	else if (!strcmp(s, "cwmp"))
		schema_protocol = SCHEMA_PROTO_CWMP;
	else
		return ucv_boolean_new(false);

	return ucv_boolean_new(true);
}

/**
 * Selects the TR-181 version whose members are visible.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: minor number, 20 for 2.20)
 * @return       true when the number fits a member tag
 */
uc_value_t *
uc_ubbf_schema_version_set(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *minor = uc_fn_arg(0);
	int64_t n;

	if (ucv_type(minor) != UC_INTEGER)
		return ucv_boolean_new(false);

	n = ucv_int64_get(minor);
	if (n < 1 || n > UINT8_MAX)
		return ucv_boolean_new(false);

	schema_minor = n;

	return ucv_boolean_new(true);
}
