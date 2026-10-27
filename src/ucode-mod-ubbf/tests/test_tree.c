/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * tree.c: json_file_load(), value_deep_clone(), navigate_or_create(),
 * navigate_by_path(), the C functions tree_node_get(), tree_node_make() and
 * object_child_make(), get(), instances(), enabled(), interface_to_name()
 * and lower_layer_resolve(); navigate_data() and ctx_config() of path.c.
 */

#include "harness.h"
#include "ubbf.h"

#include <sys/stat.h>

static const char config_json[] =
	"{ \"Device\": {"
	"  \"X\": { \"S\": \"v\", \"Zero\": 0, \"Off\": false, \"Nil\": null },"
	"  \"Ethernet\": { \"Interface\": {"
	"    \"1\": { \"Name\": \"lan1\" },"
	"    \"2\": { \"Name\": \"lan2\" },"
	"    \"3\": { \"Enable\": \"true\" },"
	"    \"4\": \"broken\" } } } }";

static void
file_put(const char *path, const char *content)
{
	FILE *fp = fopen(path, "w");

	assert_non_null(fp);
	fputs(content, fp);
	fclose(fp);
}

static void
test_json_file_load(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	file_put("/tmp/tree-obj.json", "{ \"a\": [ 1, 2 ], \"b\": { \"c\": \"d\" } }\n");
	res = json_file_load(vm, "/tmp/tree-obj.json");
	assert_json_equal(vm, res, "{ \"a\": [ 1, 2 ], \"b\": { \"c\": \"d\" } }");
	ucv_put(res);

	file_put("/tmp/tree-arr.json", "[ \"x\", null, true ]");
	res = json_file_load(vm, "/tmp/tree-arr.json");
	assert_json_equal(vm, res, "[ \"x\", null, true ]");
	ucv_put(res);

	file_put("/tmp/tree-str.json", "\"text\"\n");
	res = json_file_load(vm, "/tmp/tree-str.json");
	assert_json_equal(vm, res, "\"text\"");
	ucv_put(res);

	file_put("/tmp/tree-empty.json", "");
	assert_null(json_file_load(vm, "/tmp/tree-empty.json"));

	file_put("/tmp/tree-bad.json", "{ \"a\": ");
	assert_null(json_file_load(vm, "/tmp/tree-bad.json"));

	file_put("/tmp/tree-junk.json", "not json\n");
	assert_null(json_file_load(vm, "/tmp/tree-junk.json"));

	/* only space may follow the value; a number may end the file */
	file_put("/tmp/tree-tail.json", "{ } junk");
	assert_null(json_file_load(vm, "/tmp/tree-tail.json"));
	file_put("/tmp/tree-two.json", "{ } { }");
	assert_null(json_file_load(vm, "/tmp/tree-two.json"));
	file_put("/tmp/tree-num.json", "12");
	res = json_file_load(vm, "/tmp/tree-num.json");
	assert_json_equal(vm, res, "12");
	ucv_put(res);

	assert_null(json_file_load(vm, "/tmp/tree-missing.json"));
	assert_null(json_file_load(vm, "/tmp"));
}

static void
test_deep_clone_value(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *orig = vm_json(vm,
		"{ \"a\": { \"b\": [ 1, { \"c\": \"a string longer than a pointer\" } ] },"
		"  \"e\": [ ], \"f\": { }, \"g\": null, \"h\": 2.5 }");
	uc_value_t *clone = value_deep_clone(vm, orig);
	uc_value_t *oa, *ca, *ob, *cb, *oc, *cc, *os, *cs;

	assert_null(value_deep_clone(vm, NULL));

	assert_ptr_not_equal(clone, orig);
	assert_json_equal(vm, clone,
		"{ \"a\": { \"b\": [ 1, { \"c\": \"a string longer than a pointer\" } ] },"
		" \"e\": [ ], \"f\": { }, \"g\": null, \"h\": 2.5 }");

	oa = ucv_object_get(orig, "a", NULL);
	ca = ucv_object_get(clone, "a", NULL);
	ob = ucv_object_get(oa, "b", NULL);
	cb = ucv_object_get(ca, "b", NULL);
	oc = ucv_array_get(ob, 1);
	cc = ucv_array_get(cb, 1);
	os = ucv_object_get(oc, "c", NULL);
	cs = ucv_object_get(cc, "c", NULL);
	assert_ptr_not_equal(ca, oa);
	assert_ptr_not_equal(cb, ob);
	assert_ptr_not_equal(cc, oc);
	assert_ptr_equal(cs, os);
	assert_ptr_not_equal(ucv_object_get(clone, "e", NULL), ucv_object_get(orig, "e", NULL));

	ucv_object_add(cc, "c", ucv_string_new("changed"));
	ucv_array_push(cb, ucv_int64_new(3));
	assert_json_equal(vm, oa, "{ \"b\": [ 1, { \"c\": \"a string longer than a pointer\" } ] }");

	ucv_put(clone);
	clone = value_deep_clone(vm, os);
	assert_ptr_equal(clone, os);
	ucv_put(clone);

	ucv_put(orig);
}

static void
test_navigate_or_create(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data = vm_json(vm, "{ \"A\": { \"B\": { \"x\": 1 } }, \"S\": \"str\", \"L\": [ 1 ] }");
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ \"A\", \"B\" ]"));
	assert_ptr_equal(res, navigate_by_path(vm, data, "A.B"));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ \"A\", \"C\", \"D\" ]"));
	assert_json_equal(vm, res, "{ }");
	assert_ptr_equal(res, navigate_by_path(vm, data, "A.C.D"));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ \"S\", \"T\" ]"));
	ucv_put(res);
	res = vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ \"L\" ]"));
	ucv_put(res);
	assert_json_equal(vm, data,
		"{ \"A\": { \"B\": { \"x\": 1 }, \"C\": { \"D\": { } } }, \"S\": { \"T\": { } }, \"L\": { } }");

	res = vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ ]"));
	assert_ptr_equal(res, data);
	ucv_put(res);

	assert_null(vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), vm_json(vm, "[ \"A\", 5 ]")));
	assert_null(vm_call(vm, uc_ubbf_navigate_or_create, 2, ucv_get(data), ucv_string_new("A.B")));
	assert_null(vm_call(vm, uc_ubbf_navigate_or_create, 2, vm_json(vm, "[ ]"), vm_json(vm, "[ \"A\" ]")));
	assert_null(vm_call(vm, uc_ubbf_navigate_or_create, 2, NULL, vm_json(vm, "[ \"A\" ]")));
	assert_json_equal(vm, data,
		"{ \"A\": { \"B\": { \"x\": 1 }, \"C\": { \"D\": { } } }, \"S\": { \"T\": { } }, \"L\": { } }");

	ucv_put(data);
}

static void
test_navigate_by_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_value_t *x = ucv_object_get(ucv_object_get(config, "Device", NULL), "X", NULL);

	assert_ptr_equal(navigate_by_path(vm, config, ".Device.X."), x);
	assert_ptr_equal(navigate_by_path(vm, config, "Device.X"), x);
	assert_json_equal(vm, navigate_by_path(vm, config, "Device.X.S"), "\"v\"");
	assert_null(navigate_by_path(vm, config, "Device.X.S.T"));
	assert_null(navigate_by_path(vm, config, "Device.Y"));
	assert_null(navigate_by_path(vm, config, NULL));
	assert_null(navigate_by_path(vm, x, ""));
	assert_null(navigate_by_path(vm, NULL, "Device"));
	assert_null(navigate_by_path(vm, ucv_object_get(x, "S", NULL), "Device"));

	ucv_put(config);
}

static void
test_tree_node(void **state)
{
	char *x_s[] = { "Device", "X", "S" }, *new_path[] = { "Device", "New", "A" };
	char *over[] = { "Device", "X", "S", "T" };
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_value_t *x = ucv_object_get(ucv_object_get(config, "Device", NULL), "X", NULL);
	uc_value_t *node;

	assert_ptr_equal(tree_node_get(config, x_s, 0), config);
	assert_ptr_equal(tree_node_get(config, x_s, 2), x);
	assert_json_equal(vm, tree_node_get(config, x_s, 3), "\"v\"");
	assert_null(tree_node_get(config, over, 4));
	assert_null(tree_node_get(config, new_path, 2));
	assert_null(tree_node_get(NULL, x_s, 1));

	assert_ptr_equal(tree_node_make(vm, config, x_s, 2), x);
	node = tree_node_make(vm, config, new_path, 3);
	assert_ptr_equal(tree_node_get(config, new_path, 3), node);
	assert_json_equal(vm, node, "{ }");

	/* a value that is no object gives way to an object */
	node = object_child_make(vm, x, "S");
	assert_json_equal(vm, node, "{ }");
	assert_ptr_equal(ucv_object_get(x, "S", NULL), node);
	assert_ptr_equal(object_child_make(vm, x, "S"), node);

	ucv_put(config);
}

static void
get_expect(uc_vm_t *vm, uc_value_t *config, uc_value_t *path, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_get, 2, ucv_get(config), path);

	if (expected)
		assert_json_equal(vm, res, expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_get(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);

	get_expect(vm, config, ucv_string_new("Device.X.S"), "\"v\"");
	get_expect(vm, config, ucv_string_new(".Device.X.S."), "\"v\"");
	get_expect(vm, config, ucv_string_new("Device.X.Zero"), "0");
	get_expect(vm, config, ucv_string_new("Device.X.Off"), "false");
	get_expect(vm, config, ucv_string_new("Device.Ethernet.Interface.2"), "{ \"Name\": \"lan2\" }");
	get_expect(vm, config, ucv_string_new("Device.X.Nil"), NULL);
	get_expect(vm, config, ucv_string_new("Device.X.Missing"), NULL);
	get_expect(vm, config, ucv_string_new("Device.X.S.Deeper"), NULL);
	get_expect(vm, config, ucv_string_new(""), NULL);
	get_expect(vm, config, ucv_int64_new(1), NULL);
	get_expect(vm, config, NULL, NULL);
	get_expect(vm, NULL, ucv_string_new("Device"), NULL);

	ucv_put(config);
}

static void
test_instances(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_instances, 2, ucv_get(config), ucv_string_new("Device.Ethernet.Interface"));
	assert_json_equal(vm, res,
		"[ { \"Name\": \"lan1\", \".instance\": \"1\", \".path\": \"Device.Ethernet.Interface.1\" }, "
		"{ \"Name\": \"lan2\", \".instance\": \"2\", \".path\": \"Device.Ethernet.Interface.2\" }, "
		"{ \"Enable\": \"true\", \".instance\": \"3\", \".path\": \"Device.Ethernet.Interface.3\" } ]");
	assert_ptr_equal(ucv_array_get(res, 0), navigate_by_path(vm, config, "Device.Ethernet.Interface.1"));
	ucv_put(res);

	assert_json_equal(vm, navigate_by_path(vm, config, "Device.Ethernet.Interface.2"),
		"{ \"Name\": \"lan2\", \".instance\": \"2\", \".path\": \"Device.Ethernet.Interface.2\" }");

	res = vm_call(vm, uc_ubbf_instances, 2, ucv_get(config), ucv_string_new("Device.X"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	/* a trailing dot of the table path stays out of the row path, and a
	 * key that is no instance number is no row */
	res = vm_call(vm, uc_ubbf_instances, 2,
		      vm_json(vm, "{ \"Device\": { \"T\": { \"1\": { }, \"Meta\": { }, \"02\": { } } } }"),
		      ucv_string_new("Device.T."));
	assert_json_equal(vm, res, "[ { \".instance\": \"1\", \".path\": \"Device.T.1\" } ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_instances, 2, ucv_get(config), ucv_string_new("Device.X.S"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_instances, 2, ucv_get(config), ucv_string_new("Device.Missing"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_instances, 2, ucv_get(config), NULL);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_instances, 2, NULL, ucv_string_new("Device"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	ucv_put(config);
}

static void
enabled_expect(uc_vm_t *vm, const char *value, bool expected)
{
	char buf[128];
	uc_value_t *res;

	snprintf(buf, sizeof(buf), "{ \"Device\": { \"X\": { \"Enable\": %s } } }", value);
	res = vm_call(vm, uc_ubbf_enabled, 2, vm_json(vm, buf), ucv_string_new("Device.X.Enable"));
	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_enabled(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	enabled_expect(vm, "true", true);
	enabled_expect(vm, "false", false);
	enabled_expect(vm, "\"true\"", true);
	enabled_expect(vm, "\"1\"", true);
	enabled_expect(vm, "\"false\"", false);
	enabled_expect(vm, "\"0\"", false);
	enabled_expect(vm, "\"TRUE\"", false);
	enabled_expect(vm, "\"\"", false);
	enabled_expect(vm, "1", false);
	enabled_expect(vm, "null", false);
	enabled_expect(vm, "{ }", false);

	res = vm_call(vm, uc_ubbf_enabled, 2, vm_json(vm, "{ \"Enable\": true }"), ucv_string_new("Missing"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_enabled, 2, vm_json(vm, "{ \"Enable\": true }"), NULL);
	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_false(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_enabled, 2, NULL, ucv_string_new("Enable"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
}

static void
name_expect(uc_vm_t *vm, uc_cfn_ptr_t fn, uc_value_t *config, uc_value_t *ref, const char *expected)
{
	uc_value_t *res = vm_call(vm, fn, 2, ucv_get(config), ref);

	if (expected)
		assert_string_equal(ucv_string_get(res), expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_interface_to_name(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_cfn_ptr_t fn = uc_ubbf_interface_to_name;

	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.1"), "lan1");
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.2."), "lan2");
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.3"), NULL);
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.4"), NULL);
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.9"), NULL);
	name_expect(vm, fn, config, ucv_string_new(""), NULL);
	name_expect(vm, fn, config, ucv_int64_new(1), NULL);
	name_expect(vm, fn, config, NULL, NULL);
	name_expect(vm, fn, NULL, ucv_string_new("Device.Ethernet.Interface.1"), NULL);

	ucv_put(config);
}

static void
test_lower_layer_resolve(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_cfn_ptr_t fn = uc_ubbf_lower_layer_resolve;

	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.1"), "lan1");
	name_expect(vm, fn, config,
		    ucv_string_new("Device.Ethernet.Interface.2,Device.Ethernet.Interface.1"), "lan2");
	name_expect(vm, fn, config, ucv_string_new("  Device.Ethernet.Interface.2, X"), "lan2");
	name_expect(vm, fn, config,
		    ucv_string_new("Device.Ethernet.Interface.9,Device.Ethernet.Interface.1"), NULL);
	name_expect(vm, fn, config, ucv_string_new(",Device.Ethernet.Interface.1"), NULL);
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.3"), NULL);
	name_expect(vm, fn, config, ucv_string_new("Device.Ethernet.Interface.4"), NULL);
	name_expect(vm, fn, config, ucv_string_new(""), NULL);
	name_expect(vm, fn, config, ucv_int64_new(1), NULL);
	name_expect(vm, fn, config, NULL, NULL);
	name_expect(vm, fn, NULL, ucv_string_new("Device.Ethernet.Interface.1"), NULL);

	ucv_put(config);
}

static void
navigate_expect(uc_vm_t *vm, uc_value_t *data, const char *parts, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_navigate, 2, ucv_get(data), parts ? vm_json(vm, parts) : NULL);

	if (expected)
		assert_json_equal(vm, res, expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_navigate_data(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *config = vm_json(vm, config_json);
	uc_value_t *res;

	navigate_expect(vm, config, "[ \"Device\", \"X\", \"S\" ]", "\"v\"");
	navigate_expect(vm, config, "[ \"Device\", \"X\", \"Zero\" ]", "0");
	navigate_expect(vm, config, "[ \"Device\", \"Ethernet\", \"Interface\", \"1\" ]", "{ \"Name\": \"lan1\" }");
	navigate_expect(vm, config, "[ \"Device\", \"X\", \"Nil\" ]", NULL);
	navigate_expect(vm, config, "[ \"Device\", \"Y\" ]", NULL);
	navigate_expect(vm, config, "[ \"Device\", \"X\", \"S\", \"T\" ]", NULL);
	navigate_expect(vm, config, "[ \"Device\", 1 ]", NULL);
	navigate_expect(vm, config, "[ \"Device.X\" ]", NULL);
	navigate_expect(vm, config, "{ \"0\": \"Device\" }", NULL);
	navigate_expect(vm, config, NULL, NULL);
	navigate_expect(vm, NULL, "[ \"Device\" ]", NULL);
	navigate_expect(vm, NULL, "[ ]", NULL);

	res = vm_call(vm, uc_ubbf_navigate, 2, ucv_get(config), vm_json(vm, "[ ]"));
	assert_ptr_equal(res, config);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_navigate, 2, ucv_string_new("leaf"), vm_json(vm, "[ ]"));
	assert_string_equal(ucv_string_get(res), "leaf");
	ucv_put(res);

	ucv_put(config);
}

static void
test_ctx_config(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *ctx = vm_json(vm, "{ \"config\": { \"Enable\": \"true\" } }");
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_ctx_config, 1, ucv_get(ctx));
	assert_ptr_equal(res, ucv_object_get(ctx, "config", NULL));
	ucv_put(res);
	ucv_put(ctx);

	res = vm_call(vm, uc_ubbf_ctx_config, 1, vm_json(vm, "{ \"config\": \"x\" }"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ctx_config, 1, vm_json(vm, "{ \"config\": [ 1 ] }"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ctx_config, 1, vm_json(vm, "{ \"root\": { } }"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ctx_config, 1, vm_json(vm, "[ { \"config\": { } } ]"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ctx_config, 0);
	assert_int_equal(ucv_type(res), UC_OBJECT);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);
}

static void
test_json_file_load_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	char a[64], b[64];

	file_put("/tmp/tree-o.json", "{ \"k\": 1 }");
	res = json_file_load_object(vm, "/tmp/tree-o.json");
	assert_json_equal(vm, res, "{ \"k\": 1 }");
	ucv_put(res);

	file_put("/tmp/tree-a.json", "[ 1 ]");
	res = json_file_load_object(vm, "/tmp/tree-a.json");
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = json_file_load_object(vm, "/tmp/tree-none.json");
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	/* a rewrite of the file changes its identity */
	file_id("/tmp/tree-o.json", a, sizeof(a));
	assert_true(a[0] != '\0');
	file_put("/tmp/tree-o.json.new", "{ \"k\": 22 }");
	assert_int_equal(rename("/tmp/tree-o.json.new", "/tmp/tree-o.json"), 0);
	file_id("/tmp/tree-o.json", b, sizeof(b));
	assert_string_not_equal(a, b);

	file_id("/tmp/tree-none.json", a, sizeof(a));
	assert_string_equal(a, "");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_json_file_load),
		cmocka_unit_test(test_json_file_load_object),
		cmocka_unit_test(test_deep_clone_value),
		cmocka_unit_test(test_navigate_or_create),
		cmocka_unit_test(test_navigate_by_path),
		cmocka_unit_test(test_tree_node),
		cmocka_unit_test(test_get),
		cmocka_unit_test(test_instances),
		cmocka_unit_test(test_enabled),
		cmocka_unit_test(test_interface_to_name),
		cmocka_unit_test(test_lower_layer_resolve),
		cmocka_unit_test(test_navigate_data),
		cmocka_unit_test(test_ctx_config),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
