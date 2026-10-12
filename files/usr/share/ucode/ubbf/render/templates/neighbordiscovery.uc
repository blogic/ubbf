function render_config() {

	/**
	 * Resolves an interface reference to its underlying device name.
	 *
	 * @param {string} iface_ref - Interface path reference
	 * @returns {string|null} Device name or null if not found
	 */
	function resolve_interface_device(iface_ref) {
		if (!iface_ref)
			return null;

		let iface = ubbf_get(config, iface_ref);
		if (!iface?.Name)
			return null;

		// Must match the netdev the IP interface actually rides (ip.uc
		// ifname, netifd l3_device): the NDP sysctls are per-netdev, and
		// the TR-181 getter reads them from the l3_device. ip.uc names
		// that device with the same resolver.
		let device = lower_layer_resolve_vlan(config, iface.LowerLayers);
		if (device)
			return device;

		return iface.Name;
	}

	/**
	 * Returns the value of an NDP parameter: from InterfaceSetting.{i}.NDP
	 * from TR-181 2.21 on, else the deprecated one of the row.
	 *
	 * @param {object} setting - InterfaceSetting row
	 * @param {string} name - Parameter name
	 * @returns {string|null} Stored value
	 */
	function ndp_value(setting, name) {
		if (dm_visible('2.21', null)) {
			if (setting.NDP?.[name] != null)
				return setting.NDP[name];
		}

		return setting[name];
	}

	/**
	 * Populates device render state with the ARP settings (TR-181 2.21) of
	 * an InterfaceSetting row; only stored values, so the kernel keeps its
	 * own for the others.
	 *
	 * @param {object} setting - InterfaceSetting row
	 * @param {string} device - Netdev of the interface
	 */
	function populate_arp_settings(setting, device) {
		let arp = setting.ARP;
		if (!arp)
			return;

		for (let param, option in { BaseReachableTime: 'neigh4reachabletime',
					    RetryInterval: 'neigh4retranstime',
					    MaxRetries: 'neigh4mcastsolicit' }) {
			let v = ubbf_to_int(arp[param]);
			if (v != null)
				device_state_set(render_state, device, option, sprintf('%d', v));
		}

		if (arp.ProxyARPEnable != null)
			device_state_set(render_state, device, 'proxy_arp', ubbf_to_bool(arp.ProxyARPEnable) ? '1' : '0');
		if (arp.Enable != null)
			device_state_set(render_state, device, 'arp', ubbf_to_bool(arp.Enable) ? '1' : '0');
	}

	/**
	 * Records the Router Solicitation timing (TR-181 2.21) for ip.uc, which
	 * gives it to odhcp6c on the DHCPv6 client interface: odhcp6c, not the
	 * kernel, solicits there. Unset values take the TR-181 defaults.
	 *
	 * @param {object} setting - InterfaceSetting row
	 */
	function populate_rs_settings(setting) {
		let iface = ubbf_get(config, setting.Interface);
		if (!iface?.Name)
			return;

		let value = (name, dflt) => ubbf_to_int(ndp_value(setting, name)) ?? dflt;
		let count = value('MaxRtrSolicitations', 3);
		if (!ubbf_to_bool(ndp_value(setting, 'RSEnable') ?? 'true'))
			count = 0;
		else if (ubbf_to_bool(setting.NDP?.UnlimitedMaxRtrSolicitations))
			count = -1;

		render_state.ndp_rs ??= {};
		render_state.ndp_rs[iface.Name] = {
			rs_delay: value('MaxRtrSolicitationDelay', 1000),
			rs_interval: value('RtrSolicitationInterval', 4000),
			rs_max_interval: value('MaxRtrSolicitationInterval', 600000),
			rs_count: count,
			rs_duration: value('MaxRtrSolicitationDuration', 0)
		};
	}

	/**
	 * Populates device render state with NDP settings.
	 *
	 * @param {array} instances - InterfaceSetting instances
	 */
	function populate_ndp_settings(instances) {
		for (let setting in instances) {
			if (!setting || !ubbf_to_bool(setting.Enable))
				continue;

			let device = resolve_interface_device(setting.Interface);
			if (!device)
				continue;

			if (dm_visible('2.21', null)) {
				populate_arp_settings(setting, device);
				populate_rs_settings(setting);

				let reach = ubbf_to_int(setting.NDP?.BaseReachableTime);
				if (reach != null)
					device_state_set(render_state, device, 'neigh6reachabletime', sprintf('%d', reach));
			}

			let dad_transmits = ubbf_to_int(ndp_value(setting, 'DADTransmits'));
			if (dad_transmits != null)
				device_state_set(render_state, device, 'dadtransmits', sprintf('%d', dad_transmits));

			let retrans_timer = ubbf_to_int(ndp_value(setting, 'RetransTimer'));
			if (retrans_timer != null)
				device_state_set(render_state, device, 'retranstime', sprintf('%d', retrans_timer));

			let rtr_solicit_interval = ubbf_to_int(ndp_value(setting, 'RtrSolicitationInterval'));
			if (rtr_solicit_interval != null) {
				// TR-181 RtrSolicitationInterval is in ms; the Linux
				// router_solicitation_interval sysctl is in seconds.
				// Floor to 1 s so a sub-second TR-181 value still
				// produces a valid sysctl write.
				let interval_sec = int(rtr_solicit_interval / 1000);
				if (interval_sec < 1)
					interval_sec = 1;
				device_state_set(render_state, device, 'rtrsolicitinterval', sprintf('%d', interval_sec));
			}

			let rs_enable = ndp_value(setting, 'RSEnable');
			let max_rtr_solicits = ubbf_to_int(ndp_value(setting, 'MaxRtrSolicitations'));

			if (rs_enable != null && !ubbf_to_bool(rs_enable)) {
				device_state_set(render_state, device, 'rtrsolicits', '0');
			} else if (max_rtr_solicits != null) {
				device_state_set(render_state, device, 'rtrsolicits', sprintf('%d', max_rtr_solicits));
			}
		}
	}

	let nd = ubbf_get(config, 'Device.NeighborDiscovery');
	if (!nd || !ubbf_to_bool(nd.Enable))
		return;

	let settings = ubbf_instances(config, 'Device.NeighborDiscovery.InterfaceSetting');
	populate_ndp_settings(settings);

}
uci_comment(output, '# generated by neighbordiscovery.uc');
render_config();
