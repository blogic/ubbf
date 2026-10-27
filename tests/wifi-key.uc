// Host test of the WiFi Personal key parameters
// (Device.WiFi.AccessPoint.{i}.Security.PreSharedKey, KeyPassphrase):
// PSK derivation and the Security get and set handlers.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { netifd_patch } from 'netifd_mock';
import { wpa_psk } from 'ubbf';
import { model } from 'ubbf.tr181.WiFi';

global.USP_ERR_INVALID_VALUE = 7012;

const security = model['Device.WiFi.AccessPoint.{i}.Security'];
const root = { Device: { WiFi: { SSID: { '1': { SSID: 'IEEE' } } } } };
const parent = { SSIDReference: 'Device.WiFi.SSID.1' };
const psk = 'f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e';

describe('wpa_psk', () => {
	// 802.11-2024 J.4.2 test vectors
	it('derives the PSK of the test vectors', () => {
		assert.match('f42c6fc52df0ebef9ebb4b90b38a5f902e83fe1b135a70e23aed762e9710a12e', wpa_psk('password', 'IEEE'));
		assert.match('0dc0d6eb90555ed6419756b9a15ec3e3209b63df707dd508d14581f8982721af', wpa_psk('ThisIsAPassword', 'ThisIsASSID'));
	});
});

describe('AccessPoint Security keys', () => {
	beforeEach(() => netifd_patch({}));

	it('reads PreSharedKey from KeyPassphrase, else as stored', () => {
		assert.match(psk, security.get({ config: { KeyPassphrase: 'password' }, parent, root }).PreSharedKey,
			'generated from KeyPassphrase');
		assert.match(psk, security.get({ config: { PreSharedKey: psk }, parent, root }).PreSharedKey,
			'as stored without a passphrase');
	});

	it('accepts a PreSharedKey of 64 digits and drops KeyPassphrase', () => {
		let config = { KeyPassphrase: 'password' };
		assert.match(0, security.set({ param: 'PreSharedKey', value: psk, config }));
		assert.match({}, config);
	});

	it('accepts a KeyPassphrase and drops PreSharedKey', () => {
		let config = { PreSharedKey: psk };
		assert.match(0, security.set({ param: 'KeyPassphrase', value: 'password', config }));
		assert.match({}, config);
	});

	it('refuses a PreSharedKey of 16 bytes and accepts an empty one', () => {
		assert.match(-7012, security.set({ param: 'PreSharedKey', value: substr(psk, 0, 32), config: {} }));
		assert.match(0, security.set({ param: 'PreSharedKey', value: '', config: {} }));
	});
});
