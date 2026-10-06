// Host test of modules/usb/files/usr/share/ucode/ubbf/usb_allow.uc
// (Device.USB.USBHosts.AllowAllDevices, AllowedDevice.{i}). Builds a fake
// /sys/bus/usb/devices under /tmp, so run it with a private /tmp:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && ucode \
//     -L "$PWD/modules/usb/files/usr/share/ucode/*.uc" tests/usb-allow.uc'
'use strict';

import * as fs from 'fs';
import { descriptors_interfaces, field_match, rule_match, device_allowed, policy_apply, policy_load } from 'ubbf.usb_allow';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

// device descriptor (18 bytes), configuration (9), two interfaces (9 each)
function descriptors(ifaces) {
	let raw = chr(18, 1) + chr(0, 2, 0, 0, 0, 64, 0x34, 0x12, 0x78, 0x56, 0, 1, 1, 2, 3, 1);
	raw += chr(9, 2, 9 + 9 * length(ifaces), 0, length(ifaces), 1, 0, 0x80, 50);
	for (let i = 0; i < length(ifaces); i++)
		raw += chr(9, 4, i, 0, 2, ifaces[i][0], ifaces[i][1], ifaces[i][2], 0);
	return raw;
}

check('interfaces from descriptors', descriptors_interfaces(descriptors([ [ 0xff, 2, 1 ], [ 8, 6, 0x50 ] ])),
	[ 'ff:02:01', '08:06:50' ]);
check('no descriptors', descriptors_interfaces(null), []);
check('zero length stops', descriptors_interfaces(chr(0, 4, 1)), []);

check('empty pattern', field_match('', '1234'), true);
check('exact hex', field_match('1234', '1234'), true);
check('short hex is the same number', field_match('12', '0012'), true);
check('upper case', field_match('1D6B', '1d6b'), true);
check('other value', field_match('1235', '1234'), false);
check('wildcard prefix', field_match('1*', '1234'), true);
check('wildcard suffix', field_match('*3', '03'), true);
check('wildcard miss', field_match('2*', '1234'), false);
check('not hex', field_match('zz', '1234'), false);

const modem = { vendor: '1234', product: '5678', class: '00', subclass: '00', protocol: '00',
	interfaces: [ 'ff:02:01', 'ff:02:02' ] };

check('vendor and product', rule_match({ vendor: '1234', product: '5678', interfaces: [] }, modem), true);
check('product differs', rule_match({ vendor: '1234', product: '5679', interfaces: [] }, modem), false);
check('all interfaces match a pattern', rule_match({ interfaces: [ 'FF:02:*' ] }, modem), true);
check('one interface left out', rule_match({ interfaces: [ 'FF:02:01' ] }, modem), false);
check('both listed', rule_match({ interfaces: [ 'FF:02:01', 'ff:02:02' ] }, modem), true);
check('bad item', rule_match({ interfaces: [ 'FF:02' ] }, modem), false);

check('allow all', device_allowed({ allow_all: true, rules: [] }, modem), true);
check('no rule', device_allowed({ allow_all: false, rules: [] }, modem), false);
check('one rule matches', device_allowed({ allow_all: false, rules: [
	{ vendor: 'abcd', interfaces: [] }, { vendor: '1234', interfaces: [] } ] }, modem), true);

const cursor = { foreach: (pkg, type, cb) => {
	cb({ '.type': 'usb', '.name': 'global', allow_all: '0' });
	cb({ '.type': 'allow', '.name': 'cfg1', vendor: '1234', interface: 'ff:02:*' });
} };
check('policy from UCI', policy_load(cursor), { allow_all: false, rules: [
	{ vendor: '1234', product: '', class: '', subclass: '', protocol: '', interfaces: [ 'ff:02:*' ] } ] });
check('policy without config', policy_load(null), { allow_all: true, rules: [] });

const root = '/tmp/usb-allow-test';
fs.mkdir(root);

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

fs.mkdir(`${root}/usb1`);
fs.writefile(`${root}/usb1/authorized_default`, '1\n');
device_make('1-1', '1234', [ [ 0xff, 2, 1 ] ]);
device_make('1-2', 'abcd', [ [ 8, 6, 0x50 ] ]);
fs.mkdir(`${root}/1-1:1.0`);

let rd = (p) => trim(fs.readfile(`${root}/${p}`));

policy_apply({ allow_all: false, rules: [ { vendor: '1234', interfaces: [] } ] }, root);
check('root hub default off', rd('usb1/authorized_default'), '0');
check('listed device allowed', rd('1-1/authorized'), '1');
check('other device held back', rd('1-2/authorized'), '0');

policy_apply({ allow_all: true, rules: [] }, root);
check('root hub default on', rd('usb1/authorized_default'), '1');
check('device allowed again', rd('1-2/authorized'), '1');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
