'use strict';

global.topdir = '/usr/share/ucode/ubbf/render';

const modules_dir = '/usr/share/ucode/ubbf/modules';

import * as fs from 'fs';

import {
	b,
	s,
	uci_set_string,
	uci_set_boolean,
	uci_set_number,
	uci_set_raw,
	uci_delete,
	uci_list_string,
	uci_list_number,
	uci_section,
	uci_named_section,
	uci_set,
	uci_list,
	uci_comment,
	uci_secret_set,
	uci_output_masked,
	EASYMESH_SECRETS,
	ipversion_to_family,
	protocols_to_uci,
	format_ip_with_mask,
	target_to_uci,
	rule_window_set,
	redirect_emit_reflection
} from 'ubbf.render.uci_helpers';

import * as ubbf from 'ubbf';

import {
	vlan_termination_bridge_resolve,
	lower_layer_resolve_vlan,
	ip_interface_netdev,
	dns_relay_plan
} from 'ubbf.render.ubbf_helpers';

import * as services from 'ubbf.render.services';
import * as ubus from 'ubus';
import * as wifi from 'ubbf.utils.wifi';
import * as wifi_radio from 'ubbf.utils.wifi_radio';
import * as digest from 'digest';
import { log_warn, log_err } from 'ubbf';
import { device_state_set, device_state_list_add } from 'ubbf.render.helpers';
import { cursor as uci_cursor } from 'uci';
import { deviceinfo_get } from 'ubbf';
import { upstream_interface_ref, lower_layers_wifi, port_snooped } from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { static_address_states } from 'ubbf';
import { dm_visible } from 'ubbf.utils.dm-version';
import { nptv6_setting_check } from 'ubbf';
import {
	router_table_id, forwarding_policy_set, policy_resolve, source_prefix, source_tables,
	main_source_rules, source_rules, source_table_contents, prefix_intersect, MAIN_TABLE
} from 'ubbf';
import {
	chain_rule_unsupported, chain_rules_ordered, chain_rule_set_matches, firewall_set_resolve
} from 'ubbf';
import * as ssh_keys from 'ubbf.utils.ssh_keys';
import { dns_learned_row } from 'ubbf';
import { DNS_RESOLV_AUTO, DNS_RESOLV_FILTERED } from 'ubbf.utils.dns';
import { schedule_windows } from 'ubbf';
import { render_scope_effects } from 'ubbf.render.effects';
import { stp_timers_get } from 'ubbf.utils.stp';

/**
 * Builds the scope every template and module render runs in.
 *
 * @param {object} config - UBBF configuration data model
 * @param {array} output - Array the templates append UCI batch lines to
 * @param {array} logs - Array to collect log messages
 * @param {array} effects - Array the templates append device changes to
 * @returns {object} Template scope
 */
export function render_scope_build(config, output, logs, effects) {
	let render_state = {};
	let template_path = topdir + '/templates';
	let uci_secrets = [];

	// The core renders ScheduleRef itself, at the fixed place of each rule
	// in the firewall order; the module only provides Device.Schedules.
	let schedules_installed = !!fs.stat(modules_dir + '/schedules/handler.uc');

	let scope = {
		output,
		uci_secrets,
		uci_set_secret: (out, path, value) => uci_secret_set(out, uci_secrets, path, value),
		EASYMESH_SECRETS,
		b,
		s,
		uci_set_string,
		uci_set_boolean,
		uci_set_number,
		uci_set_raw,
		uci_delete,
		uci_list_string,
		uci_list_number,
		uci_section,
		uci_named_section,
		uci_set,
		uci_list,
		uci_comment,
		ipversion_to_family,
		protocols_to_uci,
		format_ip_with_mask,
		target_to_uci,
		config,
		render_state,

		ubbf,
		ubbf_get: ubbf.get,
		ubbf_instances: ubbf.instances,
		ubbf_enabled: ubbf.enabled,
		ubbf_to_bool: ubbf.to_bool,
		ubbf_to_int: ubbf.to_int,
		interface_to_name: ubbf.interface_to_name,
		lower_layer_resolve: ubbf.lower_layer_resolve,
		vlan_termination_bridge_resolve,
		lower_layer_resolve_vlan,
		ip_interface_netdev,
		dns_relay_plan,
		csv_to_list: ubbf.csv_to_list,

		services,
		ubus,
		wifi,
		wifi_radio,
		digest,
		ssh_keys,
		key_acceptable: ubbf.key_acceptable,

		log_warn,
		log_err,

		device_state_set,
		device_state_list_add,
		uci_cursor,
		deviceinfo_get,
		upstream_interface_ref,
		lower_layers_wifi,
		port_snooped,
		netifd_status_get,
		static_address_states,
		dm_visible,
		nptv6_setting_check,
		router_table_id,
		forwarding_policy_set,
		policy_resolve,
		source_prefix,
		source_tables,
		main_source_rules,
		source_rules,
		source_table_contents,
		prefix_intersect,
		MAIN_TABLE,
		redirect_emit_reflection,
		chain_rule_unsupported,
		chain_rules_ordered,
		chain_rule_set_matches,
		firewall_set_resolve,
		rule_window_set,
		dns_learned_row,
		DNS_RESOLV_AUTO,
		DNS_RESOLV_FILTERED,
		schedule_windows: (refs, inline_rows) =>
			schedule_windows(config, refs, inline_rows, schedules_installed),
		stp_timers_get,

		warn: (fmt, ...args) => push(logs, { level: 'warning', msg: sprintf(fmt, ...args) }),
		error: (fmt, ...args) => push(logs, { level: 'error', msg: sprintf(fmt, ...args) }),
		info: (fmt, ...args) => push(logs, { level: 'info', msg: sprintf(fmt, ...args) }),

		...render_scope_effects(effects)
	};

	/**
	 * Safely includes a template file with validation.
	 *
	 * @param {string} path - Relative path to template file
	 */
	scope.tryinclude = function(path) {
		if (!match(path, /^[A-Za-z0-9_\/-]+\.uc$/)) {
			scope.warn("Refusing to handle invalid include path '%s'", path);
			return;
		}

		try {
			include(template_path + "/" + path, scope);
		}
		catch (e) {
			scope.warn("Unable to include path '%s': %s\n%s", path, e,
				e?.stacktrace?.[0]?.context ?? '');
		}
	};

	return scope;
};

/**
 * Runs every template and module render in a scope, in render order.
 *
 * @param {object} scope - Scope from render_scope_build()
 */
export function templates_render(scope) {
	include('templates/firewall.uc', scope);
	include('templates/ssh.uc', scope);
	include('templates/dhcp.uc', scope);
	include('templates/time.uc', scope);
	include('templates/dns.uc', scope);
	include('templates/neighbordiscovery.uc', scope);
	include('templates/ethernet.uc', scope);
	include('templates/bridging.uc', scope);
	include('templates/ip.uc', scope);
	// admz.uc must render AFTER ip.uc because it overrides
	// network.<wan>.proto from 'dhcp' to 'admz' when ADMZ is configured.
	include('templates/admz.uc', scope);
	include('templates/deviceinfo.uc', scope);
	include('templates/cwmp.uc', scope);
	include('templates/routing.uc', scope);
	include('templates/wifi.uc', scope);
	include('templates/udpecho.uc', scope);
	include('templates/dnsprobe.uc', scope);

	// Out-of-tree modules render after the in-tree domain templates and
	// before device.uc, the one shared emitter that still has to run. A
	// module sees everything the in-tree templates computed, through the
	// shared scope and render_state, and the only thing it can still feed
	// is render_state.device, like any in-tree domain. Leaf domains need no
	// more, and one fixed slot is what keeps this free of per-module
	// ordering metadata.
	for (let path in sort(fs.glob(modules_dir + '/*/render.uc') ?? [])) {
		try {
			include(path, scope);
		}
		catch (e) {
			scope.warn("Unable to include module render '%s': %s\n%s", path, e,
				e?.stacktrace?.[0]?.context ?? '');
		}
	}

	include('templates/device.uc', scope);
};

/**
 * Generates UCI configuration from UBBF data model.
 *
 * The render changes nothing on the device: what a template must change
 * besides UCI comes back in `effects`, for `effects_run()` after the commit.
 *
 * @param {object} config - UBBF configuration data model
 * @param {array} logs - Array to collect log messages
 * @returns {object} Object with uci (string), uci_masked (the same batch with
 *                   every secret value masked), logs (array of {level, msg})
 *                   and effects (array, see render/effects.uc)
 */
export function generate(config, logs) {
	logs = logs || [];

	services.init();

	let output = [];
	let effects = [];
	let scope = render_scope_build(config, output, logs, effects);

	templates_render(scope);

	push(output, '');
	return {
		uci: join('\n', output),
		uci_masked: uci_output_masked(output, scope.uci_secrets),
		logs: logs,
		effects: effects
	};
};
