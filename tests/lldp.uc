// Host test of the lldp module parser against lldpcli samples. Run from the
// repository root with the native module built for the host; the search
// path has to be absolute and the fake lldpcli has to come first in PATH:
//   PATH="$PWD/tests/lldp:$PATH" ucode -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/lldp.uc
'use strict';

import * as ubbf from 'ubbf';
import { access, readfile, writefile, unlink } from 'fs';
import { datetime_format, text_clamp } from 'ubbf.utils.helpers';
import { ethernet_interface_path } from 'ubbf.utils.path';

const SAMPLE_PATH = '/tmp/ubbf-lldp-test-sample.json';

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
		helpers: { datetime_format, text_clamp },
		path: { ethernet_interface_path },
		hosts: { host_path_by_mac: (root, mac) => mac ? `HOST(${mac})` : '' }
	},
	schema: (k) => k,
	model: {}
};

include('../modules/lldp/handler.uc', { ubbf_module: api });

const root = {
	Device: {
		Ethernet: {
			Interface: {
				'1': { Name: 'lan1' },
				'2': { Name: 'lan2' }
			}
		}
	}
};

function devices_from(output) {
	writefile(SAMPLE_PATH, output);
	return api.model['Device.LLDP.Discovery.Device.{i}'].get({ instance: null, root });
}

function devices(sample) {
	return devices_from(readfile(sourcepath(0, true) + '/lldp/' + sample));
}

let d = devices('nosysname.json');
assert_eq('nosysname: one device', length(d), 1);
assert_eq('nosysname: ChassisID', d['1']?.ChassisID, 'aa:bb:cc:dd:ee:01');
assert_eq('nosysname: no ModelName', d['1']?.DeviceInformation?.ModelName, '');
assert_eq('nosysname: single capability', d['1']?.DeviceInformation?.DeviceCategory, 'Station');
assert_eq('nosysname: no OUI for a locally administered MAC', d['1']?.DeviceInformation?.ManufacturerOUI, '');
assert_eq('nosysname: ifalias port subtype', d['1']?.Port?.['1']?.PortIDSubtype, '1');
assert_eq('nosysname: Interface path', d['1']?.Interface, 'Device.Ethernet.Interface.1');
assert_eq('nosysname: LastUpdate is a dateTime', !!match(d['1']?.Port?.['1']?.LastUpdate, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T/), true);

d = devices('nosysname-nodescr.json');
assert_eq('nodescr: one device', length(d), 1);
assert_eq('nodescr: ChassisID', d['1']?.ChassisID, 'aa:bb:cc:dd:ee:01');
assert_eq('nodescr: enabled capability only', d['1']?.DeviceInformation?.DeviceCategory, 'Station');

d = devices('single-cap.json');
assert_eq('single-cap: ModelName is the System Name', d['1']?.DeviceInformation?.ModelName, 'phone-17');
assert_eq('single-cap: category', d['1']?.DeviceInformation?.DeviceCategory, 'Tel');
assert_eq('single-cap: MAC port subtype', d['1']?.Port?.['1']?.PortIDSubtype, '3');
assert_eq('single-cap: MACAddressList', d['1']?.Port?.['1']?.MACAddressList, 'aa:bb:cc:dd:ee:03');
assert_eq('single-cap: no row for lan3', d['1']?.Interface, '');
assert_eq('single-cap: Host from the MAC Port ID', d['1']?.Host, 'HOST(AA:BB:CC:DD:EE:03)');

d = devices('two-ports.json');
assert_eq('two-ports: one device', length(d), 1);
assert_eq('two-ports: two ports', d['1']?.PortNumberOfEntries, '2');
assert_eq('two-ports: Interface of the first element', d['1']?.Interface, 'Device.Ethernet.Interface.1');
assert_eq('two-ports: ifname port subtype', d['1']?.Port?.['1']?.PortIDSubtype, '5');
assert_eq('two-ports: Host from the chassis MAC', d['1']?.Host, 'HOST(AA:BB:CC:DD:EE:02)');

d = devices('control-chars.json');
assert_eq('control-chars: PortID without control bytes', d['1']?.Port?.['1']?.PortID, 'p[2Jx');
assert_eq('control-chars: PortDescription without control bytes', d['1']?.Port?.['1']?.PortDescription, 'eth0');
assert_eq('control-chars: ModelName cut at 31', length(d['1']?.DeviceInformation?.ModelName), 31);
assert_eq('control-chars: OUI of a universal MAC', d['1']?.DeviceInformation?.ManufacturerOUI, '001122');
assert_eq('control-chars: local port subtype', d['1']?.Port?.['1']?.PortIDSubtype, '7');

d = devices_from('');
assert_eq('no lldpd output: no rows', d, {});

let lldp_get = api.model['Device.LLDP'].get;
let r = lldp_get({ root: { Device: { LLDP: { Enable: 'true' } } } });
assert_eq('legacy Enable: X_UBBF_Enable', r.X_UBBF_Enable, 'true');
assert_eq('legacy Enable: status follows the lldpd socket', r.X_UBBF_Status,
	access('/var/run/lldpd.socket') ? 'Enabled' : 'Error');
r = lldp_get({ root: { Device: { LLDP: { Enable: 'true', X_UBBF_Enable: 'false' } } } });
assert_eq('X_UBBF_Enable wins over Enable', r.X_UBBF_Enable, 'false');
assert_eq('disabled status', r.X_UBBF_Status, 'Disabled');
assert_eq('no legacy key in the reply', exists(r, 'Enable'), false);
r = lldp_get({ root: {} });
assert_eq('nothing stored: disabled', [ r.X_UBBF_Enable, r.X_UBBF_Status ], [ 'false', 'Disabled' ]);
unlink(SAMPLE_PATH);

printf('\n--- lldp handler test results ---\n  passed: %d\n  failed: %d\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
