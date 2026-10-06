'use strict';

import * as ubbf from 'ubbf';

let ubbf_get = ubbf.get;
let ubbf_to_bool = ubbf.to_bool;
let ubbf_to_int = ubbf.to_int;
let lower_layer_resolve = ubbf.lower_layer_resolve;

const VLAN_DYNAMIC_START = 4090;

/**
 * Checks if a bridge has VLAN filtering enabled.
 *
 * @param {object} config - Configuration data
 * @param {string} bridge_inst - Bridge instance number
 * @returns {boolean} True if 802.1Q VLAN filtering is enabled
 */
function bridge_vlan_filtering_enabled(config, bridge_inst) {
	let bridge = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}`);
	if (!bridge?.Standard)
		return false;
	return index(bridge.Standard, '802.1Q') >= 0;
}

/**
 * Collects explicitly configured VLAN IDs for a bridge.
 *
 * @param {object} config - Configuration data
 * @param {string} bridge_inst - Bridge instance number
 * @returns {object} Map of VID to true
 */
function bridge_collect_explicit_vids(config, bridge_inst) {
	let vids = {};
	let vlans_data = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}.VLAN`);
	if (type(vlans_data) != 'object')
		return vids;

	for (let key, vlan in vlans_data) {
		if (type(vlan) != 'object')
			continue;
		if (!ubbf_to_bool(vlan.Enable))
			continue;
		let vid = ubbf_to_int(vlan.VLANID);
		if (vid != null && vid > 0)
			vids[vid] = true;
	}

	return vids;
}

/**
 * Gets the explicit VLAN ID for a bridge port.
 *
 * @param {object} config - Configuration data
 * @param {string} bridge_inst - Bridge instance number
 * @param {string} port_inst - Port instance number
 * @returns {number|null} VLAN ID or null
 */
function bridge_port_explicit_vid(config, bridge_inst, port_inst) {
	let vlanports_data = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}.VLANPort`);
	if (type(vlanports_data) != 'object')
		return null;

	let port_path = `Device.Bridging.Bridge.${bridge_inst}.Port.${port_inst}`;

	for (let key, vp in vlanports_data) {
		if (type(vp) != 'object')
			continue;
		if (!ubbf_to_bool(vp.Enable))
			continue;
		if (vp.Port != port_path)
			continue;

		let vlan_data = ubbf_get(config, vp.VLAN);
		if (!vlan_data)
			continue;

		let vid = ubbf_to_int(vlan_data.VLANID);
		if (vid != null && vid > 0)
			return vid;
	}

	return null;
}

/**
 * Computes VLAN ID for a bridge port, handling dynamic allocation.
 *
 * @param {object} config - Configuration data
 * @param {string} bridge_inst - Bridge instance number
 * @param {string} target_port_inst - Target port instance
 * @returns {object|null} { vid, dynamic } or null
 */
function bridge_port_vid_compute(config, bridge_inst, target_port_inst) {
	let explicit_vids = bridge_collect_explicit_vids(config, bridge_inst);
	let ports_data = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
	if (type(ports_data) != 'object')
		return null;

	let port_instances = [];
	for (let key, port in ports_data) {
		if (type(port) != 'object')
			continue;
		if (!ubbf_to_bool(port.Enable))
			continue;
		push(port_instances, ubbf_to_int(key));
	}

	port_instances = sort(port_instances);
	let next_dyn_vid = VLAN_DYNAMIC_START;

	for (let port_inst in port_instances) {
		let explicit_vid = bridge_port_explicit_vid(config, bridge_inst, port_inst);

		if (explicit_vid != null) {
			if (port_inst == ubbf_to_int(target_port_inst))
				return { vid: explicit_vid, dynamic: false };
			continue;
		}

		while (next_dyn_vid > 0 && explicit_vids[next_dyn_vid])
			next_dyn_vid--;

		if (next_dyn_vid <= 0)
			return null;

		if (port_inst == ubbf_to_int(target_port_inst))
			return { vid: next_dyn_vid, dynamic: true };

		explicit_vids[next_dyn_vid] = true;
		next_dyn_vid--;
	}

	return null;
}

/**
 * Resolves a VLANTermination's lower layer to bridge context.
 *
 * When the lower layer link is a member of a VLAN-filtered bridge,
 * the VLAN device must be created on the bridge rather than on the
 * physical port (the bridge rx_handler intercepts all frames on
 * member ports before VLAN sub-interfaces can process them).
 *
 * @param {object} config - Configuration data
 * @param {string} lower_layers - VLANTermination lower layer reference
 * @returns {object|null} {bridge_name, port_name, bridge_inst} or null
 */
export function vlan_termination_bridge_resolve(config, lower_layers) {
	if (!lower_layers)
		return null;

	let first_ref = ubbf.csv_to_list(lower_layers)[0];
	if (!first_ref)
		return null;
	let port_name = lower_layer_resolve(config, lower_layers);
	if (!port_name)
		return null;

	let bridges = ubbf_get(config, 'Device.Bridging.Bridge');
	if (type(bridges) != 'object')
		return null;

	for (let inst, bridge in bridges) {
		if (type(bridge) != 'object' || !bridge.Name || !bridge.Port)
			continue;
		if (!bridge.Standard || index(bridge.Standard, '802.1Q') < 0)
			continue;

		for (let pinst, port in bridge.Port) {
			if (type(port) != 'object')
				continue;
			if (ubbf_to_bool(port.ManagementPort))
				continue;
			if (!ubbf_to_bool(port.Enable))
				continue;
			if (trim(port.LowerLayers) == first_ref)
				return { bridge_name: bridge.Name, port_name, bridge_inst: inst };
		}
	}

	return null;
};

/**
 * Resolves lower layer with VLAN-aware bridge port handling.
 *
 * @param {object} config - Configuration data
 * @param {string} lower_layers - Lower layer path references
 * @returns {string|null} Resolved interface name with VLAN suffix if applicable
 */
export function lower_layer_resolve_vlan(config, lower_layers) {
	if (!lower_layers || lower_layers == '')
		return null;

	let first_ref = ubbf.csv_to_list(lower_layers)[0];
	if (!first_ref)
		return null;

	if (match(first_ref, /^Device\.Ethernet\.VLANTermination\.\d+$/)) {
		let vt = ubbf_get(config, first_ref);
		if (vt) {
			let vid = int(vt.VLANID);
			let bridge_info = vid ? vlan_termination_bridge_resolve(config, vt.LowerLayers) : null;
			if (bridge_info)
				return `${bridge_info.bridge_name}v${vid}`;
		}
		return lower_layer_resolve(config, lower_layers);
	}

	let m = match(first_ref, /^Device\.Bridging\.Bridge\.(\d+)\.Port\.(\d+)$/);
	if (!m)
		return lower_layer_resolve(config, lower_layers);

	let bridge_inst = m[1];
	let port_inst = m[2];

	let port_data = ubbf_get(config, first_ref);
	if (!port_data)
		return null;

	if (!ubbf_to_bool(port_data.ManagementPort))
		return port_data.Name;

	if (!bridge_vlan_filtering_enabled(config, bridge_inst)) {
		let bridge = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}`);
		return bridge?.Name;
	}

	let info = bridge_port_vid_compute(config, bridge_inst, port_inst);
	if (info == null) {
		let bridge = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}`);
		return bridge?.Name;
	}

	let bridge = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}`);
	let suffix = info.dynamic ? '0' : info.vid;
	return bridge?.Name ? `${bridge.Name}v${suffix}` : null;
};


