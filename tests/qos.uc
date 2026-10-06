// Host test of the qos module handler. The handler reads fixed paths, so
// run it from the repository root in a private mount namespace with the
// native module built for the host and the fake tc first in PATH. The
// logging helper imports udebug, so the search path needs that module or
// a stand-in for it:
//   unshare -rm sh -c 'mount -t tmpfs tmpfs /etc/ubbf &&
//     mkdir -p /tmp/ubbf && mount -t tmpfs tmpfs /tmp/ubbf &&
//     PATH="$PWD/tests/qos:$PATH" ucode -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" -L "<ucode modules>/*.so" tests/qos.uc'
'use strict';

import * as ubbf from 'ubbf';
import { writefile } from 'fs';
import { cmd_build } from 'ubbf.utils.process';

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%J', got);
	let exp_json = sprintf('%J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

const api = {
	ubbf,
	utils: {
		cache: { call: (fn, ...args) => fn(...args) },
		logging: { log_err: () => null, log_exception: () => null },
		netifd: { netifd_status_get: (name) => (name == 'lan') ? { l3_device: 'br-lan' } : null },
		process: { cmd_build }
	},
	schema: (k) => k,
	model: {}
};

include('../modules/qos/handler.uc', { ubbf_module: api });

const model = api.model;

writefile('/tmp/ubbf/qos-status.json', sprintf('%J', {
	'Device.QoS.Shaper.1': 'Enabled',
	'Device.QoS.Queue.1': 'Error_Misconfigured'
}));

let shaper_get = model['Device.QoS.Shaper.{i}'].get;
let queue_get = model['Device.QoS.Queue.{i}'].get;
let wifi_root = { Device: { WiFi: { SSID: { '4': { SSID: 'guest' } } } } };

assert_eq('Status: from the apply result',
	shaper_get({ instance: 1, config: { Enable: 'true', Interface: 'Device.IP.Interface.2' }, root: {} }).Status, 'Enabled');
assert_eq('Status: disabled row',
	shaper_get({ instance: 1, config: { Enable: 'false' }, root: {} }).Status, 'Disabled');
assert_eq('Status: row without a result',
	shaper_get({ instance: 2, config: { Enable: 'true' }, root: {} }).Status, 'Error');
assert_eq('Status: queue error from the apply result',
	queue_get({ instance: 1, config: { Enable: 'true' }, root: {} }).Status, 'Error_Misconfigured');
assert_eq('Status: WiFi shaper in bits per second',
	shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.4.', ShapingRate: '10000000' }, root: wifi_root }).Status,
	'Enabled');
assert_eq('Status: WiFi shaper in percent',
	shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.4', ShapingRate: '50' }, root: wifi_root }).Status,
	'Error_Misconfigured');
assert_eq('Status: WiFi shaper on a missing SSID',
	shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.9', ShapingRate: '-1' }, root: wifi_root }).Status,
	'Error_Misconfigured');

let stats_root = {
	Device: {
		IP: { Interface: { '2': { Name: 'lan' } } },
		Ethernet: { Interface: { '1': { Name: 'lo' } } },
		QoS: {
			Queue: {
				'1': { TrafficClasses: '2,3' },
				'2': { TrafficClasses: '' },
				'3': { TrafficClasses: '7' }
			}
		}
	}
};
let stats_get = model['Device.QoS.QueueStats.{i}'].get;
let stats = (queue, iface) => stats_get({ config: { Enable: 'true', Queue: queue, Interface: iface }, root: stats_root });

let s = stats('Device.QoS.Queue.1', 'Device.IP.Interface.2');
assert_eq('QueueStats: sum of the leaves',
	[ s.Status, s.OutputPackets, s.OutputBytes, s.DroppedPackets, s.DroppedBytes ],
	[ 'Enabled', '7', '7000', '3', '0' ]);
s = stats('Device.QoS.Queue.2.', 'Device.IP.Interface.2');
assert_eq('QueueStats: default class', [ s.Status, s.OutputBytes ], [ 'Enabled', '100' ]);
assert_eq('QueueStats: class missing on the device',
	stats('Device.QoS.Queue.3', 'Device.IP.Interface.2').Status, 'Error_Misconfigured');
assert_eq('QueueStats: netdev without a shaper',
	stats('Device.QoS.Queue.1', 'Device.Ethernet.Interface.1').Status, 'Error_Misconfigured');
assert_eq('QueueStats: no queue',
	stats('', 'Device.IP.Interface.2').Status, 'Error_Misconfigured');
assert_eq('QueueStats: disabled',
	stats_get({ config: { Enable: 'false' }, root: stats_root }).Status, 'Disabled');

let q = model['Device.QoS'].get({ config: { Shaper: { '1': {}, '2': {} } } });
assert_eq('QoS: Max entries and counts',
	[ q.MaxClassificationEntries, q.MaxShaperEntries, q.ShaperNumberOfEntries, q.QueueNumberOfEntries ],
	[ '64', '64', '2', '0' ]);
assert_eq('maxInstances matches MaxShaperEntries', model['Device.QoS.Shaper.{i}'].maxInstances, 64);

printf('\n--- qos handler test results ---\n  passed: %d\n  failed: %d\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
