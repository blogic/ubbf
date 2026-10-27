/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * dns.c: learned rows of Device.DNS.Client.Server and
 * Device.DNS.Relay.Forwarding.
 */

#include "harness.h"
#include "ubbf.h"

static void
test_learned_row(void **state)
{
	uc_value_t *res = vm_eval(*state,
		"return map([ null, {}, { Type: null }, { Type: 'Static' }, { Type: 'DHCPv4' },"
		"  { Type: 'RouterAdvertisement' }, { Type: '' }, 'x' ], (r) => ubbf.dns_learned_row(r));");

	assert_json_equal(*state, res, "[ false, false, false, false, true, true, true, false ]");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_learned_row),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
