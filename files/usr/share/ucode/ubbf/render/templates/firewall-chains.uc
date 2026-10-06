function render_config() {
/**
 * Returns the fw4 stop_date of a rule's ExpiryDate. fw4 takes dates
 * from 1970 to 2038; a later expiry is left out with a warning.
 *
 * @param {object} rule - Firewall chain rule object
 * @returns {string|null} YYYY-MM-DDThh:mm:ss in UTC, or null for no expiry
 */
function rule_stop_date(rule) {
	let value = rule.ExpiryDate ?? '';
	// ucode regexps match $ at the end of each line
	if (index(value, '\n') >= 0)
		return null;

	let m = match(value, /^(([0-9]{4})-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})Z$/);
	if (!m)
		return null;

	// 0001-01-01T00:00:00Z means not known, 9999-12-31T23:59:59Z never
	let year = +m[2];
	if (year == 1 || year == 9999)
		return null;

	if (year < 1970 || year > 2038) {
		warn('firewall: rule %s ExpiryDate %s is outside the fw4 date range, not applied', rule.Alias, value);
		return null;
	}

	return m[1];
}

/**
 * Tells whether a rule matches on anything but its zones.
 *
 * @param {object} rule - Firewall chain rule object
 * @returns {boolean} True if the rule has a match beyond the zones
 */
function rule_has_matches(rule) {
	if ((ubbf_to_int(rule.Protocol) ?? -1) >= 0 || (ubbf_to_int(rule.DSCP) ?? -1) >= 0)
		return true;
	if ((ubbf_to_int(rule.SourcePort) ?? -1) > 0 || (ubbf_to_int(rule.DestPort) ?? -1) > 0)
		return true;
	if (rule.SourceIP || rule.DestIP || rule.SourceMAC)
		return true;
	if (rule.SourceMatchSet || rule.SourceMatchSetExclude || rule.DestMatchSet || rule.DestMatchSetExclude)
		return true;
	if ((ubbf_to_int(rule.FloodLimit) ?? -1) >= 0 || ubbf_to_bool(rule.Log))
		return true;
	if (ubbf_to_bool(rule.SourceInterfaceExclude) || ubbf_to_bool(rule.DestInterfaceExclude))
		return true;
	return rule_stop_date(rule) != null;
}

/**
 * Determines if a chain rule represents a simple zone-to-zone forward.
 *
 * @param {object} rule - Firewall chain rule object
 * @returns {boolean} True if rule is a forwarding-only rule
 */
function is_forwarding_rule(rule) {
	if (!rule.SourceInterface || !rule.DestInterface)
		return false;
	if (uc(rule.Target) != 'ACCEPT')
		return false;
	return !rule_has_matches(rule);
}

/**
 * Resolves the zones one side of a rule applies to. An excluded interface
 * stands for every other zone, since fw4 cannot negate a zone.
 *
 * @param {object} rule - Firewall chain rule object
 * @param {string} side - 'Source' or 'Dest'
 * @param {array} any - Zones for the side's AllInterfaces
 * @param {string|null} fallback - Zone when the rule names no interface
 * @returns {array} Zones, null for no zone match; empty when the
 *                  interface does not resolve
 */
function rule_zones(rule, side, any, fallback) {
	if (ubbf_to_bool(rule[`${side}AllInterfaces`]))
		return any;

	let ref = rule[`${side}Interface`];
	if (!ref)
		return [ fallback ];

	let zone = interface_to_name(config, ref);
	if (!zone) {
		warn('firewall: rule %s %sInterface %s does not resolve, skipping', rule.Alias, side, ref);
		return [];
	}

	// The other zones, and the device itself (no zone)
	if (ubbf_to_bool(rule[`${side}InterfaceExclude`]))
		return [ ...filter(render_state.firewall_zones ?? [], (z) => z != zone), null ];

	return [ zone ];
}

/**
 * Prefixes a fw4 match value with '!' when the rule excludes it.
 *
 * @param {string} value - fw4 match value
 * @param {*} exclude - TR-181 *Exclude flag
 * @returns {string} The value, negated for an excluded match
 */
function negated(value, exclude) {
	return ubbf_to_bool(exclude) ? `!${value}` : value;
}

function rules_ordered(rules) {
	return map(chain_rules_ordered(rules), (e) => e[1]);
}

/**
 * Resolves the currently active Firewall Level based on Config.
 *
 * @returns {object|null} active Level object or null when not resolvable
 */
function active_level() {
	let firewall = ubbf_get(config, 'Device.Firewall');
	if (!firewall)
		return null;

	let ref = (firewall.Config == 'Policy')
		? firewall.PolicyLevel
		: firewall.AdvancedLevel;

	if (!ref || ref == '')
		return null;

	return ubbf_get(config, ref);
}

/**
 * Returns the Policy objects referenced by the active Level's Policies list,
 * in order. Empty when Config is not 'Policy' or the level does not resolve.
 *
 * @returns {array} Array of { path, obj } entries, ordered by Level.Policies
 */
function active_policies() {
	let firewall = ubbf_get(config, 'Device.Firewall');
	if (!firewall || firewall.Config != 'Policy')
		return [];

	let level = active_level();
	if (!level || !level.Policies || level.Policies == '')
		return [];

	let result = [];
	for (let pref in ubbf.csv_to_list(level.Policies, '')) {
		let obj = ubbf_get(config, pref);
		if (obj)
			push(result, { path: pref, obj });
	}

	return result;
}

/**
 * Emits a single firewall rule from a Chain.Rule entry. Policy-supplied
 * defaults fill in SourceInterface/DestInterface/family when the rule
 * itself does not set them, mirroring how a Policy binds a zone-pair
 * around its chain.
 *
 * @param {array} output - UCI batch accumulator
 * @param {object} rule - Chain.Rule.{i} object
 * @param {string|null} src - source zone
 * @param {string|null} dst - destination zone
 * @param {string|null} family - firewall family
 * @param {string|null} ipset - fw4 set match, from chain_rule_set_matches()
 */
function emit_chain_rule_with_zones(output, rule, src, dst, family, ipset) {
	// TR-181 2.20 FloodLimit: a rate of 0 lets no packet match the rule.
	let flood_limit = ubbf_to_int(rule.FloodLimit) ?? -1;
	if (flood_limit == 0)
		return;

	uci_section(output, 'firewall rule');
	uci_set_boolean(output, 'firewall.@rule[-1].enabled', true);

	if (rule.Description)
		uci_set_string(output, 'firewall.@rule[-1].name', rule.Description);

	if (src)
		uci_set_string(output, 'firewall.@rule[-1].src', src);

	if (dst)
		uci_set_string(output, 'firewall.@rule[-1].dest', dst);

	// fw4 takes a rule without proto as TCP and UDP only, TR-181 as all
	let proto = ubbf.protocol_to_uci(rule.Protocol ?? '-1');
	if (proto && proto != 'all')
		uci_set_string(output, 'firewall.@rule[-1].proto', negated(proto, rule.ProtocolExclude));
	else if (proto)
		uci_set_string(output, 'firewall.@rule[-1].proto', proto);

	let src_port = ubbf.port_range_format(rule.SourcePort, rule.SourcePortRangeMax);
	if (src_port)
		uci_set_string(output, 'firewall.@rule[-1].src_port', negated(src_port, rule.SourcePortExclude));

	let dest_port = ubbf.port_range_format(rule.DestPort, rule.DestPortRangeMax);
	if (dest_port)
		uci_set_string(output, 'firewall.@rule[-1].dest_port', negated(dest_port, rule.DestPortExclude));

	uci_set_string(output, 'firewall.@rule[-1].target', target_to_uci(rule.Target));

	if (family)
		uci_set_string(output, 'firewall.@rule[-1].family', family);

	let src_ip = format_ip_with_mask(rule.SourceIP, rule.SourceMask);
	if (src_ip)
		uci_set_string(output, 'firewall.@rule[-1].src_ip', negated(src_ip, rule.SourceIPExclude));

	let dest_ip = format_ip_with_mask(rule.DestIP, rule.DestMask);
	if (dest_ip)
		uci_set_string(output, 'firewall.@rule[-1].dest_ip', negated(dest_ip, rule.DestIPExclude));

	if (rule.SourceMAC && rule.SourceMAC != '')
		uci_set_string(output, 'firewall.@rule[-1].src_mac', negated(rule.SourceMAC, rule.SourceMACExclude));

	let dscp = ubbf_to_int(rule.DSCP);
	if (dscp != null && dscp >= 0) {
		// fw4 negates a match with a leading '!' on the value itself
		if (ubbf_to_bool(rule.DSCPExclude))
			uci_set_string(output, 'firewall.@rule[-1].dscp', sprintf('!%d', dscp));
		else
			uci_set_number(output, 'firewall.@rule[-1].dscp', dscp);
	}

	let stop_date = rule_stop_date(rule);
	if (stop_date) {
		uci_set_string(output, 'firewall.@rule[-1].stop_date', stop_date);
		uci_set_boolean(output, 'firewall.@rule[-1].utc_time', true);
	}

	// The spec gives FloodLimit no time unit; fw4 and nft take packets per
	// second when the unit is left out, and so does ubbf.
	if (flood_limit > 0) {
		uci_set_string(output, 'firewall.@rule[-1].limit', sprintf('%d/second', flood_limit));

		let burst_limit = ubbf_to_int(rule.BurstLimit) ?? -1;
		if (burst_limit > 0)
			uci_set_number(output, 'firewall.@rule[-1].limit_burst', burst_limit);
	}

	if (ubbf_to_bool(rule.Log))
		uci_set_boolean(output, 'firewall.@rule[-1].log', true);

	if (ipset)
		uci_set_string(output, 'firewall.@rule[-1].ipset', ipset);
}

/**
 * Tells whether a rule can be rendered, and warns when it cannot.
 *
 * @param {object} rule - Firewall chain rule object
 * @returns {boolean} False for a rule fw4 cannot express
 */
function rule_renderable(rule) {
	let reason = chain_rule_unsupported(rule, config);
	if (!reason)
		return true;

	warn('firewall: rule %s uses %s, which cannot be rendered, skipping', rule.Alias, reason);
	return false;
}

/**
 * Emits a rule once for each combination of its source and destination
 * zones, and once for each IP family of the Set it matches.
 *
 * @param {array} output - UCI batch accumulator
 * @param {object} rule - Chain.Rule.{i} object
 * @param {array} src_zones - Source zones, from rule_zones()
 * @param {array} dst_zones - Destination zones, from rule_zones()
 * @param {string|null} family - firewall family
 */
function emit_rule_zones(output, rule, src_zones, dst_zones, family) {
	let excludes = ubbf_to_bool(rule.SourceInterfaceExclude) || ubbf_to_bool(rule.DestInterfaceExclude);

	for (let set in chain_rule_set_matches(config, rule)) {
		// A rule of one family matches only the Set of that family
		if (family && set.family && family != set.family)
			continue;

		for (let src in src_zones) {
			for (let dst in dst_zones) {
				// fw4 renders a rule without src and dest as output to any
				// destination, wider than the device side of an exclude
				if (src == null && dst == null && excludes)
					continue;
				emit_chain_rule_with_zones(output, rule, src, dst, family ?? set.family, set.ipset);
			}
		}
	}
}

/**
 * Emits the fw4 ipsets of the enabled Device.Firewall.Set entries.
 */
function generate_ipsets() {
	for (let key in keys(ubbf_get(config, 'Device.Firewall.Set') ?? {})) {
		let set = firewall_set_resolve(config, `Device.Firewall.Set.${key}`);
		if (!set)
			continue;

		for (let s in set.ipsets) {
			uci_section(output, 'firewall ipset');
			uci_set_string(output, 'firewall.@ipset[-1].name', s.name);
			uci_set_string(output, 'firewall.@ipset[-1].family', s.family);
			uci_list_string(output, 'firewall.@ipset[-1].match', s.match);
			for (let entry in s.entries)
				uci_list_string(output, 'firewall.@ipset[-1].entry', entry);
		}
	}
}

function emit_chain_rule(output, rule, default_src, default_dst, default_family) {
	if (!rule_renderable(rule))
		return;

	let family = ipversion_to_family(rule.IPVersion) ?? default_family;

	emit_rule_zones(output, rule,
		rule_zones(rule, 'Source', [ '*' ], default_src),
		rule_zones(rule, 'Dest', [ '*' ], default_dst),
		family);
}

/**
 * Emits a single verdict rule for a Policy short-circuit target
 * (Drop/Accept/Reject). Used when Policy.TargetChain is not 'Chain'.
 *
 * @param {array} output - UCI batch accumulator
 * @param {string} target - uppercase uci target keyword
 * @param {string|null} src_zone - source zone name
 * @param {string|null} dst_zone - destination zone name
 * @param {string|null} family - firewall family (ipv4, ipv6, or null)
 */
function emit_policy_verdict(output, target, src_zone, dst_zone, family) {
	uci_section(output, 'firewall rule');
	uci_set_boolean(output, 'firewall.@rule[-1].enabled', true);
	if (src_zone)
		uci_set_string(output, 'firewall.@rule[-1].src', src_zone);
	if (dst_zone)
		uci_set_string(output, 'firewall.@rule[-1].dest', dst_zone);
	if (family)
		uci_set_string(output, 'firewall.@rule[-1].family', family);
	uci_set_string(output, 'firewall.@rule[-1].target', target);
}

/**
 * Emits rules from one direction of a Policy (forward uses Chain/TargetChain;
 * reverse uses ReverseChain/ReverseTargetChain).
 *
 * @param {array} output - UCI batch accumulator
 * @param {object} policy - Policy.{i} object
 * @param {string} target_field - 'TargetChain' or 'ReverseTargetChain'
 * @param {string} chain_field - 'Chain' or 'ReverseChain'
 * @param {string|null} src_zone - zone for this direction
 * @param {string|null} dst_zone - zone for this direction
 * @param {string|null} family - policy family
 */
function emit_policy_direction(output, policy, target_field, chain_field,
                                src_zone, dst_zone, family) {
	let target_raw = policy[target_field];
	if (target_raw == null || target_raw == '')
		return;

	let target = uc(target_raw);

	if (target == 'DROP' || target == 'ACCEPT' || target == 'REJECT') {
		emit_policy_verdict(output, target, src_zone, dst_zone, family);
		return;
	}

	if (target != 'CHAIN')
		return;

	let chain_ref = policy[chain_field];
	if (!chain_ref || chain_ref == '')
		return;

	let chain = ubbf_get(config, chain_ref);
	if (!chain || !ubbf_to_bool(chain.Enable))
		return;

	let rules = chain.Rule;
	if (type(rules) != 'object')
		return;

	for (let rule in rules_ordered(rules)) {
		if (!ubbf_to_bool(rule.Enable))
			continue;
		emit_chain_rule(output, rule, src_zone, dst_zone, family);
	}
}

/**
 * Renders the full Policy-mode firewall: one forwarding + chain per
 * enabled Policy referenced by the active PolicyLevel.
 */
function generate_policy() {
	let policies = active_policies();

	for (let p in policies) {
		let policy = p.obj;
		if (!ubbf_to_bool(policy.Enable))
			continue;

		let src_zone = policy.SourceInterface
			? interface_to_name(config, policy.SourceInterface)
			: null;
		let dst_zone = policy.DestinationInterface
			? interface_to_name(config, policy.DestinationInterface)
			: null;
		let family = ipversion_to_family(policy.IPVersion);

		if (src_zone && dst_zone) {
			uci_section(output, 'firewall forwarding');
			uci_set_string(output, 'firewall.@forwarding[-1].src', src_zone);
			uci_set_string(output, 'firewall.@forwarding[-1].dest', dst_zone);
			if (family)
				uci_set_string(output, 'firewall.@forwarding[-1].family', family);
		}

		emit_policy_direction(output, policy, 'TargetChain', 'Chain',
			src_zone, dst_zone, family);
		emit_policy_direction(output, policy, 'ReverseTargetChain', 'ReverseChain',
			dst_zone, src_zone, family);
	}
}

/**
 * Renders Advanced-mode firewall: the Chain of the active Level (TR-181
 * Level.Chain), with zone-pair forwardings for the simple-forwarding
 * rules and firewall rules for the rest. Other chains are reached only
 * through a Policy or a TargetChain jump, which fw4 cannot express.
 */
function generate_advanced() {
	let level = active_level();
	let chain = level?.Chain ? ubbf_get(config, rtrim(level.Chain, '.')) : null;

	if (!chain || !ubbf_to_bool(chain.Enable))
		return;

	for (let rule in rules_ordered(chain.Rule)) {
		if (!ubbf_to_bool(rule.Enable) || !rule_renderable(rule))
			continue;

		if (!is_forwarding_rule(rule)) {
			// All destinations covers the forwarded and the local traffic
			emit_rule_zones(output, rule,
				rule_zones(rule, 'Source', [ '*' ], null),
				rule_zones(rule, 'Dest', [ '*', null ], null),
				ipversion_to_family(rule.IPVersion));
			continue;
		}

		let src_zone = interface_to_name(config, rule.SourceInterface);
		let dest_zone = interface_to_name(config, rule.DestInterface);
		if (src_zone && dest_zone) {
			uci_section(output, 'firewall forwarding');
			uci_set_string(output, 'firewall.@forwarding[-1].src', src_zone);
			uci_set_string(output, 'firewall.@forwarding[-1].dest', dest_zone);
		}
	}
}

function generate_firewall_chains() {
	generate_ipsets();

	let firewall = ubbf_get(config, 'Device.Firewall');
	if (firewall && firewall.Config == 'Policy') {
		generate_policy();
		return;
	}
	generate_advanced();
}

	generate_firewall_chains();
}
render_config();
