function render_config() {
/**
 * Generates UCI firewall rules from Device.Firewall.Pinhole instances.
 *
 * @returns {string} UCI batch output for pinhole rules
 */
function generate_pinholes() {
	let pinholes = ubbf_instances(config, 'Device.Firewall.Pinhole');

	for (let ph in pinholes) {
		if (!ubbf_to_bool(ph.Enable))
			continue;

		let has_ip = (ph.DestIP ?? '') != '';
		let has_mac = (ph.DestMACAddress ?? '') != '';
		if (has_ip == has_mac)
			continue;

		let iface_name = interface_to_name(config, ph.Interface);
		if (!iface_name)
			continue;

		uci_section(output, 'firewall rule');

		if (ph.Description && ph.Description != '')
			uci_set_string(output, 'firewall.@rule[-1].name', ph.Description);

		uci_set_string(output, 'firewall.@rule[-1].src', iface_name);
		// A pinhole admits traffic routed to the internal network; without
		// a dest zone fw4 would place the rule in the DUT's input chain.
		uci_set_string(output, 'firewall.@rule[-1].dest', '*');

		let proto = ubbf.protocol_to_uci(ph.Protocol);
		if (proto)
			uci_set_string(output, 'firewall.@rule[-1].proto', proto);

		let src_port = ubbf.port_range_format(ph.SourcePort, ph.SourcePortRangeMax);
		if (src_port)
			uci_set_string(output, 'firewall.@rule[-1].src_port', src_port);

		let dest_port = ubbf.port_range_format(ph.DestPort, ph.DestPortRangeMax);
		if (dest_port)
			uci_set_string(output, 'firewall.@rule[-1].dest_port', dest_port);

		if (ph.DestIP && ph.DestIP != '')
			uci_set_string(output, 'firewall.@rule[-1].dest_ip', ph.DestIP);

		if (ph.DestMACAddress && ph.DestMACAddress != '')
			uci_set_string(output, 'firewall.@rule[-1].dest_mac', ph.DestMACAddress);

		let family = ipversion_to_family(ph.IPVersion);
		if (family)
			uci_set_string(output, 'firewall.@rule[-1].family', family);

		for (let prefix in csv_to_list(ph.SourcePrefixes, ''))
			uci_list_string(output, 'firewall.@rule[-1].src_ip', prefix);

		uci_set_string(output, 'firewall.@rule[-1].target', 'ACCEPT');

		if (ubbf_to_bool(ph.Log))
			uci_set_boolean(output, 'firewall.@rule[-1].log', true);
	}

	return;
}

	generate_pinholes();
}
render_config();
