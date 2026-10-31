// Host test of the local radio list of utils/wifi-dataelements.uc (I-2118):
// the wireless status lists an AP MLD under each of its radios with one
// netdev, and each radio shows the BSSID of its own link. The local rows and
// the rows of an EasyMesh topology share the numbers of a radio's BSS table.
'use strict';

import { describe, it, assert, mock } from 'utest';
import { writefile } from 'fs';
import { phys, ifaces } from 'iwinfo';
import { radio_link_find } from 'ubbf.utils.wifi_radio';
import { local_radios_get } from 'ubbf.utils.wifi-dataelements';

const LINKS = [
	{ link_id: 0, mac: '02:00:00:00:01:10', wiphy_freq: 2437 },
	{ link_id: 1, mac: '42:00:00:00:01:10', wiphy_freq: 5180 },
	{ link_id: 2, mac: 'c2:00:00:00:01:10', wiphy_freq: 6135 }
];

const CAPS = [
	{ name: 'radio0', band: '2g' },
	{ name: 'radio1', band: '5g', freq_ranges: [ [ 5170000, 5350000 ] ] },
	{ name: 'radio2', band: '6g' },
	{ name: 'radio3', band: '5g', freq_ranges: [ [ 5490000, 5895000 ] ] }
];

function ap_mld(ifname) {
	return { ifname, config: { mode: 'ap', mlo: (ifname == 'ap-mld0') ? '1' : true, ssid: ifname } };
}

function radio(band, index, ...interfaces) {
	return { config: { band, radio: index, test_phy: 'phy0' }, interfaces };
}

const STATUS = {
	radio0: radio('2g', 0, ap_mld('ap-mld0'), ap_mld('ap-mld1')),
	radio1: radio('5g', 1, ap_mld('ap-mld0'), ap_mld('ap-mld1'),
		{ ifname: 'phy0.1-ap0', config: { mode: 'ap', macaddr: '42:00:00:00:02:10', ssid: 'single' } }),
	radio2: radio('6g', 2, ap_mld('ap-mld0'), ap_mld('ap-mld1')),
	radio3: radio('5g', 3, ap_mld('ap-mld0'), ap_mld('ap-mld1'))
};

const PHY = {
	wiphy_name: 'phy0',
	mac: '02:00:00:00:01:10',
	radios: [
		{ index: 0, freq_ranges: [ { start: 2402000, end: 2494000 } ] },
		{ index: 1, freq_ranges: [ { start: 5170000, end: 5350000 } ] },
		{ index: 2, freq_ranges: [ { start: 5925000, end: 7125000 } ] },
		{ index: 3, freq_ranges: [ { start: 5490000, end: 5895000 } ] }
	]
};

describe('local radio list', () => {
	it('finds the link of a radio by band and frequency range', () => {
		assert.match('42:00:00:00:01:10', radio_link_find(LINKS, '5g', CAPS[1])?.mac, 'the link in the ranges');
		assert.match(null, radio_link_find(LINKS, '5g', CAPS[3]), 'a radio of the band with other ranges');
		assert.match('02:00:00:00:01:10', radio_link_find(LINKS, '2g', CAPS[0])?.mac, 'a radio without ranges, by band');
		assert.match('c2:00:00:00:01:10', radio_link_find(LINKS, '6g', null)?.mac, 'no capability radio, by band');
		assert.match(null, radio_link_find(null, '2g', CAPS[0]), 'an interface without links');
	});

	// The results stay in ubbf.cache_call() for 2 s of event loop time, so only
	// this test calls the cached functions.
	it('lists under each radio the BSSID of its own link, never the MLD address', () => {
		writefile('/tmp/ubbf/capabilities.json', sprintf('%J', { radios: CAPS }));
		push(phys, PHY);
		ifaces['ap-mld0'] = { mac: '02:00:00:00:01:10', mlo_links: LINKS };
		ifaces['ap-mld1'] = {
			mac: '06:00:00:00:01:10',
			mlo_links: map(LINKS, (l) => ({ ...l, mac: replace(l.mac, /^(.)2/, '$16') }))
		};
		mock.global.patch('ubus', { behavior: { call: (object, method) =>
			(object == 'network.wireless' && method == 'status') ? STATUS : null } });

		let out = {};
		for (let r in local_radios_get())
			out[r._radio_name] = map(r.bss, (b) => b.mac_address);

		assert.match({
			radio0: [ '02:00:00:00:01:10', '06:00:00:00:01:10' ],
			radio1: [ '42:00:00:00:01:10', '46:00:00:00:01:10', '42:00:00:00:02:10' ],
			radio2: [ 'c2:00:00:00:01:10', 'c6:00:00:00:01:10' ],
			radio3: [ '', '' ]
		}, out, 'own link, a configured address, and no key where the radio has no link yet');
	});
});
