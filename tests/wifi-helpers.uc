// Host test of the phy and htmode helpers and dscp_parse() of ubbf.so
// (wifi.c, wifi_phy.c):
//   ucode -L "<host build>/*.so" tests/wifi-helpers.uc
'use strict';

import {
	clamp_htmode, standards_bandwidth_to_htmode, phy_supported_standards,
	phy_supported_bandwidths, phy_max_bandwidth, dscp_parse
} from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

check('n at 80MHz', clamp_htmode('n', '80MHz', 'ax', '160MHz'), 'HT40');
check('ac at 160MHz on an 80MHz radio', clamp_htmode('ac', '160MHz', 'ax', '80MHz'), 'VHT80');
check('ax at 320MHz', standards_bandwidth_to_htmode('ax', '320MHz'), 'HE160');
check('be at 320MHz', standards_bandwidth_to_htmode('be', '320MHz'), 'EHT320');
check('80+80 request', clamp_htmode('ac', '80+80MHz', 'ac', '160MHz'), 'VHT160');
check('legacy', standards_bandwidth_to_htmode('g', '20MHz'), 'NOHT');

const ap_he = [ { iftypes: { ap: true }, he_cap_phy: [ 0 ] } ];
const phy = { wiphy_bands: [
	{ ht_capa: 1, iftype_data: ap_he, freqs: [ { freq: 2412, no_80mhz: true, no_160mhz: true } ] },
	{ ht_capa: 1, vht_mcs_set: 1, iftype_data: ap_he, freqs: [
		{ freq: 5180, no_160mhz: true },
		{ freq: 5500 }
	] },
	null,
	{ iftype_data: ap_he, freqs: [ { freq: 5955 } ] }
] };

check('2.4 GHz standards', phy_supported_standards(phy, 0), 'b,g,n,ax');
check('5 GHz standards', phy_supported_standards(phy, 1), 'a,n,ac,ax');
check('6 GHz standards', phy_supported_standards(phy, 3), 'ax');
check('5 GHz bandwidths', phy_supported_bandwidths(phy, 1), '20MHz,40MHz,80MHz,160MHz');
check('5 GHz maximum, first channel without 160MHz', phy_max_bandwidth(phy, 1), '160MHz');
check('2.4 GHz maximum', phy_max_bandwidth(phy, 0), '40MHz');
check('no band', phy_max_bandwidth(phy, 2), '20MHz');

check('dscp name', dscp_parse('ef'), 46);
check('dscp number', dscp_parse(' 12 '), 12);
check('dscp trailing junk', dscp_parse('12abc'), null);
check('dscp out of range', dscp_parse('64'), null);
check('dscp negative', dscp_parse('-1'), null);

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
