/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * order.c, the TR-181 data type Order.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>

static uc_value_t *
tree_new(uc_vm_t *vm, const char *rows)
{
	char buf[1024];

	snprintf(buf, sizeof(buf), "{ \"Device\": { \"QoS\": { \"Classification\": %s } } }", rows);

	return vm_json(vm, buf);
}

static uc_value_t *
rows_get(uc_value_t *data)
{
	uc_value_t *device = ucv_object_get(data, "Device", NULL);

	return ucv_object_get(ucv_object_get(device, "QoS", NULL), "Classification", NULL);
}

static void
row_set(uc_vm_t *vm, uc_value_t *data, const char *key, const char *row)
{
	ucv_object_add(rows_get(data), key, row ? vm_json(vm, row) : NULL);
}

static void
row_del(uc_value_t *data, const char *key)
{
	ucv_object_delete(rows_get(data), key);
}

static uc_value_t *
snapshot(uc_vm_t *vm, uc_value_t *data)
{
	return vm_call(vm, uc_ubbf_order_snapshot, 1, ucv_get(data));
}

static bool
compute(uc_vm_t *vm, uc_value_t *data, uc_value_t *before)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_orders_compute, 2, ucv_get(data), before);
	bool changed = ucv_boolean_get(res);

	ucv_put(res);

	return changed;
}

static void
test_snapshot(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data = vm_json(vm,
		"{ \"Device\": {"
		"  \"QoS\": { \"Classification\": { \"2\": { \"Order\": \"3\" }, \"1\": {},"
		"    \"3\": { \"Order\": \"0\" }, \"4\": { \"Order\": \"x\" }, \"5\": { \"Order\": 2 },"
		"    \"Alias\": { \"Order\": \"1\" } } },"
		"  \"Firewall\": { \"Chain\": { \"1\": { \"Rule\": { \"1\": { \"Order\": \"1\" } } },"
		"    \"2\": { \"Rule\": {} }, \"3\": {} } },"
		"  \"Bridging\": { \"Filter\": \"none\" } } }");
	uc_value_t *snap = snapshot(vm, data);

	assert_json_equal(vm, snap,
		"{ \"Device.Firewall.Chain.1.Rule\": { \"1\": 1 }, "
		"\"Device.Firewall.Chain.2.Rule\": { }, "
		"\"Device.QoS.Classification\": { \"1\": null, \"2\": 3, \"3\": null, \"4\": null, \"5\": 2 } }");

	ucv_put(snap);
	ucv_put(data);

	snap = vm_call(vm, uc_ubbf_order_snapshot, 1, NULL);
	assert_json_equal(vm, snap, "{ }");
	ucv_put(snap);
}

static void
test_loaded(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data;

	data = tree_new(vm, "{ \"1\": { \"Order\": \"2\" }, \"2\": { \"Order\": \"2\" },"
			    " \"3\": { \"Order\": \"\" }, \"4\": { \"Order\": \"1\" } }");
	assert_true(compute(vm, data, NULL));
	assert_json_equal(vm, rows_get(data),
		"{ \"1\": { \"Order\": \"2\" }, \"2\": { \"Order\": \"3\" }, "
		"\"3\": { \"Order\": \"4\" }, \"4\": { \"Order\": \"1\" } }");
	ucv_put(data);

	data = tree_new(vm, "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" } }");
	assert_false(compute(vm, data, NULL));
	ucv_put(data);

	data = tree_new(vm, "{ \"1\": { \"Order\": 1 }, \"2\": { \"Order\": 7 }, \"9\": {},"
			    " \"x\": { \"Order\": \"5\" }, \"3\": \"text\" }");
	assert_true(compute(vm, data, NULL));
	assert_json_equal(vm, rows_get(data),
		"{ \"1\": { \"Order\": 1 }, \"2\": { \"Order\": 7 }, \"9\": { \"Order\": \"9\" }, "
		"\"x\": { \"Order\": \"5\" }, \"3\": \"text\" }");
	ucv_put(data);
}

static void
test_nested(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data = vm_json(vm,
		"{ \"Device\": { \"Firewall\": { \"Chain\": { \"1\": { \"Rule\": {"
		"  \"1\": {}, \"2\": { \"Order\": \"1\" } } } } } } }");

	assert_true(compute(vm, data, NULL));
	assert_json_equal(vm, navigate_by_path(vm, data, "Device.Firewall.Chain.1.Rule"),
		"{ \"1\": { \"Order\": \"2\" }, \"2\": { \"Order\": \"1\" } }");
	ucv_put(data);
}

struct change_case {
	const char *start;
	const char *key;
	const char *row;
	const char *deleted;
	const char *expected;
};

static void
test_changed(void **state)
{
	static const struct change_case cases[] = {
		/* a new row without Order goes last */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" } }",
		  "3", "{ \"Order\": \"\" }", NULL,
		  "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"3\" } }" },
		/* a new row with a taken Order moves that row and the lower ones down */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" } }",
		  "3", "{ \"Order\": \"1\" }", NULL,
		  "{ \"1\": { \"Order\": \"2\" }, \"2\": { \"Order\": \"3\" }, \"3\": { \"Order\": \"1\" } }" },
		/* a write of a taken Order */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"3\" } }",
		  "3", "{ \"Order\": \"2\" }", NULL,
		  "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"3\" }, \"3\": { \"Order\": \"2\" } }" },
		/* a write of a free Order moves nothing */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" } }",
		  "1", "{ \"Order\": \"5\" }", NULL,
		  "{ \"1\": { \"Order\": \"5\" }, \"2\": { \"Order\": \"2\" } }" },
		/* a deletion compacts the values */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"3\" } }",
		  NULL, NULL, "2",
		  "{ \"1\": { \"Order\": \"1\" }, \"3\": { \"Order\": \"2\" } }" },
		/* a deletion compacts after a gap */
		{ "{ \"1\": { \"Order\": \"2\" }, \"2\": { \"Order\": \"7\" }, \"3\": { \"Order\": \"9\" } }",
		  NULL, NULL, "1",
		  "{ \"2\": { \"Order\": \"1\" }, \"3\": { \"Order\": \"2\" } }" },
		/* a write and a deletion together: the write moves first, then compaction */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"3\" } }",
		  "3", "{ \"Order\": \"1\" }", "1",
		  "{ \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"1\" } }" },
		/* a row without Order keeps last place after a deletion */
		{ "{ \"1\": { \"Order\": \"1\" }, \"2\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"3\" } }",
		  "4", "{ }", "2",
		  "{ \"1\": { \"Order\": \"1\" }, \"3\": { \"Order\": \"2\" }, \"4\": { \"Order\": \"3\" } }" },
		/* two writes of the same value: the lower instance gets it first */
		{ "{ \"1\": { \"Order\": \"1\" } }",
		  "3", "{ \"Order\": \"1\" }", NULL,
		  "{ \"1\": { \"Order\": \"2\" }, \"3\": { \"Order\": \"1\" } }" },
	};
	uc_vm_t *vm = *state;

	for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
		uc_value_t *data = tree_new(vm, cases[i].start);
		uc_value_t *before = snapshot(vm, data);

		if (cases[i].key)
			row_set(vm, data, cases[i].key, cases[i].row);
		if (cases[i].deleted)
			row_del(data, cases[i].deleted);

		compute(vm, data, before);
		assert_json_equal(vm, rows_get(data), cases[i].expected);
		ucv_put(data);
	}
}

static void
test_changed_two_new(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data = tree_new(vm, "{ \"1\": { \"Order\": \"1\" } }");
	uc_value_t *before = snapshot(vm, data);

	row_set(vm, data, "5", "{ }");
	row_set(vm, data, "4", "{ }");
	row_set(vm, data, "6", "{ \"Order\": \"1\" }");
	row_set(vm, data, "7", "{ \"Order\": \"1\" }");

	assert_true(compute(vm, data, before));
	assert_json_equal(vm, rows_get(data),
		"{ \"1\": { \"Order\": \"3\" }, \"5\": { \"Order\": \"5\" }, \"4\": { \"Order\": \"4\" }, "
		"\"6\": { \"Order\": \"2\" }, \"7\": { \"Order\": \"1\" } }");
	ucv_put(data);
}

static void
test_changed_new_table(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *data = vm_json(vm, "{ \"Device\": {} }");
	uc_value_t *before = snapshot(vm, data);

	ucv_put(data);
	data = tree_new(vm, "{ \"1\": { \"Order\": \"4\" }, \"2\": { \"Order\": \"4\" } }");

	assert_true(compute(vm, data, before));
	assert_json_equal(vm, rows_get(data),
		"{ \"1\": { \"Order\": \"4\" }, \"2\": { \"Order\": \"5\" } }");
	ucv_put(data);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_snapshot),
		cmocka_unit_test(test_loaded),
		cmocka_unit_test(test_nested),
		cmocka_unit_test(test_changed),
		cmocka_unit_test(test_changed_two_new),
		cmocka_unit_test(test_changed_new_table),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
