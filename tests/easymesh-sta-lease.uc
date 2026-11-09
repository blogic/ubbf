// Host test of IPV4Address, IPV6Address and Hostname of
// Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i} and of
// IPv4Address, IPv6Address and Hostname of APMLD.{i}.STAMLD.{i} in
// modules/easymesh: they come from the DHCP leases of the device that answers,
// the dnsmasq leases in /tmp/dhcp.leases and the odhcpd leases, looked up by
// the station MAC or the client MLD MAC in any case. A lease that ran out
// gives nothing, a lease of expiry 0 never runs out, and the IPv6 address is
// the first address of the odhcpd lease.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';

const AL = '02:00:00:00:00:a1';
const RUID = '02:00:00:00:05:00';
const BSSID = '02:00:00:00:05:01';
const STA = '0a:00:00:00:00:01';
const MLD = '0a:00:00:00:00:a0';

let v6_leases = {};

const api = {
	ubbf,
	model: {},
	operations: {},
	schema: (k) => k,
	utils: {
		dhcp: { ipv6_leases_get: () => v6_leases },
		'wifi-dataelements': {
			topology_devices_get: () => [ { al_address: AL } ],
			local_device_get: () => ({ al_address: AL }),
			ubus_topology_get: () => ({}),
			device_api_data_get: () => ({}),
			local_api_data_get: () => ({}),
			steering_stats_get: () => ({}),
			steering_history_get: () => ({}),
			radios_bss_sort: (radios) => radios ?? [],
			client_query_get: () => null
		},
		capabilities: { capability_radios_get },
		wifi_radio: { radio_instances_for_bands }
	}
};

const em = { easymesh_model: {}, al_index_map: () => ({}), ap_by_ssid_ref_find: () => null };
const DIR = sourcepath(0, true) + '/../modules/easymesh';
include(DIR + '/objectdata.uc', { ubbf_module: api, em });

// Each line: [ expiry, MAC, IPv4 address, hostname ], as dnsmasq writes them.
function leases_write(list) {
	fs.writefile('/tmp/dhcp.leases', join('', map(list, (l) => sprintf('%d %s %s %s *\n', l[0], l[1], l[2], l[3]))));
}

function device_read(sta_mac, mld_mac) {
	const device = { al_address: AL, map: { ap_operational_bss: [
		{ radio_unique_identifier: RUID, bss: [ { mac_address: BSSID, associated_clients: [ { mac_address: sta_mac } ] } ] }
	] } };
	const api_data = { ap_mld: { ap_mlds: { [BSSID]: {
		ap_mld_mac_addr: BSSID, affiliated_aps: [], sta_mld_associations: [ { sta_mld_mac_addr: mld_mac } ]
	} } } };

	return em.device_to_object(device, api_data, false, {}, {}, {});
}

function sta_read(sta_mac) {
	// A STA keeps its number by MAC, so another MAC gets another number.
	const sta = values(device_read(sta_mac ?? STA, MLD).Radio['1'].BSS['1'].STA)[0];

	return [ sta.IPV4Address, sta.IPV6Address, sta.Hostname ];
}

function stamld_read(mld_mac) {
	const stamld = device_read(STA, mld_mac ?? MLD).APMLD['1'].STAMLD['1'];

	return [ stamld.IPv4Address, stamld.IPv6Address, stamld.Hostname ];
}

describe('DataElements STA and STAMLD addresses and name from the leases', () => {
	beforeEach(() => {
		state_clear();
		ubbf.instance_map_own(true);
		fs.unlink('/tmp/dhcp.leases');
		v6_leases = {};
	});

	it('fills the STA row from the leases of its MAC', () => {
		leases_write([ [ time() + 600, STA, '192.168.1.102', 'laptop' ] ]);
		v6_leases = { [uc(STA)]: [ '2001:db8::102', '2001:db8::103' ] };

		assert.match([ '192.168.1.102', '2001:db8::102', 'laptop' ], sta_read());
	});

	it('fills the STAMLD row from the leases of the MLD MAC', () => {
		leases_write([ [ time() + 600, STA, '192.168.1.102', 'laptop' ], [ time() + 600, MLD, '192.168.1.160', 'phone' ] ]);
		v6_leases = { [uc(MLD)]: [ '2001:db8::160' ] };

		assert.match([ '192.168.1.160', '2001:db8::160', 'phone' ], stamld_read());
		assert.match([ '192.168.1.102', '', 'laptop' ], sta_read(), 'the STA row keeps its own lease');
	});

	it('compares the MAC addresses without case', () => {
		leases_write([ [ time() + 600, uc(STA), '192.168.1.102', 'laptop' ] ]);
		v6_leases = { [uc(STA)]: [ '2001:db8::102' ] };

		assert.match([ '192.168.1.102', '2001:db8::102', 'laptop' ], sta_read(STA), 'umapd lower case');
		assert.match([ '192.168.1.102', '2001:db8::102', 'laptop' ], sta_read(uc(STA)), 'upper case');
	});

	it('gives no hostname for a lease without one', () => {
		leases_write([ [ time() + 600, STA, '192.168.1.102', '*' ] ]);

		assert.match([ '192.168.1.102', '', '' ], sta_read());
	});

	it('leaves out a dnsmasq lease that ran out', () => {
		leases_write([ [ time() - 10, STA, '192.168.1.102', 'laptop' ], [ time() - 10, MLD, '192.168.1.160', 'phone' ] ]);
		v6_leases = { [uc(STA)]: [ '2001:db8::102' ] };

		assert.match([ '', '2001:db8::102', '' ], sta_read());
		assert.match([ '', '', '' ], stamld_read());
	});

	it('keeps a dnsmasq lease of expiry 0', () => {
		leases_write([ [ 0, STA, '192.168.1.102', 'laptop' ] ]);

		assert.match([ '192.168.1.102', '', 'laptop' ], sta_read());
	});

	it('leaves the fields empty where no lease names the MAC', () => {
		leases_write([ [ time() + 600, '0a:00:00:00:00:99', '192.168.1.199', 'other' ] ]);
		v6_leases = { '0A:00:00:00:00:99': [ '2001:db8::199' ] };

		assert.match([ '', '', '' ], sta_read());
		assert.match([ '', '', '' ], stamld_read());
	});

	it('leaves the fields empty on a device without leases', () => {
		assert.match([ '', '', '' ], sta_read());
		assert.match([ '', '', '' ], stamld_read());
	});

	it('takes the later of two leases of one MAC', () => {
		leases_write([ [ time() + 600, STA, '192.168.1.102', 'old' ], [ time() + 900, STA, '192.168.1.104', 'new' ] ]);

		assert.match([ '192.168.1.104', '', 'new' ], sta_read());
	});

	it('reads the leases again at each Get', () => {
		leases_write([ [ time() + 600, STA, '192.168.1.102', 'laptop' ] ]);
		assert.match([ '192.168.1.102', '', 'laptop' ], sta_read());

		leases_write([ [ time() + 600, STA, '192.168.1.105', 'renamed' ] ]);
		v6_leases = { [uc(STA)]: [ '2001:db8::105' ] };
		assert.match([ '192.168.1.105', '2001:db8::105', 'renamed' ], sta_read());
	});
});
