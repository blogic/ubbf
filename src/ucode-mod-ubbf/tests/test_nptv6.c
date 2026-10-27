/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * nptv6.c: the IPv6 prefixes of an NPTv6 row and its state.
 */

#include "harness.h"
#include "ubbf.h"

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_prefix6(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"return map([ 'fd00:21::/64', '2001:db8::/064', 'fd00::/129', '10.0.0.0/8', 'fd00::',"
		"  '::ffff:1.2.3.4/96', 'g::/64', '', null, 5 ], (p) => ubbf.prefix6_parse(p)?.len);",
		"[ 64, 64, null, null, null, 96, null, null, null, null ]");
	eval_expect(vm, "return ubbf.prefix6_parse('2001:db8::1/128').addr;",
		"[ 32, 1, 13, 184, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 ]");
	eval_expect(vm,
		"let p = (s) => ubbf.prefix6_parse(s);"
		"let p60 = p('2001:db8:200::/60');"
		"return [ ubbf.prefix6_contains(p60, p('2001:db8:200:8::/61')),"
		"  ubbf.prefix6_contains(p60, p('2001:db8:200:10::/64')),"
		"  ubbf.prefix6_contains(p60, p('2001:db8:200::/56')),"
		"  ubbf.prefix6_contains(p('::/0'), p60), ubbf.prefix6_contains(null, p60) ];",
		"[ true, false, false, true, false ]");
}

static void
test_setting_check(void **state)
{
	eval_expect(*state,
		"let root = { Device: { IP: { Interface: { '1': { Name: 'wan' } } } } };"
		"let row = (f) => ({ Enable: 'true', Interface: 'Device.IP.Interface.1',"
		"  InternalPrefix: 'fd00:21::/64', ExternalPrefix: '2001:db8:200:1::/64', ...f });"
		"return [ ubbf.nptv6_setting_check(root, row({})),"
		"  ubbf.nptv6_setting_check(root, row({ Enable: 'false' })).status,"
		"  ubbf.nptv6_setting_check(root, row({ Interface: 'Device.IP.Interface.9' })).status,"
		"  ubbf.nptv6_setting_check(root, row({ ExternalPrefix: '2001:db8::/60' })).status ];",
		"[ { \"status\": \"Enabled\", \"network\": \"wan\", \"internal\": \"fd00:21::/64\", "
		"\"external\": \"2001:db8:200:1::/64\" }, \"Disabled\", \"Error_Misconfigured\", "
		"\"Error_Misconfigured\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_prefix6),
		cmocka_unit_test(test_setting_check),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
