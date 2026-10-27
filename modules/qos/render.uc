function render_config() {
	/**
	 * Returns the instance number of a Device.WiFi.SSID reference, with or
	 * without the trailing dot.
	 *
	 * @param {string} iface_ref - Interface reference path
	 * @returns {string|null} Instance number, or null for another reference
	 */
	function ssid_ref_instance(iface_ref) {
		let m = match(iface_ref, /^Device\.WiFi\.SSID\.(\d+)\.?$/);
		return m ? m[1] : null;
	}

	/**
	 * Generates the ratelimit defaults of the WiFi SSID shapers.
	 *
	 * ratelimit applies the rate to each station of the SSID, in both
	 * directions. The defaults are named after the SSID text, which the
	 * sta-authorized handler of wifi-events.uc also uses, so SSIDs with the
	 * same name share one rate. A rate in percent has no link rate to refer
	 * to and is not rendered; the get handler reports Error_Misconfigured.
	 *
	 * @param {array} shapers - QoS shaper instances
	 */
	function generate_wifi_shapers(shapers) {
		for (let shaper in shapers) {
			if (!ubbf_to_bool(shaper.Enable))
				continue;

			let ssid_inst = ssid_ref_instance(shaper.Interface);
			if (!ssid_inst)
				continue;

			let rate = ubbf_to_int(shaper.ShapingRate);
			if (rate == null || rate <= 100)
				continue;

			let ssid = ubbf_get(config, `Device.WiFi.SSID.${ssid_inst}`);
			if (!ssid?.SSID)
				continue;

			let section_name = digest.md5(ssid.SSID);
			let rate_bit = sprintf('%dbit', rate);

			uci_named_section(output, `ratelimit.${section_name}`, 'rate');
			uci_set_string(output, `ratelimit.${section_name}.ingress`, rate_bit);
			uci_set_string(output, `ratelimit.${section_name}.egress`, rate_bit);
		}
	}

	/**
	 * Generates UCI QoS shaper sections. Each enabled row gets a section,
	 * so that bbf-qos-apply records a Status for it.
	 *
	 * @param {array} shapers - QoS shaper instances
	 */
	function generate_shapers(shapers) {
		for (let shaper in shapers) {
			if (!ubbf_to_bool(shaper.Enable))
				continue;
			if (ssid_ref_instance(shaper.Interface))
				continue;

			uci_section(output, 'bbf-qos shaper');
			uci_set_boolean(output, 'bbf-qos.@shaper[-1].enabled', true);
			uci_set_string(output, 'bbf-qos.@shaper[-1].path', shaper['.path']);

			let iface = interface_to_name(config, shaper.Interface);
			if (iface)
				uci_set_string(output, 'bbf-qos.@shaper[-1].interface', iface);

			let rate = ubbf_to_int(shaper.ShapingRate);
			if (rate != null)
				uci_set_number(output, 'bbf-qos.@shaper[-1].shaping_rate', rate);

			let burst = ubbf_to_int(shaper.ShapingBurstSize);
			if (burst != null && burst > 0)
				uci_set_number(output, 'bbf-qos.@shaper[-1].shaping_burst_size', burst);
		}
	}

	/**
	 * Generates UCI QoS queue sections.
	 *
	 * @param {array} queues - QoS queue instances
	 */
	function generate_queues(queues) {
		for (let queue in queues) {
			if (!ubbf_to_bool(queue.Enable))
				continue;

			uci_section(output, 'bbf-qos queue');
			uci_set_boolean(output, 'bbf-qos.@queue[-1].enabled', true);
			uci_set_string(output, 'bbf-qos.@queue[-1].path', queue['.path']);

			let iface = interface_to_name(config, queue.Interface);
			if (iface)
				uci_set_string(output, 'bbf-qos.@queue[-1].interface', iface);

			for (let traffic_class in csv_to_list(queue.TrafficClasses))
				uci_list_string(output, 'bbf-qos.@queue[-1].traffic_classes', traffic_class);

			let weight = ubbf_to_int(queue.Weight);
			if (weight != null && weight > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].weight', weight);

			let precedence = ubbf_to_int(queue.Precedence);
			if (precedence != null && precedence > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].precedence', precedence);

			if (queue.SchedulerAlgorithm && queue.SchedulerAlgorithm != '')
				uci_set_string(output, 'bbf-qos.@queue[-1].scheduler_algorithm', queue.SchedulerAlgorithm);

			let shaping_rate = ubbf_to_int(queue.ShapingRate);
			if (shaping_rate != null)
				uci_set_number(output, 'bbf-qos.@queue[-1].shaping_rate', shaping_rate);

			let shaping_burst = ubbf_to_int(queue.ShapingBurstSize);
			if (shaping_burst != null && shaping_burst > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].shaping_burst_size', shaping_burst);
		}
	}

	/**
	 * Generates UCI QoS policer sections.
	 *
	 * @param {array} policers - QoS policer instances
	 */
	function generate_policers(policers) {
		for (let policer in policers) {
			if (!ubbf_to_bool(policer.Enable))
				continue;

			uci_section(output, 'bbf-qos policer');
			uci_set_boolean(output, 'bbf-qos.@policer[-1].enabled', true);
			uci_set_string(output, 'bbf-qos.@policer[-1].path', policer['.path']);

			let committed_rate = ubbf_to_int(policer.CommittedRate);
			if (committed_rate != null && committed_rate > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].committed_rate', committed_rate);

			let committed_burst = ubbf_to_int(policer.CommittedBurstSize);
			if (committed_burst != null && committed_burst > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].committed_burst_size', committed_burst);
		}
	}

	/**
	 * Writes an integer option of a classification when it is at least
	 * the given minimum, the TR-181 value below it meaning "no match".
	 *
	 * @param {string} option - UCI option name
	 * @param {*} value - TR-181 value
	 * @param {number} minimum - Smallest value that takes effect
	 */
	function classify_number(option, value, minimum) {
		let n = ubbf_to_int(value);
		if (n != null && n >= minimum)
			uci_set_number(output, `bbf-qos.@classify[-1].${option}`, n);
	}

	/**
	 * Writes a string option of a classification when it is not empty.
	 *
	 * @param {string} option - UCI option name
	 * @param {*} value - TR-181 value
	 */
	function classify_string(option, value) {
		if (value && value != '')
			uci_set_string(output, `bbf-qos.@classify[-1].${option}`, value);
	}

	/**
	 * Generates UCI QoS classification sections.
	 *
	 * The raw Interface reference goes along with the resolved name, so
	 * that bbf-qos-apply can refuse a reference that does not resolve
	 * instead of matching every interface.
	 *
	 * @param {array} classifications - QoS classification instances
	 */
	function generate_classifications(classifications) {
		for (let c in classifications) {
			if (!ubbf_to_bool(c.Enable))
				continue;

			uci_section(output, 'bbf-qos classify');
			uci_set_boolean(output, 'bbf-qos.@classify[-1].enabled', true);
			uci_set_string(output, 'bbf-qos.@classify[-1].path', c['.path']);
			uci_set_number(output, 'bbf-qos.@classify[-1].instance', ubbf_to_int(c['.instance']));

			classify_number('order', c.Order, 1);

			if (ubbf_to_bool(c.AllInterfaces))
				uci_set_boolean(output, 'bbf-qos.@classify[-1].all_interfaces', true);

			classify_string('interface_ref', c.Interface);
			classify_string('interface', interface_to_name(config, c.Interface));
			classify_string('dest_ip', c.DestIP);
			classify_string('dest_mask', c.DestMask);
			classify_string('source_ip', c.SourceIP);
			classify_string('source_mask', c.SourceMask);
			classify_number('protocol', c.Protocol, 0);
			classify_number('dest_port', c.DestPort, 0);
			classify_number('dest_port_range_max', c.DestPortRangeMax, 0);
			classify_number('source_port', c.SourcePort, 0);
			classify_number('source_port_range_max', c.SourcePortRangeMax, 0);
			classify_string('source_mac_address', c.SourceMACAddress);
			classify_string('dest_mac_address', c.DestMACAddress);
			classify_number('ethertype', c.Ethertype, 0);
			classify_number('ip_length_min', c.IPLengthMin, 1);
			classify_number('ip_length_max', c.IPLengthMax, 1);
			classify_number('dscp_check', c.DSCPCheck, 0);
			classify_number('dscp_mark', c.DSCPMark, 0);
			classify_number('ethernet_priority_check', c.EthernetPriorityCheck, 0);
			classify_number('vlan_id_check', c.VLANIDCheck, 0);
			classify_number('traffic_class', c.TrafficClass, 0);
			classify_string('policer', c.Policer);

			if (dm_visible('2.21', null) && !ubbf_to_bool(c.StopProcessing ?? 'true'))
				uci_set_boolean(output, 'bbf-qos.@classify[-1].stop_processing', false);
		}
	}

	/**
	 * Turns on the fw4 flow offload, in hardware where the device has it,
	 * when an enabled classification asks for it.
	 *
	 * @param {array} classifications - QoS classification instances
	 */
	function generate_offload(classifications) {
		if (!dm_visible('2.21', null))
			return;

		for (let c in classifications) {
			if (!ubbf_to_bool(c.Enable) || !ubbf_to_bool(c.HardwareOffloadEnabled ?? 'false'))
				continue;

			uci_set_boolean(output, 'firewall.@defaults[-1].flow_offloading', true);
			uci_set_boolean(output, 'firewall.@defaults[-1].flow_offloading_hw', true);
			return;
		}
	}

	// wifi-events.uc sets the per-station limits of RADIUS through the
	// ratelimit daemon as well, so it runs whenever there is WiFi.
	services.set_enabled('ratelimit', length(ubbf_instances(config, 'Device.WiFi.SSID')) > 0);

	uci_named_section(output, 'firewall.bbf_qos', 'include');
	uci_set_string(output, 'firewall.bbf_qos.type', 'script');
	uci_set_string(output, 'firewall.bbf_qos.path', '/usr/share/ubbf/bbf-qos.fw4');
	uci_set_boolean(output, 'firewall.bbf_qos.fw4_compatible', true);

	if (!ubbf_get(config, 'Device.QoS'))
		return;

	let shapers = ubbf_instances(config, 'Device.QoS.Shaper');

	generate_shapers(shapers);
	generate_wifi_shapers(shapers);
	generate_queues(ubbf_instances(config, 'Device.QoS.Queue'));
	generate_policers(ubbf_instances(config, 'Device.QoS.Policer'));
	let classifications = ubbf_instances(config, 'Device.QoS.Classification');

	generate_classifications(classifications);
	generate_offload(classifications);
}
uci_comment(output, '# generated by qos/render.uc');
render_config();
