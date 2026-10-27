/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * ipv6.c: the nibble check of a prefix length, the RA prefix state of the
 * odhcp6c hook and the dynamic IPv6 prefix rows of an interface.
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
test_nibble(void **state)
{
	eval_expect(*state,
		"return map([ null, '', 0, 4, '48', 60, 63, 128, 132, -4, '4.0', 4.5, 'x', ' 64' ],"
		"  (l) => ubbf.prefix_length_nibble_check(l));",
		"[ false, false, false, true, true, true, false, true, false, false, false, false, false, true ]");
}

static void
test_hook_read(void **state)
{
	FILE *fp = fopen("/tmp/ubbf/ra-prefix.wan6", "w");

	assert_non_null(fp);
	fputs("2001:db8:1:0:211:22ff:fe33:4455/64,3600,7200\n"
	      "2001:db8:1::99/64,1800,3600\n"
	      " 2001:db8:2::5/x,100,200 \r\n"
	      "2001:db8:3::5/129,1,2\n"
	      "2001:db8:4::5/48,abc,\n"
	      "2001:db8:5::5/64\n"
	      "10.0.0.1/8,1,2\n", fp);
	fclose(fp);

	eval_expect(*state,
		"return [ ubbf.ra_prefixes_hook_read('wan6'), ubbf.ra_prefixes_hook_read('lan6'), ubbf.ra_prefixes_hook_read(null) ];",
		"[ [ { \"address\": \"2001:db8:1::\", \"mask\": 64, \"preferred\": 3600, \"valid\": 7200 }, "
		"{ \"address\": \"2001:db8:2::\", \"mask\": 64, \"preferred\": 100, \"valid\": 200 }, "
		"{ \"address\": \"2001:db8:4::\", \"mask\": 48, \"preferred\": 0, \"valid\": 0 } ], [ ], [ ] ]");
}

static void
test_rows(void **state)
{
	eval_expect(*state,
		"let st = { 'ipv6-prefix': [ { address: '2001:db8:10::', mask: 56 }, { address: '2001:db8:20::', mask: 62 } ] };"
		"return [ map(ubbf.ipv6_prefix_rows_build('lan', false, st, 'lo'), (r) => [ r.origin, r.data.address ]),"
		"  map(ubbf.ipv6_prefix_rows_build('wan', true, null, 'lo'), (r) => [ r.origin, r.data.address ]) ];",
		"[ [ [ \"PrefixDelegation\", \"2001:db8:10::\" ] ], [ [ \"RouterAdvertisement\", \"2001:db8:1::\" ], "
		"[ \"RouterAdvertisement\", \"2001:db8:2::\" ], [ \"RouterAdvertisement\", \"2001:db8:4::\" ] ] ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_nibble),
		cmocka_unit_test(test_hook_read),
		cmocka_unit_test(test_rows),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
