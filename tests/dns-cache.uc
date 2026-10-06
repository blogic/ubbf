// Host test of the DNS relay cache: TR-181 has CacheSize in KiB and the
// TTL bounds read-only, dnsmasq takes the cache in entries. The render of
// render/templates/dns.uc gives dnsmasq the X_UBBF_ settings, and the
// getter of Device.DNS.Relay.Config.{i} in tr181/DNS.uc reads them back
// in the TR-181 units. Run from the repository root with the native
// module built for the host:
//   ucode -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/dns-cache.uc
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import { model } from 'ubbf.tr181.DNS';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const TEMPLATE = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/dns.uc';

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

	include(TEMPLATE, { ...h, output, config, ubbf,
		ubbf_get: ubbf.get, ubbf_instances: ubbf.instances, ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int, csv_to_list: ubbf.csv_to_list,
		interface_to_name: ubbf.interface_to_name, services: { set_enabled: () => null } });

	return filter(output, (l) => match(l, /cache/));
}

check('the X_UBBF_ settings reach dnsmasq', render({
	Interface: '', X_UBBF_CacheEntries: '1000', X_UBBF_CacheMinTTL: '60', X_UBBF_CacheMaxTTL: '3600'
}), [
	'set dhcp.dns_relay_lan.cachesize=1000',
	'set dhcp.dns_relay_lan.max_cache_ttl=3600',
	'set dhcp.dns_relay_lan.min_cache_ttl=60'
]);

check('0 entries turn the cache off', render({
	Interface: '', X_UBBF_CacheEntries: '0', X_UBBF_CacheMinTTL: '0', X_UBBF_CacheMaxTTL: '0'
}), [ 'set dhcp.dns_relay_lan.cachesize=0' ]);

check('the read-only TR-181 names do not reach dnsmasq', render({
	Interface: '', CacheSize: '1000', CacheMinTTL: '60', CacheMaxTTL: '3600'
}), []);

let config_get = model['Device.DNS.Relay.Config.{i}'].get;

function cache(row) {
	let got = config_get({ config: row });
	return [ got?.CacheSize, got?.CacheMinTTL, got?.CacheMaxTTL ];
}

check('1000 entries are 133 KiB', cache({ X_UBBF_CacheEntries: '1000', X_UBBF_CacheMinTTL: '60', X_UBBF_CacheMaxTTL: '3600' }),
	[ '133', '60', '3600' ]);
check('5000 entries are 665 KiB', cache({ X_UBBF_CacheEntries: '5000' }), [ '665', '0', '86400' ]);
check('the defaults are 150 entries, 20 KiB', cache({}), [ '20', '0', '86400' ]);
check('no cache is 0 KiB', cache({ X_UBBF_CacheEntries: '0' }), [ '0', '0', '86400' ]);
check('a stored TR-181 value is not what the getter reports', cache({ CacheSize: '9', X_UBBF_CacheEntries: '150' }),
	[ '20', '0', '86400' ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
