// Host test of the usb module on a fake /sys/bus/usb/devices: the Host,
// Device, Configuration and Port rows that the handler builds from the
// sysfs attributes.
'use strict';

import { describe, it, assert, setup } from 'utest';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { state_clear } from 'test_env';

// tests/lib/usb.uc stands in for the native module in the other tests;
// this test reads the fake sysfs through the native one.
unshift(REQUIRE_SEARCH_PATH, getenv('UBBF_BUILD_DIR') + '/*.so');

let schemas = {};
include('../../modules/usb/schema.uc', { schemas });

const api = {
	ubbf: proto({ cache_call: (fn, ...args) => fn(...args), cache_invalidate: () => null }, ubbf),
	utils: {},
	schema: (k) => schemas[k],
	model: {},
	operations: {}
};
include('../../modules/usb/handler.uc', { ubbf_module: api });

const SYS = '/sys/bus/usb/devices';
const DRIVER = '/sys/bus/usb/drivers/usb';

function mkdir_p(path) {
	let cur = '';
	for (let part in split(ltrim(path, '/'), '/')) {
		cur += '/' + part;
		fs.mkdir(cur);
	}
}

function node_make(name, attrs) {
	mkdir_p(`${SYS}/${name}/power`);
	for (let k, v in attrs)
		fs.writefile(`${SYS}/${name}/${k}`, v + '\n');
}

function port_make(iface, port, peer, device) {
	let dir = `${SYS}/${iface}/${port}`;
	mkdir_p(dir);
	if (peer)
		fs.symlink(peer, `${dir}/peer`);
	if (device)
		fs.symlink(device, `${dir}/device`);
}

function sysfs_build() {
	node_make('usb1', { bDeviceClass: '09', bmAttributes: 'e0', bConfigurationValue: '1', devnum: '1',
		product: 'xHCI Host Controller', version: ' 2.00', speed: '480', 'power/control': 'auto',
		'power/runtime_status': 'active' });
	node_make('1-1', { bDeviceClass: '09', bDeviceProtocol: '02', bmAttributes: 'e0', bConfigurationValue: '1',
		devnum: '2', idVendor: '2109', idProduct: '2822', speed: '480', 'power/runtime_status': 'active' });
	node_make('1-1.2', { bDeviceClass: '00', bmAttributes: 'c0', bConfigurationValue: '1', devnum: '3',
		idVendor: '0781', idProduct: '5581', speed: '480', 'power/runtime_status': 'active' });
	node_make('1-1.2:1.0', { bInterfaceNumber: '00', bInterfaceClass: '08', bInterfaceSubClass: '06',
		bInterfaceProtocol: '50' });
	node_make('1-1.4:1.1', {});
	node_make('1-1.4:1.0', {});
	mkdir_p(`${SYS}/1-1.4:1.0/net/usb1x`);
	mkdir_p(`${SYS}/1-1.4:1.0/net/eth9`);
	mkdir_p(`${SYS}/1-1.4:1.1/net/eth3`);
	node_make('1-1.3', { bDeviceClass: 'ff', bmAttributes: '80', bConfigurationValue: '', devnum: '4',
		idVendor: '1234', idProduct: '5678', speed: '12', 'power/runtime_status': 'suspended' });
	node_make('1-1.4', { bDeviceClass: '00', bmAttributes: '80', bConfigurationValue: '1', devnum: '5',
		idVendor: '1234', idProduct: '0001', version: ' 1.10' });
	node_make('usb2', { bDeviceClass: '09', bmAttributes: 'e0', bConfigurationValue: '1', devnum: '1',
		product: 'Generic Host Controller', version: ' 3.10', speed: '5000' });
	fs.writefile(`${SYS}/1-1/version`, ' 2.00\n');

	port_make('1-0:1.0', 'usb1-port1', '../../2-0:1.0/usb2-port1', '../../1-1');
	port_make('2-0:1.0', 'usb2-port1', '../../1-0:1.0/usb1-port1', null);
	port_make('1-1:1.0', '1-1-port1', null, null);
	port_make('1-1:1.0', '1-1-port2', null, '../../1-1.2');
	port_make('1-1:1.0', '1-1-port3', null, '../../1-1.3');
	port_make('1-1:1.0', '1-1-port4', null, '../../1-1.4');

	mkdir_p(DRIVER);
}

function host_rows() {
	return api.model['Device.USB.USBHosts'].get({ config: {} }).Host;
}

function device_by_number(devnum) {
	for (let n, host in host_rows())
		for (let d, dev in host.Device)
			if (dev.DeviceNumber == devnum)
				return dev;
	return null;
}

function port_by_name(name) {
	for (let n, port in api.model['Device.USB.Port'].get({}))
		if (port.Name == name)
			return port;
	return null;
}

function host_by_name(name) {
	for (let n, host in host_rows())
		if (host.Name == name)
			return [ +n, host ];
	return null;
}

function reset(n) {
	return api.operations['Device.USB.USBHosts.Host.{i}.Reset()'].handler({}, '', [ n ], {});
}

setup(() => {
	state_clear();
	ubbf.instance_map_own(true);
	sysfs_build();
});

describe('USB handler', () => {
	it('reads the class values as hexBinary', () => {
		assert.match('09', device_by_number('2').DeviceClass, 'hub');
		assert.match('02', device_by_number('2').DeviceProtocol, 'hub protocol');
		assert.match('ff', device_by_number('4').DeviceClass, 'vendor class');

		let iface = device_by_number('3').Configuration['1'].Interface['1'];
		assert.match([ '08', '06', '50' ], [ iface.InterfaceClass, iface.InterfaceSubClass, iface.InterfaceProtocol ]);
	});

	it('reads IsSelfPowered from bmAttributes', () => {
		assert.match('true', device_by_number('2').IsSelfPowered, 'hub e0');
		assert.match('true', device_by_number('3').IsSelfPowered, 'storage c0');
		assert.match('false', device_by_number('4').IsSelfPowered, 'bus powered 80');
	});

	it('gives an unconfigured device no Configuration row', () => {
		let dev = device_by_number('4');
		assert.match('0', dev.ConfigurationNumberOfEntries);
		assert.match({}, dev.Configuration);
		assert.match('1', device_by_number('3').ConfigurationNumberOfEntries);
	});

	it('returns only the declared keys', () => {
		let host = host_rows()['1'];
		assert.match(null, host['.name'], 'host');
		assert.match(null, device_by_number('3')['.name'], 'device');
		for (let n, port in api.model['Device.USB.Port'].get({}))
			assert.match(null, port['.name'], `port ${n}`);
	});

	it('gives values inside the enums when sysfs lacks them', () => {
		assert.match('Unknown', host_by_name('usb2')[1].Type, 'host product without a known name');
		assert.match('xHCI', host_by_name('usb1')[1].Type, 'xHCI host');
		assert.match('Unknown', device_by_number('5').Rate, 'device without a speed');
		assert.match('Full', device_by_number('4').Rate, 'device at 12 Mbit/s');
		assert.match('Full', port_by_name('1-1-port4').Rate, 'device without a speed, USB 1.1');
		assert.match('High', port_by_name('1-1-port1').Rate, 'empty port of a USB 2 hub');
	});

	it('has one Port row per hub port, with the USB 2 and USB 3 halves merged', () => {
		let ports = api.model['Device.USB.Port'].get({});
		assert.match([ '1-1-port1', '1-1-port2', '1-1-port3', '1-1-port4', 'usb1-port1' ],
			sort(map(values(ports), (p) => p.Name)), 'no rows for devices, no usb2-port1');
		assert.match('5', api.model['Device.USB'].get({}).PortNumberOfEntries);

		let root = port_by_name('usb1-port1');
		assert.match([ 'Host', 'Standard-A', 'High' ], [ root.Type, root.Receptacle, root.Rate ], 'root port');
		assert.match('3.10', trim(root.Standard), 'highest version of the two halves');
		assert.match([ 'Hub', '' ], [ port_by_name('1-1-port2').Type, port_by_name('1-1-port2').Receptacle ], 'hub port');
	});

	it('points USBPort to the port a device is plugged into', () => {
		let number = (name) => {
			for (let n, port in api.model['Device.USB.Port'].get({}))
				if (port.Name == name)
					return `Device.USB.Port.${n}`;
		};
		assert.match(number('usb1-port1'), device_by_number('2').USBPort, 'hub on the root port');
		assert.match(number('1-1-port2'), device_by_number('3').USBPort, 'device on the hub');
	});

	it('reads IsSuspended true only for a suspended device', () => {
		assert.match('true', device_by_number('4').IsSuspended, 'suspended');
		assert.match('false', device_by_number('3').IsSuspended, 'active');
		assert.match('false', device_by_number('5').IsSuspended, 'no runtime PM state');
	});

	it('resets a host through unbind and bind', () => {
		let n = host_by_name('usb1')[0];
		assert.match({}, reset(n), 'reset');
		assert.match('usb1', fs.readfile(`${DRIVER}/bind`), 'bound again');
		assert.match(-USP_ERR_OBJECT_DOES_NOT_EXIST, reset(99), 'no such host');

		fs.unlink(`${DRIVER}/bind`);
		fs.mkdir(`${DRIVER}/bind`);
		assert.match(-USP_ERR_COMMAND_FAILURE, reset(n), 'bind fails twice');
	});

	it('reads only USB names below the USB devices directory', () => {
		let usb = require('usb');
		assert.match(null, usb.device_info('../../../etc'), 'path out of the tree');
		assert.match(null, usb.device_info('1-1:1.0'), 'interface name');
		assert.match(null, usb.device_info('9-9'), 'device that is gone');
		assert.match(null, usb.interface_info('1-1.2'), 'device name');
		assert.match(null, usb.interface_info('9-9:1.0'), 'interface that is gone');
		assert.match('09', sprintf('%02x', usb.device_info('1-1').bDeviceClass), 'device that is present');
	});

	it('sorts the USB netdevs by interface, then by name', () => {
		assert.match([ 'eth9', 'usb1x', 'eth3' ], map(require('usb').net_interfaces(), (i) => i.ifname));
		assert.match([ 'eth9', 'usb1x', 'eth3' ],
			map(values(api.model['Device.USB.Interface'].get({})), (row) => row.Name), 'Interface rows');
	});

	it('builds the same Port row for the table and for one instance', () => {
		for (let n, port in api.model['Device.USB.Port'].get({}))
			assert.match(port, api.model['Device.USB.Port.{i}'].get({ instance: n }), `port ${n}`);
	});

	it('has a read-only Host Enable and PowerManagementEnable', () => {
		assert.match(0, schemas.Host.schema.Enable & dm_type.WRITABLE, 'Enable');
		assert.match(0, schemas.Host.schema.PowerManagementEnable & dm_type.WRITABLE, 'PowerManagementEnable');
	});
});
