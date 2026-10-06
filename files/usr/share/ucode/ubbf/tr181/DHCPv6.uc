'use strict';

import * as schemas from 'ubbf.schemas.DHCPv6';
import * as ubus from 'ubus';
import * as uci from 'uci';
import {
	ipv6_leases_raw_get, prefix_length_nibble_check, client_snoop_entry
} from 'ubbf.utils.dhcp';
import { log_err } from 'ubbf.utils.logging';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { datetime_format } from 'ubbf.utils.helpers';
import * as ubbf from 'ubbf';

/**
 * Builds the SentOption table for a DHCPv6 client, merging configured rows
 * with options observed by udhcpsnoop in client-originated messages
 * (Solicit / Request / Renew / Rebind / Release / Decline / InfoRequest).
 * Configured rows keep their keys; observations are appended with fresh
 * keys and skipped if their tag is already configured.
 *
 * @param {object} parent - Client.{i} stored config
 * @param {object} root - Root data model object
 * @returns {object} Keyed instance table
 */
function sent_option_table(parent, root) {
	let table = {};
	let used_tags = {};
	let max_idx = 0;

	for (let k, v in (parent?.SentOption ?? {})) {
		table[k] = v;
		let idx = int(k);
		if (idx != null && idx > max_idx)
			max_idx = idx;
		if (v?.Tag && v.Tag != '0')
			used_tags[v.Tag] = true;
	}

	let snoop = client_snoop_entry(root, parent?.Interface);
	for (let so in (snoop?.options_v6 ?? [])) {
		if (so?.tag == null)
			continue;
		let tag_str = sprintf('%d', so.tag);
		if (used_tags[tag_str])
			continue;
		used_tags[tag_str] = true;
		max_idx++;
		table['' + max_idx] = {
			Enable: 'true',
			Alias: sprintf('cpe-SentOption-%d', max_idx),
			Tag: tag_str,
			Value: so.value ?? ''
		};
	}

	return table;
}

/**
 * Builds the ReceivedOption table for a DHCPv6 client from the udhcpsnoop
 * dump's server_options_v6 array. Each option observed in a server reply
 * (Reply / Advertise / Reconfigure) becomes a row.
 *
 * @param {object} parent - Client.{i} stored config
 * @param {object} root - Root data model object
 * @returns {object} Keyed instance table
 */
function received_option_table(parent, root) {
	let table = {};
	let snoop = client_snoop_entry(root, parent?.Interface);
	let max_idx = 0;
	for (let so in (snoop?.server_options_v6 ?? [])) {
		if (so?.tag == null)
			continue;
		max_idx++;
		table['' + max_idx] = {
			Tag: sprintf('%d', so.tag),
			Value: so.value ?? '',
			Server: ''
		};
	}
	return table;
}

/**
 * Reads the DHCPv6 DUID from UCI network globals.
 *
 * @returns {string} DUID as hex string or empty string if unavailable
 */
function duid_read() {
	let cursor = uci.cursor();
	if (!cursor)
		return '';

	cursor.load('network');
	return cursor.get('network', 'globals', 'dhcp_default_duid') ?? '';
}

/**
 * Get handler for Device.DHCPv6.Client.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} DHCPv6 client status and DUID
 */
function client_get(ctx) {
	if (!ctx.config)
		return null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = enabled ? 'Enabled' : 'Disabled';
	let duid = duid_read();

	let iface_ref = ctx.config.Interface;
	let iface = iface_ref ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref)) : null;
	let iface_name = iface?.Name;

	let server_entry = null;

	if (iface_name) {
		// netifd splits IPv4/IPv6 leases across paired interfaces named '<iface>' and '<iface>6'
		let iface_status = ubus?.call('network.interface.' + iface_name + '6', 'status', {});

		// odhcp6c registers its ubus object as odhcp6c.<l3_device>, not <netifd_iface>
		let l3_device = iface_status?.l3_device;
		let dhcp6_state = l3_device
			? ubus?.call('odhcp6c.' + l3_device, 'get_state', {}) : null;
		if (dhcp6_state) {
			let server_addr = dhcp6_state.SERVER?.[0];
			let serverid_hex = dhcp6_state.SERVERID;
			// Strip the 4-byte OPTION_SERVERID header (8 hex chars) to leave the bare DUID
			let server_duid = (type(serverid_hex) == 'string' && length(serverid_hex) > 8)
				? substr(serverid_hex, 8) : null;
			if (server_addr || server_duid) {
				server_entry = {
					'1': {
						SourceAddress: server_addr ?? '',
						DUID: server_duid ?? '',
						InformationRefreshTime: ''
					}
				};
			}
		}
	}

	let sent = sent_option_table(ctx.config, ctx.root);
	let received = received_option_table(ctx.config, ctx.root);

	return {
		...ctx.config,
		Status: status,
		DUID: duid,
		Server: server_entry,
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(server_entry)),
		SentOption: sent,
		SentOptionNumberOfEntries: sprintf('%d', ubbf.instance_count(sent)),
		ReceivedOption: received,
		ReceivedOptionNumberOfEntries: sprintf('%d', ubbf.instance_count(received))
	};
}

/**
 * Gets DHCPv6 leases for a pool, grouped by DUID.
 *
 * @param {object} ctx - Handler context with root data model
 * @returns {array} Array of client objects grouped by DUID
 */
function leases_for_pool(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let iface_ref = parent?.Interface;
	if (!iface_ref)
		return [];

	let iface = ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref));
	let iface_name = iface?.Name;
	if (!iface_name)
		return [];

	let status = netifd_status_get(iface_name);
	let device_name = status?.l3_device ?? status?.device;
	if (!device_name)
		return [];

	let leases = ipv6_leases_raw_get();
	if (!leases?.device)
		return [];

	let device_leases = leases.device[device_name];
	if (!device_leases?.leases)
		return [];

	let clients = {};
	for (let lease in device_leases.leases) {
		let duid = lease.duid;
		if (!duid)
			continue;

		clients[duid] ??= {
			duid: duid,
			hostname: lease.hostname,
			addresses: [],
			prefixes: []
		};

		for (let addr in lease['ipv6-addr'])
			push(clients[duid].addresses, addr);

		for (let prefix in lease['ipv6-prefix'])
			push(clients[duid].prefixes, prefix);
	}

	return values(clients);
}

/**
 * Converts a remaining lease lifetime in seconds into the TR-181
 * dateTime at which it expires. Negative means infinite, which TR-181
 * expresses as 9999-12-31T23:59:59Z.
 *
 * @param {number} seconds - Remaining lifetime, negative for infinite
 * @returns {string} ISO 8601 expiry or the infinite/unknown sentinel
 */
function lifetime_to_datetime(seconds) {
	if (seconds == null)
		return datetime_format(0);
	if (seconds < 0)
		return '9999-12-31T23:59:59Z';
	return datetime_format(time() + seconds);
}

/**
 * Converts a grouped client object to TR-181 client representation.
 *
 * @param {object} client - Client object with addresses/prefixes arrays
 * @param {number} index - Instance index (1-based)
 * @returns {object} TR-181 client object with embedded IPv6Address and IPv6Prefix
 */
function lease_to_client(client, index) {
	let result = {
		Alias: client.hostname ?? sprintf('cpe-client%d', index),
		Active: 'true',
		// SourceAddress is an IP address; odhcpd leases carry no client
		// source address, so the first assigned address is the closest fit
		SourceAddress: client.addresses[0]?.address ?? '',
		IPv6AddressNumberOfEntries: sprintf('%d', length(client.addresses)),
		IPv6PrefixNumberOfEntries: sprintf('%d', length(client.prefixes))
	};

	if (length(client.addresses)) {
		result.IPv6Address = {};
		for (let i, addr in client.addresses) {
			result.IPv6Address[sprintf('%d', i + 1)] = {
				IPAddress: addr.address,
				PreferredLifetime: lifetime_to_datetime(addr['preferred-lifetime']),
				ValidLifetime: lifetime_to_datetime(addr['valid-lifetime'])
			};
		}
	}

	if (length(client.prefixes)) {
		result.IPv6Prefix = {};
		for (let i, prefix in client.prefixes) {
			result.IPv6Prefix[sprintf('%d', i + 1)] = {
				Prefix: sprintf('%s/%d', prefix.address, prefix['prefix-length']),
				PreferredLifetime: lifetime_to_datetime(prefix['preferred-lifetime']),
				ValidLifetime: lifetime_to_datetime(prefix['valid-lifetime'])
			};
		}
	}

	return result;
}

/**
 * Get handler for Device.DHCPv6.Server.Pool.{i}.
 *
 * @param {object} ctx - Context with pool config
 * @returns {object|null} Pool config with dynamic ClientNumberOfEntries and Client instances
 */
function pool_get(ctx) {
	if (!ctx.config)
		return null;

	let leases = leases_for_pool(ctx);
	let to_client = (lease, idx) => lease_to_client(lease, idx + 1);

	let iface_ref = ctx.config.Interface;
	let prefix_refs = [];
	if (iface_ref) {
		let iface = ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref));
		let v6_prefixes = iface?.IPv6Prefix ?? {};
		for (let inst, prefix in v6_prefixes) {
			if (!ubbf.to_bool(prefix.Enable))
				continue;
			push(prefix_refs, sprintf('%s.IPv6Prefix.%s', iface_ref, inst));
		}
	}
	let prefix_csv = join(',', prefix_refs);

	return {
		...ctx.config,
		IANAPrefixes: prefix_csv,
		IAPDPrefixes: prefix_csv,
		ClientNumberOfEntries: sprintf('%d', length(leases)),
		Client: ubbf.enumerate_instances(leases, to_client)
	};
}

/**
 * Set handler for Device.DHCPv6.Server.Pool.{i}.
 *
 * Enforces RFC 7084 / TR-181 PD recommendation that IAPDAddLength
 * is 0 (no extra bits) or a multiple of 4 in [0, 128].
 *
 * @param {object} ctx - Context with param, value
 * @returns {number} 0 on success, -1 on failure
 */
function pool_set(ctx) {
	if (ctx.param == 'IAPDAddLength') {
		if (ctx.value == null || ctx.value == '')
			return 0;
		if (!prefix_length_nibble_check(ctx.value)) {
			log_err('DHCPv6 Pool.IAPDAddLength must be 0 or a multiple of 4, got %s', ctx.value);
			return -1;
		}
	}
	return 0;
}

/**
 * Get handler for Device.DHCPv6.Server.Pool.{i}.Client.{i}.
 *
 * @param {object} ctx - Context with parent pool config and optional instance
 * @returns {object|null} Single client or enumerated clients for the pool
 */
function pool_client_get(ctx) {
	let leases = leases_for_pool(ctx);

	let to_client = (lease, idx) => lease_to_client(lease, idx + 1);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(leases, to_client);

	let lease = ubbf.get_by_instance(leases, ctx.instance);
	if (!lease)
		return null;

	return to_client(lease, ctx.instance - 1);
}

/**
 * Get handler for Device.DHCPv6.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DHCPv6 properties with instance counts
 */
function dhcpv6_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client))
	};
}

/**
 * Get handler for Device.DHCPv6.Server.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DHCPv6 server properties with instance counts
 */
function dhcpv6_server_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		PoolNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Pool))
	};
}

/**
 * Fetches DHCPv6 stats from udhcpsnoop via ubus.
 *
 * @returns {object|null} Stats keyed by group name
 */
function dhcpsnoop_stats_get() {
	return ubus?.call('dhcpsnoop', 'stats', {});
}

/**
 * Maps a DHCPv6 client to its udhcpsnoop stats group.
 *
 * Groups are provisioned per netdev from the DHCPv4.Client table
 * (render/templates/dhcp.uc), so a v6 client shares the group of the
 * enabled v4 client bound to the same IP.Interface; the two client
 * tables are numbered independently.
 *
 * @param {object} parent - Client.{i} stored config
 * @param {object} root - Root data model object
 * @returns {string|null} udhcpsnoop group name, or null when none exists
 */
function client_stats_group(parent, root) {
	let iface_ref = trim(parent?.Interface ?? '');
	if (iface_ref == '')
		return null;

	for (let k, c in (root?.Device?.DHCPv4?.Client ?? {})) {
		if (!ubbf.is_instance_key(k))
			continue;
		if (!ubbf.to_bool(c?.Enable))
			continue;
		if (trim(c?.Interface ?? '') == iface_ref)
			return sprintf('client_%s', k);
	}

	return null;
}

/**
 * Get handler for Device.DHCPv6.Server.Stats.
 *
 * @param {object} ctx - Context object
 * @returns {object} Server stats mapped to TR-181 fields
 */
function server_stats_get(ctx) {
	let stats = dhcpsnoop_stats_get();
	let v6 = stats?.server?.v6 ?? {};

	return {
		Solicit: sprintf('%d', v6.solicit ?? 0),
		Advertise: sprintf('%d', v6.advertise ?? 0),
		Request: sprintf('%d', v6.request ?? 0),
		Confirm: sprintf('%d', v6.confirm ?? 0),
		Renew: sprintf('%d', v6.renew ?? 0),
		Rebind: sprintf('%d', v6.rebind ?? 0),
		Reply: sprintf('%d', v6.reply ?? 0),
		Release: sprintf('%d', v6.release ?? 0),
		Decline: sprintf('%d', v6.decline ?? 0),
		Reconfigure: sprintf('%d', v6.reconfigure ?? 0),
		InformationRequest: sprintf('%d', v6.information_request ?? 0),
		RelayForward: '0',
		RelayReply: '0',
		DiscardedPackets: '0',
		TransmitFailure: '0'
	};
}

/**
 * Get handler for Device.DHCPv6.Client.{i}.Stats.
 *
 * @param {object} ctx - Context object
 * @returns {object} Client stats mapped to TR-181 fields
 */
function client_stats_get(ctx) {
	let group = client_stats_group(ctx.parent ?? ctx.config, ctx.root);
	let stats = group ? dhcpsnoop_stats_get() : null;
	let v6 = (group ? stats?.[group]?.v6 : null) ?? {};

	return {
		Solicit: sprintf('%d', v6.solicit ?? 0),
		Advertise: sprintf('%d', v6.advertise ?? 0),
		Request: sprintf('%d', v6.request ?? 0),
		Confirm: sprintf('%d', v6.confirm ?? 0),
		Renew: sprintf('%d', v6.renew ?? 0),
		Rebind: sprintf('%d', v6.rebind ?? 0),
		Reply: sprintf('%d', v6.reply ?? 0),
		Release: sprintf('%d', v6.release ?? 0),
		Decline: sprintf('%d', v6.decline ?? 0),
		Reconfigure: sprintf('%d', v6.reconfigure ?? 0),
		InformationRequest: sprintf('%d', v6.information_request ?? 0),
		DiscardedPackets: '0',
		TransmitFailure: '0'
	};
}

/**
 * Reset handler for Device.DHCPv6.Client.{i}.Stats.Reset().
 *
 * The netdev's udhcpsnoop group holds both v4 and v6 counters, so this
 * resets both halves at once. That is acceptable: a TR-181 caller
 * resetting the v6 client stats has no legitimate reason to expect the
 * v4 view to be preserved on the same underlying interface.
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key for tracking (unused)
 * @param {array} instances - [client_instance]
 * @param {object} root - Root data model object
 * @returns {object} Empty result on success
 */
function client_stats_reset_op(input, command_key, instances, root) {
	let idx = instances?.[0];
	if (idx == null)
		return null;

	let parent = root?.Device?.DHCPv6?.Client?.['' + idx];
	let group = client_stats_group(parent, root);
	if (group)
		ubus?.call('dhcpsnoop', 'stats_reset', { group });
	return {};
}

/**
 * Reset handler for Device.DHCPv6.Server.Stats.Reset().
 *
 * @returns {object} Empty result on success
 */
function server_stats_reset_op() {
	ubus?.call('dhcpsnoop', 'stats_reset', { group: 'server' });
	return {};
}

/**
 * Resolves a DHCPv6 client instance to its netifd interface name.
 *
 * @param {number} instance - Client instance number
 * @returns {string|null} Interface name or null if not found
 */
function client_iface_resolve(root, instance) {
	let client = root?.Device?.DHCPv6?.Client?.['' + instance];
	if (!client?.Interface)
		return null;

	let iface = ubbf.navigate_data(root, ubbf.path_to_parts(client.Interface));
	return iface?.Name;
}

/**
 * Handles Device.DHCPv6.Client.{i}.Renew() operation.
 *
 * @param {object} input - Operation input parameters
 * @param {string} command_key - Command key for tracking
 * @param {array} instances - Instance numbers [client_instance]
 * @param {object} root - Root configuration data
 * @returns {object|null} Empty object on success, null on failure
 */
function client_renew_op(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface_name = client_iface_resolve(root, idx);
	if (!iface_name)
		return null;

	// netifd splits IPv4/IPv6 leases across paired interfaces named '<iface>' and '<iface>6'
	ubus.call('network.interface.' + iface_name + '6', 'renew', {});
	return {};
}

/**
 * Firewall hook for Device.DHCPv6.Server.Pool.{i}.
 *
 * @param {object} inst - Pool instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for DHCPv6 port 547
 */
function dhcpv6_pool_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	return [{
		type: 'Service',
		alias: sprintf('cpe-dhcp6-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: '547',
		IPVersion: '6',
		Action: 'Accept'
	}];
}

/**
 * Firewall hook for Device.DHCPv6.Client.{i}.
 *
 * @param {object} inst - Client instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for DHCPv6 client port 546
 */
function dhcpv6_client_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	return [{
		type: 'Service',
		alias: sprintf('cpe-dhcp6c-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: '546',
		IPVersion: '6',
		Action: 'Accept'
	}];
}

export const model = {
	'Device.DHCPv6': {
		schema: schemas.DHCPv6,
		get: dhcpv6_get
	},

	'Device.DHCPv6.Client': {
	},

	'Device.DHCPv6.Client.{i}': {
		schema: schemas.Client,
		get: client_get,
		firewall: dhcpv6_client_firewall
	},

	'Device.DHCPv6.Client.{i}.SentOption': {
	},

	'Device.DHCPv6.Client.{i}.SentOption.{i}': {
		schema: schemas.Client_SentOption
	},

	'Device.DHCPv6.Client.{i}.ReceivedOption': {
	},

	'Device.DHCPv6.Client.{i}.ReceivedOption.{i}': {
		schema: schemas.Client_ReceivedOption
	},

	'Device.DHCPv6.Client.{i}.Stats': {
		schema: schemas.Client_Stats,
		get: client_stats_get
	},

	'Device.DHCPv6.Client.{i}.Retransmission': {
		schema: schemas.Client_Retransmission,
		get: ubbf.ctx_config
	},

	'Device.DHCPv6.Client.{i}.Server': {
	},

	'Device.DHCPv6.Client.{i}.Server.{i}': {
		schema: schemas.Client_Server
	},

	'Device.DHCPv6.Server': {
		schema: schemas.Server,
		get: dhcpv6_server_get
	},

	'Device.DHCPv6.Server.Stats': {
		schema: schemas.Server_Stats,
		get: server_stats_get
	},

	'Device.DHCPv6.Server.Pool': {
	},

	'Device.DHCPv6.Server.Pool.{i}': {
		schema: schemas.Server_Pool,
		get: pool_get,
		set: pool_set,
		firewall: dhcpv6_pool_firewall,
		enable_status_derive: true
	},

	'Device.DHCPv6.Server.Pool.{i}.Client': {
	},

	'Device.DHCPv6.Server.Pool.{i}.Client.{i}': {
		schema: schemas.Pool_Client,
		get: pool_client_get
	},

	'Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Address': {
	},

	'Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Address.{i}': {
		schema: schemas.Client_IPv6Address
	},

	'Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Prefix': {
	},

	'Device.DHCPv6.Server.Pool.{i}.Client.{i}.IPv6Prefix.{i}': {
		schema: schemas.Client_IPv6Prefix
	},

	'Device.DHCPv6.Server.Pool.{i}.Option': {
	},

	'Device.DHCPv6.Server.Pool.{i}.Option.{i}': {
		schema: schemas.Pool_Option
	}
};

export const operations = {
	'Device.DHCPv6.Client.{i}.Renew()': {
		type: 'sync',
		handler: client_renew_op
	},

	'Device.DHCPv6.Client.{i}.Stats.Reset()': {
		type: 'sync',
		handler: client_stats_reset_op
	},

	'Device.DHCPv6.Server.Stats.Reset()': {
		type: 'sync',
		handler: server_stats_reset_op
	}
};
