// Host test of ra_prefixes_hook_read() in ipv6.c of ubbf.so, the parser of
// the state file below /tmp/ubbf that /etc/odhcp6c.user.d/10-ubbf-ra-prefix
// writes.
'use strict';

import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as fs from 'fs';
import { ra_prefixes_hook_read } from 'ubbf';

describe('ra_prefixes_hook_read', () => {
	beforeEach(() => state_clear());

	it('reads the prefixes and lifetimes of the state file', () => {
		fs.writefile('/tmp/ubbf/ra-prefix.wan6', join('\n', [
			'2001:db8:1:0:211:22ff:fe33:4455/64,3600,7200',
			'2001:db8:1::99/64,1800,3600',
			'2001:db8:2::5/,100,200',
			'2001:db8:3::5/x,100,200',
			'2001:db8:4::5/129,100,200',
			'2001:db8:5::5/48,abc,',
			'2001:db8:6::5/64',
			''
		]));

		assert.match([
			{ address: '2001:db8:1::', mask: 64, preferred: 3600, valid: 7200 },
			{ address: '2001:db8:2::', mask: 64, preferred: 100, valid: 200 },
			{ address: '2001:db8:3::', mask: 64, preferred: 100, valid: 200 },
			{ address: '2001:db8:5::', mask: 48, preferred: 0, valid: 0 }
		], ra_prefixes_hook_read('wan6'));
	});

	it('gives no rows without a file', () => {
		assert.match([], ra_prefixes_hook_read('lan6'));
	});

	it('gives no rows without an interface', () => {
		assert.match([], ra_prefixes_hook_read(null));
	});
});
