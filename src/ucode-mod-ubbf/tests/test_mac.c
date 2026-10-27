/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * mac.c: mac_is_valid(), mac_normalise(), mac_from_duid() and
 * alias_from_mac().
 */

#include "harness.h"
#include "ubbf.h"

static void
string_expect(uc_value_t *res, const char *expected)
{
	if (expected) {
		assert_int_equal(ucv_type(res), UC_STRING);
		assert_string_equal(ucv_string_get(res), expected);
	} else {
		assert_null(res);
	}

	ucv_put(res);
}

static void
valid_expect(uc_vm_t *vm, uc_value_t *val, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_mac_is_valid, 1, val);

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_mac_is_valid(void **state)
{
	uc_vm_t *vm = *state;

	valid_expect(vm, ucv_string_new("00:11:22:33:44:55"), true);
	valid_expect(vm, ucv_string_new("aa:bb:cc:dd:ee:ff"), true);
	valid_expect(vm, ucv_string_new("AA:Bb:cC:DD:EE:FF"), true);
	valid_expect(vm, ucv_string_new("ff:ff:ff:ff:ff:ff"), true);
	valid_expect(vm, ucv_string_new("00-11-22-33-44-55"), false);
	valid_expect(vm, ucv_string_new("001122334455"), false);
	valid_expect(vm, ucv_string_new("00:11:22:33:44:5"), false);
	valid_expect(vm, ucv_string_new("00:11:22:33:44:555"), false);
	valid_expect(vm, ucv_string_new("00:11:22:33:44:5g"), false);
	valid_expect(vm, ucv_string_new("0:011:22:33:44:55"), false);
	valid_expect(vm, ucv_string_new("00:11:22:33:44:55:"), false);
	valid_expect(vm, ucv_string_new(":00:11:22:33:44:5"), false);
	valid_expect(vm, ucv_string_new_length("00:11:22:33:44:5\0", 17), false);
	valid_expect(vm, ucv_string_new(""), false);
	valid_expect(vm, ucv_int64_new(5), false);
	valid_expect(vm, NULL, false);
}

static void
test_mac_normalise(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 1, ucv_string_new("aa:bb:cc:dd:ee:ff")),
		      "AA:BB:CC:DD:EE:FF");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new("aa:bb:cc:dd:ee:ff"),
			      ucv_string_new(":")),
		      "AABBCCDDEEFF");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new("aa-bb:cc.dd ee:ff"),
			      ucv_string_new(":-. ")),
		      "AABBCCDDEEFF");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new("00:1a:2B"),
			      ucv_string_new("")),
		      "00:1A:2B");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new("ab:cd"),
			      ucv_int64_new(58)),
		      "AB:CD");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new("zz-yy"),
			      ucv_string_new("-")),
		      "ZZYY");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 2, ucv_string_new(":::"),
			      ucv_string_new(":")),
		      "");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 1, ucv_string_new("")), "");
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 1, ucv_int64_new(5)), NULL);
	string_expect(vm_call(vm, uc_ubbf_mac_normalise, 1, NULL), NULL);
}

static void
duid_expect(uc_vm_t *vm, uc_value_t *duid, const char *expected)
{
	string_expect(vm_call(vm, uc_ubbf_mac_from_duid, 1, duid), expected);
}

static void
test_mac_from_duid(void **state)
{
	uc_vm_t *vm = *state;

	/* DUID-LL (RFC 8415, 11.4): type 3, hardware type 1, link-layer address */
	duid_expect(vm, ucv_string_new("00030001001122aabbcc"), "00:11:22:AA:BB:CC");
	duid_expect(vm, ucv_string_new("00030001001122AaBbCc"), "00:11:22:AA:BB:CC");
	duid_expect(vm, ucv_string_new("00030001001122aabbccdd"), "00:11:22:AA:BB:CC");
	duid_expect(vm, ucv_string_new("00030001001122aabbc"), NULL);
	duid_expect(vm, ucv_string_new("00030001001122aabbcx"), NULL);
	duid_expect(vm, ucv_string_new("00030001g01122aabbcc"), NULL);

	/* DUID-LLT (RFC 8415, 11.2): type 1, hardware type 1, time, address */
	duid_expect(vm, ucv_string_new("000100012a3b4c5d001122aabbcc"), "00:11:22:AA:BB:CC");
	duid_expect(vm, ucv_string_new("000100012a3b4c5d001122aabbc"), NULL);
	duid_expect(vm, ucv_string_new("000100012a3b4c5d001122aabbzz"), NULL);

	duid_expect(vm, ucv_string_new("00030006001122aabbcc"), NULL);
	duid_expect(vm, ucv_string_new("000100062a3b4c5d001122aabbcc"), NULL);
	duid_expect(vm, ucv_string_new("0002000000090102030405060708"), NULL);
	duid_expect(vm, ucv_string_new("00040001001122aabbcc"), NULL);
	duid_expect(vm, ucv_string_new("000300010011223"), NULL);
	duid_expect(vm, ucv_string_new("zzzzzzzzzzzzzzzzzzzz"), NULL);
	duid_expect(vm, ucv_string_new(""), NULL);
	duid_expect(vm, ucv_int64_new(3), NULL);
	duid_expect(vm, NULL, NULL);
}

static void
test_alias_from_mac(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new("AA:BB:CC:DD:EE:FF")),
		      "cpe-aabbccddeeff");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new("00:11:22:33:44:55")),
		      "cpe-001122334455");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new("aabbccddeeff")),
		      "cpe-aabbccddeeff");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new("Zz-9")),
		      "cpe-zz-9");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new(":")), "cpe-");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1,
			      ucv_string_new("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")),
		      "cpe-0123456789abcdefghijklmnop");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_string_new("")), "");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, ucv_int64_new(1)), "");
	string_expect(vm_call(vm, uc_ubbf_alias_from_mac, 1, NULL), "");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_mac_is_valid),
		cmocka_unit_test(test_mac_normalise),
		cmocka_unit_test(test_mac_from_duid),
		cmocka_unit_test(test_alias_from_mac),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
