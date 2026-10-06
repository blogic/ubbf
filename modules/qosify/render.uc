function render_config() {
	const QOSIFY_CONF_PATH = '/tmp/ubbf/qosify.conf';

	let qosify_check = {};
	include('./check.uc', { qosify_check });

	/**
	 * Logs a row that the render leaves out, with the reason.
	 *
	 * @param {string} table - Table name below Device.X_UBBF.QoSify
	 * @param {object} row - Row from ubbf_instances()
	 * @param {string} why - Reason
	 */
	function row_skip(table, row, why) {
		warn('qosify: %s.%s not rendered: %s', table, row['.instance'], why);
	}

	/**
	 * Translates a DSCP mark for the daemon, or logs and drops it.
	 *
	 * @param {string} what - Where the mark comes from, for the log
	 * @param {string} value - Mark as stored
	 * @param {array} classes - Names of the rendered DSCPMap rows
	 * @returns {string|null} Mark for the daemon, or null
	 */
	function dscp_mark(what, value, classes) {
		if (!qosify_check.dscp_mark_valid(value, classes)) {
			warn('qosify: %s %s is not a DSCP codepoint or a rendered DSCPMap Name', what, value);
			return null;
		}

		return qosify_check.dscp_mark_render(value, classes);
	}

	/**
	 * Generates UCI qosify defaults section.
	 *
	 * The schema defaults are merged under the stored values, so the daemon
	 * runs with the values that a read of Config reports.
	 *
	 * @param {object} stored - Stored Config object
	 * @param {array} classes - Names of the rendered DSCPMap rows
	 */
	function generate_defaults(stored, classes) {
		let qosify_config = { ...(ubbf.schema_defaults('qosify.Config') ?? {}), ...stored };

		uci_named_section(output, 'qosify.defaults', 'defaults');
		uci_list_string(output, 'qosify.defaults.defaults', QOSIFY_CONF_PATH);

		for (let param, option in {
			DefaultTCPDSCP: 'dscp_default_tcp',
			DefaultUDPDSCP: 'dscp_default_udp',
			ICMPDSCP: 'dscp_icmp',
			PriorityDSCP: 'dscp_prio',
			BulkDSCP: 'dscp_bulk'
		}) {
			if (!qosify_config[param])
				continue;

			let mark = dscp_mark(`Config.${param}`, qosify_config[param], classes);
			if (mark)
				uci_set_string(output, `qosify.defaults.${option}`, mark);
		}

		let bulk_pps = ubbf_to_int(qosify_config.BulkTriggerPPS);
		if (bulk_pps != null && bulk_pps > 0)
			uci_set_number(output, 'qosify.defaults.bulk_trigger_pps', bulk_pps);

		let bulk_timeout = ubbf_to_int(qosify_config.BulkTriggerTimeout);
		if (bulk_timeout != null && bulk_timeout > 0)
			uci_set_number(output, 'qosify.defaults.bulk_trigger_timeout', bulk_timeout);

		let prio_pkt_len = ubbf_to_int(qosify_config.PriorityMaxAvgPktLen);
		if (prio_pkt_len != null && prio_pkt_len > 0)
			uci_set_number(output, 'qosify.defaults.prio_max_avg_pkt_len', prio_pkt_len);
	}

	/**
	 * Generates UCI qosify class sections from DSCP maps.
	 *
	 * The daemon creates a class only with both an ingress and an egress
	 * codepoint, and knows it by the section name.
	 *
	 * @param {array} dscp_maps - DSCP map instances
	 * @returns {array} Names of the rendered classes
	 */
	function generate_classes(dscp_maps) {
		let classes = [];

		for (let dscp_map in dscp_maps) {
			if (!ubbf_to_bool(dscp_map.Enable))
				continue;

			let name = dscp_map.Name;
			if (!qosify_check.class_name_valid(name)) {
				row_skip('DSCPMap', dscp_map, `Name '${name}' is not valid`);
				continue;
			}

			if (index(classes, name) >= 0) {
				row_skip('DSCPMap', dscp_map, `another row has the Name ${name}`);
				continue;
			}

			if (!qosify_check.dscp_codepoint_valid(dscp_map.IngressDSCP) ||
			    !qosify_check.dscp_codepoint_valid(dscp_map.EgressDSCP)) {
				row_skip('DSCPMap', dscp_map, 'IngressDSCP and EgressDSCP must both be codepoints');
				continue;
			}

			let section = qosify_check.class_section(name);
			uci_named_section(output, `qosify.${section}`, 'class');
			uci_set_string(output, `qosify.${section}.ingress`, dscp_map.IngressDSCP);
			uci_set_string(output, `qosify.${section}.egress`, dscp_map.EgressDSCP);
			push(classes, name);
		}

		return classes;
	}

	/**
	 * Generates UCI qosify interface sections.
	 *
	 * @param {array} interface_configs - Interface configuration instances
	 */
	function generate_interfaces(interface_configs) {
		for (let iface_config in interface_configs) {
			if (!ubbf_to_bool(iface_config.Enable))
				continue;

			let iface_name = interface_to_name(config, iface_config.Interface);
			if (!iface_name || iface_name == '') {
				row_skip('InterfaceConfig', iface_config, `Interface ${iface_config.Interface} does not resolve`);
				continue;
			}

			if (!qosify_check.rate_valid(iface_config.BandwidthUp) ||
			    !qosify_check.rate_valid(iface_config.BandwidthDown)) {
				row_skip('InterfaceConfig', iface_config, 'a bandwidth is not a tc rate');
				continue;
			}

			if (iface_config.Mode && !qosify_check.mode_valid(iface_config.Mode)) {
				row_skip('InterfaceConfig', iface_config, `Mode ${iface_config.Mode} is not a cake diffserv mode`);
				continue;
			}

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
	 * A row matches either a port of TCP or UDP, or the address of the
	 * remote host (`SourceIP`): the daemon looks up the source address on
	 * ingress and the destination address on egress.
	 *
	 * @param {object} classifier - Classifier configuration object
	 * @param {array} classes - Names of the rendered DSCPMap rows
	 * @returns {string|null} Classifier rule line or null
	 */
	function generate_classifier_line(classifier, classes) {
		if (!qosify_check.protocol_valid(classifier.Protocol ?? '-1') ||
		    !qosify_check.port_valid(classifier.DestPort ?? '-1') ||
		    !qosify_check.port_valid(classifier.DestPortRangeEnd ?? '-1')) {
			row_skip('Classifier', classifier, 'Protocol or a port is out of range');
			return null;
		}

		if (!qosify_check.address_valid(classifier.SourceIP)) {
			row_skip('Classifier', classifier, `SourceIP ${classifier.SourceIP} is not one address`);
			return null;
		}

		let dscp = dscp_mark(`Classifier.${classifier['.instance']}.DSCPMark`,
				     classifier.DSCPMark ?? 'CS0', classes);
		if (!dscp)
			return null;

		let proto_prefix = protocol_to_prefix(classifier.Protocol);
		let dest_port = ubbf_to_int(classifier.DestPort);
		let dest_port_end = ubbf_to_int(classifier.DestPortRangeEnd);
		let source_ip = classifier.SourceIP;

		if (proto_prefix && dest_port > 0) {
			if (source_ip)
				warn('qosify: Classifier.%s matches the port only, SourceIP is ignored', classifier['.instance']);
			if (dest_port_end > 0 && dest_port_end < dest_port)
				warn('qosify: Classifier.%s DestPortRangeEnd is below DestPort, using one port', classifier['.instance']);

			let port_spec = (dest_port_end > dest_port)
				? sprintf('%s:%d-%d', proto_prefix, dest_port, dest_port_end)
				: sprintf('%s:%d', proto_prefix, dest_port);
			return sprintf('%s\t%s', port_spec, dscp);
		}

		if (source_ip)
			return sprintf('%s\t%s', source_ip, dscp);

		row_skip('Classifier', classifier, 'it names neither a TCP or UDP port nor a SourceIP');
		return null;
	}

	/**
	 * Generates the qosify DNS classifier rule lines of one row.
	 *
	 * A Suffix row matches the domain and every name below it, so it needs
	 * two patterns: `*.<domain>` does not match the domain itself.
	 *
	 * @param {object} dns_classifier - DNS classifier configuration object
	 * @param {array} classes - Names of the rendered DSCPMap rows
	 * @returns {array} Rule lines, empty when the row is not rendered
	 */
	function generate_dns_classifier_lines(dns_classifier, classes) {
		let domain = ubbf.uci_value_sanitise(dns_classifier.Domain);
		if (!domain) {
			row_skip('DNSClassifier', dns_classifier, 'Domain is empty');
			return [];
		}

		let match_type = dns_classifier.MatchType ?? 'Suffix';
		if (!qosify_check.match_type_valid(match_type)) {
			row_skip('DNSClassifier', dns_classifier, `MatchType ${match_type} is unknown`);
			return [];
		}

		if (match_type == 'Regex' && !qosify_check.regex_valid(domain)) {
			row_skip('DNSClassifier', dns_classifier, 'Domain does not compile as a regular expression');
			return [];
		}

		let dscp = dscp_mark(`DNSClassifier.${dns_classifier['.instance']}.DSCPMark`,
				     dns_classifier.DSCPMark ?? 'CS0', classes);
		if (!dscp)
			return [];

		let prefix = ubbf_to_bool(dns_classifier.CNAMEOnly) ? 'dns_c:' : 'dns:';
		let patterns;
		switch (match_type) {
		case 'Exact':
			patterns = [ domain ];
			break;
		case 'Regex':
			patterns = [ '/' + domain ];
			break;
		case 'Suffix':
			patterns = [ domain, '*.' + domain ];
			break;
		}

		return map(patterns, (p) => sprintf('%s%s\t%s', prefix, p, dscp));
	}

	/**
	 * Lists the enabled rows of a table by Order.
	 *
	 * @param {array} rows - Instances
	 * @param {boolean} descending - Highest Order first
	 * @returns {array} Rows
	 */
	function rows_by_order(rows, descending) {
		let enabled = filter(rows, (r) => ubbf_to_bool(r.Enable));

		return sort(enabled, (a, b) => {
			let d = (ubbf_to_int(a.Order) ?? 0) - (ubbf_to_int(b.Order) ?? 0);
			return descending ? -d : d;
		});
	}

	/**
	 * Generates the complete qosify classifier rules file content.
	 *
	 * The lowest Order wins in both tables. For a port or an address the
	 * daemon keeps the last line it reads, so those lines are written from
	 * the highest Order down; for a DNS pattern it keeps the first match,
	 * so those lines are written from the lowest Order up.
	 *
	 * @param {array} classifiers - Classifier instances
	 * @param {array} dns_classifiers - DNS classifier instances
	 * @param {array} classes - Names of the rendered DSCPMap rows
	 * @returns {string} Complete rules file content
	 */
	function generate_classifier_rules(classifiers, dns_classifiers, classes) {
		let lines = ['# Generated by UBBF modules/qosify/render.uc'];

		for (let c in rows_by_order(classifiers, true)) {
			let line = generate_classifier_line(c, classes);
			if (line)
				push(lines, line);
		}

		for (let d in rows_by_order(dns_classifiers, false))
			push(lines, ...generate_dns_classifier_lines(d, classes));

		return join('\n', lines) + '\n';
	}

	let qosify = ubbf_get(config, 'Device.X_UBBF.QoSify');
	if (!qosify) {
		services.set_enabled('qosify', false);
		return;
	}

	services.set_enabled('qosify', ubbf_to_bool(qosify.Enable));

	let qosify_config = ubbf_get(config, 'Device.X_UBBF.QoSify.Config') ?? {};
	let dscp_maps = ubbf_instances(config, 'Device.X_UBBF.QoSify.DSCPMap');
	let interface_configs = ubbf_instances(config, 'Device.X_UBBF.QoSify.InterfaceConfig');
	let classifiers = ubbf_instances(config, 'Device.X_UBBF.QoSify.Classifier');
	let dns_classifiers = ubbf_instances(config, 'Device.X_UBBF.QoSify.DNSClassifier');

	let classes = generate_classes(dscp_maps);

	let rules_content = generate_classifier_rules(classifiers, dns_classifiers, classes);
	if (!dry_run)
		ubbf.write_file_atomic(QOSIFY_CONF_PATH, rules_content);

	generate_defaults(qosify_config, classes);
	generate_interfaces(interface_configs);
}
uci_comment(output, '# generated by qosify/render.uc');
render_config();
