function render_config() {
	// 198.18.0.0/15 is IANA-reserved for network benchmarking
	// (RFC 2544). Safe choice for the RG's non-routable secondary on
	// the wan device: never collides with ISP or LAN address ranges.
	const ADMZ_SECONDARY = '198.18.0.1';

	/**
	 * Returns the active WAN lease for the ADMZ host, or null when no
	 * lease is available yet. Intent (Enable, MAC) comes from the TR-181
	 * config the renderer holds. Three lease sources, in order of
	 * freshness:
	 *
	 *   1. admzd's status ubus (ACTIVE state holds the lease the proto
	 *      handler published).
	 *   2. netifd interface status .data.admz_lease_ip (the proto
	 *      handler's bound callback stashes it here before admzd polls
	 *      it).
	 *   3. netifd ipv4-address, skipping the 198.18.0.1 secondary. This
	 *      catches the Enable false->true transition: at apply time the
	 *      previous script callback ran with enable=0 and bound the
	 *      leased IP normally, so eth0's ipv4-address still carries the
	 *      lease. Without this branch, the firewall is reloaded with no
	 *      admz_snat rule, RG egress sources from 198.18.0.1 unaltered,
	 *      and ACS keepalive dies within a minute.
	 *
	 * @returns {object|null} {mac, wan_pub} or null
	 */
	function admz_state_get() {
		let admz = ubbf_get(config, 'Device.NAT.X_UBBF_IPPassthrough');
		if (!admz || !ubbf_to_bool(admz.Enable))
			return null;

		let mac = lc(admz.AdvancedDMZhost ?? '');
		if (mac == '')
			return null;

		let status = ubus.call({ object: 'admz', method: 'status', data: {} });
		if (status?.state == 'ACTIVE' && status?.lease_ip)
			return { mac, wan_pub: status.lease_ip };

		for (let iface in ubbf_instances(config, 'Device.IP.Interface')) {
			if (!ubbf_to_bool(iface.Upstream))
				continue;
			if (!iface.Name)
				continue;
			let st = netifd_status_get(iface.Name);
			if (!st?.up)
				continue;

			let wan_pub = st.data?.admz_lease_ip;
			if (!wan_pub) {
				let v4 = st['ipv4-address'];
				if (type(v4) == 'array') {
					for (let entry in v4) {
						let addr = entry?.address;
						if (addr && addr != ADMZ_SECONDARY) {
							wan_pub = addr;
							break;
						}
					}
				}
			}
			if (!wan_pub)
				continue;
			return { mac, wan_pub };
		}

		return null;
	}

	/**
	 * Builds the management-port carve-out list from configured
	 * WAN-bound services. Each entry becomes a DNAT redirect that
	 * rewrites <wan-pub>:port to 198.18.0.1:port, preserving the RG's
	 * own listener (dropbear, ubbf-ui). No TR-069/7547 entry: the
	 * deployment is sole USP over MQTT, no CWMP listener binds. Same
	 * scan as render/templates/admz.uc; kept here so the firewall
	 * surface does not depend on the order in which UCI sections of
	 * /etc/config/admz are read by the daemon.
	 *
	 * @returns {array} list of {proto, port, name}
	 */
	function admz_management_ports() {
		let ports = [];

		for (let s in ubbf_instances(config, 'Device.SSH.Server')) {
			if (!ubbf_to_bool(s.Enable))
				continue;
			if (!s.Interface || s.Interface == '')
				continue;
			let iface = ubbf_get(config, s.Interface);
			if (!ubbf_to_bool(iface?.Upstream))
				continue;
			let port = ubbf_to_int(s.Port) ?? 22;
			push(ports, { proto: 'tcp', port, name: sprintf('ssh-%d', port) });
		}

		for (let h in ubbf_instances(config, 'Device.UserInterface.HTTPAccess')) {
			if (!ubbf_to_bool(h.Enable))
				continue;
			if (!h.Interface || h.Interface == '')
				continue;
			let iface = ubbf_get(config, h.Interface);
			if (!ubbf_to_bool(iface?.Upstream))
				continue;
			let port = ubbf_to_int(h.Port) ?? 443;
			push(ports, { proto: 'tcp', port, name: sprintf('http-%d', port) });
		}

		return ports;
	}

	/**
	 * Returns {wan_zone, lan_zone, wan_l2, lan_l2} bound to the
	 * upstream and the first non-upstream Device.Firewall.InterfaceSetting
	 * row, or null when either side is missing. Zone names match the
	 * network interface names rendered by ip.uc.
	 *
	 * @returns {object|null}
	 */
	function admz_zones_resolve() {
		let iface_settings = ubbf_instances(config, 'Device.Firewall.InterfaceSetting');
		let wan_zone, lan_zone, wan_l2, lan_l2;

		for (let ifs in iface_settings) {
			if (!ubbf_to_bool(ifs.Enable))
				continue;
			let name = interface_to_name(config, ifs.Interface);
			if (!name)
				continue;

			let iface = ubbf_get(config, ifs.Interface);
			let dev = lower_layer_resolve_vlan(config, iface?.LowerLayers);
			if (ubbf_to_bool(iface?.Upstream)) {
				if (!wan_zone) { wan_zone = name; wan_l2 = dev; }
			} else if (!lan_zone) {
				lan_zone = name; lan_l2 = dev;
			}
		}

		if (!wan_zone || !lan_zone)
			return null;

		return { wan_zone, lan_zone, wan_l2, lan_l2 };
	}

	/**
	 * Emits the firewall surface for Device.NAT.X_UBBF_IPPassthrough.
	 *
	 *   1. Management-port DNAT carve-outs (SSH, HTTPS) so RG-owned
	 *      services remain reachable on <wan-pub>:port even though the
	 *      IP physically lives at the ADMZ host.
	 *   2. ADMZ catchall: FORWARD ACCEPT for src=wan dest=lan
	 *      dest_ip=<wan-pub>. The /32 route to br-lan installed by the
	 *      admzd daemon steers the packet onto the LAN bridge; no DNAT
	 *      rewrite needed.
	 *   3. SNAT for RG egress: src_ip=198.18.0.1 -> SNAT to <wan-pub>.
	 *      conntrack reverses the reply path.
	 *   4. ACCEPT (no-MASQ) for ADMZ host outbound: its src is already
	 *      <wan-pub>, must not be rewritten by zone masquerade.
	 *   5. proxy_arp=1 on both L2 devices via device_state_set, picked
	 *      up by render/templates/device.uc on emission.
	 *
	 * @returns {string} UCI batch output
	 */
	function generate_admz() {
		let state = admz_state_get();
		if (!state)
			return;

		let zones = admz_zones_resolve();
		if (!zones)
			return;

		let wan_pub = state.wan_pub;

		let port_idx = 0;
		for (let p in admz_management_ports()) {
			port_idx++;
			let section = sprintf('admz_mgmt_%d', port_idx);
			uci_named_section(output, `firewall.${section}`, 'redirect');
			uci_set_string(output, `firewall.${section}.name`, sprintf('ADMZ-%s', p.name));
			uci_set_string(output, `firewall.${section}.target`, 'DNAT');
			uci_set_string(output, `firewall.${section}.src`, zones.wan_zone);
			uci_set_string(output, `firewall.${section}.src_dip`, wan_pub);
			uci_set_number(output, `firewall.${section}.src_dport`, p.port);
			uci_set_string(output, `firewall.${section}.proto`, p.proto);
			uci_set_string(output, `firewall.${section}.dest_ip`, ADMZ_SECONDARY);
			uci_set_number(output, `firewall.${section}.dest_port`, p.port);
			uci_set_boolean(output, `firewall.${section}.enabled`, true);
		}

		uci_named_section(output, 'firewall.admz_forward', 'rule');
		uci_set_string(output, 'firewall.admz_forward.name', 'ADMZ-forward');
		uci_set_string(output, 'firewall.admz_forward.src', zones.wan_zone);
		uci_set_string(output, 'firewall.admz_forward.dest', zones.lan_zone);
		uci_set_string(output, 'firewall.admz_forward.dest_ip', wan_pub);
		uci_set_string(output, 'firewall.admz_forward.target', 'ACCEPT');

		uci_named_section(output, 'firewall.admz_snat', 'nat');
		uci_set_string(output, 'firewall.admz_snat.name', 'ADMZ-snat-rg');
		uci_set_string(output, 'firewall.admz_snat.target', 'SNAT');
		uci_set_string(output, 'firewall.admz_snat.src', zones.wan_zone);
		uci_set_string(output, 'firewall.admz_snat.src_ip', ADMZ_SECONDARY);
		uci_set_string(output, 'firewall.admz_snat.snat_ip', wan_pub);

		uci_named_section(output, 'firewall.admz_nomasq', 'nat');
		uci_set_string(output, 'firewall.admz_nomasq.name', 'ADMZ-nomasq-host');
		uci_set_string(output, 'firewall.admz_nomasq.target', 'ACCEPT');
		uci_set_string(output, 'firewall.admz_nomasq.src', zones.lan_zone);
		uci_set_string(output, 'firewall.admz_nomasq.src_ip', wan_pub);

		if (zones.wan_l2)
			device_state_set(render_state, zones.wan_l2, 'proxy_arp', '1');
		if (zones.lan_l2)
			device_state_set(render_state, zones.lan_l2, 'proxy_arp', '1');
	}

	generate_admz();
}
render_config();
