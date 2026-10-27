// Host test of nptv6.c of ubbf.so (Device.NAT.NPTv6.InterfaceSetting.{i}).
// Run from the repository root with the native module built for the host:
//   ucode -L "<host build>/*.so" tests/nptv6.uc
'use strict';

import { prefix6_parse, prefix6_contains, nptv6_setting_check } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

check('parse /64', prefix6_parse('fd00:21::/64')?.len, 64);
check('parse no length', prefix6_parse('fd00:21::'), null);
check('parse IPv4', prefix6_parse('10.0.0.0/8'), null);
check('parse length 129', prefix6_parse('fd00::/129'), null);
check('parse empty', prefix6_parse(''), null);

let p60 = prefix6_parse('2001:db8:200::/60');
check('/61 inside /60', prefix6_contains(p60, prefix6_parse('2001:db8:200:8::/61')), true);
check('/64 inside /60', prefix6_contains(p60, prefix6_parse('2001:db8:200:f::/64')), true);
check('/64 outside /60', prefix6_contains(p60, prefix6_parse('2001:db8:200:10::/64')), false);
check('/56 not inside /60', prefix6_contains(p60, prefix6_parse('2001:db8:200::/56')), false);
check('same prefix', prefix6_contains(p60, p60), true);
check('/0 holds all', prefix6_contains(prefix6_parse('::/0'), p60), true);

const root = { Device: { IP: { Interface: { '1': { Name: 'wan' } } } } };

function row(over) {
	return { Enable: 'true', Interface: 'Device.IP.Interface.1', InternalPrefix: 'fd00:21::/61',
		ExternalPrefix: '2001:db8:200:8::/61', ...over };
}

check('disabled', nptv6_setting_check(root, row({ Enable: 'false' })).status, 'Disabled');
check('enabled', nptv6_setting_check(root, row({})), {
	status: 'Enabled', network: 'wan', internal: 'fd00:21::/61', external: '2001:db8:200:8::/61' });
check('bad interface', nptv6_setting_check(root, row({ Interface: 'Device.IP.Interface.9' })).status, 'Error_Misconfigured');
check('empty internal', nptv6_setting_check(root, row({ InternalPrefix: '' })).status, 'Error_Misconfigured');
check('bad external', nptv6_setting_check(root, row({ ExternalPrefix: '2001:db8::' })).status, 'Error_Misconfigured');
check('lengths differ', nptv6_setting_check(root, row({ ExternalPrefix: '2001:db8:200::/60' })).status, 'Error_Misconfigured');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
