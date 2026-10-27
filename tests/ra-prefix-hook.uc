// Host test of ra_prefixes_hook_read() in ipv6.c of ubbf.so, the parser of
// the state file that /etc/odhcp6c.user.d/10-ubbf-ra-prefix writes. The
// test writes /tmp/ubbf, so it runs on a private tmpfs:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && ucode \
//     -L "<host build>/*.so" tests/ra-prefix-hook.uc'
'use strict';

import * as fs from 'fs';
import { ra_prefixes_hook_read } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

fs.mkdir('/tmp/ubbf');
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

check('rows', ra_prefixes_hook_read('wan6'), [
	{ address: '2001:db8:1::', mask: 64, preferred: 3600, valid: 7200 },
	{ address: '2001:db8:2::', mask: 64, preferred: 100, valid: 200 },
	{ address: '2001:db8:3::', mask: 64, preferred: 100, valid: 200 },
	{ address: '2001:db8:5::', mask: 48, preferred: 0, valid: 0 }
]);
check('no file', ra_prefixes_hook_read('lan6'), []);
check('no interface', ra_prefixes_hook_read(null), []);

printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
