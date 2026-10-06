// Host test of the WiFi Personal key parameters
// (Device.WiFi.AccessPoint.{i}.Security.PreSharedKey, KeyPassphrase):
// PSK derivation and the Security get and set handlers. Run from the
// repository root with
// the native module built for the host; tests/hosts/ holds stand-ins for
// the iwinfo and udebug modules:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/wifi-key.uc
'use strict';

import { wpa_psk } from 'ubbf.utils.wifi';
import { model } from 'ubbf.tr181.WiFi';

global.USP_ERR_INVALID_VALUE = 7012;

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

// 802.11-2024 J.4.2 test vectors
check('PSK for password/IEEE', wpa_psk('password', 'IEEE'),
	'f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e');
check('PSK for ThisIsAPassword/ThisIsASSID', wpa_psk('ThisIsAPassword', 'ThisIsASSID'),
	'0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af');

const security = model['Device.WiFi.AccessPoint.{i}.Security'];
const root = { Device: { WiFi: { SSID: { '1': { SSID: 'IEEE' } } } } };
const parent = { SSIDReference: 'Device.WiFi.SSID.1' };
const psk = 'f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e';

check('PreSharedKey generated from KeyPassphrase',
	security.get({ config: { KeyPassphrase: 'password' }, parent, root }).PreSharedKey, psk);
check('PreSharedKey as stored without a passphrase',
	security.get({ config: { PreSharedKey: psk }, parent, root }).PreSharedKey, psk);

let config = { KeyPassphrase: 'password' };
check('PreSharedKey of 64 digits accepted', security.set({ param: 'PreSharedKey', value: psk, config }), 0);
check('PreSharedKey drops KeyPassphrase', config, {});

config = { PreSharedKey: psk };
check('KeyPassphrase accepted', security.set({ param: 'KeyPassphrase', value: 'password', config }), 0);
check('KeyPassphrase drops PreSharedKey', config, {});

check('PreSharedKey of 16 bytes refused', security.set({ param: 'PreSharedKey', value: substr(psk, 0, 32), config: {} }), -7012);
check('empty PreSharedKey accepted', security.set({ param: 'PreSharedKey', value: '', config: {} }), 0);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
