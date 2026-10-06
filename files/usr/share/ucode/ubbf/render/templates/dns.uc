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

		for (let srv in servers) {
			if (!ubbf_to_bool(srv.Enable))
				continue;
			if (srv.Type == 'Static' && srv.DNSServer) {
				uci_list_string(output, 'dhcp.dns_localhost.server', srv.DNSServer);
				has_static = true;
			}
		}

		if (!has_static)
			uci_set_string(output, 'dhcp.dns_localhost.resolvfile',
				'/tmp/resolv.conf.d/resolv.conf.auto');

		return;
	}

	/**
	 * Collects DNS relay forwarders grouped by downstream interface.
	 *
	 * @param {object} relay - DNS relay data model object
	 * @returns {object} Map of interface name to {servers[]}
	 */
	function collect_relay_interfaces(relay) {
		let by_iface = {};

		if (!ubbf_to_bool(relay?.Enable))
			return by_iface;

		let forwardings = ubbf_instances(config, 'Device.DNS.Relay.Forwarding');
		let ip_interfaces = ubbf_instances(config, 'Device.IP.Interface');

		for (let fwd in forwardings) {
			if (!ubbf_to_bool(fwd.Enable))
				continue;
			if (!fwd.DNSServer)
				continue;

			let iface_names = [];

			if (fwd.Interface && fwd.Interface != '') {
				let name = interface_to_name(config, fwd.Interface);
				if (name)
					push(iface_names, name);
			} else {
				for (let iface in ip_interfaces) {
					if (!iface.Name)
						continue;
					if (ubbf_to_bool(iface.Upstream))
						continue;
					push(iface_names, iface.Name);
				}
			}

			for (let name in iface_names) {
				if (!(name in by_iface))
					by_iface[name] = { servers: [] };

				if (index(by_iface[name].servers, fwd.DNSServer) < 0)
					push(by_iface[name].servers, fwd.DNSServer);
			}
		}

		return by_iface;
	}

	/**
	 * Builds a map of interface names to dnsmasq relay instance info.
	 *
	 * @param {object} by_iface - Map of interface name to relay config
	 * @returns {object} Map of interface name to {name, port}
	 */
	function build_instance_map(by_iface) {
		let instance_map = {};
		let port = 5301;

		for (let iface in by_iface) {
			instance_map[iface] = { name: `dns_relay_${iface}`, port };
			port++;
		}

		return instance_map;
	}

	/**
	 * Generates UCI dnsmasq sections for DNS relay instances.
	 *
	 * @param {object} by_iface - Map of interface name to relay config
	 * @param {object} instance_map - Map of interface name to instance info
	 * @returns {string} UCI batch output for DNS relay instances
	 */
	function generate_dns_relays(by_iface, instance_map) {

		for (let iface, data in by_iface) {
			let inst = instance_map[iface];
			let inst_name = inst.name;

			uci_named_section(output, `dhcp.${inst_name}`, 'dnsmasq');
			uci_set_number(output, `dhcp.${inst_name}.port`, inst.port);
			uci_set_boolean(output, `dhcp.${inst_name}.domainneeded`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.boguspriv`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.localise_queries`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.localservice`, true);
			uci_set_boolean(output, `dhcp.${inst_name}.noresolv`, true);

			for (let server in data.servers)
				uci_list_string(output, `dhcp.${inst_name}.server`, server);
		}

		return;
	}

	/**
	 * Applies cache settings from Relay.Config instances to relay instances.
	 *
	 * @param {object} instance_map - Map of interface name to instance info
	 * @returns {string} UCI batch output for caching settings
	 */
	function apply_caching(instance_map) {
		let configs = ubbf_instances(config, 'Device.DNS.Relay.Config');
		if (!configs || !length(configs))
			return;


		for (let cfg in configs) {
			let iface_name = cfg.Interface
				? interface_to_name(config, cfg.Interface) : null;

			for (let iface, inst in instance_map) {
				if (iface_name && iface_name != iface)
					continue;

				let inst_name = inst.name;

				if (ubbf_to_int(cfg.CacheSize))
					uci_set_number(output, `dhcp.${inst_name}.cachesize`, cfg.CacheSize);
				if (ubbf_to_int(cfg.CacheMaxTTL))
					uci_set_number(output, `dhcp.${inst_name}.max_ttl`, cfg.CacheMaxTTL);
				if (ubbf_to_int(cfg.CacheMinTTL))
					uci_set_number(output, `dhcp.${inst_name}.min_cache_ttl`, cfg.CacheMinTTL);
			}
		}

		return;
	}

	/**
	 * Applies DNS rebind protection settings to all relay instances.
	 *
	 * @param {object} rebind - Rebind protection data model object
	 * @param {object} instance_map - Map of interface name to instance info
	 * @returns {string} UCI batch output for rebind settings
	 */
	function apply_rebind_protection(rebind, instance_map) {
		if (!rebind || !ubbf_to_bool(rebind.Enable))
			return;

		let allowed_domains = [];

		if (rebind.AllowedDomains) {
			for (let domain in csv_to_list(rebind.AllowedDomains)) {
				if (!valid_rebind_domain(domain)) {
					warn('dns: rejecting invalid rebind allowed domain %s', domain);
					continue;
				}
				push(allowed_domains, domain);
			}
		}

		for (let iface, inst in instance_map) {
			let inst_name = inst.name;
			uci_set_boolean(output, `dhcp.${inst_name}.rebind_protection`, true);

			for (let domain in allowed_domains)
				uci_list_string(output, `dhcp.${inst_name}.rebind_domain_ok`, domain);
		}

		return;
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

	let by_iface = collect_relay_interfaces(relay);
	let instance_map = build_instance_map(by_iface);

	services.set_enabled('dnsmasq',
		ubbf_to_bool(client?.Enable) || ubbf_to_bool(relay?.Enable));

	generate_dns_localhost(client);
	generate_dns_relays(by_iface, instance_map);
	apply_caching(instance_map);
	apply_rebind_protection(rebind, instance_map);
	apply_local_domain(instance_map);
	generate_zone_hosts(instance_map);
}
uci_comment(output, '# generated by dns.uc');
render_config();
