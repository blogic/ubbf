function render_config() {

	const VLAN_DYNAMIC_START = 4090;

	/**
	 * Checks if bridge standard enables VLAN filtering.
	 *
	 * @param {string} standard - Bridge standard string
	 * @returns {boolean} True if 802.1Q VLAN filtering is enabled
	 */
	function standard_to_vlan_filtering(standard) {
		if (!standard)
			return false;
		return index(standard, '802.1Q') >= 0;
	}

	/**
	 * Collects explicitly configured VLAN IDs for a bridge.
	 *
	 * @param {string} bridge_inst - Bridge instance number
	 * @returns {object} Map of VID to true
	 */
	function collect_explicit_vids(bridge_inst) {
		let vids = {};
		let vlans = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.VLAN`);

		for (let vlan in vlans) {
			if (!vlan || !ubbf_to_bool(vlan.Enable))
				continue;
			let vid = ubbf_to_int(vlan.VLANID);
			if (vid != null && vid > 0)
				vids[vid] = true;
		}

		return vids;
	}

	/**
	 * Gets the explicit VLAN ID for a bridge port from VLANPort config.
	 *
	 * @param {string} bridge_inst - Bridge instance number
	 * @param {string} port_inst - Port instance number
	 * @returns {number|null} VLAN ID or null if not configured
	 */
	function port_explicit_vid_get(bridge_inst, port_inst) {
		let vlanports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.VLANPort`);
		let port_path = `Device.Bridging.Bridge.${bridge_inst}.Port.${port_inst}`;

		for (let vp in vlanports) {
			if (!vp || !ubbf_to_bool(vp.Enable))
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
	 * Computes VLAN IDs for all enabled ports on a bridge.
	 *
	 * @param {string} bridge_inst - Bridge instance number
	 * @param {boolean} vlan_filtering - Whether VLAN filtering is enabled
	 * @returns {object} Map of port instance to {vid, dynamic} info
	 */
	function compute_port_vids(bridge_inst, vlan_filtering) {
		if (!vlan_filtering)
			return {};

		let explicit_vids = collect_explicit_vids(bridge_inst);
		let port_vids = {};
		let ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
		let next_dyn_vid = VLAN_DYNAMIC_START;

		let sorted_ports = sort(ports, (a, b) => ubbf_to_int(a['.instance']) - ubbf_to_int(b['.instance']));

		for (let port in sorted_ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;

			let port_inst = port['.instance'];
			let explicit_vid = port_explicit_vid_get(bridge_inst, port_inst);

			if (explicit_vid != null) {
				port_vids[port_inst] = { vid: explicit_vid, dynamic: false };
				continue;
			}

			while (next_dyn_vid > 0 && explicit_vids[next_dyn_vid])
				next_dyn_vid--;

			if (next_dyn_vid <= 0)
				continue;

			port_vids[port_inst] = { vid: next_dyn_vid, dynamic: true };
			explicit_vids[next_dyn_vid] = true;
			next_dyn_vid--;
		}

		return port_vids;
	}

	/**
	 * Checks if a lower layer reference is a WiFi SSID.
	 *
	 * @param {string} lower_layers - Lower layers path reference
	 * @returns {boolean} True if WiFi SSID reference
	 */
	function is_wifi_link(lower_layers) {
		if (!lower_layers)
			return false;

		for (let ref in csv_to_list(lower_layers)) {
			if (!match(ref, /^Device\.WiFi\.SSID\.\d+$/))
				return false;
		}

		return true;
	}

	/**
	 * Populates render state for a bridge device with STP and port config.
	 *
	 * @param {object} bridge - Bridge data model object
	 * @param {string} bridge_inst - Bridge instance number
	 */
	function populate_bridge(bridge, bridge_inst) {
		let br_name = bridge.Name;
		if (!br_name)
			return;

		let vlan_filtering = standard_to_vlan_filtering(bridge.Standard);

		device_state_set(render_state, br_name, 'type', 'bridge');
		device_state_set(render_state, br_name, 'igmp_snooping', '1');

		let stp = ubbf_get(config, `Device.Bridging.Bridge.${bridge_inst}.STP`);
		if (stp) {
			let stp_enabled = ubbf_to_bool(stp.Enable);
			device_state_set(render_state, br_name, 'stp', stp_enabled ? '1' : '0');

			if (stp.BridgePriority && stp.BridgePriority != '')
				device_state_set(render_state, br_name, 'priority', stp.BridgePriority);
			if (stp.HelloTime && stp.HelloTime != '')
				device_state_set(render_state, br_name, 'hello_time', stp.HelloTime);
			if (stp.MaxAge && stp.MaxAge != '')
				device_state_set(render_state, br_name, 'max_age', stp.MaxAge);
			if (stp.ForwardingDelay && stp.ForwardingDelay != '')
				device_state_set(render_state, br_name, 'forward_delay', stp.ForwardingDelay);
		}

		if (!vlan_filtering) {
			let ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
			for (let port in ports) {
				if (!port || !ubbf_to_bool(port.Enable))
					continue;
				if (ubbf_to_bool(port.ManagementPort))
					continue;
				if (is_wifi_link(port.LowerLayers))
					continue;

				let port_ifname = lower_layer_resolve(config, port.LowerLayers);
				if (port_ifname)
					device_state_list_add(render_state, br_name, 'ports', port_ifname);
			}
		}

		let flood_ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
		for (let port in flood_ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;
			if (ubbf_to_bool(port.ManagementPort))
				continue;
			if (is_wifi_link(port.LowerLayers))
				continue;

			let port_ifname = lower_layer_resolve(config, port.LowerLayers);
			if (!port_ifname)
				continue;

			let unicast = port.X_UBBF_UnicastFlood;
			if (unicast != null && !ubbf_to_bool(unicast))
				device_state_set(render_state, port_ifname, 'unicast_flood', '0');

			let broadcast = port.X_UBBF_BroadcastFlood;
			if (broadcast != null && !ubbf_to_bool(broadcast))
				device_state_set(render_state, port_ifname, 'broadcast_flood', '0');
		}
	}

	/**
	 * Populates 8021q VLAN device state for management ports.
	 *
	 * @param {object} bridge - Bridge data model object
	 * @param {string} bridge_inst - Bridge instance number
	 * @param {object} port_vids - Map of port instance to VID info
	 */
	function populate_8021q_devices(bridge, bridge_inst, port_vids) {
		let br_name = bridge.Name;
		if (!br_name)
			return;

		let vlan_filtering = standard_to_vlan_filtering(bridge.Standard);
		if (!vlan_filtering)
			return;

		let ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
		for (let port in ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;
			if (!ubbf_to_bool(port.ManagementPort))
				continue;

			let port_inst = port['.instance'];
			let port_vid_info = port_vids[port_inst];
			if (!port_vid_info)
				continue;

			let vid = port_vid_info.vid;
			let suffix = port_vid_info.dynamic ? '0' : sprintf('%d', vid);
			let vlan_dev_name = `${br_name}v${suffix}`;
			let alias = 'v' + suffix;

			device_state_set(render_state, vlan_dev_name, 'type', '8021q');
			device_state_set(render_state, vlan_dev_name, 'ifname', br_name);
			device_state_set(render_state, vlan_dev_name, 'vid', alias);

			render_state.bridge ??= {};
			render_state.bridge[br_name] ??= {};
			render_state.bridge[br_name].mgmt_vlan_alias = alias;
			render_state.bridge[br_name].mgmt_vlan_suffix = suffix;
		}
	}

	/**
	 * Generates a UCI section name for a bridge VLAN.
	 *
	 * @param {string} device - Bridge device name
	 * @param {string} suffix - 8021q device name suffix (e.g. '0', '100')
	 * @returns {string} Sanitised section name
	 */
	function bridge_vlan_section_name(device, suffix) {
		let name = 'vlan_' + device + 'v' + suffix;
		return replace(name, '-', '_');
	}

	/**
	 * Checks if a lower layer reference is an Ethernet link.
	 *
	 * @param {string} lower_layers - Lower layers path reference
	 * @returns {boolean} True if Ethernet link reference
	 */
	function is_ethernet_link(lower_layers) {
		if (!lower_layers)
			return false;
		return match(lower_layers, /^Device\.Ethernet\.Link\.\d+$/) != null;
	}

	/**
	 * Generates UCI bridge-vlan sections for explicitly configured VLANs.
	 *
	 * @param {object} bridge - Bridge data model object
	 * @param {string} bridge_inst - Bridge instance number
	 * @returns {string} UCI batch output
	 */
	function generate_explicit_vlans(bridge, bridge_inst) {

		let br_name = bridge.Name;
		if (!br_name)
			return;

		let vlans = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.VLAN`);
		let vlanports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.VLANPort`);

		for (let vlan in vlans) {
			if (!vlan || !ubbf_to_bool(vlan.Enable))
				continue;

			let vid = ubbf_to_int(vlan.VLANID);
			if (vid == null || vid <= 0)
				continue;

			let section_name = bridge_vlan_section_name(br_name, sprintf('%d', vid));

			uci_named_section(output, `network.${section_name}`, 'bridge-vlan');
			uci_set_string(output, `network.${section_name}.device`, br_name);
			uci_set_number(output, `network.${section_name}.vlan`, vid);

			for (let vp in vlanports) {
				if (!vp || !ubbf_to_bool(vp.Enable))
					continue;

				let vlan_ref = vp.VLAN;
				let port_ref = vp.Port;

				if (!vlan_ref || !port_ref)
					continue;

				let vlan_data = ubbf_get(config, vlan_ref);
				if (!vlan_data || ubbf_to_int(vlan_data.VLANID) != vid)
					continue;

				let port_data = ubbf_get(config, port_ref);
				if (!port_data)
					continue;

				let port_ifname = lower_layer_resolve(config, port_data?.LowerLayers);
				if (!port_ifname)
					continue;

				let untagged = ubbf_to_bool(vp.Untagged);
				let port_spec = untagged ? `${port_ifname}:u*` : `${port_ifname}:t`;
				uci_list_string(output, `network.${section_name}.ports`, port_spec);
			}
		}

		return;
	}

	/**
	 * Generates UCI bridge-vlan sections for VLAN-aware bridges.
	 *
	 * @param {object} bridge - Bridge data model object
	 * @param {string} bridge_inst - Bridge instance number
	 * @param {object} port_vids - Map of port instance to VID info
	 * @returns {string} UCI batch output
	 */
	function generate_bridge_vlans(bridge, bridge_inst, port_vids) {

		let br_name = bridge.Name;
		if (!br_name)
			return;

		let vlan_filtering = standard_to_vlan_filtering(bridge.Standard);
		if (!vlan_filtering)
			return generate_explicit_vlans(bridge, bridge_inst);

		let eth_ports = [];

		let ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);
		for (let port in ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;
			if (!is_ethernet_link(port.LowerLayers))
				continue;

			let port_ifname = lower_layer_resolve(config, port.LowerLayers);
			if (port_ifname)
				push(eth_ports, port_ifname);
		}

		if (length(eth_ports) == 0)
			return;

		let mgmt_port = null;
		for (let port in ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;
			if (!ubbf_to_bool(port.ManagementPort))
				continue;

			let port_inst = port['.instance'];
			let port_vid_info = port_vids[port_inst];
			if (port_vid_info)
				mgmt_port = { vid: port_vid_info.vid };
			break;
		}

		if (!mgmt_port)
			return;

		let suffix = render_state.bridge?.[br_name]?.mgmt_vlan_suffix
			?? sprintf('%d', mgmt_port.vid);
		let alias = render_state.bridge?.[br_name]?.mgmt_vlan_alias;
		let section_name = bridge_vlan_section_name(br_name, suffix);

		render_state.bridge ??= {};
		render_state.bridge[br_name] ??= {};
		render_state.bridge[br_name].mgmt_vlan_section = section_name;
		render_state.bridge[br_name].mgmt_vid = mgmt_port.vid;

		uci_named_section(output, `network.${section_name}`, 'bridge-vlan');
		uci_set_string(output, `network.${section_name}.device`, br_name);
		uci_set_number(output, `network.${section_name}.vlan`, mgmt_port.vid);

		for (let port_ifname in eth_ports)
			uci_list_string(output, `network.${section_name}.ports`, port_ifname);

		if (alias)
			uci_set_string(output, `network.${section_name}.alias`, alias);

		return;
	}

	/**
	 * Generates UCI configuration for all bridges.
	 *
	 * @returns {string} UCI batch output for all bridges
	 */
	function generate_all_bridges() {
		let bridges = ubbf_instances(config, 'Device.Bridging.Bridge');
		if (length(bridges) == 0)
			return;


		for (let bridge in bridges) {
			if (!bridge)
				continue;

			let bridge_inst = bridge['.instance'];
			let vlan_filtering = standard_to_vlan_filtering(bridge.Standard);
			let port_vids = compute_port_vids(bridge_inst, vlan_filtering);

			populate_bridge(bridge, bridge_inst);
			populate_8021q_devices(bridge, bridge_inst, port_vids);
			generate_bridge_vlans(bridge, bridge_inst, port_vids);
		}
	}

	let bridging = ubbf_get(config, 'Device.Bridging');
	if (!bridging)
		return;

	generate_all_bridges();
}
uci_comment(output, '# generated by bridging.uc');
render_config();
