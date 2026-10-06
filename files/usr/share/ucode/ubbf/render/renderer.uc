'use strict';

global.topdir = '/usr/share/ucode/ubbf/render';

const modules_dir = '/usr/share/ucode/ubbf/modules';

import * as fs from 'fs';
global.fs = fs;

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
	ipversion_to_family,
	format_ip_with_mask,
	target_to_uci
} from 'ubbf.render.uci_helpers';

import * as ubbf from 'ubbf';

import {
	vlan_termination_bridge_resolve,
	lower_layer_resolve_vlan
} from 'ubbf.render.ubbf_helpers';

import * as services from 'ubbf.render.services';
import * as ubus from 'ubus';
import * as wifi from 'ubbf.utils.wifi';
import * as digest from 'digest';
import { log_warn, log_err } from 'ubbf.utils.logging';
import { device_state_set, device_state_list_add } from 'ubbf.render.helpers';
import { cursor as uci_cursor } from 'uci';
import { deviceinfo_get } from 'ubbf.utils.deviceinfo';
import { certificate_path_resolve, cabundle_path_resolve } from 'ubbf.tr181.Security';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { redirect_emit_reflection } from 'ubbf.utils.firewall';
import * as ssh_keys from 'ubbf.utils.ssh_keys';

/**
 * Generates UCI configuration from UBBF data model.
 *
 * @param {object} config - UBBF configuration data model
 * @param {array} logs - Array to collect log messages
 * @returns {object} Object with uci (string) and logs (array of {level, msg})
 */
export function generate(config, logs) {
	logs = logs || [];

	services.init();

	let render_state = {};
	let output = [];

	let template_path = topdir + '/templates';

	let scope = {
		output,
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
		csv_to_list: ubbf.csv_to_list,

		services,
		ubus,
		wifi,
		digest,
		ssh_keys,

		log_warn,
		log_err,

		device_state_set,
		device_state_list_add,
		uci_cursor,
		deviceinfo_get,
		certificate_path_resolve,
		cabundle_path_resolve,
		netifd_status_get,
		redirect_emit_reflection,

		warn: (fmt, ...args) => push(logs, { level: 'warning', msg: sprintf(fmt, ...args) }),
		error: (fmt, ...args) => push(logs, { level: 'error', msg: sprintf(fmt, ...args) }),
		info: (fmt, ...args) => push(logs, { level: 'info', msg: sprintf(fmt, ...args) })
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

	include('templates/firewall.uc', scope);
	include('templates/ssh.uc', scope);
	include('templates/dhcp.uc', scope);
	include('templates/time.uc', scope);
	include('templates/syslog.uc', scope);
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
	include('templates/umapd.uc', scope);
	include('templates/umap-director.uc', scope);
	include('templates/qos.uc', scope);
	include('templates/ppp.uc', scope);
	include('templates/userinterface.uc', scope);
	include('templates/udpecho.uc', scope);
	include('templates/containers.uc', scope);
	include('templates/bulkdata.uc', scope);
	include('templates/nlbwmon.uc', scope);
	include('templates/ddns.uc', scope);
	include('templates/pcp.uc', scope);
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

	push(output, '');
	return {
		uci: join('\n', output),
		logs: logs
	};
};
