'use strict';

import * as schemas from 'ubbf.schemas.DHCPv4';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { leases_for_pool, dhcpsnoop_dump_get, client_snoop_entry } from 'ubbf.utils.dhcp';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Builds the SentOption table for a client, merging configured rows with options
 * observed by udhcpsnoop. Configured rows keep their keys; observations are appended
 * with fresh keys and skipped if their tag is already configured.
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
	for (let opt in (snoop?.options ?? [])) {
		if (opt?.tag == null)
			continue;
		let tag_str = sprintf('%d', opt.tag);
		if (used_tags[tag_str])
			continue;
		used_tags[tag_str] = true;
		max_idx++;
		table['' + max_idx] = {
			Enable: 'true',
			Alias: sprintf('cpe-SentOption-%d', max_idx),
			Tag: tag_str,
			Value: opt.value ?? ''
		};
	}

	return table;
}

/**
 * Builds the ReqOption table for a client, merging configured rows with the
 * parameter-request-list observed by udhcpsnoop. Configured Value is left intact
 * when present; otherwise the server-returned value for that tag is filled in.
 *
 * @param {object} parent - Client.{i} stored config
 * @param {object} root - Root data model object
 * @returns {object} Keyed instance table
 */
function req_option_table(parent, root) {
	let table = {};
	let used_tags = {};
	let max_idx = 0;

	let snoop = client_snoop_entry(root, parent?.Interface);
	let server_by_tag = {};
	for (let so in (snoop?.server_options ?? [])) {
		if (so?.tag == null)
			continue;
		server_by_tag[sprintf('%d', so.tag)] = so.value;
	}

	for (let k, v in (parent?.ReqOption ?? {})) {
		let row = { ...v };
		if ((!row.Value || row.Value == '') && row.Tag && row.Tag != '0')
			row.Value = server_by_tag[row.Tag] ?? '';
		table[k] = row;
		let idx = int(k);
		if (idx != null && idx > max_idx)
			max_idx = idx;
		if (row.Tag && row.Tag != '0')
			used_tags[row.Tag] = true;
	}

	let observed = snoop?.req_options ?? [];
	for (let i = 0; i < length(observed); i++) {
		let tag = observed[i];
		if (tag == null)
			continue;
		let tag_str = sprintf('%d', tag);
		if (used_tags[tag_str])
			continue;
		used_tags[tag_str] = true;
		max_idx++;
		table['' + max_idx] = {
			Enable: 'true',
			Alias: sprintf('cpe-ReqOption-%d', max_idx),
			Order: sprintf('%d', i + 1),
			Tag: tag_str,
			Value: server_by_tag[tag_str] ?? ''
		};
	}

	return table;
}

/**
 * Get handler for Device.DHCPv4.Client.{i}.
 *
 * @param {object} ctx - Context with config and instance info
 * @returns {object|null} DHCP client status and configuration
 */
function client_get(ctx) {
	if (!ctx.config)
		return null;

	let sent = sent_option_table(ctx.config, ctx.root);
	let req = req_option_table(ctx.config, ctx.root);
	let option_fields = {
		SentOption: sent,
		ReqOption: req,
		SentOptionNumberOfEntries: sprintf('%d', ubbf.instance_count(sent)),
		ReqOptionNumberOfEntries: sprintf('%d', ubbf.instance_count(req))
	};

	let iface_ref = ctx.config.Interface;
	let iface = iface_ref ? ubbf.navigate_data(ctx.root, ubbf.path_to_parts(iface_ref)) : null;
	let iface_name = iface?.Name;
	if (!iface_name)
		return { ...ctx.config, ...option_fields };

	let status = netifd_status_get(iface_name);
	if (!status)
		return { ...ctx.config, ...option_fields };

	let ip_address = '';
	let subnet_mask = '';
	let ipv4_addr = status['ipv4-address'];
	if (ipv4_addr && length(ipv4_addr) > 0) {
		ip_address = ipv4_addr[0].address || '';
		subnet_mask = ubbf.cidr_to_netmask(ipv4_addr[0].mask || 0);
	}

	let dns_servers = [];
	let dns_list = status['dns-server'];
	if (dns_list) {
		for (let dns in dns_list)
			push(dns_servers, dns);
	}

	let ip_routers = [];
	let routes = status.route;
	if (routes) {
		for (let route in routes) {
			if (route.nexthop && route.nexthop != '0.0.0.0')
				push(ip_routers, route.nexthop);
		}
	}

	let lease_remaining = 0;
	if (status.data) {
		let leasetime = status.data.leasetime || 0;
		let uptime = status.uptime || 0;
		if (leasetime > 0) {
			// netifd exports only the lease duration, and uptime counts
			// from interface-up while udhcpc renews at T1 (50%) without
			// bouncing the interface; past T1 the elapsed time within
			// the current lease is modelled as uptime modulo T1
			let t1 = leasetime / 2;
			let elapsed = (t1 > 0 && uptime > t1) ? uptime % t1 : uptime;
			lease_remaining = leasetime > elapsed ? leasetime - elapsed : 0;
		}
	}

	let dhcp_status = 'Init';
	if (status.up && ip_address != '')
		dhcp_status = 'Bound';
	else if (ip_address != '')
		dhcp_status = 'Renewing';
	else if (status.pending)
		dhcp_status = 'Requesting';

	return {
		...ctx.config,
		...option_fields,
		DHCPStatus: dhcp_status,
		IPAddress: ip_address,
		SubnetMask: subnet_mask,
		DNSServers: join(',', dns_servers),
		IPRouters: join(',', ip_routers),
		DHCPServer: status.data?.dhcpserver ?? '',
		LeaseTimeRemaining: sprintf('%d', lease_remaining)
	};
}

/**
 * Converts a DHCP lease to TR-181 client object format.
 *
 * @param {object} lease - Lease object with mac, ip, and expiry properties
 * @returns {object} TR-181 formatted Pool_Client object
 */
function lease_to_client(lease) {
	let now = time();
	let snoop_data = dhcpsnoop_dump_get();
	let client_info = snoop_data[lc(lease.mac)] ?? {};
	let client_opts = client_info.options ?? [];

	let options = {};
	for (let i = 0; i < length(client_opts); i++) {
		let opt = client_opts[i];
		options['' + (i + 1)] = {
			Tag: sprintf('%d', opt.tag),
			Value: opt.value ?? ''
		};
	}

	return {
		Alias: ubbf.alias_from_mac(lease.mac),
		Chaddr: lease.mac,
		Active: 'true',
		IPv4AddressNumberOfEntries: '1',
		OptionNumberOfEntries: sprintf('%d', length(client_opts)),
		Option: options,
		IPv4Address: {
			'1': {
				IPAddress: lease.ip,
				LeaseTimeRemaining: lease.expiry > now ?
					ubbf.iso8601_format(lease.expiry) : ''
			}
		}
	};
}

/**
 * Get handler for Device.DHCPv4.Server.Pool.{i}.
 *
 * @param {object} ctx - Context with config containing pool settings
 * @returns {object|null} Pool properties with client count and lease data
 */
function pool_get(ctx) {
	if (!ctx.config)
		return null;

	let leases = leases_for_pool(ctx.config);

	return {
		...ctx.config,
		ClientNumberOfEntries: sprintf('%d', length(leases)),
		Client: ubbf.enumerate_instances(leases, lease_to_client)
	};
}

/**
 * Get handler for Device.DHCPv4.Server.Pool.{i}.Client.{i}.
 *
 * @param {object} ctx - Context with parent pool config and optional instance
 * @returns {object|null} Single client or enumerated clients for the pool
 */
function pool_client_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent)
		return null;

	let leases = leases_for_pool(parent);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(leases, lease_to_client);

	let lease = ubbf.get_by_instance(leases, ctx.instance);
	if (!lease)
		return null;

	return lease_to_client(lease);
}

/**
 * Resolves a DHCPv4 client instance to its netifd interface name.
 *
 * @param {number} instance - Client instance number
 * @returns {string|null} Interface name or null if not found
 */
function client_iface_resolve(root, instance) {
	let client = root?.Device?.DHCPv4?.Client?.['' + instance];
	if (!client?.Interface)
		return null;

	let iface = ubbf.navigate_data(root, ubbf.path_to_parts(client.Interface));
	return iface?.Name;
}

/**
 * Handles Device.DHCPv4.Client.{i}.Renew() operation.
 *
 * @param {object} input - Operation input parameters (unused)
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

	ubus.call('network.interface.' + iface_name, 'renew', {});
	return {};
}

/**
 * Get handler for Device.DHCPv4.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DHCPv4 properties with instance counts
 */
function dhcpv4_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client))
	};
}

/**
 * Get handler for Device.DHCPv4.Server.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DHCPv4 server properties with instance counts
 */
function server_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		PoolNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Pool))
	};
}

/**
 * Fetches DHCP stats from udhcpsnoop via ubus.
 *
 * @returns {object|null} Stats keyed by group name
 */
function dhcpsnoop_stats_get() {
	return ubus?.call('dhcpsnoop', 'stats', {});
}

/**
 * Maps a stats group object to TR-181 server stats fields.
 *
 * @param {object} g - Group stats from udhcpsnoop
 * @returns {object} TR-181 Server.Stats object
 */
function stats_to_server(g) {
	return {
		Discover: sprintf('%d', g.discover ?? 0),
		Offer: sprintf('%d', g.offer ?? 0),
		Request: sprintf('%d', g.request ?? 0),
		ACK: sprintf('%d', g.ack ?? 0),
		NACK: sprintf('%d', g.nak ?? 0),
		Decline: sprintf('%d', g.decline ?? 0),
		Release: sprintf('%d', g.release ?? 0),
		Inform: sprintf('%d', g.inform ?? 0),
		ForceRenew: sprintf('%d', g.forcerenew ?? 0),
		DiscardedPackets: '0',
		TransmitFailure: '0',
		RelayOptionDropped: '0',
		SecondServerDetected: '0'
	};
}

/**
 * Maps a stats group object to TR-181 client stats fields.
 *
 * @param {object} g - Group stats from udhcpsnoop
 * @returns {object} TR-181 Client.Stats object
 */
function stats_to_client(g) {
	return {
		Discover: sprintf('%d', g.discover ?? 0),
		Offer: sprintf('%d', g.offer ?? 0),
		Request: sprintf('%d', g.request ?? 0),
		Decline: sprintf('%d', g.decline ?? 0),
		Release: sprintf('%d', g.release ?? 0),
		Inform: sprintf('%d', g.inform ?? 0),
		ACK: sprintf('%d', g.ack ?? 0),
		NACK: sprintf('%d', g.nak ?? 0),
		ForceRenew: sprintf('%d', g.forcerenew ?? 0),
		DiscardedPackets: '0',
		TransmitFailure: '0'
	};
}

/**
 * Get handler for Device.DHCPv4.Server.Stats.
 *
 * @param {object} ctx - Context object
 * @returns {object} Server stats mapped to TR-181 fields
 */
function server_stats_get(ctx) {
	let stats = dhcpsnoop_stats_get();
	return stats_to_server(stats?.server?.v4 ?? {});
}

/**
 * Get handler for Device.DHCPv4.Client.{i}.Stats.
 *
 * @param {object} ctx - Context object
 * @returns {object} Client stats mapped to TR-181 fields
 */
function client_stats_get(ctx) {
	let stats = dhcpsnoop_stats_get();
	let group = sprintf('client_%d', ctx.instance ?? 1);
	return stats_to_client(stats?.[group]?.v4 ?? {});
}

/**
 * Reset handler for Device.DHCPv4.Client.{i}.Stats.Reset().
 *
 * Scopes the reset to the per-client udhcpsnoop group so resetting one
 * client's counters does not also wipe the server-side counters.
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key for tracking (unused)
 * @param {array} instances - [client_instance]
 * @returns {object} Empty result on success
 */
function client_stats_reset_op(input, command_key, instances) {
	let idx = instances?.[0];
	if (idx == null)
		return null;
	ubus?.call('dhcpsnoop', 'stats_reset', { group: sprintf('client_%d', idx) });
	return {};
}

/**
 * Reset handler for Device.DHCPv4.Server.Stats.Reset().
 *
 * Scopes the reset to the udhcpsnoop "server" group.
 *
 * @returns {object} Empty result on success
 */
function server_stats_reset_op() {
	ubus?.call('dhcpsnoop', 'stats_reset', { group: 'server' });
	return {};
}

/**
 * Firewall hook for Device.DHCPv4.Server.Pool.{i}.
 *
 * @param {object} inst - Pool instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for DHCP port 67
 */
function dhcpv4_pool_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	return [{
		type: 'Service',
		alias: sprintf('cpe-dhcp4-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: '67',
		IPVersion: '4',
		Action: 'Accept'
	}];
}

/**
 * Firewall hook for Device.DHCPv4.Client.{i}.
 *
 * @param {object} inst - Client instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptor for DHCP client port 68
 */
function dhcpv4_client_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let iface = ubbf.get(root, inst.Interface);
	if (!iface?.Name)
		return null;

	return [{
		type: 'Service',
		alias: sprintf('cpe-dhcp4c-%s', iface.Name),
		Interface: inst.Interface,
		Protocol: 'udp',
		DestPort: '68',
		IPVersion: '4',
		Action: 'Accept'
	}];
}

export const model = {
	'Device.DHCPv4': {
		schema: schemas.DHCPv4,
		get: dhcpv4_get
	},

	'Device.DHCPv4.Client': {
	},

	'Device.DHCPv4.Client.{i}': {
		schema: schemas.Client,
		get: client_get,
		firewall: dhcpv4_client_firewall,
		enable_status_derive: true
	},

	'Device.DHCPv4.Client.{i}.SentOption': {
	},

	'Device.DHCPv4.Client.{i}.SentOption.{i}': {
		schema: schemas.Client_SentOption,
		get: (ctx) => sent_option_table(ctx.parent, ctx.root)?.['' + ctx.instance] ?? null
	},

	'Device.DHCPv4.Client.{i}.ReqOption': {
	},

	'Device.DHCPv4.Client.{i}.ReqOption.{i}': {
		schema: schemas.Client_ReqOption,
		get: (ctx) => req_option_table(ctx.parent, ctx.root)?.['' + ctx.instance] ?? null
	},

	'Device.DHCPv4.Client.{i}.Stats': {
		schema: schemas.Client_Stats,
		get: client_stats_get
	},

	'Device.DHCPv4.Client.{i}.Retransmission': {
		schema: schemas.Client_Retransmission,
		get: ubbf.ctx_config
	},

	'Device.DHCPv4.Server': {
		schema: schemas.Server,
		get: server_get
	},

	'Device.DHCPv4.Server.Stats': {
		schema: schemas.Server_Stats,
		get: server_stats_get
	},

	'Device.DHCPv4.Server.Pool': {
	},

	'Device.DHCPv4.Server.Pool.{i}': {
		schema: schemas.Server_Pool,
		get: pool_get,
		firewall: dhcpv4_pool_firewall,
		enable_status_derive: true
	},

	'Device.DHCPv4.Server.Pool.{i}.StaticAddress': {
	},

	'Device.DHCPv4.Server.Pool.{i}.StaticAddress.{i}': {
		schema: schemas.Pool_StaticAddress,
		get: ubbf.ctx_config
	},

	'Device.DHCPv4.Server.Pool.{i}.Option': {
	},

	'Device.DHCPv4.Server.Pool.{i}.Option.{i}': {
		schema: schemas.Pool_Option
	},

	'Device.DHCPv4.Server.Pool.{i}.Client': {
	},

	'Device.DHCPv4.Server.Pool.{i}.Client.{i}': {
		schema: schemas.Pool_Client,
		get: pool_client_get
	},

	'Device.DHCPv4.Server.Pool.{i}.Client.{i}.Option': {
	},

	'Device.DHCPv4.Server.Pool.{i}.Client.{i}.Option.{i}': {
		schema: schemas.Client_Option
	},

	'Device.DHCPv4.Server.Pool.{i}.Client.{i}.IPv4Address': {
	},

	'Device.DHCPv4.Server.Pool.{i}.Client.{i}.IPv4Address.{i}': {
		schema: schemas.Client_IPv4Address
	}
};

export const operations = {
	'Device.DHCPv4.Client.{i}.Renew()': {
		type: 'sync',
		handler: client_renew_op
	},

	'Device.DHCPv4.Client.{i}.Stats.Reset()': {
		type: 'sync',
		handler: client_stats_reset_op
	},

	'Device.DHCPv4.Server.Stats.Reset()': {
		type: 'sync',
		handler: server_stats_reset_op
	}
};
