/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * dm.object_add(), dm.object_del() and the transactions of the ubbf.dm
 * resource. numbered_inst() is static; its rules are tested through
 * object_add(), which uses it. numbered_inst() takes
 * numbers from the instance map, so the program runs isolated
 * (run-isolated.sh).
 */

#include "harness.h"
#include "ubbf.h"

#include <unistd.h>
#include <sha2.h>

static const char *MODEL =
	"{"
	"  \"Device.T\": {},"
	"  \"Device.T.{i}\": { \"schema\": { \"schema\": { \"Alias\": 1, \"Name\": 1 },"
	"                      \"defaults\": { \"Alias\": \"\", \"Name\": \"x\", \"Other\": \"y\" } } },"
	"  \"Device.T.{i}.Sub\": {},"
	"  \"Device.T.{i}.Sub.{i}\": { \"schema\": { \"schema\": { \"Name\": 1 } } },"
	"  \"Device.L\": {},"
	"  \"Device.L.{i}\": { \"maxInstances\": 2, \"schema\": { \"schema\": { \"Name\": 1 } } },"
	"  \"Device.R\": {},"
	"  \"Device.R.{i}\": { \"addable\": false, \"schema\": { \"schema\": { \"Name\": 1 } } },"
	"  \"Device.M\": {},"
	"  \"Device.M.{i}\": { \"schema\": { \"schema\": { \"Alias\": 1 } } },"
	"  \"Device.M.{i}.Sub\": {},"
	"  \"Device.M.{i}.Sub.{i}\": { \"schema\": { \"schema\": { \"Name\": 1 } } }"
	"}";

static uc_value_t *
dm_new(uc_vm_t *vm, const char *config)
{
	uc_value_t *dm = vm_method(vm, vm_module(vm), "create", 0);

	ucv_put(vm_method(vm, dm, "register", 1, vm_json(vm, MODEL)));
	ucv_put(vm_method(vm, dm, "set_config", 1, vm_json(vm, config)));

	return dm;
}

static int64_t
add(uc_vm_t *vm, uc_value_t *dm, const char *path)
{
	uc_value_t *res = vm_method(vm, dm, "object_add", 1, ucv_string_new(path));
	int64_t n = ucv_int64_get(res);

	ucv_put(res);
	return n;
}

/* Numbers keys on the instance map, as a get handler of a runtime table
 * does; it makes the table one that the map numbers. */
static void
map_keys(uc_vm_t *vm, const char *table, const char *keys_json, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_instance_numbers, 2, ucv_string_new(table),
				  vm_json(vm, keys_json));

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
map_own(uc_vm_t *vm, bool owner)
{
	ucv_put(vm_call(vm, uc_ubbf_instance_map_own, 1, ucv_boolean_new(owner)));
}

static int64_t
del(uc_vm_t *vm, uc_value_t *dm, const char *path)
{
	uc_value_t *res = vm_method(vm, dm, "object_del", 1, ucv_string_new(path));
	int64_t n = ucv_int64_get(res);

	ucv_put(res);
	return n;
}

static uc_value_t *
config(uc_vm_t *vm, uc_value_t *dm)
{
	return vm_method(vm, dm, "config", 0);
}

static void
test_add_row(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }"), *cfg;

	assert_int_equal(add(vm, dm, "Device.T"), 1);

	cfg = config(vm, dm);
	assert_json_equal(vm, navigate_by_path(vm, cfg, "Device.T.1"),
			  "{ \"Alias\": \"cpe-T1\", \"Name\": \"x\" }");
	assert_json_equal(vm, navigate_by_path(vm, cfg, "Device.TNumberOfEntries"), "\"1\"");
	ucv_put(cfg);
	ucv_put(dm);
}

static char *
deep_path_new(int segments, const char *segment)
{
	char *path = xstrdup("Device"), *next;

	for (int i = 0; i < segments; i++) {
		xasprintf(&next, "%s.%s", path, segment);
		free(path);
		path = next;
	}

	return path;
}

static void
test_add_long_path(void **state)
{
	uc_vm_t *vm = *state;
	char *deep = deep_path_new(20, "Segment_with_a_long_name_000");
	char *table, *model, *row, *count;
	uc_value_t *dm, *cfg;

	xasprintf(&table, "%s.T", deep);
	free(deep);
	assert_int_equal(strlen(table), 588);

	xasprintf(&model, "{ \"%s\": {}, \"%s.{i}\": { \"schema\": { \"schema\": { \"Alias\": 1 },"
		  " \"defaults\": { \"Alias\": \"\" } } } }", table, table);
	dm = vm_method(vm, vm_module(vm), "create", 0);
	ucv_put(vm_method(vm, dm, "register", 1, vm_json(vm, model)));
	ucv_put(vm_method(vm, dm, "set_config", 1, vm_json(vm, "{ \"Device\": {} }")));

	assert_int_equal(add(vm, dm, table), 1);

	xasprintf(&row, "%s.1", table);
	xasprintf(&count, "%sNumberOfEntries", table);
	cfg = config(vm, dm);
	assert_json_equal(vm, navigate_by_path(vm, cfg, row), "{ \"Alias\": \"cpe-T1\" }");
	assert_json_equal(vm, navigate_by_path(vm, cfg, count), "\"1\"");
	assert_int_equal(del(vm, dm, row), 0);

	ucv_put(cfg);
	ucv_put(dm);
	free(count);
	free(row);
	free(model);
	free(table);
}

/* The first 64 segments of the path name a table of the model. */
static void
test_add_too_many_segments(void **state)
{
	uc_vm_t *vm = *state;
	char *prefix = deep_path_new(63, "A"), *path = deep_path_new(70, "A"), *model;
	uc_value_t *dm, *cfg;

	xasprintf(&model, "{ \"%s\": {}, \"%s.{i}\": { \"schema\": { \"schema\": { \"Name\": 1 } } } }",
		  prefix, prefix);
	dm = vm_method(vm, vm_module(vm), "create", 0);
	ucv_put(vm_method(vm, dm, "register", 1, vm_json(vm, model)));
	ucv_put(vm_method(vm, dm, "set_config", 1, vm_json(vm, "{ \"Device\": {} }")));

	assert_int_equal(add(vm, dm, path), 0);
	assert_int_equal(del(vm, dm, path), 1);

	cfg = config(vm, dm);
	assert_json_equal(vm, cfg, "{ \"Device\": { } }");

	ucv_put(cfg);
	ucv_put(dm);
	free(model);
	free(path);
	free(prefix);
}

static void
test_add_empty_segment(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"T\": { \"1\": { \"Name\": \"a\" } } } }"), *cfg;

	assert_int_equal(add(vm, dm, "Device.T..X"), 0);
	assert_int_equal(add(vm, dm, "Device.T.."), 0);
	assert_int_equal(add(vm, dm, "..Device.T"), 0);
	assert_int_equal(del(vm, dm, "Device.T.1.."), 1);
	assert_int_equal(del(vm, dm, "Device..T.1"), 1);

	cfg = config(vm, dm);
	assert_json_equal(vm, cfg, "{ \"Device\": { \"T\": { \"1\": { \"Name\": \"a\" } } } }");

	ucv_put(cfg);
	ucv_put(dm);
}

static void
test_add_takes_lowest_free_number(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"T\": { \"1\": {}, \"2\": {}, \"5\": {} } } }");

	assert_int_equal(add(vm, dm, "Device.T"), 3);
	assert_int_equal(add(vm, dm, "Device.T"), 4);
	assert_int_equal(add(vm, dm, "Device.T"), 6);
	assert_int_equal(del(vm, dm, "Device.T.2"), 0);
	assert_int_equal(add(vm, dm, "Device.T"), 2);
	ucv_put(dm);

	/* more than 256 rows with the gap above the 256th row: a free number
	 * that exists already would replace that row */
	dm = dm_new(vm, "{ \"Device\": {} }");
	for (int i = 1; i <= 300; i++)
		assert_int_equal(add(vm, dm, "Device.T"), i);
	assert_int_equal(del(vm, dm, "Device.T.290"), 0);
	assert_int_equal(add(vm, dm, "Device.T"), 290);
	assert_int_equal(add(vm, dm, "Device.T"), 301);
	ucv_put(dm);
}

static void
test_release(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }");
	uc_value_t *cfg = config(vm, dm);
	uint32_t held = cfg->refcount;

	/* the last reference to the dm frees it and with it its config slot */
	ucv_put(dm);
	assert_int_equal(cfg->refcount, held - 1);
	ucv_put(cfg);
}

static void
test_add_mapped_table(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"M\": { \"1\": {}, \"4\": {} } } }");

	map_own(vm, true);
	map_keys(vm, "Device.M", "[ \"a\", \"b\" ]", "{ \"a\": 1, \"b\": 2 }");

	/* The add takes the next number of the map, at least one above the
	 * highest stored row, and no row the CPE finds gets it later. */
	assert_int_equal(add(vm, dm, "Device.M"), 5);
	assert_int_equal(add(vm, dm, "Device.M"), 6);
	map_keys(vm, "Device.M", "[ \"a\", \"c\" ]", "{ \"a\": 1, \"c\": 7 }");
	ucv_put(dm);
}

static void
test_add_mapped_table_not_owner(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"M\": { \"1\": {}, \"4\": {} } } }");

	map_own(vm, false);
	assert_int_equal(add(vm, dm, "Device.M"), 2);
	map_own(vm, true);
	ucv_put(dm);
}

static void
test_add_mapped_resolved_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"M\": { \"3\": { \"Alias\": \"lan\" } } } }");

	map_own(vm, true);
	map_keys(vm, "Device.M.3.Sub", "[ ]", "{ }");

	/* The alias resolves to row 3, so the add numbers on Device.M.3.Sub. */
	assert_int_equal(add(vm, dm, "Device.M.lan.Sub"), 1);
	map_keys(vm, "Device.M.3.Sub", "[ \"x\" ]", "{ \"x\": 2 }");
	ucv_put(dm);
}

static void
test_add_refused(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }");

	assert_int_equal(add(vm, dm, "Device.L"), 1);
	assert_int_equal(add(vm, dm, "Device.L"), 2);
	assert_int_equal(add(vm, dm, "Device.L"), 0);
	assert_int_equal(add(vm, dm, "Device.R"), 0);
	assert_int_equal(add(vm, dm, "Device.Unknown"), 0);
	assert_int_equal(add(vm, dm, ""), 0);
	ucv_put(dm);
}

static void
test_add_missing_parent(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *stored = dm_new(vm, "{ \"Device\": { \"T\": { \"1\": {} } } }");
	uc_value_t *untracked = dm_new(vm, "{ \"Device\": {} }");

	assert_int_equal(add(vm, stored, "Device.T.7.Sub"), 0);
	assert_int_equal(add(vm, stored, "Device.T.1.Sub"), 1);

	/* A table the config does not hold belongs to a get handler, which
	 * the stored tree cannot judge. */
	assert_int_equal(add(vm, untracked, "Device.T.7.Sub"), 1);

	ucv_put(stored);
	ucv_put(untracked);
}

static void
test_del(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": { \"T\": { \"1\": {}, \"2\": {} } } }"), *cfg;

	assert_int_equal(del(vm, dm, "Device.T.1"), 0);
	assert_int_equal(del(vm, dm, "Device.T.1"), 1);
	assert_int_equal(del(vm, dm, "Device.T.x"), 1);

	cfg = config(vm, dm);
	assert_json_equal(vm, navigate_by_path(vm, cfg, "Device.TNumberOfEntries"), "\"1\"");
	ucv_put(cfg);
	ucv_put(dm);
}

static void
test_transaction_abort(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }"), *res, *cfg;

	res = vm_method(vm, dm, "trans_start", 0);
	assert_int_equal(ucv_int64_get(res), 0);
	ucv_put(res);

	assert_int_equal(add(vm, dm, "Device.T"), 1);
	cfg = config(vm, dm);
	assert_non_null(navigate_by_path(vm, cfg, "Device.T.1"));
	ucv_put(cfg);

	res = vm_method(vm, dm, "trans_abort", 0);
	assert_int_equal(ucv_int64_get(res), 0);
	ucv_put(res);

	cfg = config(vm, dm);
	assert_null(navigate_by_path(vm, cfg, "Device.T.1"));
	ucv_put(cfg);
	ucv_put(dm);
}

static void
test_transaction_commit(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }"), *res, *cfg;

	res = vm_method(vm, dm, "trans_commit", 0);
	assert_int_equal(ucv_int64_get(res), 0);
	ucv_put(res);

	ucv_put(vm_method(vm, dm, "trans_start", 0));
	assert_int_equal(add(vm, dm, "Device.T"), 1);

	res = vm_method(vm, dm, "trans_commit", 0);
	assert_int_equal(ucv_int64_get(res), 1);
	ucv_put(res);

	cfg = config(vm, dm);
	assert_non_null(navigate_by_path(vm, cfg, "Device.T.1"));
	ucv_put(cfg);
	ucv_put(dm);
}

static void
test_transaction_without_config(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = vm_method(vm, vm_module(vm), "create", 0), *res;

	res = vm_method(vm, dm, "trans_start", 0);
	assert_int_equal(ucv_int64_get(res), -1);
	ucv_put(res);
	ucv_put(dm);
}

#define CONFIG_FILE	"/tmp/ubbf/c.json"
#define RUNTIME_FILE	"/tmp/ubbf/r.json"

/* config.json content of { "Device": { "X": "1" } } */
static const char CONTENT_X1[] = "{\n\t\"Device\": {\n\t\t\"X\": \"1\"\n\t}\n}\n";

static void
file_put(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	assert_non_null(f);
	fputs(text, f);
	fclose(f);
}

static char *
file_get(const char *path)
{
	static char buf[4096];
	FILE *f = fopen(path, "r");
	size_t len;

	if (!f)
		return NULL;

	len = fread(buf, 1, sizeof(buf) - 1, f);
	buf[len] = '\0';
	fclose(f);

	return buf;
}

static bool
persist(uc_vm_t *vm, uc_value_t *dm)
{
	uc_value_t *res = vm_method(vm, dm, "config_persist", 3, ucv_string_new(CONFIG_FILE),
				    ucv_string_new(RUNTIME_FILE), ucv_int64_new(0600));
	bool b = ucv_boolean_get(res);

	ucv_put(res);

	return b;
}

static void
digest_expect(uc_vm_t *vm, uc_value_t *dm, const char *content)
{
	uc_value_t *digest = vm_method(vm, dm, "digest", 0);
	char hex[SHA256_DIGEST_STRING_LENGTH];

	assert_string_equal(ucv_string_get(digest),
			    SHA256Data((const uint8_t *)content, strlen(content), hex));
	ucv_put(digest);
}

static void
test_config_load_persist(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = vm_method(vm, vm_module(vm), "create", 0), *res, *cfg;

	unlink(CONFIG_FILE);
	res = vm_method(vm, dm, "config_load", 1, ucv_string_new(CONFIG_FILE));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);

	file_put(CONFIG_FILE, "{ \"Device\": { \"X\": \"1\" } }");
	res = vm_method(vm, dm, "config_load", 1, ucv_string_new(CONFIG_FILE));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);
	digest_expect(vm, dm, CONTENT_X1);

	/* unchanged content: only the runtime copy is written */
	unlink(RUNTIME_FILE);
	assert_false(persist(vm, dm));
	assert_string_equal(file_get(RUNTIME_FILE), CONTENT_X1);
	assert_string_equal(file_get(CONFIG_FILE), "{ \"Device\": { \"X\": \"1\" } }");

	cfg = config(vm, dm);
	ucv_object_add(ucv_object_get(cfg, "Device", NULL), "X", ucv_string_new("2"));
	ucv_put(cfg);

	assert_true(persist(vm, dm));
	assert_string_equal(file_get(CONFIG_FILE), "{\n\t\"Device\": {\n\t\t\"X\": \"2\"\n\t}\n}\n");
	digest_expect(vm, dm, "{\n\t\"Device\": {\n\t\t\"X\": \"2\"\n\t}\n}\n");
	assert_false(persist(vm, dm));

	ucv_put(dm);
}

static void
test_config_load_pins(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = vm_method(vm, vm_module(vm), "create", 0), *res, *cfg;

	/* the pins leave the live tree; a pin that no row needs is dropped,
	 * so the content differs from what was read */
	file_put(CONFIG_FILE, "{ \"Device\": { \"X\": \"1\" }, "
		 "\"_instances\": { \"Device.E.Row\": { \"2\": \"pin\" } } }");
	res = vm_method(vm, dm, "config_load", 1, ucv_string_new(CONFIG_FILE));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	cfg = config(vm, dm);
	assert_json_equal(vm, cfg, "{ \"Device\": { \"X\": \"1\" } }");
	ucv_put(cfg);

	assert_true(persist(vm, dm));
	assert_string_equal(file_get(CONFIG_FILE), CONTENT_X1);

	ucv_put(dm);
}

static void
test_config_persist_without_config(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = vm_method(vm, vm_module(vm), "create", 0);

	/* nothing to write must not become a config.json that holds null */
	file_put(CONFIG_FILE, "{ \"Device\": { } }");
	assert_null(vm_method(vm, dm, "config_persist", 3, ucv_string_new(CONFIG_FILE),
			      ucv_string_new(RUNTIME_FILE), ucv_int64_new(0600)));
	assert_string_equal(file_get(CONFIG_FILE), "{ \"Device\": { } }");
	ucv_put(dm);
}

static void
test_config_persist_fails(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm, "{ \"Device\": {} }");
	uc_value_t *res = vm_method(vm, dm, "config_persist", 3,
				    ucv_string_new("/tmp/ubbf/none/c.json"),
				    ucv_string_new(RUNTIME_FILE), ucv_int64_new(0600));

	assert_null(res);
	ucv_put(dm);
}

static void
test_config_pins_take(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *cfg = vm_json(vm, "{ \"Device\": {}, \"_instances\": { \"Device.E.Row\": { \"3\": \"k\" } } }");
	uc_value_t *pins = vm_call(vm, uc_ubbf_config_pins_take, 1, ucv_get(cfg));

	assert_json_equal(vm, pins, "{ \"Device.E.Row\": { \"3\": \"k\" } }");
	assert_json_equal(vm, cfg, "{ \"Device\": { } }");
	ucv_put(pins);

	assert_null(vm_call(vm, uc_ubbf_config_pins_take, 1, ucv_get(cfg)));
	ucv_put(cfg);
}

static void
test_wildcard_expand(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *dm = dm_new(vm,
		"{ \"Device\": { \"T\": { \"1\": { \"Sub\": { \"1\": {}, \"4\": {} } }, \"3\": {} } } }");
	uc_value_t *res;

	/* the expansion reads the rows of the runtime tree */
	ucv_put(vm_method(vm, dm, "runtime_reload", 0));

	res = vm_method(vm, dm, "wildcard_expand", 1, ucv_string_new("Device.T.*.Sub.*.Name"));
	assert_json_equal(vm, res,
		"[ \"Device.T.1.Sub.1.Name\", \"Device.T.1.Sub.4.Name\" ]");
	ucv_put(res);

	res = vm_method(vm, dm, "wildcard_expand", 1, ucv_string_new("Device.T.*."));
	assert_json_equal(vm, res, "[ \"Device.T.1.\", \"Device.T.3.\" ]");
	ucv_put(res);

	res = vm_method(vm, dm, "wildcard_expand", 1, ucv_string_new("Device.T.1.Name"));
	assert_json_equal(vm, res, "[ \"Device.T.1.Name\" ]");
	ucv_put(res);

	res = vm_method(vm, dm, "wildcard_expand", 1, ucv_string_new("Device.L.*.Name"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = vm_method(vm, dm, "wildcard_expand", 1, NULL);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	ucv_put(dm);
}

static void
test_names_compute(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	/* B names from A, so a second pass is needed for the rows of B */
	res = vm_eval(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.B.{i}': { name: (inst, data) => data.Device.A['1'].Name ? data.Device.A['1'].Name + '-b' : null },"
		"  'Device.A.{i}': { name: (inst) => inst.Low ? null : 'a' + inst.Id },"
		"});"
		"d.set_config({ Device: {"
		"  A: { '1': { Id: 1 }, '2': { Id: 2, Name: 'kept' }, '3': { Id: 3, Low: true } },"
		"  B: { '1': {}, '2': { Name: '' } } } });"
		"d.names_compute();"
		"let out = d.config();"
		"try { d.register({ 'Device.A.{i}': { name: () => die('name broken') } });"
		"  out.Device.A['1'].Name = null; d.names_compute(); }"
		"catch (e) { out.error = e.message; }"
		"return out;");
	assert_json_equal(vm, res,
		"{ \"Device\": { \"A\": { \"1\": { \"Id\": 1, \"Name\": null }, "
		"\"2\": { \"Id\": 2, \"Name\": \"kept\" }, \"3\": { \"Id\": 3, \"Low\": true } }, "
		"\"B\": { \"1\": { \"Name\": \"a1-b\" }, \"2\": { \"Name\": \"a1-b\" } } }, "
		"\"error\": \"name broken\" }");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_add_row),
		cmocka_unit_test(test_add_long_path),
		cmocka_unit_test(test_add_too_many_segments),
		cmocka_unit_test(test_add_empty_segment),
		cmocka_unit_test(test_add_takes_lowest_free_number),
		cmocka_unit_test(test_release),
		cmocka_unit_test(test_add_mapped_table),
		cmocka_unit_test(test_add_mapped_table_not_owner),
		cmocka_unit_test(test_add_mapped_resolved_path),
		cmocka_unit_test(test_add_refused),
		cmocka_unit_test(test_add_missing_parent),
		cmocka_unit_test(test_del),
		cmocka_unit_test(test_transaction_abort),
		cmocka_unit_test(test_transaction_commit),
		cmocka_unit_test(test_transaction_without_config),
		cmocka_unit_test(test_config_load_persist),
		cmocka_unit_test(test_config_load_pins),
		cmocka_unit_test(test_config_persist_fails),
		cmocka_unit_test(test_config_persist_without_config),
		cmocka_unit_test(test_config_pins_take),
		cmocka_unit_test(test_wildcard_expand),
		cmocka_unit_test(test_names_compute),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
