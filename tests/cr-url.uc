// Host test of cr_url_compose() in utils/cr_url.uc: the address family of
// the Connection Request URL follows the ACS URL. uci and the netifd
// status come from mocks; the resolveip stand-in of tests/bin logs its
// arguments to RESOLVEIP_LOG and resolves the names in RESOLVEIP_V6
// (acs6.example.com) to an IPv6 address.
'use strict';

import { describe, it, assert, beforeEach, afterEach, mock } from 'utest';
import { netifd_patch } from 'netifd_mock';
import * as fs from 'fs';
import { cr_url_compose } from 'ubbf.utils.cr_url';

let log = getenv('RESOLVEIP_LOG');

function compose(acs_url) {
	mock.global.patch('uci', { data: { cwmp: {
		cpe: { '.type': 'cpe', port: '7547', path: 'cr' },
		acs: { '.type': 'acs', url: acs_url }
	} } });
	fs.unlink(log);
	let url = cr_url_compose();
	return { url, resolved: trim(fs.readfile(log) ?? '') };
}

const WAN = { 'ipv4-address': [ { address: '192.0.2.10', mask: 24 } ] };
const WAN6 = { 'ipv6-address': [ { address: '2001:db8::10', mask: 64 } ] };

describe('cr_url_compose', () => {
	afterEach(() => fs.unlink(log));

	describe('with an IPv4 and an IPv6 WAN address', () => {
		beforeEach(() => netifd_patch({ wan: WAN, wan6: WAN6 }));

		it('uses IPv4 for an IPv4 literal', () => {
			assert.match({ url: 'http://192.0.2.10:7547/cr', resolved: '' }, compose('http://192.0.2.1/acs'));
		});

		it('uses IPv6 for an IPv6 literal', () => {
			assert.match({ url: 'http://[2001:db8::10]:7547/cr', resolved: '' }, compose('http://[2001:db8::1]:7547/acs'));
		});

		it('uses IPv6 for a name that resolves to IPv6', () => {
			assert.match({ url: 'http://[2001:db8::10]:7547/cr', resolved: '-6 -t 2 acs6.example.com' },
				compose('https://acs6.example.com/acs'));
		});

		it('uses IPv4 for a name that resolves to IPv4 only', () => {
			assert.match({ url: 'http://192.0.2.10:7547/cr', resolved: '-6 -t 2 acs4.example.com' },
				compose('https://acs4.example.com/acs'));
		});

		it('resolves the host without the user information', () => {
			assert.match({ url: 'http://[2001:db8::10]:7547/cr', resolved: '-6 -t 2 acs6.example.com' },
				compose('https://user:pw@acs6.example.com/acs'));
		});

		it('finds an IPv6 literal after the user information', () => {
			assert.match({ url: 'http://[2001:db8::10]:7547/cr', resolved: '' }, compose('https://user@[2001:db8::1]/acs'));
		});

		it('does not resolve a name with a dash first', () => {
			assert.match({ url: 'http://192.0.2.10:7547/cr', resolved: '' }, compose('https://-x.example.com/acs'));
		});
	});

	it('uses IPv6 when the WAN has no IPv4 address', () => {
		netifd_patch({ wan6: WAN6 });
		assert.match({ url: 'http://[2001:db8::10]:7547/cr', resolved: '' }, compose('http://192.0.2.1/acs'));
	});

	it('gives an empty URL when the WAN has no address', () => {
		netifd_patch({});
		assert.match({ url: '', resolved: '' }, compose('http://192.0.2.1/acs'));
	});
});
