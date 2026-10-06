function render_config() {
	/**
	 * Checks if a reference path points to a WiFi SSID.
	 *
	 * @param {string} iface_ref - Interface reference path
	 * @returns {boolean} True if path is a WiFi SSID reference
	 */
	function is_wifi_ssid_ref(iface_ref) {
		return match(iface_ref, /^Device\.WiFi\.SSID\.\d+$/);
	}

	/**
	 * Extracts the instance number from a WiFi SSID reference.
	 *
	 * @param {string} iface_ref - WiFi SSID reference path
	 * @returns {string|null} Instance number or null
	 */
	function ssid_ref_to_instance(iface_ref) {
		let m = match(iface_ref, /Device\.WiFi\.SSID\.(\d+)/);
		return m ? m[1] : null;
	}

	/**
	 * Generates ratelimit UCI sections for WiFi SSID shapers.
	 *
	 * @param {array} shapers - QoS shaper instances
	 * @returns {string} UCI batch output for ratelimit sections
	 */
	function generate_wifi_shapers(shapers) {
		let has_wifi_shaper = false;

		for (let shaper in shapers) {
			if (!ubbf_to_bool(shaper.Enable))
				continue;
			if (!is_wifi_ssid_ref(shaper.Interface))
				continue;

			let rate = ubbf_to_int(shaper.ShapingRate);
			if (rate == null || rate < 0)
				continue;

			let ssid_inst = ssid_ref_to_instance(shaper.Interface);
			let ssid = ubbf_get(config, `Device.WiFi.SSID.${ssid_inst}`);
			if (!ssid)
				continue;

			let rate_mbit = sprintf('%dmbit', rate / 1000);
			let section_name = digest.md5(ssid.SSID);

			uci_named_section(output, `ratelimit.${section_name}`, 'rate');
			uci_set_string(output, `ratelimit.${section_name}.ingress`, rate_mbit);
			uci_set_string(output, `ratelimit.${section_name}.egress`, rate_mbit);
			has_wifi_shaper = true;
		}

		services.set_enabled('ratelimit', has_wifi_shaper ? 'restart' : 'stop');

		return;
	}

	/**
	 * Generates UCI QoS shaper sections.
	 *
	 * @param {array} shapers - QoS shaper instances
	 * @returns {string} UCI batch output for shapers
	 */
	function generate_shapers(shapers) {

		for (let shaper in shapers) {
			if (!ubbf_to_bool(shaper.Enable))
				continue;
			if (is_wifi_ssid_ref(shaper.Interface))
				continue;

			let iface = interface_to_name(config, shaper.Interface);
			if (!iface)
				continue;

			let rate = ubbf_to_int(shaper.ShapingRate);
			if (rate == null || rate < 0)
				continue;

			uci_section(output, 'bbf-qos shaper');
			uci_set_boolean(output, 'bbf-qos.@shaper[-1].enabled', true);

			if (shaper.Alias && shaper.Alias != '')
				uci_set_string(output, 'bbf-qos.@shaper[-1].alias', shaper.Alias);

			uci_set_string(output, 'bbf-qos.@shaper[-1].interface', iface);
			uci_set_number(output, 'bbf-qos.@shaper[-1].shaping_rate', rate);

			let burst = ubbf_to_int(shaper.ShapingBurstSize);
			if (burst != null && burst > 0)
				uci_set_number(output, 'bbf-qos.@shaper[-1].shaping_burst_size', burst);
		}

		return;
	}

	/**
	 * Generates UCI QoS queue sections.
	 *
	 * @param {array} queues - QoS queue instances
	 * @returns {string} UCI batch output for queues
	 */
	function generate_queues(queues) {

		for (let queue in queues) {
			if (!ubbf_to_bool(queue.Enable))
				continue;

			uci_section(output, 'bbf-qos queue');
			uci_set_boolean(output, 'bbf-qos.@queue[-1].enabled', true);

			if (queue.Alias && queue.Alias != '')
				uci_set_string(output, 'bbf-qos.@queue[-1].alias', queue.Alias);

			let iface = interface_to_name(config, queue.Interface);
			if (iface)
				uci_set_string(output, 'bbf-qos.@queue[-1].interface', iface);

			let traffic_classes = json(queue.TrafficClasses);
			if (type(traffic_classes) == 'array' && length(traffic_classes))
				uci_set_string(output, 'bbf-qos.@queue[-1].traffic_classes', queue.TrafficClasses);

			let weight = ubbf_to_int(queue.Weight);
			if (weight != null && weight > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].weight', weight);

			let precedence = ubbf_to_int(queue.Precedence);
			if (precedence != null && precedence > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].precedence', precedence);

			if (queue.SchedulerAlgorithm && queue.SchedulerAlgorithm != '')
				uci_set_string(output, 'bbf-qos.@queue[-1].scheduler_algorithm', queue.SchedulerAlgorithm);

			let shaping_rate = ubbf_to_int(queue.ShapingRate);
			if (shaping_rate != null && shaping_rate >= 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].shaping_rate', shaping_rate);

			let shaping_burst = ubbf_to_int(queue.ShapingBurstSize);
			if (shaping_burst != null && shaping_burst > 0)
				uci_set_number(output, 'bbf-qos.@queue[-1].shaping_burst_size', shaping_burst);
		}

		return;
	}

	/**
	 * Generates UCI QoS policer sections.
	 *
	 * @param {array} policers - QoS policer instances
	 * @returns {string} UCI batch output for policers
	 */
	function generate_policers(policers) {

		for (let policer in policers) {
			if (!ubbf_to_bool(policer.Enable))
				continue;

			uci_section(output, 'bbf-qos policer');
			uci_set_boolean(output, 'bbf-qos.@policer[-1].enabled', true);

			if (policer['.path'])
				uci_set_string(output, 'bbf-qos.@policer[-1].path', policer['.path'] + '.');

			if (policer.Alias && policer.Alias != '')
				uci_set_string(output, 'bbf-qos.@policer[-1].alias', policer.Alias);

			let committed_rate = ubbf_to_int(policer.CommittedRate);
			if (committed_rate != null && committed_rate > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].committed_rate', committed_rate);

			let committed_burst = ubbf_to_int(policer.CommittedBurstSize);
			if (committed_burst != null && committed_burst > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].committed_burst_size', committed_burst);

			let excess_burst = ubbf_to_int(policer.ExcessBurstSize);
			if (excess_burst != null && excess_burst > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].excess_burst_size', excess_burst);

			let peak_rate = ubbf_to_int(policer.PeakRate);
			if (peak_rate != null && peak_rate > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].peak_rate', peak_rate);

			let peak_burst = ubbf_to_int(policer.PeakBurstSize);
			if (peak_burst != null && peak_burst > 0)
				uci_set_number(output, 'bbf-qos.@policer[-1].peak_burst_size', peak_burst);

			if (policer.MeterType && policer.MeterType != '')
				uci_set_string(output, 'bbf-qos.@policer[-1].meter_type', policer.MeterType);

			if (policer.PossibleMeterTypes && policer.PossibleMeterTypes != '')
				uci_set_string(output, 'bbf-qos.@policer[-1].possible_meter_types', policer.PossibleMeterTypes);
		}

		return;
	}

	/**
	 * Generates UCI QoS classification sections.
	 *
	 * @param {array} classifications - QoS classification instances
	 * @returns {string} UCI batch output for classifications
	 */
	function generate_classifications(classifications) {

		for (let c in classifications) {
			if (!ubbf_to_bool(c.Enable))
				continue;

			uci_section(output, 'bbf-qos classify');
			uci_set_boolean(output, 'bbf-qos.@classify[-1].enabled', true);

			let order = ubbf_to_int(c.Order);
			if (order != null && order > 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].order', order);

			if (c.Alias && c.Alias != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].alias', c.Alias);

			let iface = interface_to_name(config, c.Interface);
			if (iface)
				uci_set_string(output, 'bbf-qos.@classify[-1].interface', iface);

			if (ubbf_to_bool(c.AllInterfaces))
				uci_set_boolean(output, 'bbf-qos.@classify[-1].all_interfaces', true);

			if (c.DestIP && c.DestIP != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_ip', c.DestIP);

			if (c.DestMask && c.DestMask != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_mask', c.DestMask);

			if (c.SourceIP && c.SourceIP != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_ip', c.SourceIP);

			if (c.SourceMask && c.SourceMask != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_mask', c.SourceMask);

			let protocol = ubbf_to_int(c.Protocol);
			if (protocol != null && protocol >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].protocol', protocol);

			let dest_port = ubbf_to_int(c.DestPort);
			if (dest_port != null && dest_port >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].dest_port', dest_port);

			let dest_port_max = ubbf_to_int(c.DestPortRangeMax);
			if (dest_port_max != null && dest_port_max >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].dest_port_range_max', dest_port_max);

			let source_port = ubbf_to_int(c.SourcePort);
			if (source_port != null && source_port >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].source_port', source_port);

			let source_port_max = ubbf_to_int(c.SourcePortRangeMax);
			if (source_port_max != null && source_port_max >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].source_port_range_max', source_port_max);

			if (c.SourceMACAddress && c.SourceMACAddress != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_mac_address', c.SourceMACAddress);

			if (c.DestMACAddress && c.DestMACAddress != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_mac_address', c.DestMACAddress);

			let ethertype = ubbf_to_int(c.Ethertype);
			if (ethertype != null && ethertype >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].ethertype', ethertype);

			if (c.SourceVendorClassID && c.SourceVendorClassID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_vendor_class_id', c.SourceVendorClassID);

			if (c.DestVendorClassID && c.DestVendorClassID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_vendor_class_id', c.DestVendorClassID);

			if (c.SourceClientID && c.SourceClientID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_client_id', c.SourceClientID);

			if (c.DestClientID && c.DestClientID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_client_id', c.DestClientID);

			if (c.SourceUserClassID && c.SourceUserClassID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].source_user_class_id', c.SourceUserClassID);

			if (c.DestUserClassID && c.DestUserClassID != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].dest_user_class_id', c.DestUserClassID);

			let ip_length_min = ubbf_to_int(c.IPLengthMin);
			if (ip_length_min != null && ip_length_min > 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].ip_length_min', ip_length_min);

			let ip_length_max = ubbf_to_int(c.IPLengthMax);
			if (ip_length_max != null && ip_length_max > 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].ip_length_max', ip_length_max);

			let dscp_check = ubbf_to_int(c.DSCPCheck);
			if (dscp_check != null && dscp_check >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].dscp_check', dscp_check);

			let dscp_mark = ubbf_to_int(c.DSCPMark);
			if (dscp_mark != null && dscp_mark >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].dscp_mark', dscp_mark);

			let eth_prio_check = ubbf_to_int(c.EthernetPriorityCheck);
			if (eth_prio_check != null && eth_prio_check >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].ethernet_priority_check', eth_prio_check);

			let vlan_check = ubbf_to_int(c.VLANIDCheck);
			if (vlan_check != null && vlan_check >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].vlan_id_check', vlan_check);

			let forwarding_policy = ubbf_to_int(c.ForwardingPolicy);
			if (forwarding_policy != null && forwarding_policy > 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].forwarding_policy', forwarding_policy);

			let traffic_class = ubbf_to_int(c.TrafficClass);
			if (traffic_class != null && traffic_class >= 0)
				uci_set_number(output, 'bbf-qos.@classify[-1].traffic_class', traffic_class);

			if (c.Policer && c.Policer != '')
				uci_set_string(output, 'bbf-qos.@classify[-1].policer', c.Policer);
		}

		return;
	}

	/**
	 * Generates UCI QoS queue statistics sections.
	 *
	 * @param {array} queuestats - QoS queue stats instances
	 * @returns {string} UCI batch output for queue stats
	 */
	function generate_queuestats(queuestats) {

		for (let qs in queuestats) {
			if (!ubbf_to_bool(qs.Enable))
				continue;

			uci_section(output, 'bbf-qos queuestats');
			uci_set_boolean(output, 'bbf-qos.@queuestats[-1].enabled', true);

			if (qs.Alias && qs.Alias != '')
				uci_set_string(output, 'bbf-qos.@queuestats[-1].alias', qs.Alias);

			if (qs.Queue && qs.Queue != '')
				uci_set_string(output, 'bbf-qos.@queuestats[-1].queue', qs.Queue);

			let iface = interface_to_name(config, qs.Interface);
			if (iface)
				uci_set_string(output, 'bbf-qos.@queuestats[-1].interface', iface);
		}

		return;
	}

	let qos = ubbf_get(config, 'Device.QoS');
	if (!qos)
		return;

	let shapers = ubbf_instances(config, 'Device.QoS.Shaper');
	let queues = ubbf_instances(config, 'Device.QoS.Queue');
	let policers = ubbf_instances(config, 'Device.QoS.Policer');
	let classifications = ubbf_instances(config, 'Device.QoS.Classification');
	let queuestats = ubbf_instances(config, 'Device.QoS.QueueStats');

	generate_shapers(shapers);
	generate_wifi_shapers(shapers);
	generate_queues(queues);
	generate_policers(policers);
	generate_classifications(classifications);
	generate_queuestats(queuestats);
}
uci_comment(output, '# generated by qos.uc');
render_config();
