/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * wifi.c: freq_to_channel(), antenna_count(), txpower_pct_to_dbm(),
 * wifi_operating_standard(), the htmode and band helpers, dscp_parse() and
 * qos_map_set_render().
 */

#include "harness.h"
#include "ubbf.h"

static void
int_expect(uc_value_t *res, int64_t expected)
{
	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
channel_expect(uc_vm_t *vm, uc_value_t *freq, int64_t expected)
{
	int_expect(vm_call(vm, uc_ubbf_freq_to_channel, 1, freq), expected);
}

static void
test_freq_to_channel(void **state)
{
	uc_vm_t *vm = *state;

	/* 802.11-2024 Annex E: 2.4 GHz 2407 + 5n (channel 14 at 2484), 5 GHz 5000 + 5n */
	channel_expect(vm, ucv_int64_new(2412), 1);
	channel_expect(vm, ucv_int64_new(2437), 6);
	channel_expect(vm, ucv_int64_new(2472), 13);
	channel_expect(vm, ucv_int64_new(2484), 14);
	channel_expect(vm, ucv_int64_new(2411), 0);
	channel_expect(vm, ucv_int64_new(2485), 0);
	channel_expect(vm, ucv_int64_new(5180), 36);
	channel_expect(vm, ucv_int64_new(5500), 100);
	channel_expect(vm, ucv_int64_new(5825), 165);
	channel_expect(vm, ucv_int64_new(5885), 177);
	channel_expect(vm, ucv_int64_new(5179), 0);
	channel_expect(vm, ucv_int64_new(5890), 0);

	/* 6 GHz: 5950 + 5n */
	channel_expect(vm, ucv_int64_new(5935), 2);
	channel_expect(vm, ucv_int64_new(5955), 1);
	channel_expect(vm, ucv_int64_new(6115), 33);
	channel_expect(vm, ucv_int64_new(7115), 233);
	channel_expect(vm, ucv_int64_new(7120), 0);

	channel_expect(vm, ucv_string_new("2437"), 6);
	channel_expect(vm, ucv_string_new("5180"), 36);
	channel_expect(vm, ucv_string_new("2437 MHz"), 0);
	channel_expect(vm, ucv_string_new(""), 0);
	channel_expect(vm, ucv_string_new("-2437"), 0);
	channel_expect(vm, ucv_int64_new(0), 0);
	channel_expect(vm, ucv_int64_new(-5180), 0);
	channel_expect(vm, ucv_int64_new(900), 0);
	channel_expect(vm, ucv_double_new(2437.0), 0);
	channel_expect(vm, NULL, 0);
}

static void
antenna_expect(uc_vm_t *vm, uc_value_t *mask, int64_t expected)
{
	int_expect(vm_call(vm, uc_ubbf_antenna_count, 1, mask), expected);
}

static void
test_antenna_count(void **state)
{
	uc_vm_t *vm = *state;

	antenna_expect(vm, ucv_int64_new(1), 1);
	antenna_expect(vm, ucv_int64_new(3), 2);
	antenna_expect(vm, ucv_int64_new(5), 2);
	antenna_expect(vm, ucv_int64_new(15), 4);
	antenna_expect(vm, ucv_int64_new(255), 8);
	antenna_expect(vm, ucv_int64_new(0), 1);
	antenna_expect(vm, ucv_int64_new(-1), 64);
	antenna_expect(vm, ucv_string_new("7"), 3);
	antenna_expect(vm, ucv_string_new("0"), 1);
	antenna_expect(vm, ucv_string_new("0x3"), 1);
	antenna_expect(vm, ucv_string_new("3 "), 1);
	antenna_expect(vm, ucv_string_new(""), 1);
	antenna_expect(vm, ucv_double_new(3.0), 1);
	antenna_expect(vm, NULL, 1);
}

static void
txpower_expect(uc_vm_t *vm, uc_value_t *pct, uc_value_t *max, int64_t expected)
{
	int_expect(vm_call(vm, uc_ubbf_txpower_pct_to_dbm, 2, pct, max), expected);
}

static void
txpower_null_expect(uc_vm_t *vm, uc_value_t *pct, uc_value_t *max)
{
	assert_null(vm_call(vm, uc_ubbf_txpower_pct_to_dbm, 2, pct, max));
}

static void
test_txpower_pct_to_dbm(void **state)
{
	uc_vm_t *vm = *state;

	/* max - 10 * log10(100 / pct), truncated toward zero */
	txpower_expect(vm, ucv_int64_new(50), ucv_int64_new(20), 16);
	txpower_expect(vm, ucv_int64_new(25), ucv_int64_new(20), 13);
	txpower_expect(vm, ucv_int64_new(12), ucv_int64_new(30), 20);
	txpower_expect(vm, ucv_int64_new(20), ucv_int64_new(23), 16);
	txpower_expect(vm, ucv_int64_new(99), ucv_int64_new(20), 19);
	txpower_expect(vm, ucv_int64_new(1), ucv_int64_new(30), 10);

	/* the reduction exceeds the cap: the floor of 1 dBm still reduces it */
	txpower_expect(vm, ucv_int64_new(1), ucv_int64_new(20), 1);
	txpower_expect(vm, ucv_int64_new(1), ucv_int64_new(12), 1);
	txpower_expect(vm, ucv_int64_new(50), ucv_int64_new(2), 1);

	txpower_null_expect(vm, ucv_int64_new(50), ucv_int64_new(1));
	txpower_null_expect(vm, ucv_int64_new(99), ucv_int64_new(1));
	txpower_null_expect(vm, ucv_int64_new(0), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_int64_new(-10), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_int64_new(100), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_int64_new(150), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_int64_new(50), ucv_int64_new(0));
	txpower_null_expect(vm, ucv_int64_new(50), ucv_int64_new(-3));
	txpower_null_expect(vm, ucv_double_new(50.0), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_string_new("50"), ucv_int64_new(20));
	txpower_null_expect(vm, ucv_int64_new(50), ucv_string_new("20"));
	txpower_null_expect(vm, ucv_int64_new(50), NULL);
	txpower_null_expect(vm, NULL, ucv_int64_new(20));
}

static void
standard_expect(uc_vm_t *vm, const char *flags, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_wifi_operating_standard, 1,
				  flags ? vm_json(vm, flags) : NULL);

	assert_int_equal(ucv_type(res), UC_STRING);
	assert_string_equal(ucv_string_get(res), expected);
	ucv_put(res);
}

static void
test_wifi_operating_standard(void **state)
{
	uc_vm_t *vm = *state;

	standard_expect(vm, "[ \"EHT-MCS 13\", \"320MHz\" ]", "be");
	standard_expect(vm, "[ \"40MHz\", \"HE-MCS 11\", \"HE-NSS 2\" ]", "ax");
	standard_expect(vm, "[ \"VHT-MCS 9\", \"80MHz\" ]", "ac");
	standard_expect(vm, "[ \"MCS 7\", \"short GI\" ]", "n");
	standard_expect(vm, "[ \"MCS7\" ]", "n");
	standard_expect(vm, "[ 5, null, { }, \"HE-MCS 3\" ]", "ax");
	standard_expect(vm, "[ \"MCS 7\", \"HE-MCS 5\" ]", "ax");
	standard_expect(vm, "[ \"VHT-MCS 9\", \"EHT-MCS 1\", \"HE-MCS 5\" ]", "be");
	standard_expect(vm, "[ \"20MHz\", \"short GI\" ]", "");
	standard_expect(vm, "[ \"eht-mcs 1\", \"he-mcs 1\", \"mcs 1\" ]", "");
	standard_expect(vm, "[ \"EHT\", \"HE\", \"VHT\", \"MC\" ]", "");
	standard_expect(vm, "[ ]", "");
	standard_expect(vm, "\"HE-MCS 11\"", "");
	standard_expect(vm, "{ \"flags\": [ \"HE-MCS 11\" ] }", "");
	standard_expect(vm, NULL, "");
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_htmode(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"return map([ null, '', 'b/g', 'b/g/n', 'a,n,ac', 'AX', 'n/ax/be', 5 ],"
		"  (s) => ubbf.standards_to_highest(s));",
		"[ \"g\", \"g\", \"g\", \"n\", \"ac\", \"ax\", \"be\", \"g\" ]");
	eval_expect(vm,
		"return [ ubbf.standards_bandwidth_to_htmode('ax', '320MHz'), ubbf.standards_bandwidth_to_htmode('n', '80MHz'),"
		"  ubbf.standards_bandwidth_to_htmode('ac', null), ubbf.standards_bandwidth_to_htmode('be', 'x'),"
		"  ubbf.standards_bandwidth_to_htmode('g', '20MHz'), ubbf.standards_bandwidth_to_htmode(null, '20MHz') ];",
		"[ \"HE160\", \"HT40\", \"VHT20\", \"EHT20\", \"NOHT\", \"NOHT\" ]");
	eval_expect(vm,
		"return [ ubbf.clamp_htmode('n', '80MHz', 'ax', '160MHz'), ubbf.clamp_htmode('ac', '160MHz', 'ax', '80MHz'),"
		"  ubbf.clamp_htmode('ac', '80+80MHz', 'ac', '160MHz'), ubbf.clamp_htmode('be', '320MHz', 'ax', '80+80MHz'),"
		"  ubbf.clamp_htmode('x', 'y', 'ax', '80MHz') ];",
		"[ \"HT40\", \"VHT80\", \"VHT160\", \"HE160\", \"NOHT\" ]");
	eval_expect(vm,
		"return map([ 0, 3, 4, 13, 14, -1, '5', 1.5, null ], (w) => ubbf.channel_width_to_bandwidth(w));",
		"[ \"20MHz\", \"80MHz\", \"80+80MHz\", \"320MHz\", \"\", \"320MHz\", \"160MHz\", \"\", \"\" ]");
}

static void
test_bands(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"return [ map([ '2.4GHz', '5GHz', '6GHz', '60GHz', 'x', null ], (b) => ubbf.band_to_uci(b)),"
		"  map([ '2g', '5GHz', '6g', '60GHz', 'x' ], (b) => ubbf.band_to_index(b)) ];",
		"[ [ \"2g\", \"5g\", \"6g\", \"2g\", \"2g\", \"2g\" ], [ 0, 1, 3, 2, 0 ] ]");
	eval_expect(vm,
		"return [ ubbf.radio_address_derive('AA:BB:CC:DD:EE:FF', '2g'), ubbf.radio_address_derive('aa:bb:cc:dd:ee:ff', '5g'),"
		"  ubbf.radio_address_derive('00:11:22:33:44:fe', '6g'), ubbf.radio_address_derive('001122334455', '60g'),"
		"  ubbf.radio_address_derive('aa:bb:cc:dd:ee', '5g'), ubbf.radio_address_derive(null, '5g') ];",
		"[ \"aa:bb:cc:dd:ee:ff\", \"aa:bb:cc:dd:ee:00\", \"02:11:22:33:44:00\", \"02:11:22:33:44:58\", null, null ]");
}

static void
test_dscp(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"return map([ 'EF', ' af41 ', 'va', '0', '63', '64', '-1', '+5', '', 'x', null, 7 ], (t) => ubbf.dscp_parse(t));",
		"[ 46, 34, 44, 0, 63, null, null, 5, null, null, null, 7 ]");
	eval_expect(vm,
		"return [ ubbf.qos_map_set_render([ { Enable: 'true', UserPriority: '6', DSCPList: 'EF,CS6,46,x' },"
		"    { Enable: 'true', UserPriority: 0, DSCPList: '0' }, { Enable: 'false', UserPriority: 1, DSCPList: '8' },"
		"    { Enable: 'true', UserPriority: 9, DSCPList: '8' }, null ]),"
		"  ubbf.qos_map_set_render([ { Enable: 'true', UserPriority: 2, DSCPList: '' } ]), ubbf.qos_map_set_render(null) ];",
		"[ \"0,0,255,255,255,255,255,255,255,255,255,255,46,48,255,255\", \"\", \"\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_freq_to_channel),
		cmocka_unit_test(test_antenna_count),
		cmocka_unit_test(test_txpower_pct_to_dbm),
		cmocka_unit_test(test_wifi_operating_standard),
		cmocka_unit_test(test_htmode),
		cmocka_unit_test(test_bands),
		cmocka_unit_test(test_dscp),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
