// Host test of utils/wifi-dataelements.uc: the HE capabilities in an
// (Re)Association Request frame body, and the operating classes and the
// Wi-Fi 6 AP role of a radio. tests/wifi-de/ holds stand-ins for iwinfo, nl80211 and
// wifi.utils, tests/ip/ the ubus stand-in:
//   ucode -L "$PWD/tests/wifi-de/*.uc" -L "$PWD/tests/ip/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/wifi-dataelements.uc
'use strict';

import { phys } from 'iwinfo';
import { local_radio_capability_get } from 'ubbf.utils.wifi-dataelements';
import { sta_he_caps_from_frame_body } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function elem(id, bytes) {
	return chr(id, length(bytes), ...bytes);
}

// HE Capabilities element: Element ID Extension 35, 6 octets of MAC and
// 11 of PHY capabilities, then 4 octets of HE-MCS and NSS. PHY octet 4
// (B32-B39): SU beamformee, Beamformee STS <=80 MHz 3, >80 MHz 5.
let phy_caps = [ 0x0c, 0, 0, 0, 0x01 | (3 << 2) | (5 << 5), 0, 0, 0, 0, 0, 0 ];
let he = elem(255, [ 35, 0, 0, 0, 0, 0, 0, ...phy_caps, 0xfa, 0xff, 0xfa, 0xff ]);
let elements = elem(0, [ 0x61, 0x62 ]) + elem(1, [ 0x82, 0x84 ]) + he;

let assoc = chr(0x31, 0x04, 0x0a, 0x00) + elements;
let reassoc = chr(0x31, 0x04, 0x0a, 0x00, 0x02, 0, 0, 0, 0, 0x01) + elements;
// a Current AP Address that starts with 00 looks like an SSID element
let reassoc_zero = chr(0x31, 0x04, 0x0a, 0x00, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55) + elements;

function sts(body) {
	let caps = sta_he_caps_from_frame_body(b64enc(body));
	return caps ? [ caps.su_beamformee, caps.beamformee_sts_less_80, caps.beamformee_sts_greater_80 ] : null;
}

check('association request', sts(assoc), [ true, 3, 5 ]);
check('reassociation request', sts(reassoc), [ true, 3, 5 ]);
check('reassociation request, AP address 00:...', sts(reassoc_zero), [ true, 3, 5 ]);
check('no HE element', sta_he_caps_from_frame_body(b64enc(chr(0x31, 0x04, 0x0a, 0x00) + elem(0, [ 0x61 ]))), null);
check('truncated body', sta_he_caps_from_frame_body(b64enc(substr(assoc, 0, length(assoc) - 3))), null);
check('no body', sta_he_caps_from_frame_body(null), null);

let caps = sta_he_caps_from_frame_body(b64enc(assoc));
check('HE station OFDMA', [ caps.ul_ofdma, caps.dl_ofdma ], [ true, true ]);

push(phys, {
	wiphy_name: 'phy0',
	wiphy_bands: [
		{ freqs: [ { freq: 2412 }, { freq: 2472 }, { freq: 2484 } ],
		  iftype_data: [ { iftypes: { ap: true }, he_cap_phy: [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ] } ] },
		null,
		null,
		{ freqs: [ { freq: 5935 }, { freq: 5955 }, { freq: 5975, disabled: true } ] }
	]
});

function classes(band_idx) {
	let out = {};
	for (let oc in local_radio_capability_get('phy0', band_idx)?.basic_capabilities?.opclasses_supported ?? [])
		out[oc.opclass] = oc.channels;
	return out;
}

check('2.4 GHz classes', classes(0), { '81': [ 1, 13 ], '82': [ 14 ] });
check('6 GHz classes', classes(3), { '136': [ 2 ], '131': [ 1 ] });

let roles = local_radio_capability_get('phy0', 0)?.wifi6_capabilities?.roles;
check('HE AP OFDMA', map(roles ?? [], (r) => [ r.ul_ofdma, r.dl_ofdma ]), [ [ true, true ] ]);

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
