/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The instance map (map.c). It writes /tmp/ubbf/instance-map.json and reads
 * /etc/ubbf/config.json, so the program runs isolated (run-isolated.sh);
 * each case uses its own tables.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <time.h>

#define MAP_PATH	"/tmp/ubbf/instance-map.json"
#define CONFIG_PATH	"/etc/ubbf/config.json"

/* Runs ucode and compares the value of its `return` as JSON. */
static void
eval_equal(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
file_write(const char *path, const char *text)
{
	FILE *fp = fopen(path, "w");

	assert_non_null(fp);
	fputs(text, fp);
	fclose(fp);
}

static int
group_setup(void **state)
{
	if (vm_setup(state))
		return -1;

	ucv_put(vm_eval(*state, "ubbf.instance_map_own(true);"));
	return 0;
}

static void
test_numbers(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "return ubbf.instance_numbers('T', [ 'a', 'b', 'c' ]);",
		   "{ \"a\": 1, \"b\": 2, \"c\": 3 }");
	eval_equal(vm, "return ubbf.instance_numbers('T', [ 'c', 'a' ]);", "{ \"c\": 3, \"a\": 1 }");
	eval_equal(vm, "return ubbf.instance_numbers('T', [ 'd', 'a' ]);", "{ \"d\": 4, \"a\": 1 }");
	eval_equal(vm, "return ubbf.instance_numbers('T', [ 'b' ]);", "{ \"b\": 2 }");
	eval_equal(vm, "return ubbf.instance_numbers('T', [ 5 ]);", "{ \"5\": 5 }");
	eval_equal(vm, "return ubbf.instance_numbers(null, [ 'a' ]);", "{ }");
}

static void
test_key_lookup_rows(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "ubbf.instance_numbers('K', [ 'a', 'b' ]);"
		   "return [ ubbf.instance_key('K', [ 'a', 'b' ], 2), ubbf.instance_key('K', [ 'a' ], '2'),"
		   "  ubbf.instance_lookup('K', '2'), ubbf.instance_lookup('K', 9) ];",
		   "[ \"b\", null, \"b\", null ]");
	eval_equal(vm, "return ubbf.instance_rows('K', [ 'b', 'a' ], (k, n) => k + n);",
		   "{ \"2\": \"b2\", \"1\": \"a1\" }");
	eval_equal(vm, "return ubbf.instance_number('K', 'c');", "3");
}

static void
test_floor_next_known(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "return [ ubbf.instance_floor({ '1': {}, '3': {}, Alias: 'x' }), ubbf.instance_floor(null) ];",
		   "[ 4, 1 ]");
	eval_equal(vm, "return ubbf.instance_numbers('F', [ 'x' ], 4);", "{ \"x\": 4 }");
	/* the number of a dm.object_add(); a table off the map gets none */
	assert_int_equal(instance_map_add_number(vm, "F", 4), 5);
	assert_int_equal(instance_map_add_number(vm, "G", 4), 0);
	eval_equal(vm, "return ubbf.instance_numbers('F', [ 'x', 'y' ], 4);", "{ \"x\": 4, \"y\": 6 }");
	assert_int_equal(instance_map_add_number(vm, "F", 9), 9);
}

static void
test_add_number_from_c(void **state)
{
	uc_vm_t *vm = *state;

	assert_int_equal(instance_map_add_number(vm, "Device.Unknown", 1), 0);
	ucv_put(vm_eval(vm, "ubbf.instance_numbers('Device.C', [ 'a' ]);"));
	assert_int_equal(instance_map_add_number(vm, "Device.C", 1), 2);
	assert_int_equal(instance_map_add_number(vm, "Device.C", 7), 7);
}

static void
test_prune_items(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "ubbf.instance_numbers('S', [ 's1', 's2' ]); ubbf.instance_prune('S', [ 's2' ]);"
		   "return ubbf.instance_numbers_known('S', [ 's1', 's2' ]);", "{ \"s2\": 2 }");
	eval_equal(vm, "return ubbf.instance_numbers('S', [ 's2', 's3' ]);", "{ \"s2\": 2, \"s3\": 3 }");
	eval_equal(vm, "return ubbf.instance_items('I', [ { id: 7 }, { id: 9 } ], (m) => sprintf('%d', m.id));",
		   "{ \"1\": { \"id\": 7 }, \"2\": { \"id\": 9 } }");
	eval_equal(vm, "return ubbf.instance_items('I', [ { id: 9 }, { id: 4 } ], (m) => sprintf('%d', m.id));",
		   "{ \"2\": { \"id\": 9 }, \"3\": { \"id\": 4 } }");
	eval_equal(vm, "return ubbf.instance_numbers_known('I', [ '7', '9', '4' ]);",
		   "{ \"9\": 2, \"4\": 3 }");
	eval_equal(vm, "return ubbf.instance_items('I', [ { id: 5 } ], 'not a function');", "{ }");
}

static void
test_retire(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "ubbf.instance_numbers('B', [ 'lab' ], 3); ubbf.instance_retire('B', 'lab');"
		   "return [ ubbf.instance_numbers('B', [ 'lab' ]), ubbf.instance_lookup('B', 3) ];",
		   "[ { \"lab\": 4 }, \"#3\" ]");
}

static void
test_not_owner(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "ubbf.instance_numbers('O', [ 'a' ]); ubbf.instance_map_own(false); return null;", "null");
	assert_int_equal(instance_map_add_number(vm, "O", 1), 0);
	eval_equal(vm,
		   "let r = [ ubbf.instance_numbers('O', [ 'a', 'b' ]),"
		   "  ubbf.instance_number('O', 'c'), ubbf.instance_retire('O', 'a'), ubbf.instance_lookup('O', 1) ];"
		   "ubbf.instance_prune('O', []);"
		   "r[4] = ubbf.instance_lookup('O', 1);"
		   "ubbf.instance_map_own(true);"
		   "return r;",
		   "[ { \"a\": 1 }, null, null, \"a\", \"a\" ]");
}

static void
test_other_process_write(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *file = json_file_load(vm, MAP_PATH), *row;
	char *json;

	assert_non_null(file);
	row = vm_json(vm, "{ \"next\": 3, \"keys\": { \"w\": { \"n\": 2 } } }");
	ucv_object_add(file, "W", row);
	json = ucv_to_jsonstring(vm, file);

	/* Another process replaces the file: another inode. */
	unlink(MAP_PATH);
	file_write(MAP_PATH, json);
	free(json);
	ucv_put(file);

	eval_equal(vm, "return ubbf.instance_lookup('W', 2);", "\"w\"");
}

static void
test_expiry(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *file = json_file_load(vm, MAP_PATH);
	struct timespec ts;
	char row[512], *json;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	snprintf(row, sizeof(row),
		 "{ \"next\": 5, \"keys\": { \"old\": { \"n\": 1, \"last_seen\": %lld },"
		 " \"pin\": { \"n\": 2, \"last_seen\": %lld }, \"recent\": { \"n\": 3, \"last_seen\": %lld },"
		 " \"#4\": { \"n\": 4 } } }",
		 (long long)ts.tv_sec - 90000, (long long)ts.tv_sec - 90000, (long long)ts.tv_sec - 3600);
	ucv_object_add(file, "E", vm_json(vm, row));
	json = ucv_to_jsonstring(vm, file);
	unlink(MAP_PATH);
	file_write(MAP_PATH, json);
	free(json);
	ucv_put(file);

	file_write(CONFIG_PATH, "{ \"Device\": {}, \"_instances\": { \"E\": { \"2\": \"pin\" } } }");

	/* A lookup of one row removes nothing; a full one removes the stale
	 * key that no pin names, and its number is not given again. */
	eval_equal(vm, "return [ ubbf.instance_number('E', 'new'), ubbf.instance_lookup('E', 1) ];",
		   "[ 5, \"old\" ]");
	eval_equal(vm, "ubbf.instance_numbers('E', [ 'new' ]);"
		   "return map([ 1, 2, 3, 4 ], (n) => ubbf.instance_lookup('E', n));",
		   "[ null, \"pin\", \"recent\", \"#4\" ]");
	eval_equal(vm, "return ubbf.instance_numbers('E', [ 'new', 'old' ]);", "{ \"new\": 5, \"old\": 6 }");

	unlink(CONFIG_PATH);
}

static void
test_pins(void **state)
{
	uc_vm_t *vm = *state;

	uc_value_t *config, *pins;

	eval_equal(vm,
		"ubbf.instance_numbers('Device.P.Row', [ 'k1', 'k2', 'k3' ]);"
		"ubbf.instance_numbers('Device.P.Row.2.Sub', [ 's1' ]); return null;", "null");

	config = vm_json(vm, "{ \"Device\": {"
		"  \"P\": { \"Row\": { \"2\": { \"Enable\": \"false\" } } },"
		"  \"Q\": { \"Ref\": \"Device.P.Row.3.Name,Device.P.Row.2.Sub.1\", \"Text\": \"Device.P.Row.9\","
		"    \"List\": [ \"xDevice.P.Row.1\" ] } } }");
	pins = instance_pins_new(vm, config);
	assert_json_equal(vm, pins,
		"{ \"Device.P.Row\": { \"1\": \"k1\", \"2\": \"k2\", \"3\": \"k3\" }, \"Device.P.Row.2.Sub\": { \"1\": \"s1\" } }");
	ucv_put(pins);
	ucv_put(config);

	config = vm_json(vm, "{ \"Device\": { \"Q\": { \"Ref\": \"Device.Z.1\", \"R\": \"Device.\" } } }");
	pins = instance_pins_new(vm, config);
	assert_json_equal(vm, pins, "{ }");
	ucv_put(pins);
	ucv_put(config);
}

static void
test_pins_load(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "ubbf.config_pins_take({ _instances: { 'Device.R.Row': { '2': 'k2', '3': 'k3' } } });"
		   "return [ ubbf.instance_numbers('Device.R.Row', [ 'k3', 'k9' ]), ubbf.instance_numbers('Device.R.Row', [ 'k2' ]) ];",
		   "[ { \"k3\": 3, \"k9\": 4 }, { \"k2\": 2 } ]");
	eval_equal(vm, "ubbf.config_pins_take({ _instances: { 'Device.R.Row': { '4': 'k5' } } });"
		   "return ubbf.instance_numbers('Device.R.Row', [ 'k5' ]);", "{ \"k5\": 5 }");
	eval_equal(vm, "ubbf.config_pins_take({ _instances: { 'Device.R.Row': { '7': 'k3' } } });"
		   "return ubbf.instance_numbers('Device.R.Row', [ 'k3' ]);", "{ \"k3\": 7 }");
	eval_equal(vm, "ubbf.config_pins_take({ _instances: { 'Device.R.Row': { 'x': 'k8', '0': 'k8', '9': 8 }, bad: 1 } });"
		   "return ubbf.instance_lookup('Device.R.Row', 9);", "null");
}

static void
test_seed_after_reboot(void **state)
{
	uc_vm_t *vm = *state;

	file_write(CONFIG_PATH, "{ \"Device\": {}, \"_instances\": { \"Device.C.Cert\": { \"4\": \"file:/a.pem\" } } }");
	unlink(MAP_PATH);

	ucv_put(vm_eval(vm, "ubbf.instance_map_own(false);"));
	eval_equal(vm, "return ubbf.instance_numbers_known('Device.C.Cert', [ 'file:/a.pem' ]);",
		   "{ \"file:/a.pem\": 4 }");
	ucv_put(vm_eval(vm, "ubbf.instance_map_own(true);"));

	/* Any process seeds the map and writes it. */
	assert_int_equal(access(MAP_PATH, F_OK), 0);
	unlink(CONFIG_PATH);
}

static void
test_stack(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "let by_name = (row, item) => row.Name == item;"
		   "return ubbf.instance_stack({ '1': { Name: 'b' }, '3': { Name: 'a' } }, [ 'a', 'b', 'c' ], by_name);",
		   "{ \"1\": \"b\", \"3\": \"a\", \"4\": \"c\" }");
	eval_equal(vm, "let by_name = (row, item) => row.Name == item;"
		   "return ubbf.instance_stack({ '2': { Name: 'x' } }, [ 'a' ], by_name);",
		   "{ \"3\": \"a\" }");
	eval_equal(vm, "let by_name = (row, item) => row.Name == item, loose = (row, item) => row.Name == null;"
		   "return ubbf.instance_stack({ '1': {}, '2': { Name: 'a' } }, [ 'a', 'b' ], by_name, loose);",
		   "{ \"2\": \"a\", \"1\": \"b\" }");
	eval_equal(vm, "return ubbf.instance_stack(null, [ 'a', 'b' ], () => false);",
		   "{ \"1\": \"a\", \"2\": \"b\" }");
}

static void
test_ids(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "let e = [ {}, { id: 5 }, {} ]; let next = ubbf.instance_ids(e);"
		   "return [ map(e, (x) => x.id), next ];", "[ [ 6, 5, 7 ], 8 ]");
	eval_equal(vm, "let e = [ {} ]; return [ ubbf.instance_ids(e, 10), e[0].id ];", "[ 11, 10 ]");
	eval_equal(vm, "return ubbf.instance_id_rows([ { id: 2, v: 'b' }, { id: 1, v: 'a' } ], (e) => e.v);",
		   "{ \"2\": \"b\", \"1\": \"a\" }");
}

static void
test_callback_exception(void **state)
{
	uc_vm_t *vm = *state;

	eval_equal(vm, "try { ubbf.instance_rows('X', [ 'a' ], () => die('boom')); return 'no'; }"
		   "catch (e) { return e.message; }", "\"boom\"");
	eval_equal(vm, "try { ubbf.instance_stack({ '1': {} }, [ 'a' ], () => die('stack')); return 'no'; }"
		   "catch (e) { return e.message; }", "\"stack\"");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_numbers),
		cmocka_unit_test(test_key_lookup_rows),
		cmocka_unit_test(test_floor_next_known),
		cmocka_unit_test(test_add_number_from_c),
		cmocka_unit_test(test_prune_items),
		cmocka_unit_test(test_retire),
		cmocka_unit_test(test_not_owner),
		cmocka_unit_test(test_other_process_write),
		cmocka_unit_test(test_expiry),
		cmocka_unit_test(test_pins),
		cmocka_unit_test(test_pins_load),
		cmocka_unit_test(test_seed_after_reboot),
		cmocka_unit_test(test_stack),
		cmocka_unit_test(test_ids),
		cmocka_unit_test(test_callback_exception),
	};

	return cmocka_run_group_tests(tests, group_setup, vm_teardown);
}
