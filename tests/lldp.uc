// Host test of the lldp module parser against lldpcli samples. The lldpcli
// stand-in of tests/bin prints the sample that the test writes.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import { access, readfile, writefile } from 'fs';

const SAMPLE_PATH = '/tmp/ubbf-lldp-test-sample.json';

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args) }, ubbf),
	utils: {
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

describe('LLDP Discovery.Device from lldpcli', () => {
	it('reads a neighbour without a System Name', () => {
		let d = devices('nosysname.json');
		assert.match(1, length(d));
		assert.match('aa:bb:cc:dd:ee:01', d['1']?.ChassisID);
		assert.match('', d['1']?.DeviceInformation?.ModelName);
		assert.match('Station', d['1']?.DeviceInformation?.DeviceCategory);
		assert.match('', d['1']?.DeviceInformation?.ManufacturerOUI, 'no OUI for a locally administered MAC');
		assert.match('1', d['1']?.Port?.['1']?.PortIDSubtype);
		assert.match('Device.Ethernet.Interface.1', d['1']?.Interface);
		assert.match(true, !!match(d['1']?.Port?.['1']?.LastUpdate, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T/));
	});

	it('reads a neighbour without a System Name and description', () => {
		let d = devices('nosysname-nodescr.json');
		assert.match(1, length(d));
		assert.match('aa:bb:cc:dd:ee:01', d['1']?.ChassisID);
		assert.match('Station', d['1']?.DeviceInformation?.DeviceCategory, 'enabled capability only');
	});

	it('reads a neighbour with a single capability', () => {
		let d = devices('single-cap.json');
		assert.match('phone-17', d['1']?.DeviceInformation?.ModelName);
		assert.match('Tel', d['1']?.DeviceInformation?.DeviceCategory);
		assert.match('3', d['1']?.Port?.['1']?.PortIDSubtype);
		assert.match('aa:bb:cc:dd:ee:03', d['1']?.Port?.['1']?.MACAddressList);
		assert.match('', d['1']?.Interface, 'no row for lan3');
		assert.match('HOST(AA:BB:CC:DD:EE:03)', d['1']?.Host);
	});

	it('reads a neighbour on two ports as one device', () => {
		let d = devices('two-ports.json');
		assert.match(1, length(d));
		assert.match('2', d['1']?.PortNumberOfEntries);
		assert.match('Device.Ethernet.Interface.1', d['1']?.Interface);
		assert.match('5', d['1']?.Port?.['1']?.PortIDSubtype);
		assert.match('HOST(AA:BB:CC:DD:EE:02)', d['1']?.Host);
	});

	it('removes control characters and cuts the ModelName', () => {
		let d = devices('control-chars.json');
		assert.match('p[2Jx', d['1']?.Port?.['1']?.PortID);
		assert.match('eth0', d['1']?.Port?.['1']?.PortDescription);
		assert.match(31, length(d['1']?.DeviceInformation?.ModelName));
		assert.match('001122', d['1']?.DeviceInformation?.ManufacturerOUI);
		assert.match('7', d['1']?.Port?.['1']?.PortIDSubtype);
	});

	it('has no rows without lldpd output', () => {
		assert.match({}, devices_from(''));
	});
});

describe('LLDP enable', () => {
	const lldp_get = api.model['Device.LLDP'].get;

	it('takes the legacy Enable as X_UBBF_Enable', () => {
		let r = lldp_get({ root: { Device: { LLDP: { Enable: 'true' } } } });
		assert.match('true', r.X_UBBF_Enable);
		assert.match(access('/var/run/lldpd.socket') ? 'Enabled' : 'Error', r.X_UBBF_Status,
			'status follows the lldpd socket');
	});

	it('prefers X_UBBF_Enable over Enable', () => {
		let r = lldp_get({ root: { Device: { LLDP: { Enable: 'true', X_UBBF_Enable: 'false' } } } });
		assert.match('false', r.X_UBBF_Enable);
		assert.match('Disabled', r.X_UBBF_Status);
		assert.match(false, exists(r, 'Enable'), 'no legacy key in the reply');
	});

	it('is disabled when nothing is stored', () => {
		let r = lldp_get({ root: {} });
		assert.match([ 'false', 'Disabled' ], [ r.X_UBBF_Enable, r.X_UBBF_Status ]);
	});
});
