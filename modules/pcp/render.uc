function render_config() {
	// libpcpnatpmp carries at most this many FILTER options in one request
	const MAX_FILTERS = 32;

	/**
	 * Returns the address family of a numeric address.
	 *
	 * @param {string} addr - Address
	 * @returns {number} 4, 6, or 0 for no valid address
	 */
	function addr_family(addr) {
		let bytes = (type(addr) == 'string' && addr != '') ? iptoarr(addr) : null;
		if (!bytes)
			return 0;
		return (length(bytes) == 4) ? 4 : 6;
	}

	/**
	 * Converts TR-181 Filter.PrefixLength to the FILTER option prefix:
	 * RFC 6887 section 13.3 counts the bits of the IPv4-mapped address,
	 * so an IPv4 prefix n is 96 + n.
	 *
	 * @param {number} family - 4 or 6
	 * @param {number} prefix - PrefixLength
	 * @returns {number|null} Wire prefix, or null when invalid
	 */
	function filter_prefix(family, prefix) {
		if (prefix == null || prefix < 1 || prefix > 128)
			return null;
		if (family == 6 || prefix == 128)
			return prefix;
		return (prefix <= 32) ? 96 + prefix : null;
	}

	/**
	 * Renders the Filter rows of a mapping as "ip/prefix/port" entries,
	 * one per remote port of a range, since a FILTER option has one port.
	 *
	 * @param {array} filters - Filter rows
	 * @returns {array|string} Entries, or the reason the filters are invalid
	 */
	function filters_render(filters) {
		let out = [];

		for (let f in filters) {
			let family = addr_family(f.RemoteHostIPAddress);
			if (!family)
				return sprintf('Filter %s: RemoteHostIPAddress is not an IP address', f['.path']);

			let prefix = filter_prefix(family, ubbf_to_int(f.PrefixLength ?? '128'));
			if (prefix == null)
				return sprintf('Filter %s: PrefixLength does not fit the address', f['.path']);

			let first = ubbf_to_int(f.RemotePort) ?? 0;
			let last = ubbf_to_int(f.RemotePortEndRange) ?? 0;
			if (first == 0 || last < first)
				last = first;

			for (let port = first; port <= last; port++)
				push(out, sprintf('%s/%d/%d', f.RemoteHostIPAddress, prefix, port));

			if (length(out) > MAX_FILTERS)
				return sprintf('more than %d filters, counting each remote port', MAX_FILTERS);
		}

		return out;
	}

	/**
	 * Returns why a mapping cannot be requested, or null.
	 *
	 * @param {object} m - InboundMapping or OutboundMapping row
	 * @param {object} client - Client row
	 * @param {string} opcode_switch - MAPEnable or PEEREnable
	 * @returns {string|null} Reason
	 */
	function mapping_invalid(m, client, opcode_switch) {
		let port = ubbf_to_int(m.InternalPort);
		let proto = ubbf_to_int(m.ProtocolNumber);

		if (!ubbf_to_bool(client[opcode_switch]))
			return `${opcode_switch} of the client is false`;
		if (port == null || port < 1)
			return 'InternalPort is not set';
		if (proto == null || proto == 0)
			return 'ProtocolNumber is not set';
		// RFC 6887 section 11.1: all protocols needs internal port 0,
		// which TR-181 InternalPort (1 to 65535) cannot express
		if (proto == -1)
			return 'ProtocolNumber -1 needs internal port 0, which InternalPort cannot be';
		if (m.ThirdPartyAddress && !ubbf_to_bool(client.THIRDPARTYEnable))
			return 'ThirdPartyAddress is set and THIRDPARTYEnable is false';
		return null;
	}

	/**
	 * Writes the options that MAP and PEER mappings share.
	 *
	 * @param {string} section - UCI section name
	 * @param {string} server_section - UCI section of the server
	 * @param {object} m - Mapping row
	 * @param {string} reason - Why the mapping cannot be requested, or null
	 */
	function mapping_common(section, server_section, m, reason) {
		uci_set_string(output, `pcp.${section}.server`, server_section);
		uci_set_string(output, `pcp.${section}.path`, m['.path']);
		uci_set_number(output, `pcp.${section}.internal_port`, ubbf_to_int(m.InternalPort) ?? 0);
		uci_set_number(output, `pcp.${section}.protocol`, ubbf_to_int(m.ProtocolNumber) ?? 0);
		uci_set_number(output, `pcp.${section}.lifetime`, ubbf_to_int(m.Lifetime) ?? 0);

		if (m.ThirdPartyAddress)
			uci_set_string(output, `pcp.${section}.third_party`, m.ThirdPartyAddress);
		if (m.SuggestedExternalIPAddress)
			uci_set_string(output, `pcp.${section}.suggested_ip`, m.SuggestedExternalIPAddress);

		let port = ubbf_to_int(m.SuggestedExternalPort) ?? 0;
		if (port > 0)
			uci_set_number(output, `pcp.${section}.suggested_port`, port);

		if (reason)
			uci_set_string(output, `pcp.${section}.invalid`, reason);
	}

	/**
	 * Renders the InboundMapping rows of a server as MAP requests.
	 *
	 * @param {object} client - Client row
	 * @param {object} server - Server row
	 * @param {string} server_section - UCI section of the server
	 */
	function inbound_render(client, server, server_section) {
		for (let m in ubbf_instances(config, server['.path'] + '.InboundMapping')) {
			if (!ubbf_to_bool(m.Enable))
				continue;

			let section = ubbf.name_sanitise(sprintf('map_%s_%s_%s',
				client['.instance'], server['.instance'], m['.instance']));
			let reason = mapping_invalid(m, client, 'MAPEnable');
			let filters = ubbf_to_bool(client.FILTEREnable)
				? filters_render(ubbf_instances(config, m['.path'] + '.Filter')) : [];

			if (type(filters) == 'string')
				reason ??= filters;

			uci_named_section(output, `pcp.${section}`, 'mapping');
			mapping_common(section, server_section, m, reason);

			for (let f in (type(filters) == 'array') ? filters : [])
				uci_list_string(output, `pcp.${section}.filter`, f);
		}
	}

	/**
	 * Renders the OutboundMapping rows of a server as PEER requests.
	 *
	 * @param {object} client - Client row
	 * @param {object} server - Server row
	 * @param {string} server_section - UCI section of the server
	 */
	function outbound_render(client, server, server_section) {
		for (let m in ubbf_instances(config, server['.path'] + '.OutboundMapping')) {
			if (!ubbf_to_bool(m.Enable))
				continue;

			let section = ubbf.name_sanitise(sprintf('peer_%s_%s_%s',
				client['.instance'], server['.instance'], m['.instance']));
			let reason = mapping_invalid(m, client, 'PEEREnable');
			let remote_port = ubbf_to_int(m.RemotePort) ?? 0;

			if (!addr_family(m.RemoteHostIPAddress))
				reason ??= 'RemoteHostIPAddress is not an IP address';
			if (remote_port < 1)
				reason ??= 'RemotePort is not set';

			uci_named_section(output, `pcp.${section}`, 'peer');
			mapping_common(section, server_section, m, reason);
			uci_set_string(output, `pcp.${section}.remote_ip`, m.RemoteHostIPAddress ?? '');
			uci_set_number(output, `pcp.${section}.remote_port`, remote_port);
		}
	}

	/**
	 * Generates the UCI sections of ubbf-pcp and enables the daemon
	 * when there is at least one enabled server.
	 *
	 * @param {object} pcp - Device.PCP
	 */
	function generate_pcp(pcp) {
		let version = ubbf_to_int(pcp.PreferredVersion) ?? 2;
		let any_server = false;

		for (let client in ubbf_instances(config, 'Device.PCP.Client')) {
			if (!ubbf_to_bool(client.Enable))
				continue;

			for (let server in ubbf_instances(config, client['.path'] + '.Server')) {
				if (!ubbf_to_bool(server.Enable ?? 'true') || !server.ServerNameOrAddress)
					continue;

				let section = ubbf.name_sanitise(sprintf('pcp_%s_%s',
					client['.instance'], server['.instance']));

				uci_named_section(output, `pcp.${section}`, 'server');
				uci_set_string(output, `pcp.${section}.address`, server.ServerNameOrAddress);
				uci_set_string(output, `pcp.${section}.path`, server['.path']);
				uci_set_number(output, `pcp.${section}.version`, version);

				let preferred = ubbf_to_int(server.PreferredLifetime) ?? 0;
				if (preferred > 0)
					uci_set_number(output, `pcp.${section}.preferred_lifetime`, preferred);

				inbound_render(client, server, section);
				outbound_render(client, server, section);
				any_server = true;
			}
		}

		services.set_enabled('ubbf-pcp', any_server);
	}

	let pcp = ubbf_get(config, 'Device.PCP');
	if (!pcp || !ubbf_to_bool(pcp.Enable)) {
		services.set_enabled('ubbf-pcp', false);
		return;
	}

	generate_pcp(pcp);
}
uci_comment(output, '# generated by pcp/render.uc');
render_config();
