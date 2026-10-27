function render_config() {
	/**
	 * Validates a DNS name against RFC 1035 label syntax. Used to
	 * gate zone host Names, zone Names, and any other user-supplied
	 * DNS string that lands in a dnsmasq record.
	 *
	 * @param {string} s - Candidate DNS name
	 * @returns {boolean} True when the name is syntactically valid
	 */
	function valid_dns_name(s) {
		if (type(s) != 'string' || s == '' || length(s) > 253)
			return false;
		return !!match(s, /^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$/);
	}

	/**
	 * Same as valid_dns_name but allows an optional leading dot
	 * for dnsmasq rebind_domain_ok entries (`.example.com` matches
	 * the whole subtree of example.com).
	 *
	 * @param {string} s - Candidate rebind domain
	 * @returns {boolean} True when the domain is syntactically valid
	 */
	function valid_rebind_domain(s) {
		if (type(s) != 'string' || s == '' || length(s) > 253)
			return false;
		return !!match(s, /^\.?[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$/);
	}

	/**
	 * Validates an IPv4 or IPv6 literal. Does not canonicalise;
	 * dnsmasq will reject obviously malformed values on its own.
	 *
	 * @param {string} s - Candidate IP literal
	 * @returns {boolean} True when the string looks like a valid IPv4 or IPv6 address
	 */
	function valid_ip_literal(s) {
		if (type(s) != 'string' || s == '')
			return false;
		if (match(s, /^(\d{1,3}\.){3}\d{1,3}$/))
			return true;
		if (match(s, /^[0-9a-fA-F:]+$/) && length(s) <= 45)
			return true;
		return false;
	}

	/**
	 * Generates UCI dnsmasq configuration for localhost DNS.
	 *
	 * @param {object} client - DNS client data model object
	 * @returns {string} UCI batch output for localhost DNS
	 */
	function generate_dns_localhost(client) {
		let enabled = ubbf_to_bool(client?.Enable);

		uci_named_section(output, 'dhcp.dns_localhost', 'dnsmasq');
		uci_set_string(output, 'dhcp.dns_localhost.port', enabled ? '53' : '0');

		if (!enabled)
			return;

		uci_set_boolean(output, 'dhcp.dns_localhost.domainneeded', true);
		uci_set_boolean(output, 'dhcp.dns_localhost.boguspriv', true);
		uci_set_boolean(output, 'dhcp.dns_localhost.localise_queries', true);
		uci_set_boolean(output, 'dhcp.dns_localhost.rebind_protection', true);
		uci_set_boolean(output, 'dhcp.dns_localhost.rebind_localhost', true);
		uci_set_boolean(output, 'dhcp.dns_localhost.localservice', true);
		uci_set_number(output, 'dhcp.dns_localhost.cachesize', 1000);
		uci_list_string(output, 'dhcp.dns_localhost.interface', 'loopback');

		let servers = ubbf_instances(config, 'Device.DNS.Client.Server');
		let has_static = false;
		let learned_disabled = false;

		for (let srv in servers) {
			if (dns_learned_row(srv['.instance'])) {
				if (!ubbf_to_bool(srv.Enable))
					learned_disabled = true;
				continue;
			}
			if (!ubbf_to_bool(srv.Enable))
				continue;
			if (srv.Type == 'Static' && srv.DNSServer) {
				uci_list_string(output, 'dhcp.dns_localhost.server', srv.DNSServer);
				has_static = true;
			}
		}

		if (has_static)
			return;

		if (!learned_disabled) {
			uci_set_string(output, 'dhcp.dns_localhost.resolvfile', DNS_RESOLV_AUTO);
			return;
		}

		// ubbf-device writes the filtered copy (device/dns-filter.uc); the
		// dnsmasq init script turns localuse off for any other resolvfile.
		uci_set_string(output, 'dhcp.dns_localhost.resolvfile', DNS_RESOLV_FILTERED);
		uci_set_boolean(output, 'dhcp.dns_localhost.localuse', true);
	}

	/**
	 * Generates UCI dnsmasq sections for DNS relay instances.
	 *
	 * @param {object} relay_plan - Plan of dns_relay_plan()
	 */
	function generate_dns_relays(relay_plan) {
		for (let iface, inst in relay_plan) {
			let inst_name = inst.name;

			uci_named_section(output, `dhcp.${inst_name}`, 'dnsmasq');
			uci_set_number(output, `dhcp.${inst_name}.port`, inst.port);
			uci_set_boolean(output, `dhcp.${inst_name}.domainneeded`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.boguspriv`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.localise_queries`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.localservice`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.noresolv`, true);

			for (let server in inst.servers)
				uci_list_string(output, `dhcp.${inst_name}.server`, server);
		}
	}

	/**
	 * Applies the cache settings of the Relay.Config row of each relay
	 * instance.
	 *
	 * @param {object} relay_plan - Plan of dns_relay_plan()
	 */
	function apply_caching(relay_plan) {
		for (let iface, inst in relay_plan) {
			let cfg = inst.config;
			if (!cfg)
				continue;

			let inst_name = inst.name;
			let entries = ubbf_to_int(cfg.X_UBBF_CacheEntries);
			if (entries != null)
				uci_set_number(output, `dhcp.${inst_name}.cachesize`, entries);
			if (ubbf_to_int(cfg.X_UBBF_CacheMaxTTL))
				uci_set_number(output, `dhcp.${inst_name}.max_cache_ttl`, cfg.X_UBBF_CacheMaxTTL);
			if (ubbf_to_int(cfg.X_UBBF_CacheMinTTL))
				uci_set_number(output, `dhcp.${inst_name}.min_cache_ttl`, cfg.X_UBBF_CacheMinTTL);
		}
	}

	/**
	 * Applies DNS rebind protection settings to all relay instances.
	 *
	 * @param {object} rebind - Rebind protection data model object
	 * @param {object} instance_map - Map of interface name to instance info
	 */
	function apply_rebind_protection(rebind, instance_map) {
		if (!rebind)
			return;

		let enable = ubbf_to_bool(rebind.Enable);
		let exceptions = [];

		for (let domain in csv_to_list(rebind.DomainExceptions ?? '')) {
			if (!valid_rebind_domain(domain)) {
				warn('dns: rejecting invalid rebind exception domain %s', domain);
				continue;
			}
			push(exceptions, domain);
		}

		// The dnsmasq init script turns protection on when the option is
		// absent, so a disabled object has to write 0.
		for (let iface, inst in instance_map) {
			let inst_name = inst.name;
			uci_set_boolean(output, `dhcp.${inst_name}.rebind_protection`, enable);

			if (!enable)
				continue;

			for (let domain in exceptions)
				uci_list_string(output, `dhcp.${inst_name}.rebind_domain`, domain);
		}
	}

	/**
	 * Applies local domain settings from DHCP pools to relay instances.
	 *
	 * @param {object} instance_map - Map of interface name to instance info
	 * @returns {string} UCI batch output for local domain settings
	 */
	function apply_local_domain(instance_map) {
		let dhcpv4_pools = ubbf_instances(config, 'Device.DHCPv4.Server.Pool');
		let domain_name = null;

		for (let pool in dhcpv4_pools) {
			if (!ubbf_to_bool(pool.Enable))
				continue;
			if (!pool.DomainName)
				continue;
			domain_name = pool.DomainName;
			break;
		}

		if (!domain_name)
			return;


		for (let iface, inst in instance_map) {
			let inst_name = inst.name;
			uci_set_string(output, `dhcp.${inst_name}.domain`, domain_name);
			uci_set_string(output, `dhcp.${inst_name}.local`, `/${domain_name}/`);
			uci_set_boolean(output, `dhcp.${inst_name}.expandhosts`, true);
		}

		return;
	}

	/**
	 * Generates dnsmasq address records from DNS Zone host entries.
	 *
	 * @param {object} instance_map - Map of interface name to instance info
	 * @returns {string} UCI batch output for zone host records
	 */
	function generate_zone_hosts(instance_map) {
		let zones = ubbf_instances(config, 'Device.DNS.Zone');
		if (!zones || !length(zones))
			return;


		for (let zone in zones) {
			if (!ubbf_to_bool(zone.Enable))
				continue;

			let zone_name = zone.Name;
			if (!zone_name)
				continue;
			if (!valid_dns_name(zone_name)) {
				warn('dns: rejecting zone with invalid Name %s', zone_name);
				continue;
			}

			let hosts = zone.Host;
			if (type(hosts) != 'object')
				continue;

			for (let idx, host in hosts) {
				if (type(host) != 'object')
					continue;
				if (!ubbf_to_bool(host.Enable))
					continue;
				if (!host.Name || !host.Host)
					continue;
				if (!valid_dns_name(host.Name)) {
					warn('dns: rejecting zone host with invalid Name %s', host.Name);
					continue;
				}
				if (!valid_ip_literal(host.Host)) {
					warn('dns: rejecting zone host %s with invalid Host %s', host.Name, host.Host);
					continue;
				}

				let fqdn = `${host.Name}.${zone_name}`;

				for (let iface, dinst in instance_map)
					uci_list_string(output, `dhcp.${dinst.name}.address`, `/${fqdn}/${host.Host}`);
			}
		}

		return;
	}

	let dns = ubbf_get(config, 'Device.DNS');
	if (!dns)
		return;

	let client = ubbf_get(config, 'Device.DNS.Client');
	let relay = ubbf_get(config, 'Device.DNS.Relay');
	let rebind = ubbf_get(config, 'Device.DNS.RebindProtection');

	let instance_map = dns_relay_plan(config);

	services.set_enabled('dnsmasq',
		ubbf_to_bool(client?.Enable) || ubbf_to_bool(relay?.Enable));

	generate_dns_localhost(client);
	generate_dns_relays(instance_map);
	apply_caching(instance_map);
	apply_rebind_protection(rebind, instance_map);
	apply_local_domain(instance_map);
	generate_zone_hosts(instance_map);
}
uci_comment(output, '# generated by dns.uc');
render_config();
