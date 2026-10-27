/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * rtnl.c. Runs isolated (run-isolated.sh): the setup adds a dummy device
 * with addresses and routes in the private network namespace, and the
 * cases read them back.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdlib.h>

static const char *const setup_cmds[] = {
	"ip link add d0 type dummy",
	"ip link set d0 addrgenmode none",
	"ip link set d0 up",
	"ip link add d1 type dummy",
	"ip link set d1 addrgenmode none",
	"ip link set d1 up",
	"ip -6 addr add fe80::1/64 dev d0 scope link",
	"ip -6 addr add fe80::2/10 dev d0 scope link",
	"ip -6 addr add 2001:db8::1/64 dev d0",
	"ip -6 addr add fe80::9/64 dev d1 scope link",
	"ip -6 route add 2001:db8:1::/64 dev d0 proto 9 expires 300",
	"ip -6 route add 2001:db8:2::/56 dev d0 proto 9",
	"ip -6 route add 2001:db8:3::/64 dev d0 proto static",
	"ip -6 route add 2001:db8:4::/64 dev d1 proto 9",
	"ip -6 route add default dev d0 proto 9",
};

static int
group_setup(void **state)
{
	for (size_t i = 0; i < sizeof(setup_cmds) / sizeof(setup_cmds[0]); i++)
		if (system(setup_cmds[i]))
			return -1;

	return vm_setup(state);
}

static uc_value_t *
dev_call(uc_vm_t *vm, uc_cfn_ptr_t fn, const char *dev)
{
	return vm_call(vm, fn, 1, dev ? ucv_string_new(dev) : NULL);
}

static void
test_link_local_addresses(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	/* the kernel sets the order of the addresses */
	res = vm_eval(vm,
		"return sort(ubbf.link_local_addresses_get('d0'), (a, b) => a.address < b.address ? -1 : 1);");
	assert_json_equal(vm, res,
		"[ { \"address\": \"fe80::1\", \"mask\": 64 }, { \"address\": \"fe80::2\", \"mask\": 10 } ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_link_local_addresses_get, "d1");
	assert_json_equal(vm, res, "[ { \"address\": \"fe80::9\", \"mask\": 64 } ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_link_local_addresses_get, "lo");
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_link_local_addresses_get, "nope");
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_link_local_addresses_get, NULL);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

static void
test_ra_prefixes(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res, *row;
	double preferred;

	res = dev_call(vm, uc_ubbf_ra_prefixes_get, "d0");
	assert_int_equal(ucv_array_length(res), 2);

	/* the expiry counts down, so check its range and its type */
	row = ucv_array_get(res, 0);
	preferred = ucv_double_get(ucv_object_get(row, "preferred", NULL));
	assert_true(preferred > 290 && preferred <= 300);
	assert_true(ucv_is_equal(ucv_object_get(row, "preferred", NULL),
				 ucv_object_get(row, "valid", NULL)));
	ucv_object_delete(row, "preferred");
	ucv_object_delete(row, "valid");

	assert_json_equal(vm, res,
		"[ { \"address\": \"2001:db8:1::\", \"mask\": 64 }, "
		"{ \"address\": \"2001:db8:2::\", \"mask\": 56 } ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_ra_prefixes_get, "d1");
	assert_json_equal(vm, res, "[ { \"address\": \"2001:db8:4::\", \"mask\": 64 } ]");
	ucv_put(res);

	res = dev_call(vm, uc_ubbf_ra_prefixes_get, "nope");
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_link_local_addresses),
		cmocka_unit_test(test_ra_prefixes),
	};

	return cmocka_run_group_tests(tests, group_setup, vm_teardown);
}
