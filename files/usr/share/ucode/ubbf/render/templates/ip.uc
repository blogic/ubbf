function render_config() {
	/**
	 * Finds the DHCPv4 client instance bound to a given IP interface path.
	 *
	 * @param {string} iface_path - TR-181 path (e.g. "Device.IP.Interface.1")
	 * @returns {object|null} DHCPv4 client object or null
	 */
	function dhcpv4_client_find(iface_path) {
		let clients = ubbf_instances(config, 'Device.DHCPv4.Client');
		for (let client in clients) {
			if (client.Interface == iface_path)
				return client;
		}
		return null;
	}

	/**
	 * Renders DHCPv4 SentOption/ReqOption instances to UCI sendopts/reqopts.
	 *
	 * @param {array} output - UCI output array
	 * @param {string} name - UCI interface name
	 * @param {object} client - DHCPv4 client data model object
	 */
	function dhcpv4_client_opts_render(output, name, client) {
		let sent_opts = ubbf_instances(client, 'SentOption');
		for (let opt in sent_opts) {
			if (!ubbf_to_bool(opt.Enable))
				continue;
			let tag = ubbf_to_int(opt.Tag);
			if (tag == null || !opt.Value)
				continue;
			uci_list_string(output, `network.${name}.sendopts`,
				sprintf('0x%02x:%s', tag, opt.Value));
		}

		let req_tags = [];
		let req_opts = ubbf_instances(client, 'ReqOption');
		for (let opt in req_opts) {
			if (!ubbf_to_bool(opt.Enable))
				continue;
			let tag = ubbf_to_int(opt.Tag);
			if (tag == null)
				continue;
			push(req_tags, '' + tag);
		}
		if (length(req_tags))
			uci_set_string(output, `network.${name}.reqopts`,
				join(' ', req_tags));

		let rtx = client.Retransmission;
		if (rtx) {
			let initial = ubbf_to_int(rtx.DiscoverInitialTimeout);
			if (initial != null && initial > 0)
				uci_set_number(output, `network.${name}.timeout`, initial);
			let max_dur = ubbf_to_int(rtx.DiscoverMaxDuration);
			if (max_dur != null && max_dur > 0 && initial != null && initial > 0) {
				let retries = int((max_dur + initial - 1) / initial);
				if (retries > 0)
					uci_set_number(output, `network.${name}.retry`, retries);
			}
			let req_max_dur = ubbf_to_int(rtx.RequestMaxDuration);
			if (req_max_dur != null && req_max_dur > 0)
				uci_set_number(output, `network.${name}.tryagain`, req_max_dur);
		}

		let dscp = ubbf_to_int(client.DSCPMark ?? '48');
		if (dscp != null && dscp >= 0 && dscp <= 63)
			uci_set_number(output, `network.${name}.dscp`, dscp);
	}

	/**
	 * Renders DHCPv6 SentOption instances to UCI sendopts/reqopts.
	 *
	 * @param {array} output - UCI output array
	 * @param {string} name6 - UCI interface name
	 * @param {object} client - DHCPv6 client data model object
	 */
	function dhcpv6_client_opts_render(output, name6, client) {
		let req_tags = {};
		let sent_opts = ubbf_instances(client, 'SentOption');

		for (let opt in sent_opts) {
			if (!ubbf_to_bool(opt.Enable))
				continue;
			let tag = ubbf_to_int(opt.Tag);
			if (tag == null)
				continue;

			if (opt.Value)
				uci_list_string(output, `network.${name6}.sendopts`,
					sprintf('%d:%s', tag, opt.Value));

			req_tags[tag] = true;
		}

		let explicit_oro = false;
		for (let token in csv_to_list(client.RequestedOptions)) {
			let tag = ubbf_to_int(token);
			if (tag != null && tag > 0) {
				req_tags[tag] = true;
				explicit_oro = true;
			}
		}

		let req_tag_list = [];
		for (let tag in req_tags)
			push(req_tag_list, '' + tag);
		if (length(req_tag_list))
			uci_set_string(output, `network.${name6}.reqopts`,
				join(' ', req_tag_list));

		if (explicit_oro)
			uci_set_string(output, `network.${name6}.defaultreqopts`, '0');

		let rtx = client.Retransmission;
		if (rtx) {
			let sol_max = ubbf_to_int(rtx.SolicitMaxTimeout);
			if (sol_max != null && sol_max > 0)
				uci_set_number(output, `network.${name6}.soltimeout`, sol_max);
		}
	}

	/**
	 * Resolves a router reference to its routing table number.
	 *
	 * @param {string} router_ref - Data model path to router object
	 * @returns {string|null} Routing table number or default '254'
	 */
	function resolve_router_table(router_ref) {
		if (!router_ref || router_ref == '')
			return null;

		let router = ubbf_get(config, router_ref);
		if (!router)
			return null;

		// 254 is the Linux 'main' routing table (see /etc/iproute2/rt_tables)
		return router.RoutingTable || '254';
	}

	/**
	 * Returns whether an IP family is enabled on an interface: both the
	 * device-wide switch and the switch of the interface must be on.
	 *
	 * @param {object} ip - Device.IP data model object
	 * @param {object} iface - IP interface data model object
	 * @param {string} param - 'IPv4Enable' or 'IPv6Enable'
	 * @returns {boolean}
	 */
	function ip_family_enabled(ip, iface, param) {
		return ubbf_to_bool(ip[param] ?? 'true') && ubbf_to_bool(iface[param] ?? 'true');
	}

	/**
	 * Generates UCI network interfaces for DHCPv6 clients.
	 *
	 * @param {object} ip - Device.IP data model object
	 * @param {array} dhcpv6_clients - DHCPv6 client instances
	 * @returns {string} UCI batch output for DHCPv6 client interfaces
	 */
	function generate_dhcpv6_client_interfaces(ip, dhcpv6_clients) {

		for (let inst, client in dhcpv6_clients) {
			if (!ubbf_to_bool(client.Enable))
				continue;

			let iface = ubbf_get(config, client.Interface);
			if (!iface?.Name)
				continue;
			if (!ip_family_enabled(ip, iface, 'IPv6Enable'))
				continue;

			let name = iface.Name;
			let name6 = `${name}6`;

			let ppp_path = match(iface.LowerLayers, /^(Device\.PPP\.Interface\.\d+)$/);
			let device_ref, device;
			if (ppp_path) {
				let ppp = ubbf_get(config, ppp_path[1]);
				if (!ppp?.Name)
					continue;
				device_ref = '@' + ppp.Name;
			} else {
				device = lower_layer_resolve_vlan(config, iface.LowerLayers);
			}

			uci_named_section(output, `network.${name6}`, 'interface');
			if (device_ref)
				uci_set_string(output, `network.${name6}.device`, device_ref);
			else if (device)
				uci_set_string(output, `network.${name6}.ifname`, device);

			uci_set_string(output, `network.${name6}.proto`, 'dhcpv6');
			uci_set_boolean(output, `network.${name6}.accept_ra`, true);
			uci_set_boolean(output, `network.${name6}.sourcefilter`, false);

			let req_addr = ubbf_to_bool(client.RequestAddresses) ? 'try' : 'none';
			uci_set_string(output, `network.${name6}.reqaddress`, req_addr);

			let req_prefix = ubbf_to_bool(client.RequestPrefixes) ? 'auto' : 'no';
			uci_set_string(output, `network.${name6}.reqprefix`, req_prefix);

			dhcpv6_client_opts_render(output, name6, client);
		}

		return;
	}

	/**
	 * Generates UCI network globals section with ULA prefix.
	 *
	 * @param {object} ip - Device.IP data model object
	 * @returns {string} UCI batch output for globals or empty string
	 */
	function generate_globals(ip) {

		let ula_prefix = ip.ULAPrefix;
		if (!ula_prefix || ula_prefix == '')
			return;

		uci_named_section(output, 'network.globals', 'globals');
		uci_set_string(output, 'network.globals.ula_prefix', ula_prefix);

		return;
	}

	/**
	 * Populates render state with SSID to network mappings.
	 *
	 * @param {object} iface - IP interface data model object
	 */
	function populate_ssid_network_state(iface) {
		let lower = iface.LowerLayers;
		if (!lower)
			return;

		let m = match(lower, /^Device\.Bridging\.Bridge\.(\d+)\.Port\.\d+$/);
		if (!m)
			return;

		let bridge_inst = m[1];
		let ports = ubbf_instances(config, `Device.Bridging.Bridge.${bridge_inst}.Port`);

		for (let port in ports) {
			if (!port || !ubbf_to_bool(port.Enable))
				continue;
			if (ubbf_to_bool(port.ManagementPort))
				continue;

			let port_lower = port.LowerLayers;
			if (!port_lower)
				continue;

			for (let ref in csv_to_list(port_lower)) {
				if (!match(ref, /^Device\.WiFi\.SSID\.\d+$/))
					continue;

				render_state.ssid ??= {};
				render_state.ssid[ref] = { network: iface.Name };
			}
		}
	}

	/**
	 * Generates UCI network interface sections from IP interfaces.
	 *
	 * Side effect: populates render_state.ssid via
	 * populate_ssid_network_state() so that downstream WiFi
	 * templates can resolve SSID-to-network mappings.
	 *
	 * @param {object} ip - Device.IP data model object
	 * @param {array} instances - IP interface instances
	 * @returns {string} UCI batch output for network interfaces
	 */
	function generate_interfaces(ip, instances) {

		for (let iface in instances) {
			let name = iface.Name;
			if (!name)
				continue;

			populate_ssid_network_state(iface);

			let enabled = ubbf_to_bool(iface.Enable);
			let ula_enable = ubbf_to_bool(iface.ULAEnable);
			let max_mtu = ubbf_to_int(iface.MaxMTUSize);

			let device = lower_layer_resolve_vlan(config, iface.LowerLayers);
			let route_table = resolve_router_table(iface.Router);
			let ipv4_on = ip_family_enabled(ip, iface, 'IPv4Enable');
			let ipv6_on = ip_family_enabled(ip, iface, 'IPv6Enable');

			if (device && !ipv6_on)
				device_state_set(render_state, device, 'ipv6', '0');

			uci_named_section(output, `network.${name}`, 'interface');

			if (device)
				uci_set_string(output, `network.${name}.ifname`, device);

			uci_set_boolean(output, `network.${name}.disabled`, !enabled);

			// MTU on a config interface section is silently dropped by netifd
			// for devices declared via an explicit config device section
			// (dev->default_config=false gate in interface_set_device_config).
			// Stash it on the L3 device's render state so device.uc emits it
			// on the config device section, which netifd always honours.
			if (device && max_mtu && max_mtu > 0)
				device_state_set(render_state, device, 'mtu', sprintf('%d', max_mtu));

			if (ula_enable && ipv6_on)
				uci_set_boolean(output, `network.${name}.ula`, true);

			if (route_table) {
				uci_set_string(output, `network.${name}.ip4table`, route_table);
				uci_set_string(output, `network.${name}.ip6table`, route_table);
			}

			if (ubbf_to_bool(iface.Upstream)) {
				let loss_delay = ubbf_to_int(iface.X_UBBF_CarrierLossDelay);
				if (loss_delay != null && loss_delay > 0)
					uci_set_number(output, `network.${name}.carrier_loss_delay`, loss_delay);
			}

			let ipv4_addresses = ipv4_on ? ubbf_instances(iface, 'IPv4Address') : [];
			let ipv6_addresses = ipv6_on ? ubbf_instances(iface, 'IPv6Address') : [];
			let ipv6_prefixes = ipv6_on ? ubbf_instances(iface, 'IPv6Prefix') : [];

			let has_static_ipv4 = false;
			let has_dhcp = false;

			for (let addr in ipv4_addresses) {
				if (!ubbf_to_bool(addr.Enable))
					continue;

				let addr_type = addr.AddressingType || 'Static';
				if (lc(addr_type) == 'dhcp') {
					has_dhcp = true;
				} else if (lc(addr_type) == 'static' && addr.IPAddress) {
					has_static_ipv4 = true;
					let cidr = ubbf.netmask_to_cidr(addr.SubnetMask);
					let ipaddr = cidr ? `${addr.IPAddress}/${cidr}` : addr.IPAddress;
					uci_set_string(output, `network.${name}.ipaddr`, ipaddr);
				}
			}

			let ip6addrs = [];
			for (let addr in ipv6_addresses) {
				if (!ubbf_to_bool(addr.Enable))
					continue;
				if (!addr.IPAddress)
					continue;

				let ip6str = addr.IPAddress;
				if (addr.Prefix) {
					let pfx_obj = ubbf_get(config, addr.Prefix);
					if (pfx_obj?.Prefix) {
						let m = match(pfx_obj.Prefix, /\/(\d+)$/);
						if (m)
							ip6str += '/' + m[1];
					}
				}
				push(ip6addrs, ip6str);
			}

			if (has_dhcp) {
				uci_set_string(output, `network.${name}.proto`, 'dhcp');
				let dhcp_client = dhcpv4_client_find(iface['.path']);
				if (dhcp_client)
					dhcpv4_client_opts_render(output, name, dhcp_client);
			} else if (has_static_ipv4 || length(ip6addrs)) {
				uci_set_string(output, `network.${name}.proto`, 'static');
			} else {
				uci_set_string(output, `network.${name}.proto`, 'none');
			}

			for (let addr in ip6addrs)
				uci_list_string(output, `network.${name}.ip6addr`, addr);

			let ip6prefixes = [];
			let pd_assign_len = null;
			for (let prefix in ipv6_prefixes) {
				if (!ubbf_to_bool(prefix.Enable))
					continue;

				// ParentPrefix-driven rows are delegated children: drive
				// netifd's ip6assign rather than emitting a static ip6prefix.
				if (prefix.ParentPrefix) {
					pd_assign_len = ubbf_to_int(prefix.ChildPrefixBits);
					continue;
				}

				if (!prefix.Prefix)
					continue;
				push(ip6prefixes, prefix.Prefix);
			}
			for (let prefix in ip6prefixes)
				uci_list_string(output, `network.${name}.ip6prefix`, prefix);

			// ip6assign = number of bits netifd assigns from the
			// delegated PD prefix to this downstream interface.
			if (pd_assign_len)
				uci_set_number(output, `network.${name}.ip6assign`, pd_assign_len);

		}

		return;
	}

	let ip = ubbf_get(config, 'Device.IP');
	if (!ip)
		return;

	let interfaces = ubbf_instances(config, 'Device.IP.Interface');
	let dhcpv6_clients = ubbf_instances(config, 'Device.DHCPv6.Client');

	generate_globals(ip);
	generate_interfaces(ip, interfaces);
	generate_dhcpv6_client_interfaces(ip, dhcpv6_clients);
}
uci_comment(output, '# generated by ip.uc');
render_config();
