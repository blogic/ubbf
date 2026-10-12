/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * wifi_dataelements.c: the HT, VHT and HE capabilities, the radio survey
 * and capability from iwinfo data, the station list, the band priority and
 * the merge of the umap replies.
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
test_ht_vht(void **state)
{
	eval_expect(*state,
		"let band = { ht_capa: 0x62, ht_mcs_set: { rx_mcs_indexes: [ 0, 15, 32 ] },"
		"  vht_capa: 0x0800 | (1 << 2) | (1 << 5), vht_mcs_set: { rx_mcs_set: [ { streams: 1, mcs_indexes: [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 ] },"
		"  { streams: 2, mcs_indexes: [ 0, 1, 2, 3, 4, 5, 6, 7, 8 ] } ], tx_mcs_set: [ { streams: 1, mcs_indexes: [ 0 ] } ] } };"
		"return [ ord(b64dec(ubbf.ht_caps_encode(null, band)), 0),"
		"  ubbf.ht_caps_encode({ max_supported_tx_spatial_streams: 2, ht_support_40mhz: true }, null),"
		"  ubbf.ht_caps_encode(null, null), ubbf.vht_caps_encode(null, band), ubbf.vht_caps_encode(null, { vht_mcs_set: {} }) ];",
		"[ 94, \"Qg==\", \"\", \"//z/9gZg\", \"\" ]");
}

static void
test_he(void **state)
{
	eval_expect(*state,
		"let elem = (id, b) => chr(id, length(b)) + b;"
		"let he = elem(255, chr(35, 0x0a, 0, 0, 0, 0, 0, 0x08, 0, 0x40, 0x80, 0x0b, 0, 0, 0, 0, 0, 0, 0xfa, 0xff));"
		"let body = chr(0x31, 0x04, 0x0a, 0x00) + elem(0, 'net') + he;"
		"let c = ubbf.sta_he_caps_from_frame_body(b64enc(body));"
		"return [ c.he_160, c.ul_mu_mimo, c.su_beamformer, c.su_beamformee, c.beamformee_sts_less_80, c.mu_edca,"
		"  c.twt_requester, length(c.mcs_nss), ubbf.sta_he_caps_from_frame_body(b64enc(body + 'x')),"
		"  ubbf.sta_he_caps_from_flags([ 'VHT-MCS 9', 'HE-NSS 2' ], null).dl_ofdma, ubbf.sta_he_caps_from_flags([], [ 'HE-MCS 1' ]) ];",
		"[ true, true, true, true, 2, true, true, 2, null, true, null ]");
}

static void
test_radio(void **state)
{
	eval_expect(*state,
		"let phys = [ null, { wiphy_name: 'phy0', wiphy_bands: [ { freqs: [ { freq: 2412, max_tx_power: 2000 },"
		"  { freq: 2484, max_tx_power: 1500 }, { freq: 2437, disabled: true } ],"
		"  iftype_data: [ { iftypes: { ap: true }, he_cap_phy: [ 0x08, 0, 0x40, 0, 0 ], he_cap_mac: [ 0x04 ] } ] } ] } ];"
		"let cap = ubbf.radio_capability_build(phys, 'phy0', 0);"
		"let s = ubbf.radio_survey_build({ survey: { time: 1000, busy: 500, time_tx: 100, noise: -95 } });"
		"return [ cap.basic_capabilities.opclasses_supported, cap.wifi6_capabilities.roles[0].he_160,"
		"  cap.wifi6_capabilities.roles[0].twt_responder, s, ubbf.radio_survey_build(null) ];",
		"[ [ { \"opclass\": 81, \"max_txpower_eirp\": 20, \"channels\": [ 1 ] }, "
		"{ \"opclass\": 82, \"max_txpower_eirp\": 15, \"channels\": [ 14 ] } ], true, true, "
		"{ \"noise\": -95, \"utilization\": 127, \"transmit\": 25, \"receive_self\": 0, \"receive_other\": 0 }, { } ]");
}

static void
test_umap(void **state)
{
	eval_expect(*state,
		"let stas = ubbf.local_sta_data_build({ 'AA:BB:CC:DD:EE:01': { signal: -40, tx: { bitrate_raw: 50 } },"
		"  'AA:BB:CC:DD:EE:02': { signal: -200 } }, [ { mac: 'aa:bb:cc:dd:ee:01', sta_info: { he_cap: { phy_cap: [ 0x08 ] } } } ]);"
		"let dev = (al, s) => ({ al_address: al, map: { supported_services: [ { supported_service: s } ] } });"
		"let api = ubbf.device_api_data_build('al1', true, { agent: { radios: { r1: { a: 1 } } },"
		"  local: { al_mac: 'al1', radios: { r1: { b: 2 }, r2: { c: 3 } }, agent_state: 'up' }, policy: null, scan: null });"
		"return [ map(stas, (s) => [ s.link_metrics.uplink_rcpi, s.extended_metrics.last_data_downlink_rate, s.he_capabilities?.he_160 ]),"
		"  map(ubbf.topology_devices_build({ devices: [ dev('a', 1), dev('b', 0) ] }, { devices: [ dev('a', 1), dev('c', 1) ] }),"
		"    (d) => d.al_address), api.capability, api._ubus_object, api.bsta_mld ];",
		"[ [ [ 140, 5000, true ], [ 0, 0, null ] ], [ \"a\", \"c\" ], "
		"{ \"radios\": { \"r1\": { \"a\": 1, \"b\": 2 }, \"r2\": { \"c\": 3 } }, \"agent_state\": \"up\" }, \"umap\", { \"bsta_mld\": null } ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_ht_vht),
		cmocka_unit_test(test_he),
		cmocka_unit_test(test_radio),
		cmocka_unit_test(test_umap),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
