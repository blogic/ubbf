/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * sfp.c: the type of an SFP from SFPProperties, the allow list, the
 * VendorPN patterns and SUPPORTED_SFP_TYPES.
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
test_supported_types(void **state)
{
	eval_expect(*state, "return ubbf.SUPPORTED_SFP_TYPES;",
		    "[ \"Optical Ethernet\", \"Electrical Ethernet\" ]");
}

static void
test_part_numbers(void **state)
{
	/* VendorPN patterns through the allow list: * is any run of
	 * characters, the middle parts in order between the ends */
	eval_expect(*state,
		"let allowed = (pn, value) => ubbf.sfp_allowed({ AllowedSFPs: { AllowAllSFPs: 'false',"
		"  AllowedSFP: { '1': { Enable: 'true', VendorPN: pn } } } }, { VendorPN: value }, '');"
		"return map([ [ '', 'X' ], [ '*', 'X' ], [ 'SFP-10G', 'SFP-10G' ], [ 'SFP-10G', 'SFP-10GX' ],"
		"  [ 'SFP*', 'SFP-1' ], [ '*SR', 'SFP-SR' ], [ 'S*10*SR', 'SFP-10G-SR' ], [ 'S*20*SR', 'SFP-10G-SR' ],"
		"  [ 'SFP-*-SFP', 'SFP-SFP' ], [ 'A*B*C', 'ACB' ], [ 'A**C', 'AC' ] ],"
		"  (c) => allowed(c[0], c[1]));",
		"[ true, true, true, false, true, true, true, false, false, false, true ]");
}

static void
test_type_and_allowed(void **state)
{
	eval_expect(*state,
		"let sfps = { SFPProperties: { SFP: {"
		"    '2': { SFPType: 'Electrical Ethernet', VendorName: 'FS', VendorOUI: '009065' },"
		"    '1': { Enable: 'false', SFPType: 'XPON', VendorName: 'FS' },"
		"    '10': { SFPType: 'XPON' } } },"
		"  AllowedSFPs: { AllowAllSFPs: 'false', AllowedSFP: {"
		"    '1': { Enable: 'true', SFPType: 'Electrical Ethernet', VendorOUI: '009065' },"
		"    '2': { Enable: 'false', VendorName: 'Other' } } } };"
		"let fs = { VendorName: 'FS', VendorOUI: '009065', VendorPN: 'X' };"
		"let other = { VendorName: 'Other', VendorOUI: 'AABBCC', VendorPN: 'X' };"
		"return [ ubbf.sfp_type_resolve(sfps, fs, 'Optical Ethernet'),"
		"  ubbf.sfp_type_resolve(sfps, other, 'Optical Ethernet'),"
		"  ubbf.sfp_type_resolve(null, fs, 'Optical Ethernet'),"
		"  ubbf.sfp_allowed(sfps, fs, 'Electrical Ethernet'), ubbf.sfp_allowed(sfps, fs, 'XPON'),"
		"  ubbf.sfp_allowed(sfps, other, 'Electrical Ethernet'), ubbf.sfp_allowed(null, other, ''),"
		"  ubbf.sfp_allowed({ AllowedSFPs: { AllowAllSFPs: 'true' } }, other, '') ];",
		"[ \"Electrical Ethernet\", \"XPON\", \"Optical Ethernet\", true, false, false, true, true ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_supported_types),
		cmocka_unit_test(test_part_numbers),
		cmocka_unit_test(test_type_and_allowed),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
