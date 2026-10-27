'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import * as cache from 'ubbf.utils.cache';
import { interface_resolve } from 'ubbf.utils.path';
import { upstream_interface_ref } from 'ubbf.utils.helpers';
import { last_changed_get } from 'ubbf.utils.uci_change_track';
import { chain_rule_unsupported } from 'ubbf.utils.firewall';
import { log_err } from 'ubbf.utils.logging';
import { modules_registered } from 'ubbf.utils.modules';
import { refs_intervals, intervals_active, week_seconds } from 'ubbf.utils.schedule';
import { instance_items, instance_floor, instance_lookup } from 'ubbf.utils.instance-map';

const CONFIG_PATH = '/etc/ubbf/config.json';

// UPnP pinholes live in upnpd, not in the configuration. The instance map
// numbers them by the pinhole id of upnpd, which survives a restart of the
// daemon and is never given again, after the stored rows.
const PINHOLE_TABLE = 'Device.Firewall.Pinhole';

// The parameters whose write can make a Chain.Rule unsupported, for each
// reason chain_rule_unsupported() gives.
const CHAIN_RULE_UNSUPPORTED_BY = {
	ConnectionState: [ 'ConnectionState' ],
	Target: [ 'Target' ],
	MatchSet: [ 'SourceMatchSet', 'SourceMatchSetExclude', 'DestMatchSet', 'DestMatchSetExclude' ],
	ProtocolExclude: [ 'ProtocolExclude', 'Protocol', 'SourcePort', 'DestPort' ]
};

/**
 * Returns the timestamp of the last firewall configuration change as
 * an ISO 8601 string. Source of truth is the per-UCI-file state
 * written by the apply pipeline (`/tmp/ubbf/uci-last-changed.json`):
 * after each apply, the rendered UCI is hashed and a fresh timestamp
 * is recorded only when the bytes actually changed. This is per-domain
 * and survives no-net-change toggles like Enable=false then Enable=true.
 *
 * Falls back to the persisted config.json mtime before the first apply
 * after boot has populated state, and to the TR-181 sentinel when
 * neither source is available.
 *
 * @returns {string} ISO 8601 timestamp, or '0001-01-01T00:00:00Z' when unknown
 */
function last_change_get() {
	let ts = last_changed_get('firewall');
	if (ts)
		return ts;

	let st = fs.stat(CONFIG_PATH);
	if (st)
		return ubbf.iso8601_format(st.mtime);

	return '0001-01-01T00:00:00Z';
}

/**
 * Get handler for Device.Firewall.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Firewall properties with instance counts
 */
function firewall_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		LastChange: last_change_get(),
		LevelNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Level)),
		ChainNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Chain)),
		DMZNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.DMZ)),
		ServiceNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Service)),
		PinholeNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Pinhole)),
		PolicyNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Policy)),
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting)),
		SetNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Set))
	};
}

/**
 * Validates that a string parses as either an IPv4 or IPv6 address.
 * Used by Status derivation handlers that must distinguish a malformed
 * address (Status=Error_Misconfigured) from a missing one (Status=Disabled).
 *
 * @param {string} s - candidate address string
 * @returns {boolean} true when s is a structurally valid IPv4 or IPv6 address
 */
function valid_ip_address(s) {
	if (!s || s == '')
		return false;

	return iptoarr(s) != null;
}

/**
 * Get handler for Device.Firewall.Service.{i}.
 *
 * Replaces the default enable_status_derive so an enabled Service whose
 * Interface reference is missing or unresolvable surfaces as
 * Status=Error_Misconfigured rather than Enabled. The renderer's
 * firewall-services.uc silently skips such entries (no UCI rule is emitted),
 * so the previous Enabled was a contract lie.
 *
 * @param {object} ctx - handler context with config / root / instance
 * @returns {object|null} Service instance with Status derived
 */
function service_get(ctx) {
	if (!ctx.config)
		return null;

	let cfg = { ...ubbf.schema_defaults('Firewall.Service'), ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	if (!cfg.Interface || cfg.Interface == '' ||
	    !interface_resolve(ctx.root, cfg.Interface))
		return { ...cfg, Status: 'Error_Misconfigured' };

	return { ...cfg, Status: 'Enabled' };
}

/**
 * Get handler for Device.Firewall.Chain.{i}.Rule.{i}. An enabled rule
 * that the renderer cannot express, and so does not emit, reports
 * Error_Misconfigured.
 *
 * @param {object} ctx - handler context with config
 * @returns {object|null} Rule instance with Status derived
 */
function chain_rule_get(ctx) {
	if (!ctx.config)
		return null;

	let cfg = { ...ubbf.schema_defaults('Firewall.Chain_Rule'), ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	return { ...cfg, Status: chain_rule_unsupported(cfg, ctx.root) ? 'Error_Misconfigured' : 'Enabled' };
}

/**
 * Set handler for Device.Firewall.Chain.{i}.Rule.{i}: refuses the values
 * that fw4 cannot express (see chain_rule_unsupported()).
 *
 * @param {object} ctx - Context with param, value and config
 * @returns {number} 0 on success, a negative USP error code to refuse
 */
function chain_rule_set(ctx) {
	let reason = chain_rule_unsupported(ctx.config);

	if (!reason || index(CHAIN_RULE_UNSUPPORTED_BY[reason], ctx.param) < 0)
		return 0;

	log_err('Firewall rule: %s=%s cannot be rendered (%s)', ctx.param, ctx.value, reason);
	return -USP_ERR_INVALID_VALUE;
}

/**
 * Fetches the pinholes UPnP clients created.
 *
 * @returns {array} Pinhole rows from upnpd, empty when it is not running
 */
function upnp_pinholes_fetch() {
	return ubus.call({ object: 'upnpd', method: 'pinholes', data: {} })?.pinholes ?? [];
}

/**
 * Converts an upnpd pinhole row to a Device.Firewall.Pinhole instance.
 *
 * @param {object} p - upnpd pinhole row
 * @param {string} iface_ref - Upstream Device.IP.Interface path
 * @returns {object} Pinhole instance
 */
function upnp_pinhole_to_object(p, iface_ref) {
	return {
		...ubbf.schema_defaults('Firewall.Pinhole'),
		Alias: sprintf('cpe-upnp-ph-%d', p.id),
		Enable: 'true',
		Status: 'Enabled',
		Origin: 'UPnP',
		Description: sprintf('UPnP pinhole %d', p.unique_id),
		Interface: iface_ref ?? '',
		LeaseDuration: sprintf('%d', p.lease_time ?? 0),
		RemainingLeaseTime: sprintf('%d', p.remaining ?? 0),
		SourcePort: p.remote_port ? sprintf('%d', p.remote_port) : '-1',
		DestPort: sprintf('%d', p.internal_port),
		IPVersion: '6',
		Protocol: sprintf('%d', p.protocol),
		SourcePrefixes: p.remote_host ?? '',
		DestIP: p.internal_client ?? ''
	};
}

/**
 * Rows without configuration are the UPnP pinholes, numbered by the
 * instance map after the stored rows.
 *
 * @param {object} ctx - Handler context
 * @returns {object|null} One instance, or the UPnP rows in enumerate mode
 */
function upnp_pinholes_get(ctx) {
	let pinholes = instance_items(PINHOLE_TABLE, cache.call(upnp_pinholes_fetch),
		(p) => sprintf('%d', p.id), instance_floor(ctx.root?.Device?.Firewall?.Pinhole));
	let iface_ref = upstream_interface_ref(ctx.root);

	if (ctx.instance) {
		let p = pinholes[sprintf('%d', ctx.instance)];
		return p ? upnp_pinhole_to_object(p, iface_ref) : null;
	}

	let rows = {};

	for (let n, p in pinholes)
		rows[n] = upnp_pinhole_to_object(p, iface_ref);

	return rows;
}

/**
 * Del handler for Device.Firewall.Pinhole.{i}: a UPnP row is removed in
 * upnpd, which also drops its firewall rule.
 *
 * @param {object} ctx - { path, instance }
 * @returns {boolean} True when the row was a UPnP pinhole and is gone
 */
function pinhole_del(ctx) {
	let id = instance_lookup(PINHOLE_TABLE, ctx.instance);
	if (id == null)
		return false;

	let res = ubus.call({
		object: 'upnpd',
		method: 'delete_pinhole',
		data: { id: +id }
	});

	cache.invalidate(upnp_pinholes_fetch);

	return res != null && !res.error;
}

/**
 * Get handler for Device.Firewall.Pinhole.{i}.
 *
 * TR-181 makes an enabled pinhole inoperable unless exactly one of DestIP
 * and DestMACAddress is set and Interface resolves; firewall-pinholes.uc
 * emits no rule for such an entry. A scheduled pinhole is Inactive outside
 * the windows of its ScheduleRef.
 *
 * @param {object} ctx - handler context with config / root / instance
 * @returns {object|null} Pinhole instance with Status derived
 */
function pinhole_get(ctx) {
	if (!ctx.config)
		return upnp_pinholes_get(ctx);

	let cfg = { ...ubbf.schema_defaults('Firewall.Pinhole'), ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	let has_ip = (cfg.DestIP ?? '') != '';
	let has_mac = (cfg.DestMACAddress ?? '') != '';
	if (has_ip == has_mac)
		return { ...cfg, Status: 'Error_Misconfigured' };

	if (!cfg.Interface || cfg.Interface == '' ||
	    !interface_resolve(ctx.root, cfg.Interface))
		return { ...cfg, Status: 'Error_Misconfigured' };

	let iv = modules_registered.schedules ? refs_intervals(ctx.root, cfg.ScheduleRef) : null;
	if (iv != null && !intervals_active(iv, week_seconds(localtime(time()))))
		return { ...cfg, Status: 'Inactive' };

	return { ...cfg, Status: 'Enabled' };
}

/**
 * Get handler for Device.Firewall.DMZ.{i}.
 *
 * Replaces the default enable_status_derive with explicit validation:
 *  - DestIP must parse as a valid IPv4 or IPv6 address.
 *  - Interface must resolve to a netifd-known device.
 *  - At most one DMZ may be active per Interface; later instances
 *    (by instance number) on the same Interface report
 *    Status=Error_Misconfigured to surface the conflict.
 *
 * @param {object} ctx - handler context with config / root / instance
 * @returns {object|null} DMZ instance with Status derived
 */
function dmz_get(ctx) {
	if (!ctx.config)
		return null;

	let cfg = { ...ubbf.schema_defaults('Firewall.DMZ'), ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	if (!valid_ip_address(cfg.DestIP))
		return { ...cfg, Status: 'Error_Misconfigured' };

	if (!cfg.Interface || cfg.Interface == '' ||
	    !interface_resolve(ctx.root, cfg.Interface))
		return { ...cfg, Status: 'Error_Misconfigured' };

	let dmzs = ctx.root?.Device?.Firewall?.DMZ;
	if (dmzs) {
		let smallest = null;
		for (let inst, data in dmzs) {
			if (!ubbf.to_bool(data?.Enable))
				continue;
			if (data?.Interface != cfg.Interface)
				continue;
			let n = +inst;
			if (smallest == null || n < smallest)
				smallest = n;
		}
		if (smallest != null && smallest != ctx.instance)
			return { ...cfg, Status: 'Error_Misconfigured' };
	}

	return { ...cfg, Status: 'Enabled' };
}

export const model = {
	'Device.Firewall': {
		schema: 'Firewall.Firewall',
		get: firewall_get
	},

	'Device.Firewall.Level': {
	},

	'Device.Firewall.Level.{i}': {
		schema: 'Firewall.Level'
	},

	'Device.Firewall.Chain': {
	},

	'Device.Firewall.Chain.{i}': {
		schema: 'Firewall.Chain'
	},

	'Device.Firewall.Chain.{i}.Rule': {
	},

	'Device.Firewall.Chain.{i}.Rule.{i}': {
		schema: 'Firewall.Chain_Rule',
		get: chain_rule_get,
		set: chain_rule_set
	},

	'Device.Firewall.Set': {
	},

	'Device.Firewall.Set.{i}': {
		schema: 'Firewall.Set'
	},

	'Device.Firewall.Set.{i}.Rule': {
	},

	'Device.Firewall.Set.{i}.Rule.{i}': {
		schema: 'Firewall.Set_Rule'
	},

	'Device.Firewall.DMZ': {
	},

	'Device.Firewall.DMZ.{i}': {
		schema: 'Firewall.DMZ',
		get: dmz_get
	},

	'Device.Firewall.Service': {
	},

	'Device.Firewall.Service.{i}': {
		schema: 'Firewall.Service',
		get: service_get
	},

	'Device.Firewall.Pinhole': {
	},

	'Device.Firewall.Pinhole.{i}': {
		schema: 'Firewall.Pinhole',
		get: pinhole_get,
		del: pinhole_del,
		runtime_instances: true
	},

	'Device.Firewall.Policy': {
	},

	'Device.Firewall.Policy.{i}': {
		schema: 'Firewall.Policy',
		enable_status_derive: true
	},

	'Device.Firewall.InterfaceSetting': {
	},

	'Device.Firewall.InterfaceSetting.{i}': {
		schema: 'Firewall.InterfaceSetting',
		enable_status_derive: true
	},

	'Device.Firewall.X_UBBF_DoSProtection': {
		schema: 'Firewall.X_UBBF_DoSProtection'
	},

	'Device.Firewall.ConnectionTracking': {
	},

	'Device.Firewall.ConnectionTracking.SIP': {
		schema: 'Firewall.ConnectionTracking_SIP'
	},

	'Device.Firewall.ConnectionTracking.FTP': {
		schema: 'Firewall.ConnectionTracking_FTP'
	},

	'Device.Firewall.ConnectionTracking.H323': {
		schema: 'Firewall.ConnectionTracking_H323'
	},

	'Device.Firewall.ConnectionTracking.PPTP': {
		schema: 'Firewall.ConnectionTracking_PPTP'
	},

	'Device.Firewall.ConnectionTracking.TFTP': {
		schema: 'Firewall.ConnectionTracking_TFTP'
	},

	'Device.Firewall.ConnectionTracking.IRC': {
		schema: 'Firewall.ConnectionTracking_IRC'
	}
};
