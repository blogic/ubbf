function render_config() {
	// Conf-dir snippet for ADMZ. Lives in the dnsmasq instance that
	// serves DHCP on the LAN; the snippet adds `shared-network` (lets
	// dnsmasq serve the WAN subnet on the LAN bridge even though the
	// LAN's interface IP is in a different subnet) plus a static-only
	// `dhcp-range` so the WAN-subnet network is "known" to dnsmasq.
	// Without it dnsmasq silently ignores the dhcp-host stanza whose
	// IP is outside the LAN pool and falls back to LAN-pool allocation.
	const ADMZ_SNIPPET_FILE = 'admz-range.conf';
	const ADMZ_SECONDARY = '198.18.0.1';

	/**
	 * Converts a contiguous hex string to colon-separated byte form
	 * for dnsmasq's dhcp-match value syntax. Without the colons
	 * dnsmasq treats the value as an ASCII literal rather than as
	 * a byte sequence.
	 *
	 * @param {string} hex - Contiguous hex string (even length)
	 * @returns {string|null} Colon-separated hex, or null if input invalid
	 */
	function hex_string_to_colon(hex) {
		if (type(hex) != 'string' || hex == '' || (length(hex) % 2) != 0)
			return null;
		if (!match(hex, /^[0-9a-fA-F]+$/))
			return null;
		let parts = [];
		for (let i = 0; i < length(hex); i += 2)
			push(parts, substr(hex, i, 2));
		return join(':', parts);
	}

	/**
	 * Finds a DHCP pool matching an interface reference.
	 *
	 * @param {string} iface_ref - Interface path reference
	 * @param {object} pools - Pool instances
	 * @returns {object|null} Matching pool or null
	 */
	function get_pool_for_interface(iface_ref, pools) {
		for (let inst, pool in pools) {
			if (pool.Interface == iface_ref)
				return pool;
		}
		return null;
	}

	/**
	 * Returns true when a pool carries any classification field that
	 * routes a subset of clients to a tagged dhcp-range.
	 *
	 * @param {object} pool - DHCPv4 pool instance
	 * @returns {boolean}
	 */
	function pool_has_classification(pool) {
		return !!(pool.VendorClassID || pool.UserClassID
			|| pool.Chaddr || pool.ClientID);
	}

	/**
	 * Returns the per-criterion match tags that filter the pool's
	 * dhcp-range. Each entry carries the dnsmasq tag name used by both
	 * the criterion section's `set:` and the dhcp-range's `tag:`
	 * filter, plus an `exclude` flag (TR-181 *Exclude). When exclude is
	 * true the dhcp-range filter is `tag:!<name>` so the range serves
	 * clients that did not match the criterion.
	 *
	 * Skips ClientID when its hexBinary value is malformed, mirroring
	 * the rejection in generate_pool_classification.
	 *
	 * @param {object} pool - DHCPv4 pool instance
	 * @returns {array} list of {name, exclude} entries
	 */
	function pool_match_tags(pool) {
		let pool_tag = ubbf.name_sanitise(pool.Alias || `pool_${pool['.instance']}`);
		let tags = [];
		if (pool.VendorClassID)
			push(tags, { name: `${pool_tag}_vc`,
				exclude: ubbf_to_bool(pool.VendorClassIDExclude) });
		if (pool.UserClassID)
			push(tags, { name: `${pool_tag}_uc`,
				exclude: ubbf_to_bool(pool.UserClassIDExclude) });
		if (pool.Chaddr)
			push(tags, { name: `${pool_tag}_mac`,
				exclude: ubbf_to_bool(pool.ChaddrExclude) });
		if (pool.ClientID && hex_string_to_colon(pool.ClientID))
			push(tags, { name: `${pool_tag}_cid`,
				exclude: ubbf_to_bool(pool.ClientIDExclude) });
		return tags;
	}

	/**
	 * Returns every pool bound to the given interface, with the default
	 * pool (no classification rules) first so the caller can render it
	 * as the untagged dhcp-range and the remainder as tagged ranges.
	 *
	 * @param {string} iface_ref - Interface path reference
	 * @param {object} pools - Pool instances
	 * @returns {array} Ordered pool list, default pool first
	 */
	function pools_for_interface(iface_ref, pools) {
		let defaults = [];
		let tagged = [];
		for (let inst, pool in pools) {
			if (pool.Interface != iface_ref)
				continue;
			if (pool_has_classification(pool))
				push(tagged, pool);
			else
				push(defaults, pool);
		}
		let result = [];
		for (let p in defaults)
			push(result, p);
		for (let p in tagged)
			push(result, p);
		return result;
	}

	/**
	 * Builds a set of interface names that have a DNS Relay forwarder
	 * bound to them. dns.uc renders one dnsmasq instance named
	 * dns_relay_<iface> per such interface. dhcp sections must declare
	 * `option instance dns_relay_<iface>` to attach to that single
	 * instance, otherwise dnsmasq.init copies the dhcp-range into every
	 * dnsmasq instance and the DHCP daemons fight over UDP/67.
	 *
	 * @returns {object} Set keyed by interface name
	 */
	function relay_interfaces() {
		let result = {};
		let relay = ubbf_get(config, 'Device.DNS.Relay');
		if (!ubbf_to_bool(relay?.Enable))
			return result;

		let forwardings = ubbf_instances(config, 'Device.DNS.Relay.Forwarding');
		let ip_interfaces = ubbf_instances(config, 'Device.IP.Interface');

		for (let fwd in forwardings) {
			if (!ubbf_to_bool(fwd.Enable))
				continue;
			if (!fwd.DNSServer)
				continue;

			if (fwd.Interface) {
				let iface = ubbf_get(config, fwd.Interface);
				if (iface?.Name)
					result[iface.Name] = true;
			} else {
				for (let iface in ip_interfaces) {
					if (!iface.Name)
						continue;
					if (ubbf_to_bool(iface.Upstream))
						continue;
					result[iface.Name] = true;
				}
			}
		}

		return result;
	}

	/**
	 * Finds a router advertisement setting matching an interface reference.
	 *
	 * @param {string} iface_ref - Interface path reference
	 * @param {object} ra_settings - RA setting instances
	 * @returns {object|null} Matching RA setting or null
	 */
	function get_ra_for_interface(iface_ref, ra_settings) {
		for (let inst, ra in ra_settings) {
			if (ra.Interface == iface_ref)
				return ra;
		}
		return null;
	}

	/**
	 * Converts RA preference to UCI format.
	 *
	 * @param {string} pref - Preference value (high/medium/low)
	 * @returns {string|null} UCI preference value
	 */
	function ra_preference_to_uci(pref) {
		if (!pref)
			return null;
		let lc_pref = lc(pref);
		if (lc_pref == 'high')
			return 'high';
		if (lc_pref == 'low')
			return 'low';
		return 'medium';
	}

	/**
	 * Calculates dnsmasq start offset and pool size from a TR-181 DHCP pool's
	 * MinAddress, MaxAddress and SubnetMask.
	 *
	 * @param {string} min_address - Minimum IPv4 address
	 * @param {string} max_address - Maximum IPv4 address
	 * @param {string} subnet_mask - IPv4 subnet mask
	 * @returns {object} Object with start (offset within network) and limit (range size)
	 */
	function calculate_dhcp_start_limit(min_address, max_address, subnet_mask) {
		let min_int = ubbf.ip_to_int(min_address);
		let max_int = ubbf.ip_to_int(max_address);
		let mask_int = ubbf.ip_to_int(subnet_mask);

		if (!min_int || !max_int || !mask_int || max_int < min_int)
			return { start: 100, limit: 150 };

		let network = min_int & mask_int;

		return {
			start: min_int - network,
			limit: max_int - min_int + 1
		};
	}

	/**
	 * Splits [MinAddress, MaxAddress] into contiguous segments after
	 * removing every IP listed in ReservedAddresses. dnsmasq has no
	 * "exclude IP from range" knob, so each segment turns into its own
	 * dhcp-range / config dhcp section.
	 *
	 * @param {string} min_address - Minimum IPv4 address
	 * @param {string} max_address - Maximum IPv4 address
	 * @param {string} reserved_csv - Comma-separated reserved IPv4 addresses
	 * @returns {array} List of {min, max} integer segments
	 */
	function split_pool_range(min_address, max_address, reserved_csv) {
		let min_int = ubbf.ip_to_int(min_address);
		let max_int = ubbf.ip_to_int(max_address);
		if (min_int == null || max_int == null || max_int < min_int)
			return [];

		let reserved = {};
		for (let r in csv_to_list(reserved_csv)) {
			let v = ubbf.ip_to_int(r);
			if (v != null && v >= min_int && v <= max_int)
				reserved[`${v}`] = true;
		}

		if (length(reserved) == 0)
			return [{ min: min_int, max: max_int }];

		let segments = [];
		let cur = null;
		for (let v = min_int; v <= max_int; v++) {
			if (reserved[`${v}`]) {
				if (cur != null) {
					push(segments, { min: cur, max: v - 1 });
					cur = null;
				}
			} else if (cur == null) {
				cur = v;
			}
		}
		if (cur != null)
			push(segments, { min: cur, max: max_int });
		return segments;
	}

	/**
	 * Converts an integer segment to dnsmasq UCI start/limit, anchored
	 * to the subnet of the segment's first address.
	 *
	 * @param {object} segment - {min, max} integer segment
	 * @param {string} subnet_mask - IPv4 subnet mask
	 * @returns {object} {start, limit}
	 */
	function segment_to_start_limit(segment, subnet_mask) {
		let mask_int = ubbf.ip_to_int(subnet_mask);
		if (!mask_int)
			return { start: segment.min, limit: segment.max - segment.min + 1 };
		let network = segment.min & mask_int;
		return {
			start: segment.min - network,
			limit: segment.max - segment.min + 1
		};
	}

	/**
	 * Returns the first enabled static IPv4 SubnetMask of an IP.Interface,
	 * or null when none is configured. dnsmasq.init derives the dhcp-range
	 * network base from this mask, so start/limit must be computed against
	 * the same value to keep the range arithmetic in sync.
	 *
	 * @param {object} iface - IP interface instance
	 * @returns {string|null} dotted-decimal netmask
	 */
	function iface_v4_mask(iface) {
		let addrs = ubbf_instances(iface, 'IPv4Address');
		for (let addr in addrs) {
			if (!ubbf_to_bool(addr.Enable))
				continue;
			if (lc(addr.AddressingType || 'Static') != 'static')
				continue;
			if (addr.SubnetMask)
				return addr.SubnetMask;
		}
		return null;
	}

	/**
	 * Generates UCI DHCP sections for all interfaces.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @param {array} dhcpv4_pools - DHCPv4 pool instances
	 * @param {array} dhcpv6_pools - DHCPv6 pool instances
	 * @param {array} ra_settings - Router advertisement settings
	 * @returns {string} UCI batch output
	 */
	function generate_dhcp_sections(ip_interfaces, dhcpv4_pools, dhcpv6_pools, ra_settings, v4_server_enabled, v6_server_enabled, relay_ifaces) {

		for (let iface in ip_interfaces) {
			let name = iface.Name;
			if (!name)
				continue;

			let iface_ref = iface['.path'];
			let v4_pools = pools_for_interface(iface_ref, dhcpv4_pools);
			let v4_pool = v4_pools[0];
			let v4_extra_pools = slice(v4_pools, 1);
			let v6_pool = get_pool_for_interface(iface_ref, dhcpv6_pools);
			let ra = get_ra_for_interface(iface_ref, ra_settings);
			let v4_enabled = v4_server_enabled && v4_pool && ubbf_to_bool(v4_pool.Enable);
			let v6_enabled = v6_server_enabled && v6_pool && ubbf_to_bool(v6_pool.Enable);
			let ra_enabled = ra && ubbf_to_bool(ra.Enable);
			let dnsmasq_instance = relay_ifaces[name] ? `dns_relay_${name}` : null;
			let v4_segments = [];
			let v4_lease_time = null;
			let iface_mask = iface_v4_mask(iface) ?? v4_pool?.SubnetMask;

			uci_named_section(output, `dhcp.${name}`, 'dhcp');
			uci_set_string(output, `dhcp.${name}.interface`, name);
			if (dnsmasq_instance)
				uci_set_string(output, `dhcp.${name}.instance`, dnsmasq_instance);

			if (v4_enabled)
				v4_segments = split_pool_range(v4_pool.MinAddress,
					v4_pool.MaxAddress, v4_pool.ReservedAddresses);

			if (v4_enabled && length(v4_segments) > 0) {
				let main_seg = segment_to_start_limit(v4_segments[0], iface_mask);
				uci_set_string(output, `dhcp.${name}.dhcpv4`, 'server');
				uci_set_number(output, `dhcp.${name}.start`, main_seg.start);
				uci_set_number(output, `dhcp.${name}.limit`, main_seg.limit);

				if (v4_pool.SubnetMask)
					uci_list_string(output, `dhcp.${name}.dhcp_option`,
						`1,${v4_pool.SubnetMask}`);

				v4_lease_time = ubbf_to_int(v4_pool.LeaseTime);
				if (v4_lease_time)
					uci_set_string(output, `dhcp.${name}.leasetime`, sprintf('%d', v4_lease_time));

				if (v4_pool.DomainName)
					uci_set_string(output, `dhcp.${name}.domain`, v4_pool.DomainName);

				let dns_list = csv_to_list(v4_pool.DNSServers);
				if (length(dns_list) > 0)
					uci_list_string(output, `dhcp.${name}.dhcp_option`,
						`6,${join(',', dns_list)}`);

				let routers = csv_to_list(v4_pool.IPRouters);
				if (length(routers) > 0)
					uci_list_string(output, `dhcp.${name}.dhcp_option`,
						`3,${join(',', routers)}`);
				else
					uci_list_string(output, `dhcp.${name}.dhcp_option`, '3');

				let options = ubbf_instances(config,
					`Device.DHCPv4.Server.Pool.${v4_pool['.instance']}.Option`);
				for (let opt in options) {
					if (!ubbf_to_bool(opt.Enable))
						continue;
					let tag = ubbf_to_int(opt.Tag);
					if (tag == null)
						continue;
					let value = opt.Value ?? '';
					if (match(value, /[\x01-\x1f\x7f]/)) {
						warn('dhcp: option tag=%d value contains control characters, skipping', tag);
						continue;
					}
					uci_list_string(output, `dhcp.${name}.dhcp_option`,
						sprintf('%d,%s', tag, value));
				}
			} else if (v4_enabled) {
				warn('dhcp: %s: every address in [%s,%s] is reserved, disabling DHCPv4',
					name, v4_pool.MinAddress, v4_pool.MaxAddress);
				uci_set_boolean(output, `dhcp.${name}.ignore`, true);
			} else {
				uci_set_boolean(output, `dhcp.${name}.ignore`, true);
			}

			if (v6_enabled) {
				uci_set_string(output, `dhcp.${name}.dhcpv6`, 'server');
				uci_set_boolean(output, `dhcp.${name}.dhcpv6_na`, ubbf_to_bool(v6_pool.IANAEnable));

				if (ubbf_to_bool(v6_pool.IAPDEnable)) {
					uci_set_boolean(output, `dhcp.${name}.dhcpv6_pd`, true);
					let add_len = ubbf_to_int(v6_pool.IAPDAddLength);
					if (add_len) {
						let pd_len = 0;
						for (let prefix in ubbf_instances(iface, 'IPv6Prefix')) {
							if ((lc(prefix.Origin) == 'prefixdelegation' || lc(prefix.Origin) == 'child') && prefix.ChildPrefixBits) {
								pd_len = ubbf_to_int(prefix.ChildPrefixBits);
								break;
							}
						}
						if (pd_len) {
							let total = pd_len + add_len;
							if (total < 0 || total > 128 || (total % 4) != 0)
								warn('dhcp: skipping dhcpv6_pd_min_len=%d on %s, not on nibble boundary', total, name);
							else
								uci_set_number(output, `dhcp.${name}.dhcpv6_pd_min_len`, total);
						}
					}
				} else {
					uci_set_boolean(output, `dhcp.${name}.dhcpv6_pd`, false);
				}

				let v6_options = ubbf_instances(config,
					`Device.DHCPv6.Server.Pool.${v6_pool['.instance']}.Option`);
				let v6_raw = '';
				for (let opt in v6_options) {
					if (!ubbf_to_bool(opt.Enable))
						continue;
					let tag = ubbf_to_int(opt.Tag);
					if (tag == null || tag < 0 || tag > 0xffff)
						continue;
					let value = opt.Value ?? '';
					if (!match(value, /^[0-9a-fA-F]*$/) || (length(value) % 2) != 0) {
						warn('dhcp: dhcpv6 option tag=%d value not even-length hex, skipping', tag);
						continue;
					}
					let value_bytes = length(value) / 2;
					if (value_bytes > 0xffff) {
						warn('dhcp: dhcpv6 option tag=%d exceeds 65535 bytes, skipping', tag);
						continue;
					}
					v6_raw += sprintf('%04x%04x%s', tag, value_bytes, value);
				}
				if (length(v6_raw) > 0)
					uci_set_string(output, `dhcp.${name}.dhcpv6_raw`, v6_raw);
			} else {
				uci_set_string(output, `dhcp.${name}.dhcpv6`, 'disabled');
			}

			if (ra_enabled) {
				uci_set_string(output, `dhcp.${name}.ra`, 'server');

				if (!ubbf_to_bool(iface.Upstream))
					uci_set_number(output, `dhcp.${name}.ra_default`, 1);

				if (ubbf_to_bool(ra.AdvManagedFlag))
					uci_list_string(output, `dhcp.${name}.ra_flags`, 'managed-config');
				if (ubbf_to_bool(ra.AdvOtherConfigFlag))
					uci_list_string(output, `dhcp.${name}.ra_flags`, 'other-config');
				if (ubbf_to_bool(ra.AdvMobileAgentFlag))
					uci_list_string(output, `dhcp.${name}.ra_flags`, 'home-agent');

				if (ra.MaxRtrAdvInterval)
					uci_set_number(output, `dhcp.${name}.ra_maxinterval`, ra.MaxRtrAdvInterval);
				if (ra.MinRtrAdvInterval)
					uci_set_number(output, `dhcp.${name}.ra_mininterval`, ra.MinRtrAdvInterval);
				if (ra.AdvDefaultLifetime)
					uci_set_number(output, `dhcp.${name}.ra_lifetime`, ra.AdvDefaultLifetime);

				let pref = ra_preference_to_uci(ra.AdvPreferredRouterFlag);
				if (pref)
					uci_set_string(output, `dhcp.${name}.ra_preference`, pref);

				if (ra.AdvLinkMTU)
					uci_set_number(output, `dhcp.${name}.ra_mtu`, ra.AdvLinkMTU);
				if (ra.AdvCurHopLimit)
					uci_set_number(output, `dhcp.${name}.ra_hoplimit`, ra.AdvCurHopLimit);
				if (ra.AdvReachableTime)
					uci_set_number(output, `dhcp.${name}.ra_reachabletime`, ra.AdvReachableTime);
				if (ra.AdvRetransTimer)
					uci_set_number(output, `dhcp.${name}.ra_retranstime`, ra.AdvRetransTimer);

				for (let dns in csv_to_list(ra.RDNSS))
					uci_list_string(output, `dhcp.${name}.dns`, dns);

				for (let domain in csv_to_list(ra.DNSSL))
					uci_list_string(output, `dhcp.${name}.domain`, domain);
			} else if (v6_enabled && !ra) {
				uci_set_string(output, `dhcp.${name}.ra`, 'server');
			} else {
				uci_set_string(output, `dhcp.${name}.ra`, 'disabled');
				uci_set_string(output, `dhcp.${name}.ndp`, 'disabled');
			}

			uci_set_boolean(output, `dhcp.${name}.master`, false);

			if (v4_enabled && length(v4_segments) > 1) {
				for (let idx = 1; idx < length(v4_segments); idx++) {
					let seg = segment_to_start_limit(v4_segments[idx], iface_mask);
					let section = `dhcp.${name}_resv${idx}`;

					uci_named_section(output, section, 'dhcp');
					uci_set_string(output, `${section}.interface`, name);
					if (dnsmasq_instance)
						uci_set_string(output, `${section}.instance`, dnsmasq_instance);

					uci_set_string(output, `${section}.dhcpv4`, 'server');
					uci_set_number(output, `${section}.start`, seg.start);
					uci_set_number(output, `${section}.limit`, seg.limit);

					if (v4_pool.SubnetMask)
						uci_list_string(output, `${section}.dhcp_option`,
							`1,${v4_pool.SubnetMask}`);

					if (v4_lease_time)
						uci_set_string(output, `${section}.leasetime`,
							sprintf('%d', v4_lease_time));

					uci_set_boolean(output, `${section}.master`, false);
				}
			}

			if (v4_enabled) {
				for (let pool in v4_extra_pools) {
					if (!ubbf_to_bool(pool.Enable))
						continue;

					let pool_tag = ubbf.name_sanitise(pool.Alias || `pool_${pool['.instance']}`);
					let section = `dhcp.${name}_${pool_tag}`;

					uci_named_section(output, section, 'dhcp');
					uci_set_string(output, `${section}.interface`, name);
					if (dnsmasq_instance)
						uci_set_string(output, `${section}.instance`, dnsmasq_instance);

					uci_set_string(output, `${section}.dhcpv4`, 'server');
					let range = calculate_dhcp_start_limit(
						pool.MinAddress, pool.MaxAddress, iface_mask);
					uci_set_number(output, `${section}.start`, range.start);
					uci_set_number(output, `${section}.limit`, range.limit);

					if (pool.SubnetMask)
						uci_list_string(output, `${section}.dhcp_option`,
							`1,${pool.SubnetMask}`);

					let lease_time = ubbf_to_int(pool.LeaseTime);
					if (lease_time)
						uci_set_string(output, `${section}.leasetime`, sprintf('%d', lease_time));

					uci_set_string(output, `${section}.networkid`, pool_tag);
					for (let mt in pool_match_tags(pool))
						uci_list_string(output, `${section}.tag`,
							mt.exclude ? `!${mt.name}` : mt.name);
					uci_set_boolean(output, `${section}.master`, false);
				}
			}
		}

		return;
	}

	/**
	 * Generates UCI static DHCP host entries.
	 *
	 * @param {array} dhcpv4_pools - DHCPv4 pool instances
	 * @returns {string} UCI batch output
	 */
	function generate_static_hosts(dhcpv4_pools) {

		for (let pool_inst, pool_data in dhcpv4_pools) {
			if (!pool_data || !ubbf_to_bool(pool_data.Enable))
				continue;

			let static_addresses = ubbf_instances(config, `Device.DHCPv4.Server.Pool.${pool_data['.instance']}.StaticAddress`);
			for (let static_inst, static_data in static_addresses) {
				if (!static_data || !ubbf_to_bool(static_data.Enable))
					continue;

				uci_section(output, 'dhcp host');
				uci_set_string(output, 'dhcp.@host[-1].name', static_data.Alias || `static_${pool_data['.instance']}_${static_data['.instance']}`);
				uci_set_string(output, 'dhcp.@host[-1].mac', static_data.Chaddr);
				uci_set_string(output, 'dhcp.@host[-1].ip', static_data.Yiaddr);
			}
		}

		return;
	}

	/**
	 * Generates UCI classification sections for dnsmasq tag-based pool matching.
	 *
	 * @param {array} dhcpv4_pools - DHCPv4 pool instances
	 * @returns {string} UCI batch output
	 */
	function generate_pool_classification(dhcpv4_pools) {

		for (let pool in dhcpv4_pools) {
			if (!ubbf_to_bool(pool.Enable))
				continue;

			let has_class = pool.VendorClassID || pool.UserClassID
				|| pool.Chaddr || pool.ClientID;
			if (!has_class)
				continue;

			let pool_tag = ubbf.name_sanitise(pool.Alias || `pool_${pool['.instance']}`);

			if (pool.VendorClassID) {
				/* dnsmasq's --dhcp-vendorclass is substring-only, so
				 * VendorClassIDMode=Exact has to route through
				 * --dhcp-match against option 60 instead. The init
				 * script's `mode` UCI option drives that switch. */
				let mode = pool.VendorClassIDMode == 'Exact' ?
					'exact' : 'prefix';
				uci_section(output, 'dhcp vendorclass');
				uci_set_string(output, 'dhcp.@vendorclass[-1].networkid', `${pool_tag}_vc`);
				uci_set_string(output, 'dhcp.@vendorclass[-1].vendorclass', pool.VendorClassID);
				uci_set_string(output, 'dhcp.@vendorclass[-1].mode', mode);
			}

			if (pool.UserClassID) {
				uci_section(output, 'dhcp userclass');
				uci_set_string(output, 'dhcp.@userclass[-1].networkid', `${pool_tag}_uc`);
				uci_set_string(output, 'dhcp.@userclass[-1].userclass', pool.UserClassID);
			}

			if (pool.Chaddr) {
				let mac = pool.Chaddr;
				if (pool.ChaddrMask) {
					let mac_parts = split(mac, ':');
					let mask_parts = split(pool.ChaddrMask, ':');
					let result = [];
					for (let i = 0; i < length(mac_parts); i++) {
						if (i < length(mask_parts) && lc(mask_parts[i]) == 'ff')
							push(result, mac_parts[i]);
						else
							push(result, '*');
					}
					mac = join(':', result);
				}
				uci_section(output, 'dhcp mac');
				uci_set_string(output, 'dhcp.@mac[-1].networkid', `${pool_tag}_mac`);
				uci_set_string(output, 'dhcp.@mac[-1].mac', mac);
			}

			if (pool.ClientID) {
				let client_id = hex_string_to_colon(pool.ClientID);
				if (!client_id) {
					warn('dhcp: rejecting pool %s ClientID=%s, not valid hexBin', pool['.instance'], pool.ClientID);
				} else {
					uci_section(output, 'dhcp match');
					uci_set_string(output, 'dhcp.@match[-1].networkid', `${pool_tag}_cid`);
					uci_set_string(output, 'dhcp.@match[-1].match', sprintf('61,%s', client_id));
				}
			}
		}

		return;
	}

	/**
	 * Returns the first non-upstream IP.Interface name, used as the LAN
	 * dhcp section the tagged dhcp_option entries are written into.
	 * Multi-LAN ADMZ requires a knob; V1 picks the first match.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {string|null}
	 */
	function admz_lan_interface_name(ip_interfaces) {
		for (let iface in ip_interfaces) {
			if (ubbf_to_bool(iface.Upstream))
				continue;
			if (!iface.Name)
				continue;
			return iface.Name;
		}
		return null;
	}

	/**
	 * Returns the L2 device backing the LAN IP.Interface (e.g. br-lanv0),
	 * needed for the shared-network directive.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {string|null}
	 */
	function admz_lan_l2_dev(ip_interfaces) {
		for (let iface in ip_interfaces) {
			if (ubbf_to_bool(iface.Upstream))
				continue;
			if (!iface.Name)
				continue;
			return lower_layer_resolve_vlan(config, iface.LowerLayers);
		}
		return null;
	}

	/**
	 * Returns the dnsmasq instance name that serves DHCP on the LAN,
	 * derived the same way generate_dhcp_sections does it: a DNS-relay
	 * binding on the LAN forces a `dns_relay_<name>` instance; otherwise
	 * the LAN section ends up in the default dnsmasq instance (cfg<id>).
	 * In the testbed deployments where DNS relay is always configured
	 * this resolves to `dns_relay_lan`; on a stripped-down build the
	 * conf-dir lives in the auto-named default and the snippet should
	 * still take effect because dnsmasq merges all of them at startup.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {string|null}
	 */
	function admz_dnsmasq_instance(ip_interfaces) {
		let relay_ifaces = relay_interfaces();
		let lan_name = admz_lan_interface_name(ip_interfaces);
		if (!lan_name)
			return null;
		if (relay_ifaces[lan_name])
			return sprintf('dns_relay_%s', lan_name);
		return null;
	}

	/**
	 * Returns the absolute path to the ADMZ snippet for the current
	 * LAN-side dnsmasq instance, or null when no instance is in play
	 * (e.g. DNS relay not configured).
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {string|null}
	 */
	function admz_snippet_path(ip_interfaces) {
		let inst = admz_dnsmasq_instance(ip_interfaces);
		if (!inst)
			return null;
		return sprintf('/tmp/dnsmasq.%s.d/%s', inst, ADMZ_SNIPPET_FILE);
	}

	/**
	 * Writes the shared-network + static-range snippet for ADMZ to
	 * the dnsmasq instance's conf-dir so dnsmasq accepts the WAN-subnet
	 * dhcp-host stanza on the LAN bridge. Idempotent; the snippet is
	 * regenerated on every render with current lease values.
	 *
	 * @param {string} path - conf-dir snippet path
	 * @param {string} lan_dev - LAN L2 device name
	 * @param {string} net_base - WAN network base (e.g. 172.16.100.0)
	 * @param {string} mask - WAN netmask (e.g. 255.255.255.0)
	 * @param {number} lease_time - lease in seconds
	 */
	function admz_snippet_write(path, lan_dev, net_base, mask, lease_time) {
		let lines = [];
		if (lan_dev)
			push(lines, sprintf('shared-network=%s,%s', lan_dev, net_base));
		push(lines, sprintf('dhcp-range=%s,static,%s,%d', net_base, mask, lease_time));
		let m = match(path, /^(.+)\/[^\/]+$/);
		if (m)
			fs.mkdir(m[1], 0755);
		fs.writefile(path, join('\n', lines) + '\n');
	}

	/**
	 * Resolves the current WAN lease snapshot for ADMZ rendering. Three
	 * lease sources, in order of freshness:
	 *
	 *   1. admzd's status ubus (ACTIVE state holds the lease the proto
	 *      handler published).
	 *   2. netifd interface status .data.admz_lease_* (the proto
	 *      handler's bound callback stashes it here before admzd polls).
	 *   3. netifd ipv4-address, skipping the 198.18.0.1 secondary. This
	 *      catches the Enable false->true transition: at apply time the
	 *      previous script callback ran with enable=0 and bound the
	 *      leased IP normally, so eth0's ipv4-address still carries the
	 *      lease. Without this branch the dnsmasq host stanza is
	 *      emitted as "ignore" on the first ADMZ enable, the ADMZ MAC
	 *      cannot DORA the public IP, and the wire tests fail. Gateway
	 *      and DNS are derived from netifd's route and dns-server
	 *      fields.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {object|null} {ip, mask_cidr, gw, dns:[]} or null
	 */
	function admz_lease_lookup(ip_interfaces) {
		let status = ubus.call({ object: 'admz', method: 'status', data: {} });
		if (status?.state == 'ACTIVE' && status?.lease_ip) {
			let mask_cidr = null;
			if (status?.lease_netmask)
				mask_cidr = ubbf.netmask_to_cidr(status.lease_netmask);
			return {
				ip: status.lease_ip,
				mask_cidr: mask_cidr,
				gw: status.gateway,
				dns: status.dns_servers ?? []
			};
		}

		for (let iface in ip_interfaces) {
			if (!ubbf_to_bool(iface.Upstream))
				continue;
			if (!iface.Name)
				continue;
			let st = netifd_status_get(iface.Name);
			if (!st?.up)
				continue;

			let data = st.data ?? {};
			if (data.admz_lease_ip) {
				let dns = [];
				if (type(data.admz_lease_dns) == 'string')
					dns = split(data.admz_lease_dns, ' ');
				let mask_cidr = null;
				if (data.admz_lease_netmask)
					mask_cidr = ubbf.netmask_to_cidr(data.admz_lease_netmask);
				return {
					ip: data.admz_lease_ip,
					mask_cidr: mask_cidr,
					gw: data.admz_lease_router,
					dns: dns
				};
			}

			let v4 = st['ipv4-address'];
			if (type(v4) == 'array') {
				for (let entry in v4) {
					let addr = entry?.address;
					if (!addr || addr == ADMZ_SECONDARY)
						continue;
					let gw = null;
					for (let r in st.route ?? []) {
						if (r?.target == '0.0.0.0' && (r?.mask == 0 || r?.mask == '0')) {
							gw = r.nexthop;
							break;
						}
					}
					return {
						ip: addr,
						mask_cidr: entry.mask,
						gw: gw,
						dns: st['dns-server'] ?? []
					};
				}
			}
		}
		return null;
	}

	/**
	 * Generates the dnsmasq host stanza for Device.NAT.X_UBBF_IPPassthrough.
	 * Intent (Enable, MAC, LeaseTime) is read directly from the TR-181
	 * config object the renderer already has in hand: this is the
	 * freshest source for the current apply cycle. The lease snapshot
	 * (wan_pub, mask, gw, dns) is read from admz_lease_lookup which
	 * prefers admzd's cache and falls back to netifd. Three branches:
	 *
	 *   Enable=false / no MAC -> empty output, ADMZ MAC (if any)
	 *                              falls into the normal LAN pool.
	 *   no lease available    -> dhcp host with `option ignore '1'`,
	 *                              the MVP-2020 hold-down: the ADMZ
	 *                              MAC receives no DHCP offer at all
	 *                              until the WAN is up.
	 *   lease available       -> dhcp host with the public IPv4 and
	 *                              the `admz` tag, plus tagged
	 *                              dhcp_option entries on the LAN
	 *                              dhcp section carrying the WAN-side
	 *                              mask (option 1), gateway (option 3)
	 *                              and DNS (option 6).
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @returns {string} UCI batch output
	 */
	function generate_admz_hosts(ip_interfaces) {
		let admz = ubbf_get(config, 'Device.NAT.X_UBBF_IPPassthrough');
		let snippet_path = admz_snippet_path(ip_interfaces);

		// Default: remove the conf-dir snippet. We rewrite it below
		// only when ADMZ is in the ACTIVE-with-lease branch.
		if (snippet_path)
			fs.unlink(snippet_path);

		if (!admz || !ubbf_to_bool(admz.Enable))
			return;

		let mac = lc(admz.AdvancedDMZhost ?? '');
		if (mac == '')
			return;

		let lease_time = ubbf_to_int(admz.LeaseTime) ?? 3600;
		if (lease_time < 60) lease_time = 60;
		if (lease_time > 604800) lease_time = 604800;

		let lease = admz_lease_lookup(ip_interfaces);

		if (!lease || !lease.ip) {
			uci_named_section(output, 'dhcp.admz', 'host');
			uci_set_string(output, 'dhcp.admz.name', 'admz');
			uci_set_string(output, 'dhcp.admz.mac', mac);
			uci_set_boolean(output, 'dhcp.admz.ignore', true);
			return;
		}

		let wan_mask = ubbf.cidr_to_netmask(lease.mask_cidr);
		let wan_gw = lease.gw;
		let wan_dns = lease.dns ?? [];

		// Write the dnsmasq conf-dir snippet so the WAN subnet is
		// known to the dnsmasq instance that serves DHCP on the LAN.
		// Without this, dnsmasq rejects dhcp-host stanzas whose IP
		// falls outside the LAN dhcp-range and falls back to the
		// LAN pool.
		if (snippet_path) {
			let mask_int = ubbf.ip_to_int(wan_mask);
			let ip_int = ubbf.ip_to_int(lease.ip);
			if (mask_int && ip_int) {
				let net_int = ip_int & mask_int;
				let net_base = ubbf.int_to_ip(net_int);
				let lan_dev = admz_lan_l2_dev(ip_interfaces);
				admz_snippet_write(snippet_path, lan_dev, net_base, wan_mask, lease_time);
			}
		}

		uci_named_section(output, 'dhcp.admz', 'host');
		uci_set_string(output, 'dhcp.admz.name', 'admz');
		uci_set_string(output, 'dhcp.admz.mac', mac);
		uci_set_string(output, 'dhcp.admz.ip', lease.ip);
		uci_list_string(output, 'dhcp.admz.tag', 'admz');
		uci_set_string(output, 'dhcp.admz.leasetime', sprintf('%d', lease_time));

		let lan_name = admz_lan_interface_name(ip_interfaces);
		if (!lan_name)
			return;

		if (wan_mask)
			uci_list_string(output, sprintf('dhcp.%s.dhcp_option', lan_name),
				sprintf('tag:admz,1,%s', wan_mask));
		if (wan_gw)
			uci_list_string(output, sprintf('dhcp.%s.dhcp_option', lan_name),
				sprintf('tag:admz,3,%s', wan_gw));
		if (length(wan_dns) > 0)
			uci_list_string(output, sprintf('dhcp.%s.dhcp_option', lan_name),
				sprintf('tag:admz,6,%s', join(',', wan_dns)));
	}

	/**
	 * Generates UCI dhcpsnoop device sections for DHCP interfaces.
	 *
	 * @param {array} ip_interfaces - IP interface instances
	 * @param {array} dhcpv4_pools - DHCPv4 pool instances
	 * @param {array} dhcpv4_clients - DHCPv4 client instances
	 * @returns {string} UCI batch output
	 */
	function generate_dhcpsnoop_config(ip_interfaces, dhcpv4_pools, dhcpv4_clients) {
		let has_devices;

		for (let iface in ip_interfaces) {
			let name = iface.Name;
			if (!name)
				continue;

			let iface_ref = iface['.path'];
			let v4_pool = get_pool_for_interface(iface_ref, dhcpv4_pools);
			if (v4_pool && ubbf_to_bool(v4_pool.Enable)) {
				uci_named_section(output, `dhcpsnoop.${name}`, 'device');
				uci_set_string(output, `dhcpsnoop.${name}.name`, name);
				uci_set_boolean(output, `dhcpsnoop.${name}.ingress`, true);
				uci_set_boolean(output, `dhcpsnoop.${name}.egress`, true);
				uci_set_string(output, `dhcpsnoop.${name}.group`, 'server');
				has_devices = true;
			}
		}

		for (let client in dhcpv4_clients) {
			if (!ubbf_to_bool(client.Enable))
				continue;

			let client_iface = client.Interface;
			if (!client_iface)
				continue;

			let iface_data = ubbf_get(config, client_iface);
			let name = iface_data?.Name;
			if (!name)
				continue;

			let group = sprintf('client_%s', client['.instance']);
			uci_named_section(output, `dhcpsnoop.${name}`, 'device');
			uci_set_string(output, `dhcpsnoop.${name}.name`, name);
			uci_set_boolean(output, `dhcpsnoop.${name}.ingress`, true);
			uci_set_boolean(output, `dhcpsnoop.${name}.egress`, true);
			uci_set_string(output, `dhcpsnoop.${name}.group`, group);
			has_devices = true;
		}

		services.set_enabled('dhcpsnoop', has_devices);

		return;
	}

	let ip = ubbf_get(config, 'Device.IP');
	if (!ip)
		return;

	let ip_interfaces = ubbf_instances(config, 'Device.IP.Interface');
	let dhcpv4_pools = ubbf_instances(config, 'Device.DHCPv4.Server.Pool');
	let dhcpv4_clients = ubbf_instances(config, 'Device.DHCPv4.Client');
	let dhcpv6_pools = ubbf_instances(config, 'Device.DHCPv6.Server.Pool');
	let ra_settings = ubbf_instances(config, 'Device.RouterAdvertisement.InterfaceSetting');
	let v4_server = ubbf_get(config, 'Device.DHCPv4.Server');
	let v4_server_enabled = !v4_server || ubbf_to_bool(v4_server.Enable);
	let v6_server = ubbf_get(config, 'Device.DHCPv6.Server');
	let v6_server_enabled = !v6_server || ubbf_to_bool(v6_server.Enable);
	let relay_ifaces = relay_interfaces();
	services.set_enabled('odhcpd', true);

	generate_dhcp_sections(ip_interfaces, dhcpv4_pools, dhcpv6_pools, ra_settings, v4_server_enabled, v6_server_enabled, relay_ifaces);
	generate_static_hosts(dhcpv4_pools);
	generate_admz_hosts(ip_interfaces);
	generate_pool_classification(dhcpv4_pools);
	generate_dhcpsnoop_config(ip_interfaces, dhcpv4_pools, dhcpv4_clients);
}
uci_comment(output, '# generated by dhcp.uc');
render_config();
