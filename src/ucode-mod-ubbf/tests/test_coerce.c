/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * coerce.c: to_bool(), to_int() and csv_to_list(), and the C functions
 * value_to_bool(), value_to_int(), loose_equal() and csv_list_new().
 */

#include "harness.h"
#include "ubbf.h"

static void
test_value_to_bool(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *obj = vm_json(vm, "{ \"a\": true }");
	uc_value_t *arr = vm_json(vm, "[ true ]");
	uc_value_t *vals[] = {
		ucv_string_new("TRUE"), ucv_string_new("True"), ucv_string_new("yes"),
		ucv_string_new("on"), ucv_string_new("0"), ucv_string_new("false"),
		ucv_string_new(""), ucv_string_new("true "), ucv_string_new(" 1"),
		ucv_string_new("01"), ucv_int64_new(1), ucv_double_new(1.0),
	};
	uc_value_t *t = ucv_string_new("true"), *one = ucv_string_new("1");

	assert_true(value_to_bool(ucv_boolean_new(true)));
	assert_false(value_to_bool(ucv_boolean_new(false)));
	assert_true(value_to_bool(t));
	assert_true(value_to_bool(one));
	assert_false(value_to_bool(NULL));
	assert_false(value_to_bool(obj));
	assert_false(value_to_bool(arr));

	for (size_t i = 0; i < sizeof(vals) / sizeof(vals[0]); i++) {
		assert_false(value_to_bool(vals[i]));
		ucv_put(vals[i]);
	}

	ucv_put(t);
	ucv_put(one);
	ucv_put(obj);
	ucv_put(arr);
}

static void
bool_expect(uc_vm_t *vm, uc_value_t *val, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_to_bool, 1, val);

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_to_bool(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	bool_expect(vm, ucv_boolean_new(true), true);
	bool_expect(vm, ucv_boolean_new(false), false);
	bool_expect(vm, ucv_string_new("true"), true);
	bool_expect(vm, ucv_string_new("1"), true);
	bool_expect(vm, ucv_string_new("false"), false);
	bool_expect(vm, ucv_string_new("0"), false);
	bool_expect(vm, ucv_string_new("TRUE"), false);
	bool_expect(vm, ucv_string_new(""), false);
	bool_expect(vm, ucv_int64_new(1), false);
	bool_expect(vm, NULL, false);

	res = vm_call(vm, uc_ubbf_to_bool, 0);
	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
}

static void
int_expect(uc_vm_t *vm, uc_value_t *val, int64_t expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_to_int, 1, val);

	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
int_null_expect(uc_vm_t *vm, uc_value_t *val)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_to_int, 1, val);

	assert_null(res);
}

static void
test_to_int(void **state)
{
	uc_vm_t *vm = *state;

	int_expect(vm, ucv_int64_new(42), 42);
	int_expect(vm, ucv_int64_new(-7), -7);
	int_expect(vm, ucv_int64_new(INT64_MAX), INT64_MAX);
	int_expect(vm, ucv_string_new("123"), 123);
	int_expect(vm, ucv_string_new("-45"), -45);
	int_expect(vm, ucv_string_new("+5"), 5);
	int_expect(vm, ucv_string_new("0"), 0);
	int_expect(vm, ucv_string_new("007"), 7);
	int_expect(vm, ucv_string_new("9223372036854775807"), INT64_MAX);
	int_expect(vm, ucv_string_new("-9223372036854775808"), INT64_MIN);

	int_null_expect(vm, ucv_string_new("12 "));
	int_null_expect(vm, ucv_string_new("99999999999999999999"));
	int_null_expect(vm, ucv_string_new("-9223372036854775809"));
	int_null_expect(vm, ucv_string_new("12a"));
	int_null_expect(vm, ucv_string_new("0x10"));
	int_null_expect(vm, ucv_string_new("1.5"));
	int_null_expect(vm, ucv_string_new("abc"));
	int_null_expect(vm, ucv_string_new("-"));
	int_null_expect(vm, ucv_string_new(" "));
	int_null_expect(vm, ucv_string_new(""));
	int_null_expect(vm, ucv_double_new(3.0));
	int_null_expect(vm, ucv_boolean_new(true));
	int_null_expect(vm, vm_json(vm, "[ 1 ]"));
	int_null_expect(vm, NULL);
}

static void
test_value_to_int(void **state)
{
	uc_value_t *dbl = ucv_double_new(1.0);
	int64_t n = -1;

	(void)state;

	assert_true(value_to_int(ucv_string_new("42"), &n));
	assert_int_equal(n, 42);
	assert_true(value_to_int(ucv_int64_new(-3), &n));
	assert_int_equal(n, -3);
	assert_false(value_to_int(ucv_string_new("4x"), &n));
	assert_false(value_to_int(ucv_string_new(""), &n));
	assert_false(value_to_int(dbl, &n));
	assert_false(value_to_int(NULL, &n));
	assert_int_equal(n, -3);

	ucv_put(dbl);
}

static void
test_loose_equal(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *obj = vm_json(vm, "{ }");

	/* the results of ucode's == for the same pairs */
	assert_true(loose_equal(ucv_string_new("6"), ucv_int64_new(6)));
	assert_true(loose_equal(ucv_string_new(" 6"), ucv_int64_new(6)));
	assert_true(loose_equal(ucv_string_new(""), ucv_int64_new(0)));
	assert_true(loose_equal(ucv_boolean_new(true), ucv_int64_new(1)));
	assert_true(loose_equal(ucv_string_new("x"), ucv_string_new("x")));
	assert_true(loose_equal(NULL, NULL));
	assert_true(loose_equal(obj, obj));
	assert_false(loose_equal(NULL, ucv_string_new("")));
	assert_false(loose_equal(NULL, ucv_int64_new(0)));
	assert_false(loose_equal(ucv_string_new("x"), ucv_string_new("y")));
	assert_false(loose_equal(obj, vm_json(vm, "{ }")));

	ucv_put(obj);
}

static void
csv_expect(uc_vm_t *vm, uc_value_t *csv, uc_value_t *filter, const char *expected)
{
	uc_value_t *res = filter ? vm_call(vm, uc_ubbf_csv_to_list, 2, csv, filter)
				 : vm_call(vm, uc_ubbf_csv_to_list, 1, csv);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_csv_to_list(void **state)
{
	uc_vm_t *vm = *state;

	csv_expect(vm, ucv_string_new("a,b,c"), NULL, "[ \"a\", \"b\", \"c\" ]");
	csv_expect(vm, ucv_string_new("single"), NULL, "[ \"single\" ]");
	csv_expect(vm, ucv_string_new(" a , b\t,\tc "), NULL, "[ \"a\", \"b\", \"c\" ]");
	csv_expect(vm, ucv_string_new("a b, c d"), NULL, "[ \"a b\", \"c d\" ]");
	csv_expect(vm, ucv_string_new("a,,b"), NULL, "[ \"a\", \"b\" ]");
	csv_expect(vm, ucv_string_new(",a,"), NULL, "[ \"a\" ]");
	csv_expect(vm, ucv_string_new("a, ,\t,b"), NULL, "[ \"a\", \"b\" ]");
	csv_expect(vm, ucv_string_new("a\r\n,\n b \r"), NULL, "[ \"a\", \"b\" ]");
	csv_expect(vm, ucv_string_new("  ,\t"), NULL, "[ ]");
	csv_expect(vm, ucv_string_new("a,-1,b, -1 "), NULL, "[ \"a\", \"b\" ]");
	csv_expect(vm, ucv_string_new("-1"), NULL, "[ ]");
	csv_expect(vm, ucv_string_new("-10,1"), NULL, "[ \"-10\", \"1\" ]");
	csv_expect(vm, ucv_string_new("x,-1,y"), ucv_string_new("x"), "[ \"-1\", \"y\" ]");
	csv_expect(vm, ucv_string_new("x,-1"), ucv_string_new(""), "[ \"x\", \"-1\" ]");
	csv_expect(vm, ucv_string_new("x,-1"), ucv_int64_new(-1), "[ \"x\" ]");
	csv_expect(vm, ucv_string_new(""), NULL, "[ ]");
	csv_expect(vm, ucv_string_new(","), NULL, "[ ]");
	csv_expect(vm, ucv_int64_new(5), NULL, "[ ]");
	csv_expect(vm, vm_json(vm, "[ \"a\" ]"), NULL, "[ ]");
	csv_expect(vm, NULL, NULL, "[ ]");
}

static void
test_csv_list_new(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = csv_list_new(vm, NULL, "-1");
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = csv_list_new(vm, "", "-1");
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = csv_list_new(vm, "Device.IP.Interface.1, Device.IP.Interface.2", "-1");
	assert_json_equal(vm, res, "[ \"Device.IP.Interface.1\", \"Device.IP.Interface.2\" ]");
	ucv_put(res);

	res = csv_list_new(vm, "a,b,a", "a");
	assert_json_equal(vm, res, "[ \"b\" ]");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_value_to_bool),
		cmocka_unit_test(test_to_bool),
		cmocka_unit_test(test_to_int),
		cmocka_unit_test(test_value_to_int),
		cmocka_unit_test(test_loose_equal),
		cmocka_unit_test(test_csv_to_list),
		cmocka_unit_test(test_csv_list_new),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
