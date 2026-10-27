// Host test of Device.Ethernet.RMONStats.{i} in tr181/Ethernet.uc: the
// RFC 2819 receive counters come from the ethtool MAC and RMON statistics,
// the length buckets of the driver map to the TR-181 ones, and a row that
// the driver statistics cannot serve reports its Status. The driver
// statistics are fixtures in the form of ubbf.ethtool_stats_get(), with the
// receive buckets of mt7530_rmon_ranges[] in drivers/net/dsa/mt7530.c.
'use strict';

import { describe, it, assert } from 'utest';
import { rmon_stats_build } from 'ubbf.tr181.Ethernet';

function bucket(low, high, value) {
	return { low, high, value };
}

const driver_stats = {
	lan1: {
		mac: { "0": 900, "3": 1000, "4": 2, "5": 1, "12": 123456, "17": 40, "18": 60 },
		rmon: { "0": 4, "1": 7, "2": 6, "3": 3 },
		hist_rx: [ bucket(0, 64, 110), bucket(65, 127, 200), bucket(128, 255, 300),
		           bucket(256, 511, 150), bucket(512, 1023, 100), bucket(1024, 15338, 150) ]
	},
	lan2: { mac: {}, rmon: {}, hist_rx: [] },
	lan3: { mac: { "3": 10, "12": 5000000000, "4": 4294967300 }, rmon: {}, hist_rx: [] }
};

const root = { Device: { Ethernet: { Interface: {
	'1': { Name: 'lan1' }, '2': { Name: 'lan2' }, '3': { Name: 'lan3' }
} } } };

let rmon_get = (ctx) => rmon_stats_build(ctx, (name) => driver_stats[name]);

function row(cfg) {
	return rmon_get({ config: { Enable: 'true', VLANID: '0', Queue: '', AllQueues: 'false', ...cfg }, root, instance: 1 });
}

function counters(r) {
	return [ r.Status, r.Name, r.Bytes, r.Packets, r.BroadcastPackets, r.MulticastPackets,
		r.CRCErroredPackets, r.UndersizePackets, r.OversizePackets ];
}

function buckets(r) {
	return [ r.Packets64Bytes, r.Packets65to127Bytes, r.Packets128to255Bytes,
		r.Packets256to511Bytes, r.Packets512to1023Bytes, r.Packets1024to1518Bytes ];
}

describe('RMONStats counters', () => {
	it('takes the MAC and RMON counters and maps the length buckets', () => {
		let full = row({ Interface: 'Device.Ethernet.Interface.1' });
		assert.match([ 'Enabled', 'lan1', '123456', '1010', '60', '40', '3', '4', '7' ], counters(full));
		assert.match([ '100', '200', '300', '150', '100', '140' ], buckets(full),
			'buckets: 64 without undersize and fragments, 1024..1518 without oversize and jabbers');
	});

	it('is Error without counters from the driver', () => {
		assert.match([ 'Error', 'lan2', null, null, null, null, null, null, null ],
			counters(row({ Interface: 'Device.Ethernet.Interface.2' })));
	});

	it('takes Packets from the MAC counters alone, wrapping an unsignedInt but not an unsignedLong', () => {
		let mac_only = row({ Interface: 'Device.Ethernet.Interface.3' });
		assert.match([ 'Enabled', '4294967310', '5000000000', '4', '0' ],
			[ mac_only.Status, mac_only.Packets, mac_only.Bytes, mac_only.CRCErroredPackets, mac_only.Packets64Bytes ]);
	});
});

describe('RMONStats Status', () => {
	it('is Error for a VLAN or queue filter, and Enabled for a queue with AllQueues', () => {
		assert.match('Error', row({ Interface: 'Device.Ethernet.Interface.1', VLANID: '10' }).Status, 'a VLAN filter');
		assert.match('Error', row({ Interface: 'Device.Ethernet.Interface.1', Queue: 'Device.QoS.Queue.1' }).Status, 'a queue filter');
		assert.match('Enabled', row({ Interface: 'Device.Ethernet.Interface.1', Queue: 'Device.QoS.Queue.1', AllQueues: 'true' }).Status);
	});

	it('is Error_Misconfigured without an Interface row', () => {
		assert.match('Error_Misconfigured', row({ Interface: '' }).Status, 'no Interface');
		assert.match('Error_Misconfigured', row({ Interface: 'Device.Ethernet.Interface.9' }).Status, 'an Interface without a row');
	});

	it('is Disabled for a disabled row', () => {
		assert.match('Disabled', row({ Enable: 'false', Interface: 'Device.Ethernet.Interface.1' }).Status);
	});
});
