// Host test of the DNS relay cache: TR-181 has CacheSize in KiB and the
// TTL bounds read-only, dnsmasq takes the cache in entries. The render of
// render/templates/dns.uc gives dnsmasq the X_UBBF_ settings, and the
// getter of Device.DNS.Relay.Config.{i} in tr181/DNS.uc reads them back
// in the TR-181 units.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import * as dns from 'ubbf.utils.dns';
import { dns_relay_plan } from 'ubbf.render.ubbf_helpers';
import { model } from 'ubbf.tr181.DNS';

const TEMPLATE = '/usr/share/ucode/ubbf/render/templates/dns.uc';

function render(relay_config) {
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'lan', Upstream: 'false' } } },
		DNS: { Relay: {
			Enable: 'true',
			Forwarding: { '1': { Enable: 'true', DNSServer: '192.0.2.53', Interface: '' } },
			Config: { '1': relay_config }
		} }
	} };
	let output = [];

	include(TEMPLATE, { ...h, ...dns, output, config, ubbf, dns_learned_row: ubbf.dns_learned_row,
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		interface_to_name: ubbf.interface_to_name, dns_relay_plan,
		services: { set_enabled: () => null } });

	return filter(output, (l) => match(l, /cache/));
}

const config_get = model['Device.DNS.Relay.Config.{i}'].get;

function cache(row) {
	let got = config_get({ config: row });
	return [ got?.CacheSize, got?.CacheMinTTL, got?.CacheMaxTTL ];
}

describe('DNS relay cache render', () => {
	it('gives dnsmasq the X_UBBF_ settings', () => {
		assert.match([
			'set dhcp.dns_relay_lan.cachesize=1000',
			'set dhcp.dns_relay_lan.max_cache_ttl=3600',
			'set dhcp.dns_relay_lan.min_cache_ttl=60'
		], render({ Interface: '', X_UBBF_CacheEntries: '1000', X_UBBF_CacheMinTTL: '60', X_UBBF_CacheMaxTTL: '3600' }));
	});

	it('turns the cache off for 0 entries', () => {
		assert.match([ 'set dhcp.dns_relay_lan.cachesize=0' ],
			render({ Interface: '', X_UBBF_CacheEntries: '0', X_UBBF_CacheMinTTL: '0', X_UBBF_CacheMaxTTL: '0' }));
	});

	it('does not give dnsmasq the read-only TR-181 names', () => {
		assert.match([], render({ Interface: '', CacheSize: '1000', CacheMinTTL: '60', CacheMaxTTL: '3600' }));
	});
});

describe('DNS Relay.Config cache getter', () => {
	it('reads 1000 entries as 133 KiB', () => {
		assert.match([ '133', '60', '3600' ],
			cache({ X_UBBF_CacheEntries: '1000', X_UBBF_CacheMinTTL: '60', X_UBBF_CacheMaxTTL: '3600' }));
	});

	it('reads 5000 entries as 665 KiB', () => {
		assert.match([ '665', '0', '86400' ], cache({ X_UBBF_CacheEntries: '5000' }));
	});

	it('reads the defaults as 150 entries, 20 KiB', () => {
		assert.match([ '20', '0', '86400' ], cache({}));
	});

	it('reads no cache as 0 KiB', () => {
		assert.match([ '0', '0', '86400' ], cache({ X_UBBF_CacheEntries: '0' }));
	});

	it('does not report a stored TR-181 value', () => {
		assert.match([ '20', '0', '86400' ], cache({ CacheSize: '9', X_UBBF_CacheEntries: '150' }));
	});
});
