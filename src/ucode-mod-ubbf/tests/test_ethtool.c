/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * ethtool.c. Runs isolated (run-isolated.sh): the setup adds a veth pair,
 * which reports a duplex and the MDI-X state but no link modes and no
 * MAC or RMON counters, and a dummy device, which has no ethtool link
 * operations. The link mode names need a real port; the testbed covers
 * them.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdlib.h>

static const char *const setup_cmds[] = {
	"ip link add v0 type veth peer name v1",
	"ip link set v0 up",
	"ip link set v1 up",
	"ip link add d0 type dummy",
};

static int
group_setup(void **state)
{
	for (size_t i = 0; i < sizeof(setup_cmds) / sizeof(setup_cmds[0]); i++)
		if (system(setup_cmds[i]))
			return -1;

	return vm_setup(state);
}

static void
expect(uc_vm_t *vm, uc_cfn_ptr_t fn, const char *dev, const char *json)
{
	uc_value_t *res = vm_call(vm, fn, 1, dev ? ucv_string_new(dev) : NULL);

	if (json)
		assert_json_equal(vm, res, json);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_properties(void **state)
{
	uc_vm_t *vm = *state;

	expect(vm, uc_ubbf_ethtool_properties_get, "v0",
		"{ \"SupportedLinkModes\": \"\", \"AdvertisedLinkModes\": \"\", "
		"\"LinkPartnerAdvertisedLinkModes\": \"\", \"CurrentDuplexMode\": \"Full\", "
		"\"CurrentMDIX\": \"Unknown\", \"MDIX\": \"Auto\" }");
	expect(vm, uc_ubbf_ethtool_properties_get, "d0", "{ }");
	expect(vm, uc_ubbf_ethtool_properties_get, "nope", "{ }");
	expect(vm, uc_ubbf_ethtool_properties_get, NULL, "{ }");

	/* a failed request leaves no reply behind for the next one */
	expect(vm, uc_ubbf_ethtool_properties_get, "v1",
		"{ \"SupportedLinkModes\": \"\", \"AdvertisedLinkModes\": \"\", "
		"\"LinkPartnerAdvertisedLinkModes\": \"\", \"CurrentDuplexMode\": \"Full\", "
		"\"CurrentMDIX\": \"Unknown\", \"MDIX\": \"Auto\" }");
}

static void
test_stats(void **state)
{
	uc_vm_t *vm = *state;

	expect(vm, uc_ubbf_ethtool_stats_get, "v0",
		"{ \"mac\": { }, \"rmon\": { }, \"hist_rx\": [ ] }");
	expect(vm, uc_ubbf_ethtool_stats_get, "d0",
		"{ \"mac\": { }, \"rmon\": { }, \"hist_rx\": [ ] }");
	expect(vm, uc_ubbf_ethtool_stats_get, "nope", NULL);
	expect(vm, uc_ubbf_ethtool_stats_get, "", NULL);
	expect(vm, uc_ubbf_ethtool_stats_get, NULL, NULL);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_properties),
		cmocka_unit_test(test_stats),
	};

	return cmocka_run_group_tests(tests, group_setup, vm_teardown);
}
