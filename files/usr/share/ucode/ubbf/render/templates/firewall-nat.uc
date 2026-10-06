function render_config() {
/**
 * Collects DNS relay interfaces, mirroring the grouping logic in dns.uc.
 * Port assignments must match dns.uc exactly.
 *
 * @returns {object} Map of interface name to {port}
 */
function dns_relay_collect() {
	let relay = ubbf_get(config, 'Device.DNS.Relay');
	if (!relay || !ubbf_to_bool(relay.Enable))
		return {};

	let forwardings = ubbf_instances(config, 'Device.DNS.Relay.Forwarding');
	if (!forwardings || !length(forwardings))
		return {};

	let ip_interfaces = ubbf_instances(config, 'Device.IP.Interface');
	let by_iface = {};

	for (let fwd in forwardings) {
		if (!ubbf_to_bool(fwd.Enable))
			continue;
		if (!fwd.DNSServer)
			continue;

		if (fwd.Interface && fwd.Interface != '') {
			let name = interface_to_name(config, fwd.Interface);
			if (name)
				by_iface[name] = true;
		} else {
			for (let iface in ip_interfaces) {
				if (!iface.Name)
					continue;
				if (ubbf_to_bool(iface.Upstream))
					continue;
				by_iface[iface.Name] = true;
			}
		}
	}

	let result = {};
	let port = 5301;

	for (let iface in by_iface) {
		result[iface] = { port };
		port++;
	}

	return result;
}

/**
 * Generates UCI DNS relay redirect entries from Device.DNS.Relay.Forwarding.
 *
 * @returns {string} UCI batch output for DNS redirects and allow rules
 */
function generate_dns_redirects() {
	let by_iface = dns_relay_collect();

	for (let iface, data in by_iface) {
		let redir_name = `dns_redir_${iface}`;
		let rule_name = `dns_allow_${iface}`;

		uci_named_section(output, `firewall.${redir_name}`, 'redirect');
		uci_set_string(output, `firewall.${redir_name}.name`, `DNS-redirect-${iface}`);
		uci_set_string(output, `firewall.${redir_name}.src`, iface);
		uci_set_number(output, `firewall.${redir_name}.src_dport`, 53);
		uci_set_number(output, `firewall.${redir_name}.dest_port`, data.port);
		uci_set_string(output, `firewall.${redir_name}.proto`, 'tcp udp');
		uci_set_string(output, `firewall.${redir_name}.target`, 'DNAT');

		uci_named_section(output, `firewall.${rule_name}`, 'rule');
		uci_set_string(output, `firewall.${rule_name}.name`, `Allow-DNS-${iface}`);
		uci_set_string(output, `firewall.${rule_name}.src`, iface);
		uci_set_number(output, `firewall.${rule_name}.dest_port`, data.port);
		uci_set_string(output, `firewall.${rule_name}.proto`, 'tcp udp');
		uci_set_string(output, `firewall.${rule_name}.target`, 'ACCEPT');
	}

	return;
}

/**
 * Generates UCI port mapping redirect entries from Device.NAT.PortMapping.
 *
 * @returns {string} UCI batch output for port forwards
 */
function generate_port_mappings() {
	let instances = ubbf_instances(config, 'Device.NAT.PortMapping');

	for (let pm in instances) {
		if (!ubbf_to_bool(pm.Enable))
			continue;

		uci_section(output, 'firewall redirect');
		uci_set_string(output, 'firewall.@redirect[-1].target', 'DNAT');
		uci_set_boolean(output, 'firewall.@redirect[-1].enabled', true);

		let src_zone;
		let all_interfaces = ubbf_to_bool(pm.AllInterfaces);

		if (all_interfaces) {
			// AllInterfaces=true means "match the port regardless of which
			// WAN address it arrived at". fw4 already matches any daddr
			// when src_dip is omitted; emitting src_dip='*' instead makes
			// fw4 reject the whole redirect ("invalid value '*'") and
			// also drops the hairpin reflection rule.
			let iface_name = interface_to_name(config, pm.Interface);
			src_zone = iface_name ?? 'wan';
		} else {
			src_zone = interface_to_name(config, pm.Interface);
		}

		if (src_zone)
			uci_set_string(output, 'firewall.@redirect[-1].src', src_zone);

		let iface_settings = ubbf_instances(config, 'Device.Firewall.InterfaceSetting');
		for (let ifs in iface_settings) {
			if (!ubbf_to_bool(ifs.Enable))
				continue;
			let dest_name = interface_to_name(config, ifs.Interface);
			if (!dest_name || dest_name == src_zone)
				continue;
			let dest_iface = ubbf_get(config, ifs.Interface);
			if (dest_iface?.Upstream == 'true')
				continue;
			uci_set_string(output, 'firewall.@redirect[-1].dest', dest_name);
			break;
		}

		let proto = ubbf.protocol_to_uci(pm.Protocol) ?? 'tcp';
		uci_set_string(output, 'firewall.@redirect[-1].proto', proto);

		let src_dport = ubbf.port_range_format(pm.ExternalPort, pm.ExternalPortEndRange);
		if (src_dport)
			uci_set_string(output, 'firewall.@redirect[-1].src_dport', src_dport);

		let dest_port = ubbf_to_int(pm.InternalPort);
		if (dest_port != null && dest_port > 0)
			uci_set_number(output, 'firewall.@redirect[-1].dest_port', dest_port);

		if (pm.InternalClient && pm.InternalClient != '')
			uci_set_string(output, 'firewall.@redirect[-1].dest_ip', pm.InternalClient);

		if (pm.RemoteHost && pm.RemoteHost != '')
			uci_set_string(output, 'firewall.@redirect[-1].src_ip', pm.RemoteHost);

		if (pm.Description && pm.Description != '')
			uci_set_string(output, 'firewall.@redirect[-1].name', pm.Description);

		let lease_duration = ubbf_to_int(pm.LeaseDuration);
		if (lease_duration != null && lease_duration > 0) {
			let expiry = time() + lease_duration;
			uci_set_string(output, 'firewall.@redirect[-1].expiry', expiry);
		}

		redirect_emit_reflection(config, output);
	}

	return;
}

	generate_dns_redirects();
	generate_port_mappings();
}
render_config();
