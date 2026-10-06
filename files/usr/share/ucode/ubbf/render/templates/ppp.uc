function render_config() {
	/**
	 * Resolves a LANInterface TR-181 reference to a Linux netdev name.
	 *
	 * Accepts Device.Bridging.Bridge.{i} or Device.IP.Interface.{i}. Any
	 * other shape, an unset reference, or one that fails to resolve all
	 * the way to a netdev returns null - the caller must skip the
	 * passthrough section. No fallback to 'br-lan' or similar guess.
	 *
	 * @param {string} ref - TR-181 path reference (e.g. Device.Bridging.Bridge.1)
	 * @returns {string|null} Resolved netdev name, or null on any failure
	 */
	function resolve_lan_dev(ref) {
		if (!ref || ref == '')
			return null;

		if (match(ref, /^Device\.Bridging\.Bridge\.[0-9]+$/)) {
			let bridge = ubbf_get(config, ref);
			let name = bridge?.Name;
			return (name && name != '') ? name : null;
		}

		if (match(ref, /^Device\.IP\.Interface\.[0-9]+$/)) {
			let ip_iface = ubbf_get(config, ref);
			if (!ip_iface?.LowerLayers)
				return null;
			return lower_layer_resolve_vlan(config, ip_iface.LowerLayers);
		}

		return null;
	}

	/**
	 * Generates /etc/config/pppoe-relay sections from
	 * Device.PPP.Interface.{i}.PPPoE.X_UBBF_Passthrough subtrees. Missing
	 * or unresolvable LANInterface / LowerLayers means the section is
	 * skipped entirely; the daemon never starts without explicit config.
	 *
	 * @param {array} interfaces - PPP interface instances
	 * @returns {boolean} true when at least one passthrough instance was emitted
	 */
	function generate_passthrough(interfaces) {
		let any_enabled = false;

		for (let iface in interfaces) {
			if (!ubbf_to_bool(iface.Enable))
				continue;

			let pt = iface.PPPoE?.X_UBBF_Passthrough;
			if (!pt || !ubbf_to_bool(pt.Enable))
				continue;

			let wan_dev = lower_layer_resolve_vlan(config, iface.LowerLayers);
			if (!wan_dev)
				continue;

			let lan_dev = resolve_lan_dev(pt.LANInterface);
			if (!lan_dev)
				continue;

			let max_sessions = ubbf_to_int(pt.MaxSessions);
			if (max_sessions == null || max_sessions <= 0)
				continue;

			let section = replace(pt.LANInterface, /[^a-zA-Z0-9_]/g, '_');
			any_enabled = true;

			uci_named_section(output, `pppoe-relay.${section}`, 'instance');
			uci_set_string(output, `pppoe-relay.${section}.lan_interface`, pt.LANInterface);
			uci_set_string(output, `pppoe-relay.${section}.lan_dev`, lan_dev);
			uci_set_string(output, `pppoe-relay.${section}.wan_dev`, wan_dev);
			uci_set_number(output, `pppoe-relay.${section}.max_sessions`, max_sessions);
		}

		return any_enabled;
	}

	/**
	 * Generates UCI network interface sections for PPP connections.
	 *
	 * @param {array} interfaces - PPP interface instances
	 * @returns {string} UCI batch output for PPPoE interfaces
	 */
	function generate_interfaces(interfaces) {

		for (let iface in interfaces) {
			if (!ubbf_to_bool(iface.Enable))
				continue;

			let name = iface.Name;
			if (!name)
				continue;

			let device = lower_layer_resolve_vlan(config, iface.LowerLayers);

			uci_named_section(output, `network.${name}`, 'interface');
			uci_set_string(output, `network.${name}.proto`, 'pppoe');

			if (device)
				uci_set_string(output, `network.${name}.device`, device);

			if (iface.Username && iface.Username != '')
				uci_set_string(output, `network.${name}.username`, iface.Username);

			if (iface.Password && iface.Password != '')
				uci_set_string(output, `network.${name}.password`, iface.Password);

			let max_mru = ubbf_to_int(iface.MaxMRUSize);
			if (max_mru != null && max_mru > 0)
				uci_set_number(output, `network.${name}.mtu`, max_mru);

			let conn_trigger = iface.ConnectionTrigger;
			if (conn_trigger == 'OnDemand') {
				let idle_time = ubbf_to_int(iface.IdleDisconnectTime);
				if (idle_time == null || idle_time == 0)
					idle_time = ubbf_to_int(iface.AutoDisconnectTime);
				if (idle_time != null && idle_time > 0)
					uci_set_number(output, `network.${name}.demand`, idle_time);
			}

			let lcp_echo = ubbf_to_int(iface.LCPEcho);
			let lcp_retry = ubbf_to_int(iface.LCPEchoRetry);
			if (lcp_echo != null && lcp_echo > 0) {
				lcp_retry = lcp_retry ?? 5;
				uci_set_string(output, `network.${name}.keepalive`, `${lcp_echo} ${lcp_retry}`);

				let lcp_adaptive = ubbf_to_bool(iface.LCPEchoAdaptive);
				uci_set_boolean(output, `network.${name}.keepalive_adaptive`, lcp_adaptive);
			}

			let ipv6_enable = ubbf_to_bool(iface.IPv6CPEnable);
			if (!ipv6_enable)
				uci_set_string(output, `network.${name}.ipv6`, '0');
			else
				// '1' negotiates IPv6CP without netifd's AUTOIPV6 dhcpv6
				// add_dynamic. The TR-181 DHCPv6.Client renderer in ip.uc
				// emits the dhcpv6 UCI section instead, avoiding two
				// odhcp6c instances racing on the same ppp device.
				uci_set_string(output, `network.${name}.ipv6`, '1');

			let ipcp_enable = ubbf_to_bool(iface.IPCPEnable);
			if (!ipcp_enable)
				uci_set_string(output, `network.${name}.pppd_options`, 'noip');

			let pppoe = iface.PPPoE;
			if (pppoe) {
				if (pppoe.ACName && pppoe.ACName != '')
					uci_set_string(output, `network.${name}.ac`, pppoe.ACName);

				if (pppoe.ServiceName && pppoe.ServiceName != '')
					uci_set_string(output, `network.${name}.service`, pppoe.ServiceName);
			}
		}

		return;
	}

	let interfaces = ubbf_instances(config, 'Device.PPP.Interface');

	generate_interfaces(interfaces);
	services.set_enabled('pppoe-relay', generate_passthrough(interfaces));
}
uci_comment(output, '# generated by ppp.uc');
render_config();
