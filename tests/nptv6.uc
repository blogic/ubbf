// Host test of nptv6.c of ubbf.so (Device.NAT.NPTv6.InterfaceSetting.{i}).
'use strict';

import { describe, it, assert } from 'utest';
import { prefix6_parse, prefix6_contains, nptv6_setting_check } from 'ubbf';

const root = { Device: { IP: { Interface: { '1': { Name: 'wan' } } } } };

function row(over) {
	return { Enable: 'true', Interface: 'Device.IP.Interface.1', InternalPrefix: 'fd00:21::/61',
		ExternalPrefix: '2001:db8:200:8::/61', ...over };
}

describe('nptv6 prefixes', () => {
	it('parses address/length', () => {
		assert.match(64, prefix6_parse('fd00:21::/64')?.len);
		assert.match(null, prefix6_parse('fd00:21::'));
		assert.match(null, prefix6_parse('10.0.0.0/8'));
		assert.match(null, prefix6_parse('fd00::/129'));
		assert.match(null, prefix6_parse(''));
	});

	it('tells whether one prefix lies inside another', () => {
		let p60 = prefix6_parse('2001:db8:200::/60');

		assert.match(true, prefix6_contains(p60, prefix6_parse('2001:db8:200:8::/61')));
		assert.match(true, prefix6_contains(p60, prefix6_parse('2001:db8:200:f::/64')));
		assert.match(false, prefix6_contains(p60, prefix6_parse('2001:db8:200:10::/64')));
		assert.match(false, prefix6_contains(p60, prefix6_parse('2001:db8:200::/56')));
		assert.match(true, prefix6_contains(p60, p60));
		assert.match(true, prefix6_contains(prefix6_parse('::/0'), p60));
	});
});

describe('nptv6 InterfaceSetting state', () => {
	it('is Disabled for a disabled row', () => {
		assert.match('Disabled', nptv6_setting_check(root, row({ Enable: 'false' })).status);
	});

	it('is Enabled with the network and both prefixes', () => {
		assert.match({ status: 'Enabled', network: 'wan', internal: 'fd00:21::/61', external: '2001:db8:200:8::/61' },
			nptv6_setting_check(root, row({})));
	});

	it('is Error_Misconfigured for a bad interface or prefix', () => {
		assert.match('Error_Misconfigured', nptv6_setting_check(root, row({ Interface: 'Device.IP.Interface.9' })).status);
		assert.match('Error_Misconfigured', nptv6_setting_check(root, row({ InternalPrefix: '' })).status);
		assert.match('Error_Misconfigured', nptv6_setting_check(root, row({ ExternalPrefix: '2001:db8::' })).status);
		assert.match('Error_Misconfigured', nptv6_setting_check(root, row({ ExternalPrefix: '2001:db8:200::/60' })).status);
	});
});
