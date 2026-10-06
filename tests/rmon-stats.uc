// Host test of Device.Ethernet.RMONStats.{i} in tr181/Ethernet.uc: the
// RFC 2819 receive counters come from the ethtool MAC and RMON statistics,
// the length buckets of the driver map to the TR-181 ones, and a row that
// the driver statistics cannot serve reports its Status. tests/rmon/ holds
// a stand-in for gnl, tests/hosts/ one for udebug. Run from the repository
// root with the native module built for the host:
//   ucode -L "$PWD/tests/rmon/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/rmon-stats.uc
'use strict';

import { model } from 'ubbf.tr181.Ethernet';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function bucket(low, high, value) {
	return { "hist-bkt-low": low, "hist-bkt-hi": high, "hist-val": value };
}

global.ethtool_replies = {
	lan1: {
		header: { "dev-index": 6, "dev-name": "lan1" },
		grp: [
			{ id: 1, "ss-id": 18, stat: { "0": 900, "3": 1000, "4": 2, "5": 1, "12": 123456, "17": 40, "18": 60 } },
			{ id: 3, "ss-id": 20,
			  "hist-rx": [ bucket(0, 64, 110), bucket(65, 127, 200), bucket(128, 255, 300),
			               bucket(256, 511, 150), bucket(512, 1023, 100), bucket(1024, 15338, 150) ],
			  stat: { "0": 4, "1": 7, "2": 6, "3": 3 } }
		]
	},
	lan2: {
		header: { "dev-index": 7, "dev-name": "lan2" },
		grp: [ { id: 1, "ss-id": 18 }, { id: 3, "ss-id": 20 } ]
	},
	lan3: {
		header: { "dev-index": 8, "dev-name": "lan3" },
		grp: [ { id: 1, "ss-id": 18, stat: { "3": 10, "12": 5000000000, "4": 4294967300 } } ]
	}
};

const root = { Device: { Ethernet: { Interface: {
	'1': { Name: 'lan1' }, '2': { Name: 'lan2' }, '3': { Name: 'lan3' }
} } } };

let rmon_get = model['Device.Ethernet.RMONStats.{i}'].get;

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

let full = row({ Interface: 'Device.Ethernet.Interface.1' });
check('MAC and RMON counters', counters(full),
	[ 'Enabled', 'lan1', '123456', '1010', '60', '40', '3', '4', '7' ]);
check('buckets: 64 without undersize and fragments, 1024..1518 without oversize and jabbers',
	buckets(full), [ '100', '200', '300', '150', '100', '140' ]);

check('no counters from the driver', counters(row({ Interface: 'Device.Ethernet.Interface.2' })),
	[ 'Error', 'lan2', null, null, null, null, null, null, null ]);

let mac_only = row({ Interface: 'Device.Ethernet.Interface.3' });
check('MAC counters only: Packets from the MAC, an unsignedInt wraps, an unsignedLong does not',
	[ mac_only.Status, mac_only.Packets, mac_only.Bytes, mac_only.CRCErroredPackets, mac_only.Packets64Bytes ],
	[ 'Enabled', '4294967310', '5000000000', '4', '0' ]);

check('a VLAN filter', row({ Interface: 'Device.Ethernet.Interface.1', VLANID: '10' }).Status, 'Error');
check('a queue filter', row({ Interface: 'Device.Ethernet.Interface.1', Queue: 'Device.QoS.Queue.1' }).Status, 'Error');
check('a queue with AllQueues', row({ Interface: 'Device.Ethernet.Interface.1', Queue: 'Device.QoS.Queue.1', AllQueues: 'true' }).Status, 'Enabled');
check('no Interface', row({ Interface: '' }).Status, 'Error_Misconfigured');
check('an Interface without a row', row({ Interface: 'Device.Ethernet.Interface.9' }).Status, 'Error_Misconfigured');
check('disabled', row({ Enable: 'false', Interface: 'Device.Ethernet.Interface.1' }).Status, 'Disabled');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
