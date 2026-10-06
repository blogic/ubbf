// Host test of utils/instance-map.uc and the stable numbering of
// Device.Optical, Cellular and USB tables (TR-369 R-ARC.8). The map
// files live in /etc/ubbf and /tmp/ubbf, so run it in a private mount
// namespace; tests/instance-map/ holds stand-ins for ubus and usb,
// tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /etc/ubbf &&
//     mount -t tmpfs none /tmp/ubbf && ucode -L "$PWD/tests/instance-map/*.uc" \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/instance-map.uc'
'use strict';

import * as fs from 'fs';
import { instance_numbers, instance_key, instance_rows, instance_seed, instance_prune } from 'ubbf.utils.instance-map';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

check('first numbers follow the order', instance_numbers('T', [ 'a', 'b', 'c' ]), { a: 1, b: 2, c: 3 });
check('a key keeps its number', instance_numbers('T', [ 'c', 'a' ]), { c: 3, a: 1 });
check('a new key gets a new number', instance_numbers('T', [ 'd', 'a' ]), { d: 4, a: 1 });
check('a number is not reused', instance_numbers('T', [ 'b' ]), { b: 2 });
check('key of a number', instance_key('T', [ 'a', 'd' ], 4), 'd');
check('key of a number not present', instance_key('T', [ 'a' ], 4), null);
check('rows by number', instance_rows('T', [ 'd', 'a' ], (k, n) => k), { '4': 'd', '1': 'a' });
check('map persisted', json(fs.readfile('/etc/ubbf/instance-map.json')).T.keys, { a: 1, b: 2, c: 3, d: 4 });
check('volatile map in /tmp', [ instance_numbers('H', [ 'x' ], true), !!fs.stat('/tmp/ubbf/instance-map.json') ],
	[ { x: 1 }, true ]);

// Random session ids never come back: their keys go, the next number stays.
instance_numbers('S', [ 's1', 's2' ], true);
instance_prune('S', [ 's2' ], true);
check('pruned key is gone', json(fs.readfile('/tmp/ubbf/instance-map.json')).S.keys, { s2: 2 });
check('a pruned number is not reused', instance_numbers('S', [ 's2', 's3' ], true), { s2: 2, s3: 3 });
instance_prune('none', [ 'a' ], true);
check('prune of an unknown table writes nothing', json(fs.readfile('/tmp/ubbf/instance-map.json')).none, null);

// Device.Optical.Interface: two optical cages, a setting on cage A, then
// cage A loses its optical SFP.
const api = {
	ubbf: require('ubbf'),
	utils: {
		cache: { call: (fn, ...args) => fn(...args) },
		'instance-map': { instance_numbers, instance_key, instance_rows, instance_seed },
		'dm-version': { dm_visible: () => true },
		ethtool: { ethtool_properties_get: () => ({}) },
		netdev_change: { last_change_get: () => '0' },
		helpers: { upstream_interface_ref: () => null },
		sfp: { sfp_type_resolve: (sfps, ident, type) => type, sfp_allowed: () => true }
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

// Device.Cellular.Interface: a stored row names its modem by device path,
// a second modem comes first in the dump, then the first modem leaves.
const capi = { ...api, model: {}, operations: {} };
include('../modules/cellular/handler.uc', { ubbf_module: capi });
const cellular = capi.model['Device.Cellular.Interface.{i}'];

global.mm_modems = [ { generic: { device: '/sys/devB' } }, { generic: { device: '/sys/devA' } } ];
let croot = { Device: { Cellular: { Interface: { '1': { X_UBBF_Device: '/sys/devA', Enable: 'false' } } } } };
let crows = cellular.get({ root: croot });
check('stored modem keeps its row', crows['1'].X_UBBF_Device, '/sys/devA');
check('other modem gets a new number', crows['2'].X_UBBF_Device, '/sys/devB');

global.mm_modems = [ { generic: { device: '/sys/devB' } } ];
check('a leaving modem does not shift the other', keys(cellular.get({ root: croot })), [ '2' ]);

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
