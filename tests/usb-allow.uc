// Host test of modules/usb/files/usr/share/ucode/ubbf/usb_allow.uc
// (Device.USB.USBHosts.AllowAllDevices, AllowedDevice.{i}): the parse of
// the USB descriptors, the match of AllowedDevice rules, the policy from UCI
// and its application to a fake /sys/bus/usb/devices below /tmp.
'use strict';

import { describe, it, assert } from 'utest';
import * as fs from 'fs';
import { descriptors_interfaces, field_match, rule_match, device_allowed, policy_apply, policy_load }
	from '../modules/usb/files/usr/share/ucode/ubbf/usb_allow.uc';

// device descriptor (18 bytes), configuration (9), two interfaces (9 each)
function descriptors(ifaces) {
	let raw = chr(18, 1) + chr(0, 2, 0, 0, 0, 64, 0x34, 0x12, 0x78, 0x56, 0, 1, 1, 2, 3, 1);
	raw += chr(9, 2, 9 + 9 * length(ifaces), 0, length(ifaces), 1, 0, 0x80, 50);
	for (let i = 0; i < length(ifaces); i++)
		raw += chr(9, 4, i, 0, 2, ifaces[i][0], ifaces[i][1], ifaces[i][2], 0);
	return raw;
}

const modem = { vendor: '1234', product: '5678', class: '00', subclass: '00', protocol: '00',
	interfaces: [ 'ff:02:01', 'ff:02:02' ] };

const hub = { vendor: '2109', product: '2822', class: '09', subclass: '00', protocol: '02',
	interfaces: [ '09:00:01', '09:00:02' ] };

const root = '/tmp/usb-allow-test';

function device_make(name, vendor, ifaces) {
	let dir = `${root}/${name}`;
	fs.mkdir(dir);
	fs.writefile(`${dir}/idVendor`, vendor + '\n');
	fs.writefile(`${dir}/idProduct`, '5678\n');
	fs.writefile(`${dir}/bDeviceClass`, '00\n');
	fs.writefile(`${dir}/bDeviceSubClass`, '00\n');
	fs.writefile(`${dir}/bDeviceProtocol`, '00\n');
	fs.writefile(`${dir}/descriptors`, descriptors(ifaces));
	fs.writefile(`${dir}/authorized`, '1\n');
}

describe('USB allow list', () => {
	it('reads the interface classes from the descriptors', () => {
		assert.match([ 'ff:02:01', '08:06:50' ], descriptors_interfaces(descriptors([ [ 0xff, 2, 1 ], [ 8, 6, 0x50 ] ])),
			'interfaces from descriptors');
		assert.match([], descriptors_interfaces(null), 'no descriptors');
		assert.match([], descriptors_interfaces(chr(0, 4, 1)), 'zero length stops');
	});

	it('matches a hex field against a pattern', () => {
		assert.match(true, field_match('', '1234'), 'empty pattern');
		assert.match(true, field_match('1234', '1234'), 'exact hex');
		assert.match(true, field_match('12', '0012'), 'short hex is the same number');
		assert.match(true, field_match('1D6B', '1d6b'), 'upper case');
		assert.match(false, field_match('1235', '1234'), 'other value');
		assert.match(true, field_match('1*', '1234'), 'wildcard prefix');
		assert.match(true, field_match('*3', '03'), 'wildcard suffix');
		assert.match(false, field_match('2*', '1234'), 'wildcard miss');
		assert.match(false, field_match('zz', '1234'), 'not hex');
	});

	it('matches a device against a rule', () => {
		assert.match(true, rule_match({ vendor: '1234', product: '5678', interfaces: [] }, modem), 'vendor and product');
		assert.match(false, rule_match({ vendor: '1234', product: '5679', interfaces: [] }, modem), 'product differs');
		assert.match(true, rule_match({ interfaces: [ 'FF:02:*' ] }, modem), 'all interfaces match a pattern');
		assert.match(false, rule_match({ interfaces: [ 'FF:02:01' ] }, modem), 'one interface left out');
		assert.match(true, rule_match({ interfaces: [ 'FF:02:01', 'ff:02:02' ] }, modem), 'both listed');
		assert.match(false, rule_match({ interfaces: [ 'FF:02' ] }, modem), 'bad item');
	});

	it('allows a device by policy', () => {
		assert.match(true, device_allowed({ allow_all: true, rules: [] }, modem), 'allow all');
		assert.match(false, device_allowed({ allow_all: false, rules: [] }, modem), 'no rule');
		assert.match(true, device_allowed({ allow_all: false, rules: [
			{ vendor: 'abcd', interfaces: [] }, { vendor: '1234', interfaces: [] } ] }, modem), 'one rule matches');
		assert.match(true, device_allowed({ allow_all: false, rules: [] }, hub), 'hub without a rule');
	});

	it('loads the policy from UCI', () => {
		const cursor = { foreach: (pkg, type, cb) => {
			cb({ '.type': 'usb', '.name': 'global', allow_all: '0' });
			cb({ '.type': 'allow', '.name': 'cfg1', vendor: '1234', interface: 'ff:02:*' });
		} };
		assert.match({ allow_all: false, rules: [
			{ vendor: '1234', product: '', class: '', subclass: '', protocol: '', interfaces: [ 'ff:02:*' ] } ] },
			policy_load(cursor), 'policy from UCI');
		assert.match({ allow_all: true, rules: [] }, policy_load(null), 'policy without config');
	});

	it('applies the policy to the authorized files of sysfs', () => {
		fs.mkdir(root);
		fs.mkdir(`${root}/usb1`);
		fs.writefile(`${root}/usb1/authorized_default`, '1\n');
		device_make('1-1', '1234', [ [ 0xff, 2, 1 ] ]);
		device_make('1-2', 'abcd', [ [ 8, 6, 0x50 ] ]);
		fs.mkdir(`${root}/1-1:1.0`);

		let rd = (p) => trim(fs.readfile(`${root}/${p}`));

		policy_apply({ allow_all: false, rules: [ { vendor: '1234', interfaces: [] } ] }, root);
		assert.match('0', rd('usb1/authorized_default'), 'root hub default off');
		assert.match('1', rd('1-1/authorized'), 'listed device allowed');
		assert.match('0', rd('1-2/authorized'), 'other device held back');

		policy_apply({ allow_all: true, rules: [] }, root);
		assert.match('1', rd('usb1/authorized_default'), 'root hub default on');
		assert.match('1', rd('1-2/authorized'), 'device allowed again');
	});
});
