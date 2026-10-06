'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { handler as nslookup_handler } from 'ubbf.tr143.NSLookup';
import { op_trigger_set, op_overlay_get } from 'ubbf.utils.cwmp-op-trigger';

/**
 * Sync operation handler for Device.DNS.Relay.Config.{i}.FlushCache().
 *
 * @param {object} input - Unused
 * @param {string} command_key - USP command key
 * @returns {object} Empty result object
 */
function flush_cache_handler(input, command_key) {
	system('killall -HUP dnsmasq');
	return {};
}

/**
 * Get handler for Device.DNS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS properties with instance counts
 */
function dns_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ZoneNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Zone))
	};
}

/**
 * Classifies a learned DNS server address by netifd proto and family.
 *
 * odhcp6c merges DHCPv6 OPTION_DNS_SERVERS and RA RDNSS into one
 * `dns-server` list before netifd publishes it. The RA-only addresses
 * are captured by /etc/odhcp6c.user.d/10-ubbf-dns-source and handled
 * by the caller; this function is the fallback classifier for
 * addresses not flagged as RA-sourced.
 *
 * @param {string} address - DNS server literal
 * @param {string} proto - netifd interface proto (dhcp, dhcpv6, static, ...)
 * @returns {string} TR-181 Type string (DHCPv4, DHCPv6, Static)
 */
function dns_server_type_classify(address, proto) {
	let is_ipv4 = !!match(address, /^[0-9.]+$/);
	if (is_ipv4)
		return (proto == 'dhcp' || proto == 'dhcpv4') ? 'DHCPv4' : 'Static';
	return (proto == 'dhcpv6') ? 'DHCPv6' : 'Static';
}

/**
 * Reads the RA-sourced DNS address set for a netifd interface.
 *
 * The state file is written by /etc/odhcp6c.user.d/10-ubbf-dns-source
 * on every odhcp6c event, one address per line, for the interface in
 * $INTERFACE. An absent or empty file yields an empty set.
 *
 * @param {string} iface_name - netifd logical interface (e.g. 'wan6')
 * @returns {object} Map with each RA DNS address as a truthy key
 */
function ra_dns_set_read(iface_name) {
	if (!iface_name)
		return {};
	let data = fs.readfile(sprintf('/tmp/ubbf/ra-dns.%s', iface_name));
	if (!data)
		return {};
	let set = {};
	for (let line in split(data, '\n')) {
		let addr = trim(line);
		if (addr != '')
			set[addr] = true;
	}
	return set;
}

/**
 * Appends one TR-181 Client.Server-shaped record per address in a
 * netifd dns-server list. When `ra_set` is provided, addresses
 * present in it are tagged Type=RouterAdvertisement regardless of
 * the netifd proto classification.
 *
 * @param {array} result - Destination array
 * @param {array} dns_list - netifd status['dns-server']
 * @param {string} proto - netifd interface proto
 * @param {string} iface_ref - TR-181 path of the source interface
 * @param {object} [ra_set] - RA-sourced address set (may be null)
 */
function dns_servers_collect(result, dns_list, proto, iface_ref, ra_set) {
	if (!dns_list || !length(dns_list))
		return;

	for (let addr in dns_list) {
		let dns_type = (ra_set && ra_set[addr])
			? 'RouterAdvertisement'
			: dns_server_type_classify(addr, proto);
		push(result, {
			Enable: 'true',
			Status: 'Enabled',
			Alias: sprintf('%s-%s', proto != '' ? proto : 'learned', addr),
			DNSServer: addr,
			Interface: iface_ref,
			Type: dns_type
		});
	}
}

/**
 * Enumerates DNS servers learned at runtime from netifd interface state.
 *
 * Walks Device.IP.Interface in the runtime tree. For each interface we
 * inspect its netifd status (`name`) for IPv4 DNS. Upstream interfaces
 * also get their sibling IPv6 netifd logical interface (`name + '6'`)
 * inspected, which is where odhcp6c publishes the DHCPv6-OPTION-DNS-
 * SERVERS / RA-RDNSS merged list on a typical OpenWrt WAN setup.
 *
 * @param {object} root - Runtime data model tree (ctx.root)
 * @returns {array} Array of server objects (Enable, Status, Alias, DNSServer, Interface, Type)
 */
function learned_dns_servers_get(root) {
	let interfaces = root?.Device?.IP?.Interface ?? {};
	let result = [];

	for (let inst_key, iface in interfaces) {
		if (!ubbf.is_instance_key(inst_key))
			continue;
		let name = iface?.Name;
		if (!name)
			continue;

		let iface_ref = sprintf('Device.IP.Interface.%d', +inst_key);

		let status = netifd_status_get(name);
		dns_servers_collect(result, status?.['dns-server'],
				    status?.proto ?? '', iface_ref, null);

		if (!ubbf.to_bool(iface.Upstream))
			continue;

		let status6 = netifd_status_get(name + '6');
		if (!status6)
			continue;
		let ra_set = ra_dns_set_read(name + '6');
		dns_servers_collect(result, status6['dns-server'],
				    status6.proto ?? '', iface_ref, ra_set);
	}

	return result;
}

/**
 * Get handler for Device.DNS.Client.Server.
 *
 * Produces dynamic server instances from netifd-learned DNS addresses
 * (DHCPv4 / DHCPv6 / merged-RA). Static instances persisted under the
 * same container are hydrated separately by the framework through the
 * Device.DNS.Client.Server.{i} pattern, so this handler only returns
 * the dynamic tail and never overwrites a static entry. Instance
 * numbers start above the highest static key in ctx.config.
 *
 * @param {object} ctx - Context with config (Server subtree) and root
 * @returns {object} Instance-keyed object with learned entries only
 */
function dns_client_server_get(ctx) {
	let config = ctx.config ?? {};
	let max_static = 0;
	for (let k in keys(config)) {
		if (!ubbf.is_instance_key(k))
			continue;
		let n = +k;
		if (n > max_static)
			max_static = n;
	}

	let dynamic = learned_dns_servers_get(ctx.root);
	let result = {};
	let next = max_static + 1;
	for (let srv in dynamic) {
		result[sprintf('%d', next)] = srv;
		next++;
	}
	return result;
}

/**
 * Get handler for Device.DNS.Client.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS client properties with instance counts
 */
function dns_client_get(ctx) {
	let static_count = ubbf.instance_count(ctx.config?.Server);
	let learned_count = length(learned_dns_servers_get(ctx.root));
	return {
		...ubbf.ctx_config(ctx),
		ServerNumberOfEntries: sprintf('%d', static_count + learned_count)
	};
}

/**
 * Enumerates non-upstream Device.IP.Interface instances paired with
 * the TR-181 interface reference.
 *
 * @param {object} root - Runtime data model tree
 * @returns {array} Array of { ref, ipv6 } pairs
 */
function downstream_interfaces_get(root) {
	let interfaces = root?.Device?.IP?.Interface ?? {};
	let out = [];
	for (let inst_key, iface in interfaces) {
		if (!ubbf.is_instance_key(inst_key))
			continue;
		if (ubbf.to_bool(iface?.Upstream))
			continue;
		push(out, {
			ref: sprintf('Device.IP.Interface.%d', +inst_key),
			ipv6: ubbf.to_bool(iface?.IPv6Enable)
		});
	}
	return out;
}

/**
 * Get handler for Device.DNS.Relay.Forwarding.
 *
 * TR-181 semantics for Forwarding.Interface name the DOWNSTREAM
 * listener the relay binds to (mirrored by collect_relay_interfaces
 * in render/templates/dns.uc and dns_relay_collect in firewall-nat.uc).
 * DNS.Client.Server.Interface, by contrast, names the upstream source.
 *
 * For every learned upstream DNS server (via learned_dns_servers_get)
 * and every non-upstream IP.Interface, emit one Forwarding instance
 * with DNSServer=<upstream address>, Interface=<downstream ref> and
 * the learned Type. IPv6 forwarders are skipped on downstreams that
 * have IPv6Enable=false (e.g. Guest on the default initial.json).
 *
 * Static Forwarding entries are hydrated by the Forwarding.{i}
 * framework path; this handler only returns the dynamic tail.
 *
 * @param {object} ctx - Context with config (Forwarding subtree) and root
 * @returns {object} Instance-keyed object with learned entries only
 */
function dns_relay_forwarding_get(ctx) {
	let config = ctx.config ?? {};
	let max_static = 0;
	for (let k in keys(config)) {
		if (!ubbf.is_instance_key(k))
			continue;
		let n = +k;
		if (n > max_static)
			max_static = n;
	}

	let upstream_servers = learned_dns_servers_get(ctx.root);
	let downstreams = downstream_interfaces_get(ctx.root);

	let result = {};
	let next = max_static + 1;
	for (let srv in upstream_servers) {
		let is_ipv6 = (srv.Type == 'DHCPv6' || srv.Type == 'RouterAdvertisement');
		for (let down in downstreams) {
			if (is_ipv6 && !down.ipv6)
				continue;
			result[sprintf('%d', next)] = {
				Enable: 'true',
				Status: 'Enabled',
				Alias: sprintf('%s-%s', srv.Type, down.ref),
				DNSServer: srv.DNSServer,
				Interface: down.ref,
				Type: srv.Type
			};
			next++;
		}
	}
	return result;
}

/**
 * Get handler for Device.DNS.Relay.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS relay properties with instance counts
 */
function dns_relay_get(ctx) {
	let static_forwarding = ubbf.instance_count(ctx.config?.Forwarding);
	let upstream_servers = learned_dns_servers_get(ctx.root);
	let downstreams = downstream_interfaces_get(ctx.root);

	let learned_count = 0;
	for (let srv in upstream_servers) {
		let is_ipv6 = (srv.Type == 'DHCPv6' || srv.Type == 'RouterAdvertisement');
		for (let down in downstreams) {
			if (is_ipv6 && !down.ipv6)
				continue;
			learned_count++;
		}
	}

	return {
		...ubbf.ctx_config(ctx),
		ConfigNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Config)),
		ForwardNumberOfEntries: sprintf('%d', static_forwarding + learned_count)
	};
}

// sizeof(struct crec) of dnsmasq 2.93 on aarch64; dnsmasq allocates the
// cache as that many entries, names up to SMALLDNAME inline
const DNSMASQ_CACHE_ENTRY_BYTES = 136;

/**
 * Get handler for Device.DNS.Relay.Config.{i}. CacheSize (kilobytes in
 * TR-181) and the TTL bounds read back from the X_UBBF_ settings that
 * dnsmasq takes; dnsmasq sizes its cache in entries.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Relay.Config properties
 */
function dns_relay_config_get(ctx) {
	if (!ctx.config)
		return null;

	let cfg = { ...ubbf.schema_defaults('DNS.Relay_Config'), ...ctx.config };
	let entries = ubbf.to_int(cfg.X_UBBF_CacheEntries) ?? 150;

	return {
		...cfg,
		CacheSize: sprintf('%d', (entries * DNSMASQ_CACHE_ENTRY_BYTES + 1023) / 1024),
		CacheMinTTL: sprintf('%d', ubbf.to_int(cfg.X_UBBF_CacheMinTTL) ?? 0),
		CacheMaxTTL: sprintf('%d', ubbf.to_int(cfg.X_UBBF_CacheMaxTTL) ?? 86400)
	};
}

/**
 * Get handler for Device.DNS.Zone.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Zone entry with computed HostNumberOfEntries
 */
function zone_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		HostNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Host))
	};
}

export const model = {
	'Device.DNS': {
		schema: 'DNS.DNS',
		get: dns_get
	},

	'Device.DNS.Client': {
		schema: 'DNS.Client',
		get: dns_client_get,
		enable_status_derive: true
	},

	'Device.DNS.Client.Server': {
		get: dns_client_server_get
	},

	'Device.DNS.Client.Server.{i}': {
		schema: 'DNS.Client_Server',
		enable_status_derive: true
	},

	'Device.DNS.Relay': {
		schema: 'DNS.Relay',
		get: dns_relay_get,
		enable_status_derive: true
	},

	'Device.DNS.RebindProtection': {
		schema: 'DNS.RebindProtection'
	},

	'Device.DNS.Relay.Forwarding': {
		get: dns_relay_forwarding_get
	},

	'Device.DNS.Relay.Forwarding.{i}': {
		schema: 'DNS.Relay_Forwarding',
		enable_status_derive: true
	},

	'Device.DNS.Relay.Config': {
	},

	'Device.DNS.Relay.Config.{i}': {
		schema: 'DNS.Relay_Config',
		get: dns_relay_config_get
	},

	'Device.DNS.Zone': {
	},

	'Device.DNS.Zone.{i}': {
		schema: 'DNS.Zone',
		get: zone_get
	},

	'Device.DNS.Zone.{i}.Host': {
	},

	'Device.DNS.Zone.{i}.Host.{i}': {
		schema: 'DNS.Zone_Host'
	},

	'Device.DNS.Diagnostics': {
		schema: 'DNS.Diagnostics'
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics': {
		schema: 'DNS.NSLookupDiagnostics',
		get: op_overlay_get('Device.DNS.Diagnostics.NSLookupDiagnostics'),
		set: op_trigger_set('Device.DNS.Diagnostics.NSLookupDiagnostics', 'DiagnosticsState')
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics.Result': {
	},

	'Device.DNS.Diagnostics.NSLookupDiagnostics.Result.{i}': {
		schema: 'DNS.NSLookupResult'
	}
};

export const operations = {
	'Device.DNS.Diagnostics.NSLookupDiagnostics()': {
		type: 'async',
		handler: nslookup_handler,
		store_results: 'Device.DNS.Diagnostics.NSLookupDiagnostics',
		output_key_map: { Status: 'DiagnosticsState' }
	},

	'Device.DNS.Relay.Config.{i}.FlushCache()': {
		type: 'sync',
		handler: flush_cache_handler
	}
};
