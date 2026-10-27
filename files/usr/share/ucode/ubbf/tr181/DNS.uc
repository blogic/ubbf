'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { instance_numbers, instance_floor, instance_lookup } from 'ubbf.utils.instance-map';
import { dns_learned_row } from 'ubbf.utils.dns';
import { handler as nslookup_handler } from 'ubbf.tr143.NSLookup';
import { op_trigger_set, op_overlay_get } from 'ubbf.utils.cwmp-op-trigger';

const SERVER_TABLE = 'Device.DNS.Client.Server';
const FORWARDING_TABLE = 'Device.DNS.Relay.Forwarding';

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
 * Returns the stable key of a learned row: its source and its address.
 *
 * @param {object} row - Row with Type, Interface and DNSServer
 * @returns {string} The key
 */
function learned_key(row) {
	return join('|', [ row.Type, row.Interface, row.DNSServer ]);
}

/**
 * Numbers the learned rows of a table after the stored rows. A stored row
 * of a learned server keeps its number after a reboot through its pin in
 * config.json.
 *
 * @param {string} table - Table path
 * @param {array} rows - Learned rows
 * @param {object} stored - Stored rows of the table by instance
 * @returns {object} Instance number to learned row
 */
function learned_rows_number(table, rows, stored) {
	let numbers = instance_numbers(table, map(rows, learned_key), instance_floor(stored));
	let result = {};
	for (let row in rows) {
		let inst = sprintf('%d', numbers[learned_key(row)]);
		result[inst] = { ...row, Alias: `cpe-${inst}` };
	}
	return result;
}

/**
 * Builds the get handler of a table that holds the rows a controller adds
 * and the rows the CPE learns (runtime_instances, writable_rows).
 *
 * TR-181 makes Enable writable on every row and DNSServer and Interface
 * on the Static rows only. A learned row is stored once a controller
 * writes it, and the stored Enable then applies over the learned one.
 * A stored row whose server is no longer learned reads Disabled.
 *
 * @param {string} table - Table path
 * @param {function} stored_get - Returns the stored rows from ctx.root
 * @param {function} learned_get - Returns the learned rows from ctx.root
 * @returns {function} The get handler
 */
function learned_table_get(table, stored_get, learned_get) {
	return function(ctx) {
		let stored = stored_get(ctx.root);
		let rows = learned_rows_number(table, learned_get(ctx.root), stored);

		for (let n, row in rows)
			row.Status = ubbf.to_bool(row.Enable) ? 'Enabled' : 'Disabled';

		if (ctx.instance == null) {
			for (let n in keys(rows))
				if (stored?.[n])
					delete rows[n];
			return rows;
		}

		let live = rows[sprintf('%d', ctx.instance)];

		if (!ctx.config)
			return live;

		let row = live ? { ...live, Enable: ctx.config.Enable ?? live.Enable } : ubbf.ctx_config(ctx);
		let present = live || !dns_learned_row(ctx.config);

		row.Status = (present && ubbf.to_bool(row.Enable)) ? 'Enabled' : 'Disabled';
		return row;
	};
}

/**
 * Builds the set handler of a table with learned rows. The first write
 * into a learned row stores its Type, Interface and DNSServer, so the
 * render and a later boot can match the stored row to its server.
 *
 * @param {string} table - Table path
 * @param {function} stored_get - Returns the stored rows from ctx.root
 * @param {function} learned_get - Returns the learned rows from ctx.root
 * @returns {function} The set handler
 */
function learned_table_set(table, stored_get, learned_get) {
	return function(ctx) {
		if (instance_lookup(table, ctx.instance) == null)
			return 0;

		if (ctx.param == 'DNSServer' || ctx.param == 'Interface')
			return -USP_ERR_PARAM_READ_ONLY;

		if (ctx.config.Type)
			return 0;

		let rows = learned_rows_number(table, learned_get(ctx.root), stored_get(ctx.root));
		let live = rows[sprintf('%d', ctx.instance)];
		if (!live)
			return 0;

		ctx.config.Type = live.Type;
		ctx.config.Interface = live.Interface;
		ctx.config.DNSServer = live.DNSServer;
		return 0;
	};
}

/**
 * Returns the stored rows of Device.DNS.Client.Server.
 *
 * @param {object} root - Configuration tree
 * @returns {object|null} Rows by instance
 */
function stored_servers_get(root) {
	return root?.Device?.DNS?.Client?.Server;
}

/**
 * Builds the learned rows of Device.DNS.Relay.Forwarding: one for each
 * learned server. TR-181 names in Forwarding.Interface the IP interface
 * over which the query is sent, which for a learned row is the interface
 * that DHCP, IPCP or an RA configured it on.
 *
 * @param {object} root - Runtime data model tree
 * @returns {array} Learned forwarders
 */
function learned_forwarders_get(root) {
	return map(learned_dns_servers_get(root), (srv) => ({
		Enable: 'true',
		DNSServer: srv.DNSServer,
		Interface: srv.Interface,
		Type: srv.Type
	}));
}

/**
 * Returns the stored rows of Device.DNS.Relay.Forwarding.
 *
 * @param {object} root - Configuration tree
 * @returns {object|null} Rows by instance
 */
function stored_forwarders_get(root) {
	return root?.Device?.DNS?.Relay?.Forwarding;
}

/**
 * Get handler for Device.DNS.Relay.
 *
 * The core recounts a table from its name, but TR-181 names the count of
 * Forwarding ForwardNumberOfEntries, so the handler counts it.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DNS relay properties with instance counts
 */
function dns_relay_get(ctx) {
	let stored = ctx.config?.Forwarding ?? {};
	let learned = learned_rows_number(FORWARDING_TABLE, learned_forwarders_get(ctx.root), stored);
	let count = ubbf.instance_count(stored);

	for (let n in keys(learned))
		if (!stored[n])
			count++;

	return {
		...ubbf.ctx_config(ctx),
		ConfigNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Config)),
		ForwardNumberOfEntries: sprintf('%d', count)
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
		enable_status_derive: true
	},

	'Device.DNS.Client.Server': {
	},

	'Device.DNS.Client.Server.{i}': {
		schema: 'DNS.Client_Server',
		get: learned_table_get(SERVER_TABLE, stored_servers_get, learned_dns_servers_get),
		set: learned_table_set(SERVER_TABLE, stored_servers_get, learned_dns_servers_get),
		runtime_instances: true,
		writable_rows: true
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
	},

	'Device.DNS.Relay.Forwarding.{i}': {
		schema: 'DNS.Relay_Forwarding',
		get: learned_table_get(FORWARDING_TABLE, stored_forwarders_get, learned_forwarders_get),
		set: learned_table_set(FORWARDING_TABLE, stored_forwarders_get, learned_forwarders_get),
		runtime_instances: true,
		writable_rows: true
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
