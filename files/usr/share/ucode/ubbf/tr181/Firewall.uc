'use strict';

import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.Firewall';
import * as ubbf from 'ubbf';
import { interface_resolve } from 'ubbf.utils.path';
import { last_changed_get } from 'ubbf.utils.uci_change_track';

const CONFIG_PATH = '/etc/ubbf/config.json';

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
		InterfaceSettingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.InterfaceSetting))
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

	let cfg = { ...schemas.Service.defaults, ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	if (!cfg.Interface || cfg.Interface == '' ||
	    !interface_resolve(ctx.root, cfg.Interface))
		return { ...cfg, Status: 'Error_Misconfigured' };

	return { ...cfg, Status: 'Enabled' };
}

/**
 * Get handler for Device.Firewall.Pinhole.{i}.
 *
 * TR-181 makes an enabled pinhole inoperable unless exactly one of DestIP
 * and DestMACAddress is set and Interface resolves; firewall-pinholes.uc
 * emits no rule for such an entry.
 *
 * @param {object} ctx - handler context with config / root / instance
 * @returns {object|null} Pinhole instance with Status derived
 */
function pinhole_get(ctx) {
	if (!ctx.config)
		return null;

	let cfg = { ...schemas.Pinhole.defaults, ...ctx.config };

	if (!ubbf.to_bool(cfg.Enable))
		return { ...cfg, Status: 'Disabled' };

	let has_ip = (cfg.DestIP ?? '') != '';
	let has_mac = (cfg.DestMACAddress ?? '') != '';
	if (has_ip == has_mac)
		return { ...cfg, Status: 'Error_Misconfigured' };

	if (!cfg.Interface || cfg.Interface == '' ||
	    !interface_resolve(ctx.root, cfg.Interface))
		return { ...cfg, Status: 'Error_Misconfigured' };

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

	let cfg = { ...schemas.DMZ.defaults, ...ctx.config };

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
		schema: schemas.Firewall,
		get: firewall_get
	},

	'Device.Firewall.Level': {
	},

	'Device.Firewall.Level.{i}': {
		schema: schemas.Level
	},

	'Device.Firewall.Chain': {
	},

	'Device.Firewall.Chain.{i}': {
		schema: schemas.Chain
	},

	'Device.Firewall.Chain.{i}.Rule': {
	},

	'Device.Firewall.Chain.{i}.Rule.{i}': {
		schema: schemas.Chain_Rule,
		enable_status_derive: true
	},

	'Device.Firewall.DMZ': {
	},

	'Device.Firewall.DMZ.{i}': {
		schema: schemas.DMZ,
		get: dmz_get
	},

	'Device.Firewall.Service': {
	},

	'Device.Firewall.Service.{i}': {
		schema: schemas.Service,
		get: service_get
	},

	'Device.Firewall.Pinhole': {
	},

	'Device.Firewall.Pinhole.{i}': {
		schema: schemas.Pinhole,
		get: pinhole_get
	},

	'Device.Firewall.Policy': {
	},

	'Device.Firewall.Policy.{i}': {
		schema: schemas.Policy,
		enable_status_derive: true
	},

	'Device.Firewall.InterfaceSetting': {
	},

	'Device.Firewall.InterfaceSetting.{i}': {
		schema: schemas.InterfaceSetting,
		enable_status_derive: true
	},

	'Device.Firewall.X_UBBF_DoSProtection': {
		schema: schemas.X_UBBF_DoSProtection
	},

	'Device.Firewall.ConnectionTracking': {
	},

	'Device.Firewall.ConnectionTracking.SIP': {
		schema: schemas.ConnectionTracking_SIP
	},

	'Device.Firewall.ConnectionTracking.FTP': {
		schema: schemas.ConnectionTracking_FTP
	},

	'Device.Firewall.ConnectionTracking.H323': {
		schema: schemas.ConnectionTracking_H323
	},

	'Device.Firewall.ConnectionTracking.PPTP': {
		schema: schemas.ConnectionTracking_PPTP
	},

	'Device.Firewall.ConnectionTracking.TFTP': {
		schema: schemas.ConnectionTracking_TFTP
	},

	'Device.Firewall.ConnectionTracking.IRC': {
		schema: schemas.ConnectionTracking_IRC
	}
};
