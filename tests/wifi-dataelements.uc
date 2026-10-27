// Host test of utils/wifi-dataelements.uc: the HE capabilities in an
// (Re)Association Request frame body, and the operating classes and the
// Wi-Fi 6 AP role of a radio. The radio is a wiphy in the phys of the
// iwinfo stand-in.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { netifd_patch } from 'netifd_mock';
import { phys } from 'iwinfo';
import { local_radio_capability_get } from 'ubbf.utils.wifi-dataelements';
import { sta_he_caps_from_frame_body } from 'ubbf';

function elem(id, bytes) {
	return chr(id, length(bytes), ...bytes);
}

// HE Capabilities element: Element ID Extension 35, 6 octets of MAC and
// 11 of PHY capabilities, then 4 octets of HE-MCS and NSS. PHY octet 4
// (B32-B39): SU beamformee, Beamformee STS <=80 MHz 3, >80 MHz 5.
const phy_caps = [ 0x0c, 0, 0, 0, 0x01 | (3 << 2) | (5 << 5), 0, 0, 0, 0, 0, 0 ];
const he = elem(255, [ 35, 0, 0, 0, 0, 0, 0, ...phy_caps, 0xfa, 0xff, 0xfa, 0xff ]);
const elements = elem(0, [ 0x61, 0x62 ]) + elem(1, [ 0x82, 0x84 ]) + he;

const assoc = chr(0x31, 0x04, 0x0a, 0x00) + elements;
const reassoc = chr(0x31, 0x04, 0x0a, 0x00, 0x02, 0, 0, 0, 0, 0x01) + elements;
// a Current AP Address that starts with 00 looks like an SSID element
const reassoc_zero = chr(0x31, 0x04, 0x0a, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55) + elements;

function sts(body) {
	let caps = sta_he_caps_from_frame_body(b64enc(body));
	return caps ? [ caps.su_beamformee, caps.beamformee_sts_less_80, caps.beamformee_sts_greater_80 ] : null;
}

const PHY0 = {
	wiphy_name: 'phy0',
	wiphy_bands: [
		{ freqs: [ { freq: 2412 }, { freq: 2472 }, { freq: 2484 } ],
		  iftype_data: [ { iftypes: { ap: true }, he_cap_phy: [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ] } ] },
		null,
		null,
		{ freqs: [ { freq: 5935 }, { freq: 5955 }, { freq: 5975, disabled: true } ] }
	]
};

function classes(band_idx) {
	let out = {};
	for (let oc in local_radio_capability_get('phy0', band_idx)?.basic_capabilities?.opclasses_supported ?? [])
		out[oc.opclass] = oc.channels;
	return out;
}

describe('STA HE capabilities from a frame body', () => {
	it('finds the HE element in an (Re)Association Request', () => {
		assert.match([ true, 3, 5 ], sts(assoc), 'association request');
		assert.match([ true, 3, 5 ], sts(reassoc), 'reassociation request');
		assert.match([ true, 3, 5 ], sts(reassoc_zero), 'reassociation request, AP address 00:...');
	});

	it('gives null without an HE element or a complete body', () => {
		assert.match(null, sta_he_caps_from_frame_body(b64enc(chr(0x31, 0x04, 0x0a, 0x00) + elem(0, [ 0x61 ]))), 'no HE element');
		assert.match(null, sta_he_caps_from_frame_body(b64enc(substr(assoc, 0, length(assoc) - 3))), 'truncated body');
		assert.match(null, sta_he_caps_from_frame_body(null), 'no body');
	});

	it('reports OFDMA for an HE station', () => {
		let caps = sta_he_caps_from_frame_body(b64enc(assoc));
		assert.match([ true, true ], [ caps.ul_ofdma, caps.dl_ofdma ]);
	});
});

describe('local radio capabilities', () => {
	beforeEach(() => {
		netifd_patch({});
		splice(phys, 0);
		push(phys, PHY0);
	});

	it('gives the operating classes of a band', () => {
		assert.match({ '81': [ 1, 13 ], '82': [ 14 ] }, classes(0), '2.4 GHz classes');
		assert.match({ '136': [ 2 ], '131': [ 1 ] }, classes(3), '6 GHz classes');
	});

	it('reports OFDMA for an HE AP', () => {
		let roles = local_radio_capability_get('phy0', 0)?.wifi6_capabilities?.roles;
		assert.match([ [ true, true ] ], map(roles ?? [], (r) => [ r.ul_ofdma, r.dl_ofdma ]));
	});
});
