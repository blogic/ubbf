function render_config() {
	if (!fs.stat('/usr/sbin/umapd'))
		return;

	let network = ubbf_get(config, 'Device.WiFi.DataElements.Network');
	if (!network)
		return;

	// Three-letter lowercase abbreviations match the umapd schedule day format.
	const DAY_MAP = {
		'Monday': 'mon', 'Tuesday': 'tue', 'Wednesday': 'wed',
		'Thursday': 'thu', 'Friday': 'fri', 'Saturday': 'sat', 'Sunday': 'sun'
	};

	/**
	 * Maps a TR-181 day name to the umapd UCI day abbreviation.
	 *
	 * Falls back to the lowercased first three characters of the input
	 * to tolerate unexpected casing or abbreviated input.
	 *
	 * @param {string} day - TR-181 day name (e.g. "Monday")
	 * @returns {string} UCI day token (e.g. "mon")
	 */
	function day_tr181_to_uci(day) {
		return DAY_MAP[day] ?? lc(substr(day, 0, 3));
	}

	let bridge_path = network.X_UBBF_EasyMesh?.Bridge;
	let bridge = ubbf_get(config, bridge_path);
	let br_name = bridge?.Name;
	let br_state = br_name ? render_state.bridge?.[br_name] : null;

	let network_name;
	if (bridge_path) {
		let ip_interfaces = ubbf_instances(config, 'Device.IP.Interface');
		for (let iface in ip_interfaces) {
			if (index(iface.LowerLayers ?? '', bridge_path) >= 0) {
				network_name = iface.Name;
				break;
			}
		}
	}


	if (ubbf_to_bool(network.X_UBBF_EasyMesh?.Agent?.Enable) && br_name) {
		uci_named_section(output, 'umapd.agent', 'agent');
		uci_set_boolean(output, 'umapd.agent.enabled', true);
		uci_list_string(output, 'umapd.agent.radio', '*');
		uci_list_string(output, 'umapd.agent.bridge', br_name);

		// The agent adds its backhaul station to this bridge, and a wired port
		// can be a member of it as well. That is a loop, and umapd does not
		// resolve it: it chooses which medium carries 1905 and never removes a
		// bridge port. Spanning tree is what blocks the redundant path, so a
		// bridge the agent runs on gets it whatever the data model asked for.
		// Measured on a test bed on 2026-09-12, with stp off: a cabled agent
		// that also held a station lost 30 per cent of its packets and the
		// controller's bridge flapped its address between the two ports.
		device_state_set(render_state, br_name, 'stp', '1');

		if (network_name)
			uci_set_string(output, 'umapd.agent.network', network_name);

		if (br_state?.mgmt_vlan_section)
			uci_list_string(output, 'umapd.agent.bridge_default_vlan', br_state.mgmt_vlan_section);

		uci_set_number(output, 'umapd.agent.verbosity', 1);
	}

	if (ubbf_to_bool(network.X_UBBF_EasyMesh?.Controller?.Enable)) {
		uci_named_section(output, 'umapd.controller', 'controller');
		uci_set_boolean(output, 'umapd.controller.enabled', true);

		if (network_name)
			uci_set_string(output, 'umapd.controller.network', network_name);

		let keys = config.EasyMesh?.Controller;
		if (keys)
			for (let key in ['c_sign_key_privkey', 'c_sign_key_pubkey_x', 'c_sign_key_pubkey_y',
			                 'net_access_key_privkey', 'net_access_key_pubkey_x', 'net_access_key_pubkey_y', 'connector'])
				uci_set_string(output, `umapd.controller.${key}`, keys[key]);

		let ts = config.EasyMesh?.TrafficSeparation;
		if (ts?.enabled)
			uci_set_boolean(output, 'umapd.controller.traffic_separation', true);

		let primary_vid = ts?.primary_vid ?? br_state?.mgmt_vid;
		if (primary_vid)
			uci_set_number(output, 'umapd.controller.primary_vlan_id', primary_vid);

		uci_set_boolean(output, 'umapd.controller.dpp_backhaul', true);
		uci_set_number(output, 'umapd.controller.verbosity', 1);
	}

	let ssids = config.EasyMesh?.SSIDs ?? [];
	for (let i, entry in ssids) {
		if (!entry.enabled)
			continue;

		let section_type = (entry.backhaul && !entry.fronthaul) ? 'backhaul' : 'fronthaul';
		let section_name = replace(lc(entry.ssid), /[^a-z0-9_]/g, '_');
		if (length(section_name) == 0 || match(section_name, /^[0-9]/))
			section_name = 'ssid_' + section_name;

		uci_named_section(output, `umapd.${section_name}`, section_type);
		uci_set_string(output, `umapd.${section_name}.ssid`, entry.ssid);

		if (entry.key)
			uci_set_string(output, `umapd.${section_name}.key`, entry.key);

		for (let auth in entry.authentication ?? [])
			uci_list_string(output, `umapd.${section_name}.authentication`, auth);

		for (let b in entry.band ?? [])
			uci_list_string(output, `umapd.${section_name}.band`, b);

		if (entry.hidden != null)
			uci_set_boolean(output, `umapd.${section_name}.hidden`, entry.hidden);

		if (entry.fronthaul && entry.backhaul)
			uci_set_boolean(output, `umapd.${section_name}.backhaul`, true);

		let ts = config.EasyMesh?.TrafficSeparation;
		if (ts?.enabled && entry.fronthaul) {
			let vid = ts.ssid_vid_mappings?.[entry.ssid];
			if (vid)
				uci_set_number(output, `umapd.${section_name}.vlan`, vid);
		}
	}

	let sta_blocks = ubbf_instances(config, 'Device.WiFi.DataElements.Network.STABlock');
	for (let block in sta_blocks) {
		let inst = block['.instance'];
		let section_name = sprintf('blocked_sta_%s', inst);

		uci_named_section(output, `umapd.${section_name}`, 'blocked_sta');
		uci_set_string(output, `umapd.${section_name}.sta`, block.BlockedSTA);

		for (let bssid in csv_to_list(block.BSSID))
			uci_list_string(output, `umapd.${section_name}.bssid`, bssid);

		let schedules = ubbf_instances(config, `${block['.path']}.Schedule`);
		for (let schedule in schedules) {
			let sched_inst = schedule['.instance'];
			let sched_name = sprintf('blocked_sta_%s_sched_%s', inst, sched_inst);

			uci_named_section(output, `umapd.${sched_name}`, 'blocked_sta_schedule');
			uci_set_string(output, `umapd.${sched_name}.blocked_sta`, section_name);

			for (let day in csv_to_list(schedule.Day))
				uci_list_string(output, `umapd.${sched_name}.day`, day_tr181_to_uci(day));

			if (schedule.StartTime)
				uci_set_string(output, `umapd.${sched_name}.start_time`, schedule.StartTime);

			if (schedule.Duration)
				uci_set_number(output, `umapd.${sched_name}.duration`, ubbf_to_int(schedule.Duration));
		}
	}

	let dpp_entries = ubbf_instances(config, 'Device.WiFi.DataElements.Network.ProvisionedDPP');
	for (let entry in dpp_entries) {
		if (!entry.DPPURI)
			continue;

		let inst = entry['.instance'];
		let section_name = sprintf('dpp_bootstrap_%s', inst);

		uci_named_section(output, `umapd.${section_name}`, 'dpp_bootstrap');
		uci_set_string(output, `umapd.${section_name}.uri`, entry.DPPURI);
	}

	let policy_path = '/etc/umap-policy.d/ubbf.json';
	let policy_data = {};
	let policy_entries = ubbf_instances(config, 'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Controller.Policy');
	for (let entry in policy_entries) {
		if (!entry.ALMAC || !entry.Data)
			continue;

		let parsed = json(entry.Data);
		if (type(parsed) != 'object')
			continue;

		policy_data[entry.ALMAC] = parsed;
	}

	let sp = config.EasyMesh?.ServicePrioritization;
	if (sp?.enabled) {
		policy_data["*"] ??= {};
		policy_data["*"].service_prioritization = {
			rules: sp.rules,
			dscp_mapping_table: sp.dscp_mapping_table
		};
	}

	let qm = config.EasyMesh?.QoSManagement;
	if (qm) {
		policy_data["*"] ??= {};
		policy_data["*"].qos_management = {};
		if (qm.mscs_disallowed_sta)
			policy_data["*"].qos_management.mscs_disallowed_sta = qm.mscs_disallowed_sta;
		if (qm.scs_disallowed_sta)
			policy_data["*"].qos_management.scs_disallowed_sta = qm.scs_disallowed_sta;
	}

	for (let al_mac, pd in policy_data) {
		let mr = pd.metric_reporting;
		if (type(mr) != 'object')
			continue;
		pd.unsuccessful_association ??= {};
		if (type(mr.report_unsuccessful_associations) == 'bool')
			pd.unsuccessful_association.report_unsuccessful_assocs ??= mr.report_unsuccessful_associations;
		if (type(mr.max_reporting_rate) == 'int')
			pd.unsuccessful_association.max_reporting_rate ??= mr.max_reporting_rate;
	}

	policy_data["*"] ??= {};
	policy_data["*"].unsuccessful_association ??= {};
	policy_data["*"].unsuccessful_association.report_unsuccessful_assocs ??= true;
	policy_data["*"].unsuccessful_association.max_reporting_rate ??= 30;

	for (let al_mac, disallowed in config.EasyMesh?.STASteeringDisallowed ?? {}) {
		if (!disallowed)
			continue;
		policy_data[al_mac] ??= {};
		policy_data[al_mac].agent_steering = { disallowed: true };
	}

	for (let al_mac, entries in config.EasyMesh?.TxPowerLimit ?? {}) {
		if (length(entries) > 0) {
			policy_data[al_mac] ??= {};
			policy_data[al_mac].txpower_limit = entries;
		}
	}

	for (let al_mac, descriptors in config.EasyMesh?.QMDescriptors ?? {}) {
		if (length(descriptors) > 0) {
			policy_data[al_mac] ??= {};
			policy_data[al_mac].service_prioritization ??= {};
			policy_data[al_mac].service_prioritization.descriptors = descriptors;
		}
	}

	for (let al_mac, radios in config.EasyMesh?.EHTOperations ?? {}) {
		if (length(keys(radios)) > 0) {
			policy_data[al_mac] ??= {};
			policy_data[al_mac].eht_operations = radios;
		}
	}

	for (let al_mac, ruids in config.EasyMesh?.DisabledRadios ?? {}) {
		let entries = map(keys(ruids), (ruid) => ({ ruid }));
		if (length(entries) > 0) {
			policy_data[al_mac] ??= {};
			policy_data[al_mac].disabled_radios = entries;
		}
	}

	let de_devices = config?.Device?.WiFi?.DataElements?.Network?.Device;
	for (let al_mac, ruid_map in config.EasyMesh?.DisAllowedChannels ?? {}) {
		let dc = {};
		for (let ruid, data in ruid_map) {
			let radio_cfg = de_devices?.[sprintf('%d', data.device_inst)]
				?.Radio?.[sprintf('%d', data.radio_inst)];
			let entries = [];
			for (let inst, dac in radio_cfg?.DisAllowedOpClassChannels ?? {}) {
				if (ubbf_to_bool(dac.Enable))
					push(entries, { opclass: ubbf_to_int(dac.OpClass), channels: map(csv_to_list(dac.ChannelList), (c) => int(c)) });
			}
			if (length(entries) > 0)
				dc[ruid] = entries;
		}
		if (length(keys(dc)) > 0) {
			policy_data[al_mac] ??= {};
			policy_data[al_mac].disallowed_channels = dc;
		}
	}

	let new_content = sprintf('%.J\n', policy_data);
	let old_content = fs.readfile(policy_path);
	if (new_content != old_content) {
		fs.mkdir('/etc/umap-policy.d', 0755);
		fs.writefile(policy_path, new_content);
		ubus.call({ object: 'umap', method: 'reload' });
	}

}
uci_comment(output, '# generated by umapd.uc');
render_config();
