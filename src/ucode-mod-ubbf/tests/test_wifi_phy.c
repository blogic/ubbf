/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * wifi_phy.c: the capabilities of a wiphy per band; wifi_psk.c: the WPA2
 * pre-shared key of a passphrase.
 */

#include "harness.h"
#include "ubbf.h"

static const char phy_js[] =
	"let ap_he = [ { iftypes: { station: true }, eht_cap_phy: [ 0 ] }, { iftypes: { ap: true }, he_cap_phy: [ 0 ] } ];"
	"let ap_eht = [ { iftypes: { ap: true }, he_cap_phy: [ 0 ], eht_cap_phy: [ 0 ] } ];"
	"let phy = { wiphy_antenna_tx: 3,"
	"  interface_combinations: [ { limits: [ { types: { station: true }, max: 1 }, { types: { ap: true }, max: 16 } ] } ],"
	"  wiphy_bands: ["
	"  { ht_capa: 1, iftype_data: ap_he, freqs: ["
	"    { freq: 2412, no_80mhz: true, no_160mhz: true, max_tx_power: 2000 },"
	"    { freq: 2484, disabled: true, max_tx_power: 3000 } ] },"
	"  { ht_capa: 1, vht_mcs_set: 1, iftype_data: ap_he, freqs: ["
	"    { freq: 5180, no_160mhz: true, max_tx_power: 2350 }, { freq: 5500, no_ht40_minus: true, no_ht40_plus: true } ] },"
	"  null,"
	"  { iftype_data: ap_eht, freqs: [ { freq: 5955, max_tx_power: 1250.5 }, { freq: 6115, no_320mhz: true } ] } ] };";

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	char buf[4096];
	uc_value_t *res;

	snprintf(buf, sizeof(buf), "%s%s", phy_js, code);
	res = vm_eval(vm, buf);
	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_standards(void **state)
{
	eval_expect(*state,
		"return [ map([ 0, 1, 2, 3, -1, '1', 9 ], (i) => ubbf.phy_max_standard(phy, i)),"
		"  map([ 0, 1, 3, 2 ], (i) => ubbf.phy_supported_standards(phy, i)),"
		"  ubbf.phy_supported_bands(phy), ubbf.phy_supported_bands(null) ];",
		"[ [ \"ax\", \"ax\", \"g\", \"be\", \"be\", \"ax\", \"g\" ], "
		"[ \"b,g,n,ax\", \"a,n,ac,ax\", \"ax,be\", \"\" ], \"2.4GHz,5GHz,6GHz\", \"\" ]");
}

static void
test_bandwidths(void **state)
{
	eval_expect(*state,
		"return [ map([ 0, 1, 3, 2 ], (i) => ubbf.phy_supported_bandwidths(phy, i)),"
		"  map([ 0, 1, 3, 2 ], (i) => ubbf.phy_max_bandwidth(phy, i)),"
		"  [ ubbf.channel_valid_for_bandwidth(phy, 1, 36, '160MHz'), ubbf.channel_valid_for_bandwidth(phy, 1, '100', '160MHz'),"
		"    ubbf.channel_valid_for_bandwidth(phy, 1, 100, '40MHz'), ubbf.channel_valid_for_bandwidth(phy, 0, 14, '40MHz'),"
		"    ubbf.channel_valid_for_bandwidth(phy, 2, 1, '20MHz'), ubbf.channel_valid_for_bandwidth(phy, 3, 1, 'x') ] ];",
		"[ [ \"20MHz,40MHz\", \"20MHz,40MHz,80MHz,160MHz\", \"20MHz,40MHz,80MHz,160MHz,320MHz\", \"20MHz\" ], "
		"[ \"40MHz\", \"160MHz\", \"320MHz\", \"20MHz\" ], [ false, true, false, false, true, true ] ]");
}

static void
test_limits(void **state)
{
	eval_expect(*state,
		"return [ ubbf.phy_max_ssids(phy), ubbf.phy_max_ssids({}), map([ 0, 1, 3, 2 ], (i) => ubbf.phy_max_bitrate(phy, i)),"
		"  ubbf.phy_max_bitrate({ ...phy, wiphy_antenna_tx: null }, 1),"
		"  map([ 0, 1, 3, 2 ], (i) => ubbf.phy_max_txpower(phy, i)), ubbf.phy_possible_channels(phy, 0),"
		"  ubbf.phy_possible_channels(phy, 1), ubbf.phy_possible_channels(phy, 2) ];",
		"[ 16, 0, [ 344, 1441, 2882, 0 ], 721, [ 20, 23, 12.505, null ], \"1\", \"36,100\", \"\" ]");
}

static void
test_psk(void **state)
{
	/* 802.11-2024 J.4.2 test vectors, the second call from the cache */
	eval_expect(*state,
		"return [ ubbf.wpa_psk('password', 'IEEE'), ubbf.wpa_psk('ThisIsAPassword', 'ThisIsASSID'),"
		"  ubbf.wpa_psk('password', 'IEEE') ];",
		"[ \"f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e\", "
		"\"0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af\", "
		"\"f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_standards),
		cmocka_unit_test(test_bandwidths),
		cmocka_unit_test(test_limits),
		cmocka_unit_test(test_psk),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
