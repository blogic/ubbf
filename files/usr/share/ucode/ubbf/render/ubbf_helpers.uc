'use strict';

import * as ubbf from 'ubbf';
import { dns_learned_row } from 'ubbf';

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

/**
 * Returns the netdev that the traffic of an IP interface uses.
 *
 * Over PPP that is the pppd link, which ppp.sh of netifd names
 * `<proto>-<interface>`, so `pppoe-<Name>` for a PPP row; the Name of the
 * row itself is the netifd interface, not a netdev.
 *
 * @param {object} config - Configuration data
 * @param {object} iface - Device.IP.Interface row
 * @returns {string|null} netdev name
 */
export function ip_interface_netdev(config, iface) {
	let lower = ubbf.csv_to_list(iface?.LowerLayers ?? '')[0] ?? '';

	if (match(lower, /^Device\.PPP\.Interface\.[0-9]+$/)) {
		let ppp = ubbf_get(config, lower);
		return ppp?.Name ? `pppoe-${ppp.Name}` : null;
	}

	return lower_layer_resolve_vlan(config, iface?.LowerLayers);
};

// The first port of the dnsmasq relay instances; the main instance keeps 53.
const DNS_RELAY_PORT_BASE = 5301;

/**
 * Returns the dnsmasq server value of a Forwarding row: the address, bound
 * to the netdev of Forwarding.Interface, over which TR-181 sends the query.
 * An empty Interface leaves the choice to the routing table.
 *
 * @param {object} config - Configuration data
 * @param {object} fwd - Device.DNS.Relay.Forwarding row
 * @returns {string|null} Server value, or null for a row that cannot forward,
 *   such as one whose Interface has no netdev
 */
function dns_forwarder_server(config, fwd) {
	if (!ubbf_to_bool(fwd?.Enable) || !fwd.DNSServer)
		return null;

	if (!fwd.Interface)
		return fwd.DNSServer;

	let iface = ubbf_get(config, rtrim(fwd.Interface, '.'));
	let netdev = iface ? ip_interface_netdev(config, iface) : null;
	return netdev ? `${fwd.DNSServer}@${netdev}` : null;
}

/**
 * Returns the servers of a Relay.Config row. An empty Forwarders list takes
 * the static rows; the learned rows reach the clients through the main
 * dnsmasq, which reads them from the resolv file of netifd.
 *
 * @param {object} config - Configuration data
 * @param {array} forwardings - Device.DNS.Relay.Forwarding rows
 * @param {object|null} cfg - Device.DNS.Relay.Config row
 * @returns {array} Server values
 */
function dns_relay_servers(config, forwardings, cfg) {
	let refs = filter(ubbf.csv_to_list(cfg?.Forwarders ?? ''),
		(ref) => match(ref, /^Device\.DNS\.Relay\.Forwarding\.[0-9]+\.?$/));

	let rows = length(refs)
		? map(refs, (ref) => ubbf_get(config, rtrim(ref, '.')))
		: filter(forwardings, (fwd) => !dns_learned_row(fwd));

	return uniq(filter(map(rows, (fwd) => dns_forwarder_server(config, fwd)), (s) => s != null));
}

/**
 * Lists the Name of each downstream IP interface.
 *
 * @param {object} config - Configuration data
 * @returns {array} netifd interface names
 */
function downstream_interfaces(config) {
	let names = [];
	for (let iface in ubbf.instances(config, 'Device.IP.Interface'))
		if (iface.Name && !ubbf_to_bool(iface.Upstream))
			push(names, iface.Name);
	return names;
}

/**
 * Works out the dnsmasq relay instances of Device.DNS.Relay.
 *
 * A Relay.Config row serves the queries that arrive on its Interface; an
 * empty Interface serves every downstream interface that no other row
 * names. Without Relay.Config rows, every downstream interface uses the
 * static forwarders. An interface without a server gets no instance.
 *
 * @param {object} config - Configuration data
 * @returns {object} Interface name to `{ name, port, servers, config }`,
 *   where config is the Relay.Config row or null
 */
export function dns_relay_plan(config) {
	let plan = {};
	if (!ubbf_to_bool(ubbf_get(config, 'Device.DNS.Relay')?.Enable))
		return plan;

	let forwardings = ubbf.instances(config, 'Device.DNS.Relay.Forwarding');
	let configs = ubbf.instances(config, 'Device.DNS.Relay.Config');
	let wanted = {};

	for (let cfg in configs) {
		let name = cfg.Interface ? ubbf.interface_to_name(config, cfg.Interface) : null;
		if (name && !(name in wanted))
			wanted[name] = cfg;
	}

	for (let cfg in configs) {
		if (cfg.Interface)
			continue;
		for (let name in downstream_interfaces(config))
			if (!(name in wanted))
				wanted[name] = cfg;
	}

	if (!length(configs))
		for (let name in downstream_interfaces(config))
			wanted[name] = null;

	let port = DNS_RELAY_PORT_BASE;
	for (let name, cfg in wanted) {
		let servers = dns_relay_servers(config, forwardings, cfg);
		if (!length(servers))
			continue;

		plan[name] = { name: `dns_relay_${name}`, port: port++, servers, config: cfg };
	}

	return plan;
};
