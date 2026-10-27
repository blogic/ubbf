// Host test of the qos module handler: the Status of Shaper and Queue rows
// from the apply result, QueueStats from the class statistics of the tc
// stand-in in tests/bin, and the limits of Device.QoS.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { writefile } from 'fs';

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args) }, ubbf),
	utils: {
		netifd: { netifd_status_get: (name) => (name == 'lan') ? { l3_device: 'br-lan' } : null }
	},
	schema: (k) => k,
	model: {}
};

include('../modules/qos/handler.uc', { ubbf_module: api });

const model = api.model;

describe('qos handler', () => {
	beforeEach(() => state_clear());

	it('reads the Status of Shaper and Queue rows', () => {
		writefile('/tmp/ubbf/qos-status.json', sprintf('%J', {
			'Device.QoS.Shaper.1': 'Enabled',
			'Device.QoS.Queue.1': 'Error_Misconfigured'
		}));

		let shaper_get = model['Device.QoS.Shaper.{i}'].get;
		let queue_get = model['Device.QoS.Queue.{i}'].get;
		let wifi_root = { Device: { WiFi: { SSID: { '4': { SSID: 'guest' } } } } };

		assert.match('Enabled',
			shaper_get({ instance: 1, config: { Enable: 'true', Interface: 'Device.IP.Interface.2' }, root: {} }).Status,
			'Status: from the apply result');
		assert.match('Disabled', shaper_get({ instance: 1, config: { Enable: 'false' }, root: {} }).Status, 'Status: disabled row');
		assert.match('Error', shaper_get({ instance: 2, config: { Enable: 'true' }, root: {} }).Status, 'Status: row without a result');
		assert.match('Error_Misconfigured', queue_get({ instance: 1, config: { Enable: 'true' }, root: {} }).Status,
			'Status: queue error from the apply result');
		assert.match('Enabled',
			shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.4.', ShapingRate: '10000000' }, root: wifi_root }).Status,
			'Status: WiFi shaper in bits per second');
		assert.match('Error_Misconfigured',
			shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.4', ShapingRate: '50' }, root: wifi_root }).Status,
			'Status: WiFi shaper in percent');
		assert.match('Error_Misconfigured',
			shaper_get({ instance: 3, config: { Enable: 'true', Interface: 'Device.WiFi.SSID.9', ShapingRate: '-1' }, root: wifi_root }).Status,
			'Status: WiFi shaper on a missing SSID');
	});

	it('sums the QueueStats from the tc class statistics', () => {
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
		assert.match([ 'Enabled', '7', '7000', '3', '0' ],
			[ s.Status, s.OutputPackets, s.OutputBytes, s.DroppedPackets, s.DroppedBytes ], 'QueueStats: sum of the leaves');
		s = stats('Device.QoS.Queue.2.', 'Device.IP.Interface.2');
		assert.match([ 'Enabled', '100' ], [ s.Status, s.OutputBytes ], 'QueueStats: default class');
		assert.match('Error_Misconfigured', stats('Device.QoS.Queue.3', 'Device.IP.Interface.2').Status,
			'QueueStats: class missing on the device');
		assert.match('Error_Misconfigured', stats('Device.QoS.Queue.1', 'Device.Ethernet.Interface.1').Status,
			'QueueStats: netdev without a shaper');
		assert.match('Error_Misconfigured', stats('', 'Device.IP.Interface.2').Status, 'QueueStats: no queue');
		assert.match('Disabled', stats_get({ config: { Enable: 'false' }, root: stats_root }).Status, 'QueueStats: disabled');
	});

	it('gives the limits and counts of Device.QoS', () => {
		let q = model['Device.QoS'].get({ config: { Shaper: { '1': {}, '2': {} } } });
		assert.match([ '64', '64', '2', '0' ],
			[ q.MaxClassificationEntries, q.MaxShaperEntries, q.ShaperNumberOfEntries, q.QueueNumberOfEntries ],
			'QoS: Max entries and counts');
		assert.match(64, model['Device.QoS.Shaper.{i}'].maxInstances, 'maxInstances matches MaxShaperEntries');
	});
});
