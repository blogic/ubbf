/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * vm.c: callback_call(), callback_invoke() and registry_get().
 */

#include "harness.h"
#include "ubbf.h"

static void
test_callback_call(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *fn = vm_eval(vm, "return function(a, b) { return [ this?.k, a, b ]; };");
	uc_value_t *this = vm_json(vm, "{ \"k\": 7 }");
	uc_value_t *args[] = { ucv_string_new("x"), ucv_int64_new(2) };
	uc_value_t *res;

	res = callback_call(vm, this, fn, 2, args);
	assert_json_equal(vm, res, "[ 7, \"x\", 2 ]");
	ucv_put(res);

	res = callback_call(vm, NULL, fn, 1, args);
	assert_json_equal(vm, res, "[ null, \"x\", null ]");
	ucv_put(res);

	/* the arguments stay with the caller */
	assert_string_equal(ucv_string_get(args[0]), "x");

	res = callback_invoke(vm, fn, 2, args[1], args[0]);
	assert_json_equal(vm, res, "[ null, 2, \"x\" ]");
	ucv_put(res);

	/* a value that is not a function gives NULL and raises nothing */
	assert_null(callback_call(vm, NULL, args[0], 0, NULL));
	assert_int_equal(vm->exception.type, EXCEPTION_NONE);

	ucv_put(args[0]);
	ucv_put(args[1]);
	ucv_put(this);
	ucv_put(fn);
}

static void
test_callback_exception(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *fn = vm_eval(vm, "return () => die('broken');");

	/* the exception stays raised until the caller takes it */
	assert_null(callback_invoke(vm, fn, 0));
	assert_int_not_equal(vm->exception.type, EXCEPTION_NONE);
	assert_true(exception_log_clear(vm, "test"));
	assert_int_equal(vm->exception.type, EXCEPTION_NONE);
	assert_false(exception_log_clear(vm, "test"));

	ucv_put(fn);
}

static void
test_registry_get(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *obj = registry_get(vm, "ubbf.test.obj", UC_OBJECT);
	uc_value_t *arr = registry_get(vm, "ubbf.test.arr", UC_ARRAY);

	assert_int_equal(ucv_type(obj), UC_OBJECT);
	assert_int_equal(ucv_type(arr), UC_ARRAY);
	assert_ptr_equal(registry_get(vm, "ubbf.test.obj", UC_OBJECT), obj);
	assert_ptr_equal(uc_vm_registry_get(vm, "ubbf.test.arr"), arr);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_callback_call),
		cmocka_unit_test(test_callback_exception),
		cmocka_unit_test(test_registry_get),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
