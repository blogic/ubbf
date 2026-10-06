function render_config() {
/**
 * Generates UCI firewall redirect entries for DMZ (DNAT all inbound traffic).
 *
 * @returns {string} UCI batch output for DMZ redirect entries
 */
function generate_dmz() {
	// ADMZ (Device.NAT.X_UBBF_IPPassthrough) wins when both are active.
	// firewall-admz.uc sets render_state.admz_active when its catchall
	// is being emitted; a classic DMZ rule on top would compete for
	// inbound WAN traffic on <wan-pub>, so skip classic DMZ emission
	// entirely in that case. The reverse precedence needs no guard:
	// ADMZ is only emitted when its own state is Enabled_Active.
	if (render_state?.admz_active)
		return;

	let dmz_instances = ubbf_instances(config, 'Device.Firewall.DMZ');

	for (let dmz in dmz_instances) {
		if (!ubbf_to_bool(dmz.Enable))
			continue;
		if (!dmz.DestIP || dmz.DestIP == '')
			continue;

		uci_section(output, 'firewall redirect');
		uci_set_string(output, 'firewall.@redirect[-1].target', 'DNAT');
		uci_set_boolean(output, 'firewall.@redirect[-1].enabled', true);

		let iface_name = interface_to_name(config, dmz.Interface);
		if (iface_name)
			uci_set_string(output, 'firewall.@redirect[-1].src', iface_name);

		let iface_settings = ubbf_instances(config, 'Device.Firewall.InterfaceSetting');
		for (let ifs in iface_settings) {
			if (!ubbf_to_bool(ifs.Enable))
				continue;
			let dest_name = interface_to_name(config, ifs.Interface);
			if (!dest_name || dest_name == iface_name)
				continue;
			let dest_iface = ubbf_get(config, ifs.Interface);
			if (dest_iface?.Upstream == 'true')
				continue;
			uci_set_string(output, 'firewall.@redirect[-1].dest', dest_name);
			break;
		}

		uci_set_string(output, 'firewall.@redirect[-1].dest_ip', dmz.DestIP);

		if (dmz.SourcePrefix && dmz.SourcePrefix != '')
			uci_set_string(output, 'firewall.@redirect[-1].src_ip', dmz.SourcePrefix);

		if (dmz.Description && dmz.Description != '')
			uci_set_string(output, 'firewall.@redirect[-1].name', dmz.Description);

		redirect_emit_reflection(config, output);
	}

	return;
}

	generate_dmz();
}
render_config();
