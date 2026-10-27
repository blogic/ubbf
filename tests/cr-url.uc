// Host test of cr_url_compose() in utils/cr_url.uc: the address family of
// the Connection Request URL follows the ACS URL. tests/cr-url/ holds a
// uci stand-in and a resolveip stand-in, tests/ip/ the ubus stand-in:
//   PATH="$PWD/tests/cr-url/bin:$PATH" RESOLVEIP_LOG=/tmp/resolveip.log \
//     RESOLVEIP_V6=acs6.example.com ucode -L "$PWD/tests/cr-url/*.uc" \
//     -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/cr-url.uc
'use strict';

import * as fs from 'fs';
import { cr_url_compose } from 'ubbf.utils.cr_url';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

// The command line sets RESOLVEIP_LOG and RESOLVEIP_V6=acs6.example.com.
let log = getenv('RESOLVEIP_LOG');

function compose(acs_url) {
	global.uci = { cwmp: { cpe: { port: '7547', path: 'cr' }, acs: { url: acs_url } } };
	fs.unlink(log);
	let url = cr_url_compose();
	return { url, resolved: trim(fs.readfile(log) ?? '') };
}

global.netifd = {
	wan: { 'ipv4-address': [ { address: '192.0.2.10', mask: 24 } ] },
	wan6: { 'ipv6-address': [ { address: '2001:db8::10', mask: 64 } ] }
};

check('v4 literal', compose('http://192.0.2.1/acs'),
	{ url: 'http://192.0.2.10:7547/cr', resolved: '' });
check('v6 literal', compose('http://[2001:db8::1]:7547/acs'),
	{ url: 'http://[2001:db8::10]:7547/cr', resolved: '' });
check('name on v6', compose('https://acs6.example.com/acs'),
	{ url: 'http://[2001:db8::10]:7547/cr', resolved: '-6 -t 2 acs6.example.com' });
check('name on v4', compose('https://acs4.example.com/acs'),
	{ url: 'http://192.0.2.10:7547/cr', resolved: '-6 -t 2 acs4.example.com' });
check('user information', compose('https://user:pw@acs6.example.com/acs'),
	{ url: 'http://[2001:db8::10]:7547/cr', resolved: '-6 -t 2 acs6.example.com' });
check('user information, v6 literal', compose('https://user@[2001:db8::1]/acs'),
	{ url: 'http://[2001:db8::10]:7547/cr', resolved: '' });
check('name with a dash first', compose('https://-x.example.com/acs'),
	{ url: 'http://192.0.2.10:7547/cr', resolved: '' });

global.netifd = { wan6: { 'ipv6-address': [ { address: '2001:db8::10', mask: 64 } ] } };
check('no v4', compose('http://192.0.2.1/acs'),
	{ url: 'http://[2001:db8::10]:7547/cr', resolved: '' });

global.netifd = {};
check('no address', compose('http://192.0.2.1/acs'), { url: '', resolved: '' });

fs.unlink(log);
printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
