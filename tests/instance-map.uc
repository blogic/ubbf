// Host test of the instance map of ubbf.so (map.c) and the stable numbering of
// Device.Optical, Cellular and USB tables (TR-369 R-ARC.8). The map lives in
// /tmp/ubbf, and /etc/ubbf holds none. The usfpd and ModemManager answers
// come from a ubus mock, the USB devices from the usb stand-in of tests/lib.
'use strict';

import { describe, it, assert, mock, beforeEach, not, equals } from 'utest';
import { state_clear } from 'test_env';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import {
	instance_numbers, instance_key, instance_rows, instance_prune, instance_floor,
	instance_lookup, instance_retire, instance_numbers_known, instance_stack, instance_number,
	instance_map_own, config_pins_take
} from 'ubbf';

const MAP = '/tmp/ubbf/instance-map.json';

// config.json brings its pins to the map as the agent loads or replaces it.
function pins_load(pins) {
	config_pins_take({ _instances: pins });
}

// The pins that config.json gets for a tree, as the agent persists it.
function pins_of(root) {
	let d = ubbf.create();

	d.set_config(json(sprintf('%J', root)));
	d.config_persist('/tmp/ubbf/pins.json', '/tmp/ubbf/pins-runtime.json', 0600);
	return json(fs.readfile('/tmp/ubbf/pins.json'))._instances ?? {};
}

function file_numbers(table) {
	let numbers = {};
	for (let key, entry in json(fs.readfile(MAP))[table]?.keys ?? {})
		numbers[key] = entry.n;
	return numbers;
}

function map_file() {
	return json(fs.readfile(MAP) ?? '{}');
}

// Answers the usfpd methods from devices.cages, a cage name to
// { optical, netdev } map, and the ModemManager dump from devices.modems.
function ubus_set(devices) {
	mock.global.patch('ubus', { behavior: {
		call: (object, method, args) => {
			let cages = devices.cages ?? {};

			if (object == 'modemmanager' && method == 'dump')
				return { modem: devices.modems ?? [] };
			if (method == 'cages')
				return { cages: keys(cages) };
			if (method == 'cage_status')
				return { SFPPresent: !!cages[args.name], Optical: !!cages[args.name]?.optical };
			if (method == 'optical_status')
				return { Name: cages[args.name]?.netdev, Status: 'Up' };
			return null;
		},
		error: () => 'Not found'
	} });
}

function api_new() {
	return {
		ubbf: proto({ cache_call: (fn, ...args) => fn(...args), ethtool_properties_get: () => ({}),
			upstream_interface_ref: () => null,
			sfp_type_resolve: (sfps, ident, type) => type, sfp_allowed: () => true }, require('ubbf')),
		utils: {
			'dm-version': { dm_visible: () => true },
			netdev_change: { last_change_get: () => '0' },
			ifstats: {}
		},
		schema: (k) => k,
		model: {},
		operations: {}
	};
}

// The handlers require ubus when they load, so they load after the mock.
function handler_load(module) {
	let api = api_new();

	include(`../modules/${module}/handler.uc`, { ubbf_module: api });
	return api;
}

describe('instance map', () => {
	beforeEach(() => {
		state_clear();
		instance_map_own(true);
	});

	it('numbers the keys of a table once and keeps the numbers', () => {
		assert.match({ a: 1, b: 2, c: 3 }, instance_numbers('T', [ 'a', 'b', 'c' ]), 'first numbers follow the order');
		assert.match({ c: 3, a: 1 }, instance_numbers('T', [ 'c', 'a' ]), 'a key keeps its number');
		assert.match({ d: 4, a: 1 }, instance_numbers('T', [ 'd', 'a' ]), 'a new key gets a new number');
		assert.match({ b: 2 }, instance_numbers('T', [ 'b' ]), 'a number is not reused');
		assert.match('d', instance_key('T', [ 'a', 'd' ], 4), 'key of a number');
		assert.match(null, instance_key('T', [ 'a' ], 4), 'key of a number not present');
		assert.match({ '4': 'd', '1': 'a' }, instance_rows('T', [ 'd', 'a' ], (k, n) => k), 'rows by number');
		assert.match([ { a: 1, b: 2, c: 3, d: 4 }, null ], [ file_numbers('T'), fs.stat('/etc/ubbf/instance-map.json') ],
			'map in /tmp only');
	});

	// Random session ids never come back: their keys go, the next number stays.
	it('drops pruned keys and does not reuse their numbers', () => {
		instance_numbers('S', [ 's1', 's2' ]);
		instance_prune('S', [ 's2' ]);
		assert.match({ s2: 2 }, file_numbers('S'), 'pruned key is gone');
		assert.match({ s2: 2, s3: 3 }, instance_numbers('S', [ 's2', 's3' ]), 'a pruned number is not reused');
		instance_prune('none', [ 'a' ]);
		assert.match(null, json(fs.readfile(MAP)).none, 'prune of an unknown table writes nothing');
	});

	// Rows that the CPE finds follow the stored rows, and an add takes a
	// number that no found row gets afterwards.
	it('numbers found rows above the stored rows', () => {
		assert.match(4, instance_floor({ '1': {}, '3': {}, Alias: 'x' }), 'floor of a stored table');
		assert.match(1, instance_floor(null), 'floor of an empty table');
		assert.match({ x: 4 }, instance_numbers('F', [ 'x' ], 4), 'a found row follows the stored rows');
	});

	// Stored rows keep their numbers and take the items they claim; the other
	// items follow the highest stored row in their order.
	it('stacks the found items on the stored rows', () => {
		let by_name = (row, item) => row.Name == item;
		let loose = (row, item) => row.Name == null;

		assert.match({ '1': 'b', '3': 'a', '4': 'c' },
			instance_stack({ '1': { Name: 'b' }, '3': { Name: 'a' } }, [ 'a', 'b', 'c' ], by_name),
			'stack: stored rows take their items');
		assert.match({ '3': 'a' }, instance_stack({ '2': { Name: 'x' } }, [ 'a' ], by_name),
			'stack: a stored row without its item is absent');
		assert.match({ '2': 'a', '1': 'b' }, instance_stack({ '1': {}, '2': { Name: 'a' } }, [ 'a', 'b' ], by_name, loose),
			'stack: a named item goes to its row before a loose row takes one');
		assert.match({ '1': 'a', '2': 'b' }, instance_stack(null, [ 'a', 'b' ], by_name), 'stack: no stored rows');
	});

	// Pins: config.json keeps the numbers of the mapped rows that it stores or
	// names; a reboot clears the map, and the pins give those numbers back.
	it('pins the numbers of the rows that config.json stores or names', () => {
		instance_numbers('Device.P.Row', [ 'k1', 'k2', 'k3' ]);
		instance_numbers('Device.P.Row.2.Sub', [ 's1' ]);
		let pconfig = { Device: {
			P: { Row: { '2': { Enable: 'false' } } },
			Q: { Ref: 'Device.P.Row.3.Name,Device.P.Row.2.Sub.1', Text: 'Device.P.Row.9' }
		} };
		assert.match({ 'Device.P.Row': { '2': 'k2', '3': 'k3' }, 'Device.P.Row.2.Sub': { '1': 's1' } }, pins_of(pconfig),
			'pins of stored and named rows');
		assert.match({}, pins_of({ Device: { Q: { Ref: 'Device.Z.1' } } }), 'no pins without mapped rows');
	});

	// A table that the map does not hold stands for one after a reboot.
	it('gives pinned keys their numbers after a reboot', () => {
		pins_load({ 'Device.R.Row': { '2': 'k2', '3': 'k3' } });
		assert.match({ k3: 3, k9: 4 }, instance_numbers('Device.R.Row', [ 'k3', 'k9' ]),
			'a pinned key keeps its number after a reboot');
		assert.match({ k2: 2 }, instance_numbers('Device.R.Row', [ 'k2' ]),
			'a pinned key that is absent keeps its number reserved');
		pins_load({ 'Device.R.Row': { '4': 'k5' } });
		assert.match({ k5: 5 }, instance_numbers('Device.R.Row', [ 'k5' ]), 'a pin yields to a key that holds its number');
		pins_load({ 'Device.R.Row': { '7': 'k3' } });
		assert.match({ k3: 7 }, instance_numbers('Device.R.Row', [ 'k3' ]), 'a pin moves its key to the pinned number');
	});

	// A row gone for good keeps its number under a key no row has. Another
	// process only reads the numbers, and sees what the agent writes.
	it('keeps retired numbers and lets only the owner number rows', () => {
		instance_numbers('Device.B.Bundle', [ 'lab' ], 3);
		instance_retire('Device.B.Bundle', 'lab');
		assert.match({ lab: 4 }, instance_numbers('Device.B.Bundle', [ 'lab' ]), 'a retired key gets a new number');
		assert.match('#3', instance_lookup('Device.B.Bundle', 3), 'the retired number stays taken');

		assert.match({ lab: 4 }, instance_numbers_known('Device.B.Bundle', [ 'lab', 'new' ]), 'known numbers only');
		instance_map_own(false);
		assert.match([ { lab: 4 }, null, null, 'lab' ],
			[ instance_numbers('Device.B.Bundle', [ 'lab', 'new' ]), instance_lookup('Device.B.Bundle', 5),
			  instance_retire('Device.B.Bundle', 'lab'), instance_lookup('Device.B.Bundle', 4) ],
			'another process numbers nothing');
		instance_map_own(true);
		let file = json(fs.readfile(MAP));
		file['Device.W.Row'] = { next: 3, keys: { w: { n: 2 } } };
		fs.writefile(MAP, sprintf('%J', file));
		assert.match('w', instance_lookup('Device.W.Row', 2), 'a write of another process is read');
	});

	// A key that no read saw for a day leaves the map; a pinned or retired key
	// stays, and the next free number stays.
	it('drops keys that no read saw for a day', () => {
		let up = clock(true)[0];
		let file = map_file();
		file['Device.E.Row'] = { next: 5, keys: {
			old: { n: 1, last_seen: up - 90000 },
			pin: { n: 2, last_seen: up - 90000 },
			recent: { n: 3, last_seen: up - 3600 },
			'#4': { n: 4 }
		} };
		fs.writefile(MAP, sprintf('%J', file));
		fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {}, _instances: { 'Device.E.Row': { '2': 'pin' } } }));
		assert.match([ 5, 'old' ], [ instance_number('Device.E.Row', 'new'), instance_lookup('Device.E.Row', 1) ],
			'a lookup of one row removes no key');
		instance_numbers('Device.E.Row', [ 'new' ]);
		assert.match([ null, 'pin', 'recent', '#4' ], map([ 1, 2, 3, 4 ], (n) => instance_lookup('Device.E.Row', n)),
			'an absent key unseen for a day leaves the map');
		assert.match({ new: 5, old: 6 }, instance_numbers('Device.E.Row', [ 'new', 'old' ]), 'its number is not given again');
		assert.match(true, json(fs.readfile(MAP))['Device.E.Row'].keys.pin.last_seen >= up, 'a pinned stale key counts as seen');
	});

	// After a reboot the first reader seeds the map from the pins of config.json.
	it('seeds a missing map from the pins of config.json', () => {
		fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {}, _instances: { 'Device.C.Cert': { '4': 'file:/a.pem' } } }));
		fs.unlink(MAP);
		assert.match({ 'file:/a.pem': 4 }, instance_numbers_known('Device.C.Cert', [ 'file:/a.pem' ]),
			'the pins of config.json seed a missing map');
		assert.match({ 'file:/a.pem': 4 }, file_numbers('Device.C.Cert'), 'the seeded map is written');
	});
});

describe('stable numbering of found rows', () => {
	beforeEach(() => {
		state_clear();
		instance_map_own(true);
	});

	// Two optical cages, a setting on cage A, then cage A loses its optical
	// SFP.
	it('keeps the Optical.Interface numbers when a cage loses its SFP', () => {
		let devices = { cages: { sfpA: { optical: true, netdev: 'ethA' }, sfpB: { optical: true, netdev: 'ethB' } } };
		ubus_set(devices);
		const optical = handler_load('usfpd').model['Device.Optical.Interface.{i}'];

		assert.match([ 'ethA', 'ethB' ], map(values(optical.get({ root: {} })), (r) => r.Name), 'both cages');

		// The dispatcher reads a stored row one by one, so enumerate mode
		// leaves it out (runtime_instances with writable_rows).
		let stored = { '1': { Enable: 'false' } };
		let root = { Device: { Optical: { Interface: stored } } };
		assert.match([ '2' ], keys(optical.get({ root })), 'enumerate leaves the stored row to the dispatcher');
		optical.set({ instance: 1, config: stored['1'] });
		assert.match('ethA', stored['1'].Name, 'set stamps cage A on row 1');
		assert.match([ 'ethA', 'false' ],
			[ optical.get({ instance: 1, config: stored['1'], root }).Name, optical.get({ instance: 1, config: stored['1'], root }).Enable ],
			'stored row 1 is cage A with its setting');

		devices.cages = { sfpB: { optical: true, netdev: 'ethB' } };
		let rows = optical.get({ root });
		assert.match([ '2' ], keys(rows), 'cage B keeps instance 2');
		assert.match('true', rows['2'].Enable, 'cage B does not take row 1 settings');
		assert.match('NotPresent', optical.get({ instance: 1, config: stored['1'], root }).Status, 'row 1 without its SFP is NotPresent');

		devices.cages = { sfpA: { optical: true, netdev: 'ethA' }, sfpB: { optical: true, netdev: 'ethB' } };
		assert.match('ethA', optical.get({ instance: 1, config: stored['1'], root }).Name, 'cage A back on instance 1');
	});

	// Two modems in dump order, a setting on row 1, then the first modem
	// leaves; after a reboot the pin of row 1 keeps its modem on row 1
	// although the dump lists it second.
	it('keeps the Cellular.Interface numbers when a modem leaves and after a reboot', () => {
		let devices = { modems: [ { generic: { device: '/sys/devA' } }, { generic: { device: '/sys/devB' } } ] };
		ubus_set(devices);
		const cellular = handler_load('cellular').model['Device.Cellular.Interface.{i}'];

		let croot = { Device: { Cellular: { Interface: { '1': { Enable: 'false' } } } } };
		let crows = cellular.get({ root: croot });
		assert.match([ '/sys/devA', '/sys/devB' ], [ crows['1'].X_UBBF_Device, crows['2'].X_UBBF_Device ],
			'first modems follow the dump order');
		assert.match('false', crows['1'].Enable, 'row 1 has its setting');

		devices.modems = [ { generic: { device: '/sys/devB' } } ];
		assert.match([ '2' ], keys(cellular.get({ root: croot })), 'a leaving modem does not shift the other');

		let cpins = pins_of(croot);
		assert.match({ '1': '/sys/devA' }, cpins['Device.Cellular.Interface'], 'the stored row pins its modem');
		fs.unlink(MAP);
		pins_load(cpins);
		devices.modems = [ { generic: { device: '/sys/devB' } }, { generic: { device: '/sys/devA' } } ];
		crows = cellular.get({ root: croot });
		assert.match([ '/sys/devA', '/sys/devB' ], [ crows['1'].X_UBBF_Device, crows['2'].X_UBBF_Device ],
			'the pinned modem keeps row 1 after a reboot');
	});

	// Two devices, the first leaves, then another device takes its port.
	it('keeps the USB numbers when a device leaves and numbers a new device anew', () => {
		const uapi = handler_load('usb');
		const ports = uapi.model['Device.USB.Port'];
		const usb_ifaces = uapi.model['Device.USB.Interface.{i}'];

		function port_names() {
			let names = {};
			for (let n, p in ports.get({}))
				names[n] = p.Name;
			return names;
		}

		global.usb_devices = { '1-1': { vid: 1, pid: 2, serial: 'A' }, '1-2': { vid: 3, pid: 4, serial: 'B' } };
		let before = port_names();
		let iface_b = filter(keys(usb_ifaces.get({})), (n) => usb_ifaces.get({})[n].Name == 'usb-1-2')[0];

		global.usb_devices = { '1-2': { vid: 3, pid: 4, serial: 'B' } };
		let after = port_names();
		assert.match(filter(keys(before), (n) => before[n] == '1-2'), filter(keys(after), (n) => after[n] == '1-2'),
			'a USB device keeps its port number when another leaves');
		assert.match('usb-1-2', usb_ifaces.get({ instance: iface_b })?.Name, 'a USB interface keeps its number');

		global.usb_devices = { '1-1': { vid: 9, pid: 9, serial: 'C' }, '1-2': { vid: 3, pid: 4, serial: 'B' } };
		let other = port_names();
		assert.match(not(equals(filter(keys(before), (n) => before[n] == '1-1'))), filter(keys(other), (n) => other[n] == '1-1'),
			'another device in the same port gets a new number');

		// ConfigurationNumberOfEntries counts the Configuration rows, not the
		// configurations the device descriptor announces.
		global.usb_devices = { '1-1': { vid: 1, pid: 2, serial: 'A' } };
		let usb_host = uapi.model['Device.USB.USBHosts.Host.{i}'].get({ instance: 1, config: {} });
		let usb_dev = values(usb_host?.Device ?? {})[0];
		assert.match(sprintf('%d', length(keys(usb_dev?.Configuration ?? {}))), usb_dev?.ConfigurationNumberOfEntries,
			'USB ConfigurationNumberOfEntries matches the rows');
	});
});
