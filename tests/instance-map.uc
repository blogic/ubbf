// Host test of the instance map of ubbf.so (map.c) and the stable numbering of
// Device.Optical, Cellular and USB tables (TR-369 R-ARC.8). The map
// lives in /tmp/ubbf, and the test checks that /etc/ubbf holds none, so
// run it in a private mount namespace; tests/instance-map/ holds
// stand-ins for ubus and usb,
// tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /etc/ubbf &&
//     mount -t tmpfs none /tmp/ubbf && ucode -L "$PWD/tests/instance-map/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/instance-map.uc'
'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import {
	instance_numbers, instance_key, instance_rows, instance_prune, instance_floor,
	instance_lookup, instance_retire, instance_numbers_known, instance_stack, instance_number,
	instance_map_own, config_pins_take
} from 'ubbf';

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

// This process numbers rows, as the agent does.
instance_map_own(true);

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const MAP = '/tmp/ubbf/instance-map.json';

function file_numbers(table) {
	let numbers = {};
	for (let key, entry in json(fs.readfile(MAP))[table]?.keys ?? {})
		numbers[key] = entry.n;
	return numbers;
}

check('first numbers follow the order', instance_numbers('T', [ 'a', 'b', 'c' ]), { a: 1, b: 2, c: 3 });
check('a key keeps its number', instance_numbers('T', [ 'c', 'a' ]), { c: 3, a: 1 });
check('a new key gets a new number', instance_numbers('T', [ 'd', 'a' ]), { d: 4, a: 1 });
check('a number is not reused', instance_numbers('T', [ 'b' ]), { b: 2 });
check('key of a number', instance_key('T', [ 'a', 'd' ], 4), 'd');
check('key of a number not present', instance_key('T', [ 'a' ], 4), null);
check('rows by number', instance_rows('T', [ 'd', 'a' ], (k, n) => k), { '4': 'd', '1': 'a' });
check('map in /tmp only', [ file_numbers('T'), fs.stat('/etc/ubbf/instance-map.json') ],
	[ { a: 1, b: 2, c: 3, d: 4 }, null ]);

// Random session ids never come back: their keys go, the next number stays.
instance_numbers('S', [ 's1', 's2' ]);
instance_prune('S', [ 's2' ]);
check('pruned key is gone', file_numbers('S'), { s2: 2 });
check('a pruned number is not reused', instance_numbers('S', [ 's2', 's3' ]), { s2: 2, s3: 3 });
instance_prune('none', [ 'a' ]);
check('prune of an unknown table writes nothing', json(fs.readfile('/tmp/ubbf/instance-map.json')).none, null);

// Rows that the CPE finds follow the stored rows, and an add takes a
// number that no found row gets afterwards.
check('floor of a stored table', instance_floor({ '1': {}, '3': {}, Alias: 'x' }), 4);
check('floor of an empty table', instance_floor(null), 1);
check('a found row follows the stored rows', instance_numbers('F', [ 'x' ], 4), { x: 4 });

// Stored rows keep their numbers and take the items they claim; the other
// items follow the highest stored row in their order.
let by_name = (row, item) => row.Name == item;
let loose = (row, item) => row.Name == null;
check('stack: stored rows take their items', instance_stack({ '1': { Name: 'b' }, '3': { Name: 'a' } }, [ 'a', 'b', 'c' ], by_name),
	{ '1': 'b', '3': 'a', '4': 'c' });
check('stack: a stored row without its item is absent', instance_stack({ '2': { Name: 'x' } }, [ 'a' ], by_name), { '3': 'a' });
check('stack: a named item goes to its row before a loose row takes one',
	instance_stack({ '1': {}, '2': { Name: 'a' } }, [ 'a', 'b' ], by_name, loose), { '2': 'a', '1': 'b' });
check('stack: no stored rows', instance_stack(null, [ 'a', 'b' ], by_name), { '1': 'a', '2': 'b' });

// Pins: config.json keeps the numbers of the mapped rows that it stores or
// names; a reboot clears the map, and the pins give those numbers back.
instance_numbers('Device.P.Row', [ 'k1', 'k2', 'k3' ]);
instance_numbers('Device.P.Row.2.Sub', [ 's1' ]);
let pconfig = { Device: {
	P: { Row: { '2': { Enable: 'false' } } },
	Q: { Ref: 'Device.P.Row.3.Name,Device.P.Row.2.Sub.1', Text: 'Device.P.Row.9' }
} };
check('pins of stored and named rows', pins_of(pconfig),
	{ 'Device.P.Row': { '2': 'k2', '3': 'k3' }, 'Device.P.Row.2.Sub': { '1': 's1' } });
check('no pins without mapped rows', pins_of({ Device: { Q: { Ref: 'Device.Z.1' } } }), {});

// A table that the map does not hold stands for one after a reboot.
pins_load({ 'Device.R.Row': { '2': 'k2', '3': 'k3' } });
check('a pinned key keeps its number after a reboot', instance_numbers('Device.R.Row', [ 'k3', 'k9' ]), { k3: 3, k9: 4 });
check('a pinned key that is absent keeps its number reserved', instance_numbers('Device.R.Row', [ 'k2' ]), { k2: 2 });
pins_load({ 'Device.R.Row': { '4': 'k5' } });
check('a pin yields to a key that holds its number', instance_numbers('Device.R.Row', [ 'k5' ]), { k5: 5 });
pins_load({ 'Device.R.Row': { '7': 'k3' } });
check('a pin moves its key to the pinned number', instance_numbers('Device.R.Row', [ 'k3' ]), { k3: 7 });

// A row gone for good keeps its number under a key no row has.
instance_numbers('Device.B.Bundle', [ 'lab' ], 3);
instance_retire('Device.B.Bundle', 'lab');
check('a retired key gets a new number', instance_numbers('Device.B.Bundle', [ 'lab' ]), { lab: 4 });
check('the retired number stays taken', instance_lookup('Device.B.Bundle', 3), '#3');

// Another process only reads the numbers, and sees what the agent writes.
check('known numbers only', instance_numbers_known('Device.B.Bundle', [ 'lab', 'new' ]), { lab: 4 });
instance_map_own(false);
check('another process numbers nothing',
	[ instance_numbers('Device.B.Bundle', [ 'lab', 'new' ]), instance_lookup('Device.B.Bundle', 5),
	  instance_retire('Device.B.Bundle', 'lab'), instance_lookup('Device.B.Bundle', 4) ],
	[ { lab: 4 }, null, null, 'lab' ]);
instance_map_own(true);
let file = json(fs.readfile('/tmp/ubbf/instance-map.json'));
file['Device.W.Row'] = { next: 3, keys: { w: { n: 2 } } };
fs.writefile('/tmp/ubbf/instance-map.json', sprintf('%J', file));
check('a write of another process is read', instance_lookup('Device.W.Row', 2), 'w');

// A key that no read saw for a day leaves the map; a pinned or retired key
// stays, and the next free number stays.
let up = clock(true)[0];
file = json(fs.readfile(MAP));
file['Device.E.Row'] = { next: 5, keys: {
	old: { n: 1, last_seen: up - 90000 },
	pin: { n: 2, last_seen: up - 90000 },
	recent: { n: 3, last_seen: up - 3600 },
	'#4': { n: 4 }
} };
fs.writefile(MAP, sprintf('%J', file));
fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {}, _instances: { 'Device.E.Row': { '2': 'pin' } } }));
check('a lookup of one row removes no key', [ instance_number('Device.E.Row', 'new'), instance_lookup('Device.E.Row', 1) ], [ 5, 'old' ]);
instance_numbers('Device.E.Row', [ 'new' ]);
check('an absent key unseen for a day leaves the map',
	map([ 1, 2, 3, 4 ], (n) => instance_lookup('Device.E.Row', n)), [ null, 'pin', 'recent', '#4' ]);
check('its number is not given again', instance_numbers('Device.E.Row', [ 'new', 'old' ]), { new: 5, old: 6 });
check('a pinned stale key counts as seen', json(fs.readfile(MAP))['Device.E.Row'].keys.pin.last_seen >= up, true);
fs.unlink('/etc/ubbf/config.json');

// After a reboot the first reader seeds the map from the pins of config.json.
fs.writefile('/etc/ubbf/config.json', sprintf('%J', { Device: {}, _instances: { 'Device.C.Cert': { '4': 'file:/a.pem' } } }));
fs.unlink('/tmp/ubbf/instance-map.json');
check('the pins of config.json seed a missing map', instance_numbers_known('Device.C.Cert', [ 'file:/a.pem' ]), { 'file:/a.pem': 4 });
check('the seeded map is written', file_numbers('Device.C.Cert'), { 'file:/a.pem': 4 });
fs.unlink('/etc/ubbf/config.json');

// Device.Optical.Interface: two optical cages, a setting on cage A, then
// cage A loses its optical SFP.
const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args), ethtool_properties_get: () => ({}),
		upstream_interface_ref: () => null,
		sfp_type_resolve: (sfps, ident, type) => type, sfp_allowed: () => true }, require('ubbf')),
	utils: {
		'dm-version': { dm_visible: () => true },
		netdev_change: { last_change_get: () => '0' }
	},
	schema: (k) => k,
	model: {},
	operations: {}
};
include('../modules/usfpd/handler.uc', { ubbf_module: api });

const optical = api.model['Device.Optical.Interface.{i}'];
global.usfpd_cages = { sfpA: { optical: true, netdev: 'ethA' }, sfpB: { optical: true, netdev: 'ethB' } };

check('both cages', map(values(optical.get({ root: {} })), (r) => r.Name), [ 'ethA', 'ethB' ]);

// The dispatcher reads a stored row one by one, so enumerate mode leaves it
// out (runtime_instances with writable_rows).
let stored = { '1': { Enable: 'false' } };
let root = { Device: { Optical: { Interface: stored } } };
check('enumerate leaves the stored row to the dispatcher', keys(optical.get({ root })), [ '2' ]);
optical.set({ instance: 1, config: stored['1'] });
check('set stamps cage A on row 1', stored['1'].Name, 'ethA');
check('stored row 1 is cage A with its setting',
	[ optical.get({ instance: 1, config: stored['1'], root }).Name, optical.get({ instance: 1, config: stored['1'], root }).Enable ],
	[ 'ethA', 'false' ]);

global.usfpd_cages = { sfpB: { optical: true, netdev: 'ethB' } };
let rows = optical.get({ root });
check('cage B keeps instance 2', keys(rows), [ '2' ]);
check('cage B does not take row 1 settings', rows['2'].Enable, 'true');
check('row 1 without its SFP is NotPresent', optical.get({ instance: 1, config: stored['1'], root }).Status, 'NotPresent');

global.usfpd_cages = { sfpA: { optical: true, netdev: 'ethA' }, sfpB: { optical: true, netdev: 'ethB' } };
check('cage A back on instance 1', optical.get({ instance: 1, config: stored['1'], root }).Name, 'ethA');

// Device.Cellular.Interface: two modems in dump order, a setting on row 1,
// then the first modem leaves; after a reboot the pin of row 1 keeps its
// modem on row 1 although the dump lists it second.
const capi = { ...api, model: {}, operations: {} };
include('../modules/cellular/handler.uc', { ubbf_module: capi });
const cellular = capi.model['Device.Cellular.Interface.{i}'];

global.mm_modems = [ { generic: { device: '/sys/devA' } }, { generic: { device: '/sys/devB' } } ];
let croot = { Device: { Cellular: { Interface: { '1': { Enable: 'false' } } } } };
let crows = cellular.get({ root: croot });
check('first modems follow the dump order', [ crows['1'].X_UBBF_Device, crows['2'].X_UBBF_Device ], [ '/sys/devA', '/sys/devB' ]);
check('row 1 has its setting', crows['1'].Enable, 'false');

global.mm_modems = [ { generic: { device: '/sys/devB' } } ];
check('a leaving modem does not shift the other', keys(cellular.get({ root: croot })), [ '2' ]);

let cpins = pins_of(croot);
check('the stored row pins its modem', cpins['Device.Cellular.Interface'], { '1': '/sys/devA' });
fs.unlink('/tmp/ubbf/instance-map.json');
pins_load(cpins);
global.mm_modems = [ { generic: { device: '/sys/devB' } }, { generic: { device: '/sys/devA' } } ];
crows = cellular.get({ root: croot });
check('the pinned modem keeps row 1 after a reboot', [ crows['1'].X_UBBF_Device, crows['2'].X_UBBF_Device ], [ '/sys/devA', '/sys/devB' ]);

// Device.USB: two devices, the first leaves, then another device takes its
// port.
const uapi = { ...api, utils: { ...api.utils, ifstats: {} }, model: {}, operations: {} };
include('../modules/usb/handler.uc', { ubbf_module: uapi });
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
check('a USB device keeps its port number when another leaves',
	filter(keys(after), (n) => after[n] == '1-2'), filter(keys(before), (n) => before[n] == '1-2'));
check('a USB interface keeps its number', usb_ifaces.get({ instance: iface_b })?.Name, 'usb-1-2');

global.usb_devices = { '1-1': { vid: 9, pid: 9, serial: 'C' }, '1-2': { vid: 3, pid: 4, serial: 'B' } };
let other = port_names();
check('another device in the same port gets a new number',
	sprintf('%J', filter(keys(other), (n) => other[n] == '1-1')) != sprintf('%J', filter(keys(before), (n) => before[n] == '1-1')), true);

// ConfigurationNumberOfEntries counts the Configuration rows, not the
// configurations the device descriptor announces
global.usb_devices = { '1-1': { vid: 1, pid: 2, serial: 'A' } };
let usb_host = uapi.model['Device.USB.USBHosts.Host.{i}'].get({ instance: 1, config: {} });
let usb_dev = values(usb_host?.Device ?? {})[0];
check('USB ConfigurationNumberOfEntries matches the rows',
	usb_dev?.ConfigurationNumberOfEntries, sprintf('%d', length(keys(usb_dev?.Configuration ?? {}))));

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
