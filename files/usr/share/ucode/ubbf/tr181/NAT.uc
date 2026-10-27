'use strict';

import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import * as cache from 'ubbf.utils.cache';
import { upstream_interface_ref, text_clamp } from 'ubbf.utils.helpers';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { ipv6_prefix_rows } from 'ubbf.utils.ipv6';
import { nptv6_setting_check, prefix6_parse, prefix6_contains } from 'ubbf.utils.nptv6';
import { instance_items, instance_floor, instance_lookup } from 'ubbf.utils.instance-map';

// UPnP mappings live in upnpd, not in the configuration. The instance map
// numbers them by the mapping id of upnpd, which survives a restart of the
// daemon and is never given again, after the stored rows.
const PORT_MAPPING_TABLE = 'Device.NAT.PortMapping';

/**
 * Get handler for Device.NAT.
 *
 * @param {object} ctx - Context with config
 * @returns {object} NAT properties with instance counts
 */
function nat_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting)),
		PortMappingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.PortMapping)),
		X_UBBF_ActiveSessions: sprintf('%d',
			ubbf.readfile_int('/proc/sys/net/netfilter/nf_conntrack_count', 0))
	};
}

/**
 * Fetches the mappings UPnP clients created.
 *
 * @returns {array} Mapping rows from upnpd, empty when it is not running
 */
function upnp_mappings_fetch() {
	return ubus.call({ object: 'upnpd', method: 'mappings', data: {} })?.mappings ?? [];
}

/**
 * Converts an upnpd mapping row to a Device.NAT.PortMapping instance.
 *
 * @param {object} m - upnpd mapping row
 * @param {string} iface_ref - Upstream Device.IP.Interface path
 * @returns {object} PortMapping instance
 */
function upnp_mapping_to_object(m, iface_ref) {
	return {
		...ubbf.schema_defaults('NAT.PortMapping'),
		Enable: 'true',
		Status: 'Enabled',
		Alias: sprintf('cpe-upnp-%d', m.id),
		Interface: iface_ref ?? '',
		AllInterfaces: 'false',
		LeaseDuration: sprintf('%d', m.lease_duration ?? 0),
		RemainingLeaseTime: sprintf('%d', m.remaining ?? 0),
		RemoteHost: m.remote_host ?? '',
		ExternalPort: sprintf('%d', m.external_port),
		ExternalPortEndRange: sprintf('%d', m.external_port),
		InternalPort: sprintf('%d', m.internal_port),
		Protocol: m.protocol ?? '',
		InternalClient: m.internal_client ?? '',
		Description: text_clamp(m.description, 256),
		Origin: 'UPnP'
	};
}

/**
 * Get handler for Device.NAT.PortMapping.{i}.
 *
 * Persisted rows come back with their configuration; rows without
 * configuration are the UPnP mappings, numbered by the instance map after
 * the stored rows.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One instance, or the UPnP rows in enumerate mode
 */
function port_mapping_get(ctx) {
	if (ctx.config) {
		return {
			...ubbf.ctx_config(ctx),
			Origin: ctx.config.Origin ?? 'Controller',
			RemainingLeaseTime: '0',
			Status: ubbf.to_bool(ctx.config.Enable) ? 'Enabled' : 'Disabled'
		};
	}

	let mappings = instance_items(PORT_MAPPING_TABLE, cache.call(upnp_mappings_fetch),
		(m) => sprintf('%d', m.id), instance_floor(ctx.root?.Device?.NAT?.PortMapping));
	let iface_ref = upstream_interface_ref(ctx.root);

	if (ctx.instance) {
		let m = mappings[sprintf('%d', ctx.instance)];
		return m ? upnp_mapping_to_object(m, iface_ref) : null;
	}

	let rows = {};

	for (let n, m in mappings)
		rows[n] = upnp_mapping_to_object(m, iface_ref);

	return rows;
}

/**
 * Del handler for Device.NAT.PortMapping.{i}: a UPnP row is removed in
 * upnpd, which also drops its firewall rule.
 *
 * @param {object} ctx - { path, instance }
 * @returns {boolean} True when the row was a UPnP mapping and is gone
 */
function port_mapping_del(ctx) {
	let id = instance_lookup(PORT_MAPPING_TABLE, ctx.instance);
	if (id == null)
		return false;

	let res = ubus.call({
		object: 'upnpd',
		method: 'delete_mapping',
		data: { id: +id }
	});

	cache.invalidate(upnp_mappings_fetch);

	return res != null && !res.error;
}

/**
 * Canonicalises a MAC string to lower-case colon form. Accepts either
 * case on input and either separator (colon or dash). Returns the
 * original string when the input is not a recognisable MAC; the renderer
 * decides whether to act on it.
 *
 * @param {string} mac - candidate MAC string
 * @returns {string} canonical form, or the original on failure
 */
function mac_canonical(mac) {
	if (type(mac) != 'string' || mac == '')
		return mac;
	let lc_mac = lc(mac);
	let normalised = replace(lc_mac, '-', ':', true);
	if (match(normalised, /^[0-9a-f]{2}(:[0-9a-f]{2}){5}$/))
		return normalised;
	return mac;
}

/**
 * Maps the admzd daemon's internal state to the TR-181 Status enum.
 *
 * Daemon -> TR-181:
 *   DISABLED -> Disabled
 *   NO_MAC   -> Enabled_NoMAC
 *   ARMED    -> Enabled_NoWANIP
 *   ACTIVE   -> Enabled_Active
 *
 * @param {string} daemon_state - daemon state string
 * @returns {string} TR-181 Status enum
 */
function status_from_daemon(daemon_state) {
	if (daemon_state == 'DISABLED')
		return 'Disabled';
	if (daemon_state == 'NO_MAC')
		return 'Enabled_NoMAC';
	if (daemon_state == 'ARMED')
		return 'Enabled_NoWANIP';
	if (daemon_state == 'ACTIVE')
		return 'Enabled_Active';
	return 'Error';
}

/**
 * Get handler for Device.NAT.X_UBBF_IPPassthrough. The renderer holds
 * the freshest INTENT (Enable, AdvancedDMZhost) in ctx.config; admzd
 * holds the actual KERNEL state. The two can diverge briefly during a
 * config-change transition (procd's reload trigger fires only after
 * UCI commit, then admzd issues a netifd renew, then the proto handler
 * publishes the new lease, then admzd's next poll picks it up). We use
 * a hybrid:
 *
 *  - When daemon's view of Enable+MAC matches ctx.config, trust the
 *    daemon's enum directly.
 *  - Otherwise derive Status from config alone: Disabled when
 *    Enable=false, Enabled_NoMAC when MAC is empty, else
 *    Enabled_NoWANIP until the daemon catches up. The daemon converges
 *    within its 2s poll.
 *
 * @param {object} ctx - handler context with config / root
 * @returns {object} IPPassthrough instance with Status derived
 */
function ip_passthrough_get(ctx) {
	let cfg = { ...ubbf.schema_defaults('NAT.X_UBBF_IPPassthrough'), ...ctx.config };

	cfg.AdvancedDMZhost = mac_canonical(cfg.AdvancedDMZhost ?? '');

	let cfg_enable = ubbf.to_bool(cfg.Enable);
	let cfg_mac = cfg.AdvancedDMZhost ?? '';

	let status = ubus.call({ object: 'admz', method: 'status', data: {} });
	let daemon_enable = !!status?.enable;
	// compare separator- and case-insensitively so a dash-separated
	// configured MAC still matches the daemon's colon-form report
	let daemon_key = ubbf.mac_normalise(status?.mac ?? '', ':-') ?? '';
	let cfg_key = ubbf.mac_normalise(cfg_mac, ':-') ?? '';

	if (status?.state && daemon_enable == cfg_enable && daemon_key == cfg_key)
		return { ...cfg, Status: status_from_daemon(status.state) };

	if (!cfg_enable)
		return { ...cfg, Status: 'Disabled' };
	if (cfg_mac == '')
		return { ...cfg, Status: 'Enabled_NoMAC' };
	return { ...cfg, Status: 'Enabled_NoWANIP' };
}

/**
 * Get handler for Device.NAT.InterfaceSetting.{i}.
 *
 * @param {object} ctx - Handler context
 * @returns {object} InterfaceSetting instance with Status derived from Enable
 */
function interface_setting_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		Status: ubbf.to_bool(ctx.config?.Enable) ? 'Enabled' : 'Disabled'
	};
}

/**
 * Lists the prefixes of the IPv6Prefix table of an interface: the
 * configured rows and the rows that netifd and the RAs supply.
 *
 * @param {object} iface - Device.IP.Interface.{i} row
 * @returns {array} Prefix strings
 */
function interface_prefixes6(iface) {
	let list = map(values(iface?.IPv6Prefix ?? {}), (p) => p?.Prefix);

	let base = netifd_status_get(iface?.Name);
	let rows = ipv6_prefix_rows(iface?.Name, ubbf.to_bool(iface?.Upstream),
		base?.l3_device ?? base?.device);
	for (let row in rows)
		push(list, `${row.data.address}/${row.data.mask}`);

	return filter(list, (p) => p);
}

/**
 * Get handler for Device.NAT.NPTv6.InterfaceSetting.{i}.
 *
 * ExternalPrefix must be part of Interface (TR-181); else the row is
 * Error_Misconfigured.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} Row with Status
 */
function nptv6_setting_get(ctx) {
	if (!ctx.config)
		return null;

	let check = nptv6_setting_check(ctx.root, ctx.config);
	let status = check.status;

	if (status == 'Enabled') {
		let iface = ubbf.navigate_data(ctx.root, ubbf.path_to_parts(ctx.config.Interface));
		let external = prefix6_parse(ctx.config.ExternalPrefix);
		let parts = filter(map(interface_prefixes6(iface), prefix6_parse), (p) => p);

		if (!length(filter(parts, (p) => prefix6_contains(p, external))))
			status = 'Error_Misconfigured';
	}

	return { ...ubbf.ctx_config(ctx), Status: status };
}

/**
 * Get handler for Device.NAT.NPTv6.
 *
 * @param {object} ctx - Context with config
 * @returns {object} NPTv6 with the row count
 */
function nptv6_get(ctx) {
	return {
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
	};
}

export const model = {
	'Device.NAT': {
		schema: 'NAT.NAT',
		get: nat_get
	},

	'Device.NAT.InterfaceSetting': {
	},

	'Device.NAT.InterfaceSetting.{i}': {
		schema: 'NAT.InterfaceSetting',
		get: interface_setting_get
	},

	'Device.NAT.PortMapping': {
	},

	'Device.NAT.PortMapping.{i}': {
		schema: 'NAT.PortMapping',
		get: port_mapping_get,
		del: port_mapping_del,
		runtime_instances: true
	},

	'Device.NAT.NPTv6': {
		schema: 'NAT.NPTv6',
		get: nptv6_get,
		since: '2.21'
	},

	'Device.NAT.NPTv6.InterfaceSetting': {
		since: '2.21'
	},

	'Device.NAT.NPTv6.InterfaceSetting.{i}': {
		schema: 'NAT.NPTv6_InterfaceSetting',
		get: nptv6_setting_get,
		since: '2.21'
	},

	'Device.NAT.X_UBBF_Hairpinning': {
		schema: 'NAT.X_UBBF_Hairpinning'
	},

	'Device.NAT.X_UBBF_IPPassthrough': {
		schema: 'NAT.X_UBBF_IPPassthrough',
		get: ip_passthrough_get
	}
};
