/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * cache.c. The expiry runs on the libubox event loop, which a case runs
 * for a little more than the 2 s of the cache.
 */

#include "harness.h"
#include "ubbf.h"

#include <libubox/uloop.h>

static void
test_cache_hits(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm,
		"let n = 0, m = 0;"
		"let f = (a, b) => (a == 'nul') ? (n++, null) : { a, b, n: ++n };"
		"let g = (a) => ++m;"
		"let r = [ ubbf.cache_call(f, 'x', 1), ubbf.cache_call(f, 'x', 1),"
		"  ubbf.cache_call(f, 'x', '1'), ubbf.cache_call(f, 'nul'),"
		"  ubbf.cache_call(f, 'nul'), ubbf.cache_call(g, 'x'), ubbf.cache_call(g, 'x') ];"
		"ubbf.cache_invalidate(f);"
		"push(r, ubbf.cache_call(f, 'x', 1), ubbf.cache_call(g, 'x'), n, m);"
		"ubbf.cache_invalidate(() => 0);"
		"ubbf.cache_invalidate(null);"
		"return r;");

	assert_json_equal(vm, res,
		"[ { \"a\": \"x\", \"b\": 1, \"n\": 1 }, { \"a\": \"x\", \"b\": 1, \"n\": 1 }, "
		"{ \"a\": \"x\", \"b\": \"1\", \"n\": 2 }, null, null, 1, 1, "
		"{ \"a\": \"x\", \"b\": 1, \"n\": 4 }, 1, 4, 1 ]");
	ucv_put(res);
}

static void
test_cache_exception(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm,
		"let n = 0;"
		"let f = () => { if (++n == 1) die('first'); return n; };"
		"let msg;"
		"try { ubbf.cache_call(f); } catch (e) { msg = e.message; }"
		"return [ msg, ubbf.cache_call(f), ubbf.cache_call(f) ];");

	assert_json_equal(vm, res, "[ \"first\", 2, 2 ]");
	ucv_put(res);

	res = vm_eval(vm, "try { ubbf.cache_call(5); } catch (e) { return e.message; }");
	assert_string_equal(ucv_string_get(res), "cache_call: not a function");
	ucv_put(res);
}

static void
loop_end(struct uloop_timeout *t)
{
	uloop_end();
}

static void
test_cache_expiry(void **state)
{
	struct uloop_timeout end = { .cb = loop_end };
	uc_vm_t *vm = *state;
	uc_value_t *res;

	ucv_put(vm_eval(vm,
		"global.cache_n = 0;"
		"global.cache_f = () => ++global.cache_n;"
		"ubbf.cache_call(global.cache_f);"));

	uloop_init();
	uloop_timeout_set(&end, 2100);
	uloop_run();
	uloop_done();

	res = vm_eval(vm, "return [ ubbf.cache_call(global.cache_f), ubbf.cache_call(global.cache_f) ];");
	assert_json_equal(vm, res, "[ 2, 2 ]");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_cache_hits),
		cmocka_unit_test(test_cache_exception),
		cmocka_unit_test(test_cache_expiry),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
