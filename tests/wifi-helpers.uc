// Host test of the phy and htmode helpers and dscp_parse() of ubbf.so
// (wifi.c, wifi_phy.c).
'use strict';

import { describe, it, assert } from 'utest';
import {
	clamp_htmode, standards_bandwidth_to_htmode, phy_supported_standards,
	phy_supported_bandwidths, phy_max_bandwidth, dscp_parse
} from 'ubbf';

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

describe('htmode helpers', () => {
	it('clamps the bandwidth to the standard and the radio', () => {
		assert.match('HT40', clamp_htmode('n', '80MHz', 'ax', '160MHz'), 'n at 80MHz');
		assert.match('VHT80', clamp_htmode('ac', '160MHz', 'ax', '80MHz'), 'ac at 160MHz on an 80MHz radio');
		assert.match('VHT160', clamp_htmode('ac', '80+80MHz', 'ac', '160MHz'), '80+80 request');
	});

	it('maps a standard and a bandwidth to an htmode', () => {
		assert.match('HE160', standards_bandwidth_to_htmode('ax', '320MHz'), 'ax at 320MHz');
		assert.match('EHT320', standards_bandwidth_to_htmode('be', '320MHz'), 'be at 320MHz');
		assert.match('NOHT', standards_bandwidth_to_htmode('g', '20MHz'), 'legacy');
	});
});

describe('phy helpers', () => {
	it('gives the supported standards of a band', () => {
		assert.match('b,g,n,ax', phy_supported_standards(phy, 0), '2.4 GHz');
		assert.match('a,n,ac,ax', phy_supported_standards(phy, 1), '5 GHz');
		assert.match('ax', phy_supported_standards(phy, 3), '6 GHz');
	});

	it('gives the supported bandwidths of a band', () => {
		assert.match('20MHz,40MHz,80MHz,160MHz', phy_supported_bandwidths(phy, 1), '5 GHz');
	});

	it('gives the maximum bandwidth of a band', () => {
		assert.match('160MHz', phy_max_bandwidth(phy, 1), '5 GHz, first channel without 160MHz');
		assert.match('40MHz', phy_max_bandwidth(phy, 0), '2.4 GHz');
		assert.match('20MHz', phy_max_bandwidth(phy, 2), 'no band');
	});
});

describe('dscp_parse', () => {
	it('parses a name or a number', () => {
		assert.match(46, dscp_parse('ef'), 'name');
		assert.match(12, dscp_parse(' 12 '), 'number');
	});

	it('rejects junk and values out of range', () => {
		assert.match(null, dscp_parse('12abc'), 'trailing junk');
		assert.match(null, dscp_parse('64'), 'out of range');
		assert.match(null, dscp_parse('-1'), 'negative');
	});
});
