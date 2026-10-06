'use strict';

import * as rtnl from 'rtnl';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.PPP';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';
import { link_local_addresses_get } from 'ubbf.utils.ipv6';
import { datetime_format } from 'ubbf.utils.helpers';
import * as cache from 'ubbf.utils.cache';
import * as ubbf from 'ubbf';

/**
 * Maps netifd status to TR-181 PPP ConnectionStatus.
 *
 * @param {object} status - Netifd interface status
 * @returns {string} TR-181 ConnectionStatus value
 */
function connection_status_map(status) {
	if (!status)
		return 'Unconfigured';

	let uptime = int(status.uptime);
	if (uptime != null && uptime > 0)
		return 'Connected';

	// netifd "pending" means setup in progress, not teardown
	if (status.pending)
		return 'Connecting';

	return 'Disconnected';
}

/**
 * Maps a pppd-derived error code (numeric exit status or the
 * string emitted by `ppp_exitcode_tostring` in netifd's ppp.sh)
 * to a TR-181 LastConnectionError enum value.
 *
 * @param {number|string} error_code - pppd numeric exit code or string code
 * @returns {string} TR-181 LastConnectionError value
 */
function last_connection_error_map(error_code) {
	const string_map = {
		'OK': 'ERROR_NONE',
		'FATAL_ERROR': 'ERROR_UNKNOWN',
		'OPTION_ERROR': 'ERROR_COMMAND_ABORTED',
		'NOT_ROOT': 'ERROR_COMMAND_ABORTED',
		'NO_KERNEL_SUPPORT': 'ERROR_COMMAND_ABORTED',
		'USER_REQUEST': 'ERROR_USER_DISCONNECT',
		'LOCK_FAILED': 'ERROR_COMMAND_ABORTED',
		'OPEN_FAILED': 'ERROR_COMMAND_ABORTED',
		'CONNECT_FAILED': 'ERROR_IP_CONFIGURATION',
		'PTYCMD_FAILED': 'ERROR_COMMAND_ABORTED',
		'NEGOTIATION_FAILED': 'ERROR_UNKNOWN',
		'PEER_AUTH_FAILED': 'ERROR_AUTHENTICATION_FAILURE',
		'IDLE_TIMEOUT': 'ERROR_IDLE_DISCONNECT',
		'CONNECT_TIME': 'ERROR_UNKNOWN',
		'CALLBACK': 'ERROR_UNKNOWN',
		'PEER_DEAD': 'ERROR_USER_DISCONNECT',
		'HANGUP': 'ERROR_ISP_DISCONNECT',
		'LOOPBACK': 'ERROR_UNKNOWN',
		'INIT_FAILED': 'ERROR_UNKNOWN',
		'AUTH_TOPEER_FAILED': 'ERROR_AUTHENTICATION_FAILURE',
		'TRAFFIC_LIMIT': 'ERROR_UNKNOWN',
		'CNID_AUTH_FAILED': 'ERROR_AUTHENTICATION_FAILURE',
		'UNKNOWN_ERROR': 'ERROR_UNKNOWN'
	};

	if (type(error_code) == 'string' && error_code in string_map)
		return string_map[error_code];

	let code = int(error_code);
	if (code == null || code == 0)
		return 'ERROR_NONE';
	if (index([1, 10, 13, 14, 17, 18, 20, 22], code) >= 0)
		return 'ERROR_UNKNOWN';
	if (index([2, 3, 4, 6, 7, 9], code) >= 0)
		return 'ERROR_COMMAND_ABORTED';
	if (index([5, 15], code) >= 0)
		return 'ERROR_USER_DISCONNECT';
	if (code == 8)
		return 'ERROR_IP_CONFIGURATION';
	if (index([11, 19, 21], code) >= 0)
		return 'ERROR_AUTHENTICATION_FAILURE';
	if (code == 12)
		return 'ERROR_IDLE_DISCONNECT';
	if (code == 16)
		return 'ERROR_ISP_DISCONNECT';

	return 'ERROR_NONE';
}

/**
 * Walks netifd's per-interface errors[] for entries from any PPP-family
 * proto handler (ppp / pppoe / pppoa / pptp) and returns the most
 * recent error string, or null if no PPP error is present.
 *
 * @param {object} status - netifd interface status object
 * @returns {string|null}
 */
function ppp_error_string_get(status) {
	if (!status?.errors)
		return null;
	let last;
	for (let entry in status.errors) {
		if (!entry?.subsystem || !entry?.code)
			continue;
		if (entry.subsystem == 'ppp' || entry.subsystem == 'pppoe'
		    || entry.subsystem == 'pppoa' || entry.subsystem == 'pptp')
			last = entry.code;
	}
	return last;
}

/**
 * Gets the PPP device name for an interface.
 *
 * @param {string} ifname - Interface name
 * @returns {string|null} PPP device name (e.g., ppp0) or null
 */
function ppp_device_get(ifname) {
	let status = netifd_status_get(ifname);
	return status?.l3_device;
}

/**
 * Get handler for Device.PPP.Interface.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} PPP interface properties with status
 */
function interface_get(ctx) {
	if (!ctx.config)
		return null;

	let ifname = ctx.config.Name;
	if (!ifname)
		return {
			...ctx.config,
			Status: 'Down',
			ConnectionStatus: 'Unconfigured',
			LastConnectionError: 'ERROR_NONE',
			LastChange: '0',
			CurrentMRUSize: '0'
		};
	let status = netifd_status_get(ifname);
	let ppp_dev = status?.l3_device;

	let conn_status = connection_status_map(status);
	let iface_status = conn_status == 'Connected' ? 'Up' : 'Down';

	let last_error = last_connection_error_map(ppp_error_string_get(status));

	let uptime = '0';
	if (status?.uptime != null)
		uptime = sprintf('%d', status.uptime);

	let current_mru = '0';
	if (ppp_dev)
		current_mru = ubbf.readfile_trim(`/sys/class/net/${ppp_dev}/mtu`, '0');

	return {
		...ctx.config,
		Name: ppp_dev ?? ifname,
		Status: iface_status,
		ConnectionStatus: conn_status,
		LastConnectionError: last_error,
		LastChange: uptime,
		CurrentMRUSize: current_mru
	};
}

/**
 * Get handler for Device.PPP.Interface.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} PPP interface statistics
 */
function interface_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	let ppp_dev = ppp_device_get(parent.Name);
	if (!ppp_dev)
		return null;

	return ifstats_get(ppp_dev);
}

/**
 * Sync operation handler for PPP.Interface.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function interface_stats_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface = root?.Device?.PPP?.Interface?.['' + idx];
	if (!iface?.Name)
		return null;

	let ppp_dev = ppp_device_get(iface.Name);
	if (!ppp_dev)
		return null;

	if (!ifstats_reset(ppp_dev))
		return null;
	return {};
}

/**
 * Sync operation handler for PPP.Interface.{i}.Reset().
 * Tears down and re-establishes the PPP connection via netifd.
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @param {object} root - Root config data
 * @returns {object|null} Empty object on success, null on failure
 */
function interface_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let iface = root?.Device?.PPP?.Interface?.['' + idx];
	if (!iface?.Name)
		return null;

	let name = iface.Name;
	ubus.call('network.interface.' + name, 'down', {});
	ubus.call('network.interface.' + name, 'up', {});

	return {};
}

/**
 * Get handler for Device.PPP.Interface.{i}.PPPoE.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} PPPoE properties with session ID
 */
function pppoe_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return {
			...ubbf.ctx_config(ctx),
			SessionID: '0'
		};

	let session_id = '0';
	let lower_dev = netifd_status_get(parent.Name)?.device;
	let content = lower_dev ? ubbf.readfile_trim('/proc/net/pppoe') : null;
	if (content) {
		// rows: "<hex session id> <peer MAC> <underlying device>"; pick
		// the row for this interface's lower device, not the first one
		let lines = split(content, '\n');
		for (let i = 1; i < length(lines); i++) {
			let parts = filter(split(trim(lines[i]), /[ \t]+/), p => p != '');
			if (length(parts) < 3 || parts[2] != lower_dev)
				continue;
			let num = hex(parts[0]);
			if (num != null)
				session_id = sprintf('%d', num);
			break;
		}
	}

	return {
		...ubbf.ctx_config(ctx),
		SessionID: session_id
	};
}

/**
 * Get handler for Device.PPP.Interface.{i}.IPCP.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} IPCP properties with IP addresses and DNS
 */
function ipcp_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	let ifname = parent.Name;
	let status = netifd_status_get(ifname);

	let local_ip = '';
	let remote_ip = '';
	let dns_servers = '';

	if (status) {
		let ipv4_addrs = status['ipv4-address'];
		if (type(ipv4_addrs) == 'array' && length(ipv4_addrs) > 0) {
			local_ip = ipv4_addrs[0].address ?? '';
			remote_ip = ipv4_addrs[0].ptpaddress ?? '';
		}

		if (remote_ip == '') {
			let routes = status.route;
			if (type(routes) == 'array' && length(routes) > 0)
				remote_ip = routes[0].nexthop ?? '';
		}

		let dns_list = status['dns-server'];
		if (type(dns_list) == 'array')
			dns_servers = join(',', dns_list);
	}

	return {
		LocalIPAddress: local_ip,
		RemoteIPAddress: remote_ip,
		DNSServers: dns_servers
	};
}

/**
 * Gets the first link-local IPv6 address for a network device.
 *
 * @param {string} dev - Network device name (e.g., ppp0)
 * @returns {string|null} Link-local IPv6 address or null
 */
function dev_link_local_get(dev) {
	let addrs = link_local_addresses_get(dev);
	return length(addrs) > 0 ? addrs[0].address : null;
}

/**
 * Gets the remote link-local IPv6 address on a PPP device via rtnl.
 * On PPP links, pppd creates fe80::/128 host routes for both local and
 * remote interface identifiers. The remote is the one that doesn't match
 * the local link-local address.
 *
 * @param {string} dev - Network device name (e.g., pppoe-eth0_7)
 * @param {string} local_ll - Local link-local address to exclude
 * @returns {string|null} Remote link-local IPv6 address or null
 */
function dev_remote_link_local_get(dev, local_ll) {
	let routes = rtnl.request(rtnl.const.RTM_GETROUTE, rtnl.const.NLM_F_DUMP, {
		family: rtnl.const.AF_INET6
	});

	if (type(routes) != 'array')
		return null;

	for (let route in routes) {
		if (route.oif != dev)
			continue;

		let m = match(route.dst, /^(fe80:[0-9a-f:]+)\/128$/);
		if (!m || m[1] == local_ll)
			continue;

		return m[1];
	}

	return null;
}

/**
 * Get handler for Device.PPP.Interface.{i}.IPv6CP.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} IPv6CP properties with interface identifiers
 */
function ipv6cp_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	if (parent.IPv6CPEnable != 'true')
		return {
			LocalInterfaceIdentifier: '',
			RemoteInterfaceIdentifier: ''
		};

	let ifname = parent.Name;
	let status = netifd_status_get(ifname);

	let local_id = '';
	let remote_id = '';

	if (status) {
		let ppp_dev = status.l3_device;
		if (ppp_dev) {
			local_id = dev_link_local_get(ppp_dev) ?? '';
			remote_id = dev_remote_link_local_get(ppp_dev, local_id) ?? status.data?.llremote ?? '';
		}
	}

	return {
		LocalInterfaceIdentifier: local_id,
		RemoteInterfaceIdentifier: remote_id
	};
}

/**
 * Fetches passthrough status for one LANInterface ref from the
 * pppoe-relay daemon (uncached).
 *
 * @param {string} lan_ref - TR-181 reference identifying the passthrough instance
 * @returns {object|null} Daemon status payload or null
 */
function passthrough_status_fetch(lan_ref) {
	if (!lan_ref || lan_ref == '')
		return null;
	return ubus.call('pppoe-relay', 'status', { lan_interface: lan_ref });
}

/**
 * Fetches the active session list from the pppoe-relay daemon. Pass
 * an empty lan_ref to get sessions across every relay instance (the
 * common case: one PPP interface drives the relay, so we don't bother
 * filtering by LAN ref at the TR-181 handler layer).
 *
 * @param {string} lan_ref - TR-181 reference, or '' for all
 * @returns {array} Session list, empty array on miss
 */
function passthrough_sessions_fetch(lan_ref) {
	let result = ubus.call('pppoe-relay', 'sessions',
		{ lan_interface: lan_ref ?? '' });
	return result?.sessions ?? [];
}

/**
 * Maps a daemon session entry to a TR-181 Session.{i} row.
 *
 * @param {object} s - Daemon session payload
 * @returns {object} TR-181 Session row
 */
function session_to_object(s) {
	return {
		Alias: ubbf.alias_from_mac(s.client_mac ?? ''),
		ClientMACAddress: s.client_mac ?? '',
		SessionID: sprintf('%d', s.session_id ?? 0),
		StartTime: datetime_format(s.start_time ?? 0),
		LastActivityTime: datetime_format(s.last_activity ?? 0)
	};
}

/**
 * Get handler for Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.
 *
 * @param {object} ctx - Context with config (Enable, MaxSessions, LANInterface)
 * @returns {object} Passthrough properties with live session count
 */
function passthrough_get(ctx) {
	let lan_ref = ctx.config?.LANInterface ?? '';
	let status = cache.call(passthrough_status_fetch, lan_ref);
	let count = status?.session_count ?? 0;

	return {
		...ubbf.ctx_config(ctx),
		SessionNumberOfEntries: sprintf('%d', count)
	};
}

/**
 * Get handler for Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.Session.{i}.
 *
 * Queries the pppoe-relay daemon with an empty lan_interface filter so
 * the response covers every active session (the daemon currently
 * supports one instance per box; the filter would only matter on a
 * future multi-LAN deployment). ctx.parent is unreliable at this nesting
 * depth.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} Single session row, enumerated rows, or null
 */
function session_get(ctx) {
	let sessions = cache.call(passthrough_sessions_fetch, '');

	if (ctx.instance == null)
		return ubbf.enumerate_instances(sessions, session_to_object);

	let s = ubbf.get_by_instance(sessions, ctx.instance);
	if (!s)
		return null;
	return session_to_object(s);
}

/**
 * Name callback for Device.PPP.Interface.{i}.
 *
 * @param {object} inst - Instance data
 * @param {object} root - Root config data
 * @returns {string|null} Sanitised lower-layer device name
 */
function interface_name(inst, root) {
	let dev = ubbf.lower_layer_resolve(root, inst.LowerLayers);
	if (!dev)
		return null;
	return replace(dev, /[^a-zA-Z0-9_]/g, '_');
}

/**
 * Get handler for Device.PPP.
 *
 * @param {object} ctx - Context with config
 * @returns {object} PPP properties with instance counts
 */
function ppp_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Interface))
	};
}

export const model = {
	'Device.PPP': {
		schema: schemas.PPP,
		get: ppp_get
	},

	'Device.PPP.Interface': {
	},

	'Device.PPP.Interface.{i}': {
		schema: schemas.Interface,
		get: interface_get,
		name: interface_name
	},

	'Device.PPP.Interface.{i}.PPPoE': {
		schema: schemas.Interface_PPPoE,
		get: pppoe_get
	},

	'Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough': {
		schema: schemas.Interface_PPPoE_X_UBBF_Passthrough,
		get: passthrough_get
	},

	'Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.Session': {
	},

	'Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough.Session.{i}': {
		schema: schemas.Interface_PPPoE_X_UBBF_Passthrough_Session,
		get: session_get
	},

	'Device.PPP.Interface.{i}.IPCP': {
		schema: schemas.Interface_IPCP,
		get: ipcp_get
	},

	'Device.PPP.Interface.{i}.IPv6CP': {
		schema: schemas.Interface_IPv6CP,
		get: ipv6cp_get
	},

	'Device.PPP.Interface.{i}.Stats': {
		schema: schemas.Interface_Stats,
		get: interface_stats_get
	}
};

export const operations = {
	'Device.PPP.Interface.{i}.Reset()': {
		type: 'sync',
		handler: interface_reset
	},

	'Device.PPP.Interface.{i}.Stats.Reset()': {
		type: 'sync',
		handler: interface_stats_reset
	}
};
