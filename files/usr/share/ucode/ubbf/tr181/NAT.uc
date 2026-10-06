'use strict';

import * as schemas from 'ubbf.schemas.NAT';
import * as ubbf from 'ubbf';
import * as ubus from 'ubus';

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
 *   ARMED    -> Enabled_NoWANIP   (MVP-2020 visibility)
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
	let cfg = { ...schemas.X_UBBF_IPPassthrough.defaults, ...ctx.config };

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

export const model = {
	'Device.NAT': {
		schema: schemas.NAT,
		get: nat_get
	},

	'Device.NAT.InterfaceSetting': {
	},

	'Device.NAT.InterfaceSetting.{i}': {
		schema: schemas.InterfaceSetting
	},

	'Device.NAT.PortMapping': {
	},

	'Device.NAT.PortMapping.{i}': {
		schema: schemas.PortMapping
	},

	'Device.NAT.X_UBBF_Hairpinning': {
		schema: schemas.X_UBBF_Hairpinning
	},

	'Device.NAT.X_UBBF_IPPassthrough': {
		schema: schemas.X_UBBF_IPPassthrough,
		get: ip_passthrough_get
	}
};
