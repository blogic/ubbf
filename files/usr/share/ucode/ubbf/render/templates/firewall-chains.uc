function render_config() {
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
	if (rule.Protocol || rule.SourcePort || rule.DestPort)
		return false;
	if (rule.SourceIP || rule.DestIP)
		return false;
	return true;
}

/**
 * Returns the rules of a chain in TR-181 evaluation order: ascending
 * Order, the instance number breaking ties. fw4 matches rules in UCI
 * order, so this is the order they are emitted in.
 *
 * @param {object} rules - Chain.Rule instances keyed by instance number
 * @returns {array} rule objects
 */
function rules_ordered(rules) {
	let list = [];
	for (let inst, rule in rules)
		push(list, { inst: ubbf_to_int(inst) ?? 0, order: ubbf_to_int(rule.Order) ?? 0, rule });

	sort(list, (a, b) => (a.order - b.order) || (a.inst - b.inst));
	return map(list, e => e.rule);
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
 * @param {string|null} default_src - zone name inherited from enclosing Policy
 * @param {string|null} default_dst - zone name inherited from enclosing Policy
 * @param {string|null} default_family - family inherited from enclosing Policy
 */
function emit_chain_rule_with_zones(output, rule, src, dst, family) {
	uci_section(output, 'firewall rule');
	uci_set_boolean(output, 'firewall.@rule[-1].enabled', true);

	if (rule.Description)
		uci_set_string(output, 'firewall.@rule[-1].name', rule.Description);

	if (src)
		uci_set_string(output, 'firewall.@rule[-1].src', src);

	if (dst)
		uci_set_string(output, 'firewall.@rule[-1].dest', dst);

	let proto = ubbf.protocol_to_uci(rule.Protocol);
	if (proto)
		uci_set_string(output, 'firewall.@rule[-1].proto', proto);

	let src_port = ubbf.port_range_format(rule.SourcePort, rule.SourcePortRangeMax);
	if (src_port)
		uci_set_string(output, 'firewall.@rule[-1].src_port', src_port);

	let dest_port = ubbf.port_range_format(rule.DestPort, rule.DestPortRangeMax);
	if (dest_port)
		uci_set_string(output, 'firewall.@rule[-1].dest_port', dest_port);

	uci_set_string(output, 'firewall.@rule[-1].target', target_to_uci(rule.Target));

	if (family)
		uci_set_string(output, 'firewall.@rule[-1].family', family);

	let src_ip = format_ip_with_mask(rule.SourceIP, rule.SourceMask);
	if (src_ip)
		uci_set_string(output, 'firewall.@rule[-1].src_ip', src_ip);

	let dest_ip = format_ip_with_mask(rule.DestIP, rule.DestMask);
	if (dest_ip)
		uci_set_string(output, 'firewall.@rule[-1].dest_ip', dest_ip);

	if (rule.SourceMAC && rule.SourceMAC != '')
		uci_set_string(output, 'firewall.@rule[-1].src_mac', rule.SourceMAC);

	let dscp = ubbf_to_int(rule.DSCP);
	if (dscp != null && dscp >= 0) {
		uci_set_number(output, 'firewall.@rule[-1].dscp', dscp);
		if (ubbf_to_bool(rule.DSCPExclude))
			uci_set_boolean(output, 'firewall.@rule[-1].dscp_negate', true);
	}

	if (rule.ExpiryDate && rule.ExpiryDate != '' && rule.ExpiryDate != '9999-12-31T23:59:59Z')
		uci_set_string(output, 'firewall.@rule[-1].stop_time', rule.ExpiryDate);

	if (ubbf_to_bool(rule.Log))
		uci_set_boolean(output, 'firewall.@rule[-1].log', true);
}

function emit_chain_rule(output, rule, default_src, default_dst, default_family) {
	let src;
	if (ubbf_to_bool(rule.SourceAllInterfaces))
		src = '*';
	else if (rule.SourceInterface)
		src = interface_to_name(config, rule.SourceInterface);
	else
		src = default_src;

	let dst;
	if (ubbf_to_bool(rule.DestAllInterfaces))
		dst = '*';
	else if (rule.DestInterface)
		dst = interface_to_name(config, rule.DestInterface);
	else
		dst = default_dst;

	let family = ipversion_to_family(rule.IPVersion) ?? default_family;

	emit_chain_rule_with_zones(output, rule, src, dst, family);
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
 * Renders Advanced-mode firewall: iterate every enabled Chain, emit
 * zone-pair forwardings for the simple-forwarding rules and firewall
 * rules for the rest. This is the pre-Policy-mode behaviour.
 */
function generate_advanced() {
	let chains = ubbf_instances(config, 'Device.Firewall.Chain');

	for (let chain in chains) {
		if (!ubbf_to_bool(chain.Enable))
			continue;

		let rules = chain.Rule;
		if (type(rules) != 'object')
			continue;

		for (let rule in rules_ordered(rules)) {
			if (!ubbf_to_bool(rule.Enable))
				continue;

			if (is_forwarding_rule(rule)) {
				let src_zone = interface_to_name(config, rule.SourceInterface);
				let dest_zone = interface_to_name(config, rule.DestInterface);
				if (src_zone && dest_zone) {
					uci_section(output, 'firewall forwarding');
					uci_set_string(output, 'firewall.@forwarding[-1].src', src_zone);
					uci_set_string(output, 'firewall.@forwarding[-1].dest', dest_zone);
				}
				continue;
			}

			let dst_zones = [null];
			if (ubbf_to_bool(rule.DestAllInterfaces))
				dst_zones = ['*', null];
			else if (rule.DestInterface) {
				let dz = interface_to_name(config, rule.DestInterface);
				if (dz)
					dst_zones = [dz];
			}

			let src_zone;
			if (ubbf_to_bool(rule.SourceAllInterfaces))
				src_zone = '*';
			else if (rule.SourceInterface)
				src_zone = interface_to_name(config, rule.SourceInterface);

			let family = ipversion_to_family(rule.IPVersion);

			for (let dest_zone in dst_zones)
				emit_chain_rule_with_zones(output, rule, src_zone, dest_zone, family);
		}
	}
}

function generate_firewall_chains() {
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
