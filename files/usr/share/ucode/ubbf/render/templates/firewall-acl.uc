function render_config() {
/**
 * Computes a fw4 stop_time HH:MM:SS by adding a duration in seconds
 * to a HH:MM start time. Wraps modulo 24 hours; the caller decides
 * whether the wrap is meaningful.
 *
 * @param {string} start_time - Start time in HH:MM format
 * @param {number} duration - Duration in seconds
 * @returns {string|null} Stop time in HH:MM:SS format, or null on parse failure
 */
function schedule_stop_time(start_time, duration) {
	let m = match(start_time, /^([0-9]{2}):([0-9]{2})$/);
	if (!m)
		return null;

	let total_secs = (int(m[1]) * 3600) + (int(m[2]) * 60) + duration;
	let hours = int(total_secs / 3600) % 24;
	let mins = int((total_secs % 3600) / 60);
	let secs = total_secs % 60;
	return sprintf('%02d:%02d:%02d', hours, mins, secs);
}

/**
 * Emits firewall rules for a single AccessControl entry against a zone.
 * Deny entries produce a forward and input REJECT pair; scheduled
 * Allow entries produce per-schedule ACCEPT rules followed by a
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

	let schedules = ac.Schedule;
	if (type(schedules) != 'object')
		return;

	let has_enabled_schedule;
	for (let inst, sched in schedules) {
		if (!ubbf_to_bool(sched.Enable))
			continue;

		has_enabled_schedule = true;

		uci_section(output, 'firewall rule');
		uci_set_string(output, 'firewall.@rule[-1].name',
			sprintf('ACL-Allow-%s-%s-S%s', name_prefix, zone, inst));
		uci_set_string(output, 'firewall.@rule[-1].proto', 'all');
		uci_set_string(output, 'firewall.@rule[-1].src', zone);
		uci_set_string(output, 'firewall.@rule[-1].dest', '*');
		uci_set_string(output, 'firewall.@rule[-1].src_mac', mac);
		uci_set_string(output, 'firewall.@rule[-1].target', 'ACCEPT');

		if (sched.StartTime && sched.StartTime != '') {
			uci_set_string(output, 'firewall.@rule[-1].start_time',
				sched.StartTime + ':00');

			let duration = ubbf_to_int(sched.Duration);
			if (duration && duration > 0) {
				let stop = schedule_stop_time(sched.StartTime, duration);
				if (stop)
					uci_set_string(output, 'firewall.@rule[-1].stop_time', stop);
			}
		}

		let days = csv_to_list(sched.Day);
		for (let day in days)
			uci_list_string(output, 'firewall.@rule[-1].weekdays', day);
	}

	if (!has_enabled_schedule)
		return;

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
