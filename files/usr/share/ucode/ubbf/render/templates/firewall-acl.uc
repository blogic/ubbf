function render_config() {
/**
 * Returns the time windows of an AccessControl entry: its ScheduleRef and,
 * until TR-181 2.21, its inline Schedule rows.
 *
 * @param {object} ac - AccessControl instance
 * @returns {array|null} Windows, or null when the entry is not scheduled
 */
function acl_windows(ac) {
	let inline = (dm_visible(null, '2.21') && type(ac.Schedule) == 'object') ? values(ac.Schedule) : null;
	return schedule_windows(ac.ScheduleRef, inline);
}

/**
 * Emits firewall rules for a single AccessControl entry against a zone.
 * Deny entries produce a forward and input REJECT pair; scheduled
 * Allow entries produce an ACCEPT rule per time window followed by a
 * Block REJECT pair to deny traffic outside the schedule windows.
 *
 * @param {array} output - UCI batch output array to append to
 * @param {object} ac - AccessControl instance
 * @param {string} zone - Zone name to apply the rule against
 */
function acl_rules_emit(output, ac, zone) {
	let mac = ac.PhysAddress;
	let name_prefix = ac.HostName || mac;

	if (ac.AccessPolicy == 'Deny') {
		uci_section(output, 'firewall rule');
		uci_set_string(output, 'firewall.@rule[-1].name',
			sprintf('ACL-Deny-%s-%s', name_prefix, zone));
		uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
		uci_set_string(output, 'firewall.@rule[-1].src', zone);
		uci_set_string(output, 'firewall.@rule[-1].dest', '*');
		uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
		uci_set_string(output, 'firewall.@rule[-1].target', 'REJECT');

		uci_section(output, 'firewall rule');
		uci_set_string(output, 'firewall.@rule[-1].name',
			sprintf('ACL-Deny-Input-%s-%s', name_prefix, zone));
		uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
		uci_set_string(output, 'firewall.@rule[-1].src', zone);
		uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
		uci_set_string(output, 'firewall.@rule[-1].target', 'REJECT');
		return;
	}

	let windows = acl_windows(ac);
	if (windows == null)
		return;

	for (let n = 0; n < length(windows); n++) {
		uci_section(output, 'firewall rule');
		uci_set_string(output, 'firewall.@rule[-1].name',
			sprintf('ACL-Allow-%s-%s-W%d', name_prefix, zone, n + 1));
		uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
		uci_set_string(output, 'firewall.@rule[-1].src', zone);
		uci_set_string(output, 'firewall.@rule[-1].dest', '*');
		uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
		uci_set_string(output, 'firewall.@rule[-1].target', 'ACCEPT');
		rule_window_set(output, windows[n]);
	}

	uci_section(output, 'firewall rule');
	uci_set_string(output, 'firewall.@rule[-1].name',
		sprintf('ACL-Block-%s-%s', name_prefix, zone));
	uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
	uci_set_string(output, 'firewall.@rule[-1].src', zone);
	uci_set_string(output, 'firewall.@rule[-1].dest', '*');
	uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
	uci_set_string(output, 'firewall.@rule[-1].target', 'REJECT');

	uci_section(output, 'firewall rule');
	uci_set_string(output, 'firewall.@rule[-1].name',
		sprintf('ACL-Block-Input-%s-%s', name_prefix, zone));
	uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
	uci_set_string(output, 'firewall.@rule[-1].src', zone);
	uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
	uci_set_string(output, 'firewall.@rule[-1].target', 'REJECT');
}

/**
 * Generates access control firewall rules from Device.Hosts.AccessControl.
 *
 * @returns {string} UCI batch output for ACL rules
 */
function generate_access_control() {
	let ac_instances = ubbf_instances(config, 'Device.Hosts.AccessControl');
	if (!ac_instances || !length(ac_instances))
		return;

	let iface_settings = ubbf_instances(config, 'Device.Firewall.InterfaceSetting');
	let zones = [];
	for (let ifs in iface_settings) {
		if (!ubbf_to_bool(ifs.Enable))
			continue;
		if (ubbf_to_bool(ifs.StealthMode))
			continue;
		let name = interface_to_name(config, ifs.Interface);
		if (name)
			push(zones, name);
	}

	if (!length(zones))
		return;


	for (let ac in ac_instances) {
		if (!ubbf_to_bool(ac.Enable))
			continue;
		if (!ac.PhysAddress || ac.PhysAddress == '')
			continue;

		for (let zone in zones)
			acl_rules_emit(output, ac, zone);
	}

	return;
}

	generate_access_control();
}
render_config();
