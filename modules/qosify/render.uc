function render_config() {
	const QOSIFY_CONF_PATH = '/tmp/ubbf/qosify.conf';

	/**
	 * Generates UCI qosify defaults section.
	 *
	 * @param {object} qosify_config - QoSify configuration object
	 * @returns {string} UCI batch output for defaults
	 */
	function generate_defaults(qosify_config) {

		uci_named_section(output, 'qosify.defaults', 'defaults');
		uci_list_string(output, 'qosify.defaults.defaults', QOSIFY_CONF_PATH);

		if (qosify_config.DefaultTCPDSCP)
			uci_set_string(output, 'qosify.defaults.dscp_default_tcp', qosify_config.DefaultTCPDSCP);

		if (qosify_config.DefaultUDPDSCP)
			uci_set_string(output, 'qosify.defaults.dscp_default_udp', qosify_config.DefaultUDPDSCP);

		if (qosify_config.ICMPDSCP)
			uci_set_string(output, 'qosify.defaults.dscp_icmp', qosify_config.ICMPDSCP);

		if (qosify_config.PriorityDSCP)
			uci_set_string(output, 'qosify.defaults.dscp_prio', qosify_config.PriorityDSCP);

		if (qosify_config.BulkDSCP)
			uci_set_string(output, 'qosify.defaults.dscp_bulk', qosify_config.BulkDSCP);

		let bulk_pps = ubbf_to_int(qosify_config.BulkTriggerPPS);
		if (bulk_pps != null && bulk_pps > 0)
			uci_set_number(output, 'qosify.defaults.bulk_trigger_pps', bulk_pps);

		let bulk_timeout = ubbf_to_int(qosify_config.BulkTriggerTimeout);
		if (bulk_timeout != null && bulk_timeout > 0)
			uci_set_number(output, 'qosify.defaults.bulk_trigger_timeout', bulk_timeout);

		let prio_pkt_len = ubbf_to_int(qosify_config.PriorityMaxAvgPktLen);
		if (prio_pkt_len != null && prio_pkt_len > 0)
			uci_set_number(output, 'qosify.defaults.prio_max_avg_pkt_len', prio_pkt_len);

		return;
	}

	/**
	 * Generates UCI qosify class sections from DSCP maps.
	 *
	 * @param {array} dscp_maps - DSCP map instances
	 * @returns {string} UCI batch output for classes
	 */
	function generate_classes(dscp_maps) {

		for (let inst, dscp_map in dscp_maps) {
			if (!ubbf_to_bool(dscp_map.Enable))
				continue;

			let name = dscp_map.Name;
			if (!name || name == '')
				continue;

			let section_name = ubbf.name_sanitise(name);
			uci_named_section(output, `qosify.${section_name}`, 'class');

			if (dscp_map.IngressDSCP)
				uci_set_string(output, `qosify.${section_name}.ingress`, dscp_map.IngressDSCP);

			if (dscp_map.EgressDSCP)
				uci_set_string(output, `qosify.${section_name}.egress`, dscp_map.EgressDSCP);
		}

		return;
	}

	/**
	 * Generates UCI qosify interface sections.
	 *
	 * @param {array} interface_configs - Interface configuration instances
	 * @returns {string} UCI batch output for interfaces
	 */
	function generate_interfaces(interface_configs) {

		for (let inst, iface_config in interface_configs) {
			if (!ubbf_to_bool(iface_config.Enable))
				continue;

			let iface_name = interface_to_name(config, iface_config.Interface);
			if (!iface_name || iface_name == '')
				continue;

			let section_name = ubbf.name_sanitise(iface_name);
			uci_named_section(output, `qosify.${section_name}`, 'interface');
			uci_set_string(output, `qosify.${section_name}.name`, iface_name);

			if (iface_config.BandwidthUp)
				uci_set_string(output, `qosify.${section_name}.bandwidth_up`, iface_config.BandwidthUp);

			if (iface_config.BandwidthDown)
				uci_set_string(output, `qosify.${section_name}.bandwidth_down`, iface_config.BandwidthDown);

			uci_set_boolean(output, `qosify.${section_name}.ingress`, ubbf_to_bool(iface_config.Ingress));
			uci_set_boolean(output, `qosify.${section_name}.egress`, ubbf_to_bool(iface_config.Egress));

			if (iface_config.Mode)
				uci_set_string(output, `qosify.${section_name}.mode`, iface_config.Mode);

			uci_set_boolean(output, `qosify.${section_name}.nat`, ubbf_to_bool(iface_config.NAT));
			uci_set_boolean(output, `qosify.${section_name}.host_isolate`, ubbf_to_bool(iface_config.HostIsolate));
		}

		return;
	}

	/**
	 * Converts protocol number to qosify prefix string.
	 *
	 * @param {number|string} protocol - Protocol number
	 * @returns {string|null} 'tcp', 'udp', or null
	 */
	function protocol_to_prefix(protocol) {
		let proto = ubbf_to_int(protocol);
		if (proto == 6)
			return 'tcp';
		if (proto == 17)
			return 'udp';
		return null;
	}

	/**
	 * Generates a qosify classifier rule line.
	 *
	 * @param {object} classifier - Classifier configuration object
	 * @returns {string|null} Classifier rule line or null
	 */
	function generate_classifier_line(classifier) {
		let proto_prefix = protocol_to_prefix(classifier.Protocol);
		let dest_port = ubbf_to_int(classifier.DestPort);
		let dest_port_end = ubbf_to_int(classifier.DestPortRangeEnd);
		let source_ip = ubbf.uci_value_sanitise(classifier.SourceIP);
		let dscp = ubbf.uci_value_sanitise(classifier.DSCPMark) ?? 'CS0';

		if (proto_prefix && dest_port != null && dest_port > 0) {
			let port_spec;
			if (dest_port_end != null && dest_port_end > dest_port)
				port_spec = sprintf('%s:%d-%d', proto_prefix, dest_port, dest_port_end);
			else
				port_spec = sprintf('%s:%d', proto_prefix, dest_port);
			return sprintf('%s\t%s', port_spec, dscp);
		}

		if (source_ip && source_ip != '')
			return sprintf('%s\t%s', source_ip, dscp);

		return null;
	}

	/**
	 * Generates a qosify DNS classifier rule line.
	 *
	 * @param {object} dns_classifier - DNS classifier configuration object
	 * @returns {string|null} DNS classifier rule line or null
	 */
	function generate_dns_classifier_line(dns_classifier) {
		let domain = ubbf.uci_value_sanitise(dns_classifier.Domain);
		if (!domain || domain == '')
			return null;

		let dscp = ubbf.uci_value_sanitise(dns_classifier.DSCPMark) ?? 'CS0';
		let match_type = dns_classifier.MatchType ?? 'Suffix';
		let cname_only = ubbf_to_bool(dns_classifier.CNAMEOnly);
		let prefix = cname_only ? 'dns_c:' : 'dns:';

		let pattern;
		switch (match_type) {
		case 'Exact':
			pattern = domain;
			break;
		case 'Regex':
			pattern = '/' + domain + '/';
			break;
		case 'Suffix':
		default:
			pattern = '*.' + domain;
			break;
		}

		return sprintf('%s%s\t%s', prefix, pattern, dscp);
	}

	/**
	 * Generates the complete qosify classifier rules file content.
	 *
	 * @param {array} classifiers - Classifier instances
	 * @param {array} dns_classifiers - DNS classifier instances
	 * @returns {string} Complete rules file content
	 */
	function generate_classifier_rules(classifiers, dns_classifiers) {
		let lines = ['# Generated by UBBF qosify.uc'];

		let sorted_classifiers = [];
		for (let inst, c in classifiers) {
			if (!ubbf_to_bool(c.Enable))
				continue;
			push(sorted_classifiers, { order: ubbf_to_int(c.Order) ?? 0, data: c });
		}
		sorted_classifiers = sort(sorted_classifiers, (a, b) => a.order - b.order);

		for (let item in sorted_classifiers) {
			let line = generate_classifier_line(item.data);
			if (line)
				push(lines, line);
		}

		let sorted_dns = [];
		for (let inst, d in dns_classifiers) {
			if (!ubbf_to_bool(d.Enable))
				continue;
			push(sorted_dns, { order: ubbf_to_int(d.Order) ?? 0, data: d });
		}
		sorted_dns = sort(sorted_dns, (a, b) => a.order - b.order);

		for (let item in sorted_dns) {
			let line = generate_dns_classifier_line(item.data);
			if (line)
				push(lines, line);
		}

		return join('\n', lines) + '\n';
	}

	let qosify = ubbf_get(config, 'Device.X_UBBF.QoSify');
	if (!qosify)
		return;

	services.set_enabled('qosify', ubbf_to_bool(qosify.Enable));

	let qosify_config = ubbf_get(config, 'Device.X_UBBF.QoSify.Config') ?? {};
	let dscp_maps = ubbf_instances(config, 'Device.X_UBBF.QoSify.DSCPMap');
	let interface_configs = ubbf_instances(config, 'Device.X_UBBF.QoSify.InterfaceConfig');
	let classifiers = ubbf_instances(config, 'Device.X_UBBF.QoSify.Classifier');
	let dns_classifiers = ubbf_instances(config, 'Device.X_UBBF.QoSify.DNSClassifier');

	let rules_content = generate_classifier_rules(classifiers, dns_classifiers);
	ubbf.write_file_atomic(QOSIFY_CONF_PATH, rules_content);

	generate_defaults(qosify_config);
	generate_classes(dscp_maps);
	generate_interfaces(interface_configs);
}
uci_comment(output, '# generated by qosify/render.uc');
render_config();
