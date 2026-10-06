function render_config() {
/**
 * Generates UCI firewall rules from Device.Firewall.Service instances.
 *
 * @returns {string} UCI batch output for service allow rules
 */
function generate_services() {
	let service_instances = ubbf_instances(config, 'Device.Firewall.Service');

	for (let svc in service_instances) {
		if (!ubbf_to_bool(svc.Enable))
			continue;

		let iface_name = interface_to_name(config, svc.Interface);
		if (!iface_name)
			continue;

		uci_section(output, 'firewall rule');

		let alias = svc.Alias ?? '';
		if (alias != '')
			uci_set_string(output, 'firewall.@rule[-1].name', alias);

		uci_set_string(output, 'firewall.@rule[-1].src', iface_name);

		for (let port in csv_to_list(svc.DestPort))
			uci_list_string(output, 'firewall.@rule[-1].dest_port', port);

		for (let proto in csv_to_list(svc.Protocol))
			uci_list_string(output, 'firewall.@rule[-1].proto', ubbf.protocol_to_uci(proto));

		let family = ipversion_to_family(svc.IPVersion);
		if (family)
			uci_set_string(output, 'firewall.@rule[-1].family', family);

		let icmp_type = ubbf_to_int(svc.ICMPType);
		if (icmp_type != null && icmp_type != -1)
			uci_set_number(output, 'firewall.@rule[-1].icmp_type', icmp_type);

		for (let prefix in csv_to_list(svc.SourcePrefixes, ''))
			uci_list_string(output, 'firewall.@rule[-1].src_ip', prefix);

		let action = target_to_uci(svc.Action);
		uci_set_string(output, 'firewall.@rule[-1].target', action);
	}

	return;
}

	generate_services();
}
render_config();
