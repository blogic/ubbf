'use strict';

import * as ubbf from 'ubbf';
import { uci_set_boolean, uci_set_string } from 'ubbf.render.uci_helpers';

/**
 * Sets the time options of a schedule window on the most recently emitted
 * firewall.@rule[-1] section.
 *
 * @param {string[]} output - UCI batch line accumulator
 * @param {object} window - Window from intervals_to_windows() in
 *     utils/schedule.uc
 */
export function rule_window_set(output, window) {
	uci_set_string(output, 'firewall.@rule[-1].start_time', window.start_time);
	uci_set_string(output, 'firewall.@rule[-1].stop_time', window.stop_time);
	// fw4 rejects a list for weekdays; it wants one space separated option
	uci_set_string(output, 'firewall.@rule[-1].weekdays', join(' ', window.weekdays));
};

/**
 * Appends fw4 reflection options to the most recently emitted
 * firewall.@redirect[-1] section. fw4 defaults to reflection=1 with
 * reflection_src=internal, so without this the SNAT source on a
 * hairpinned packet is the gateway LAN IP. To give the target the
 * external WAN IP/port as source, Device.NAT.X_UBBF_Hairpinning.Enable=true
 * flips reflection_src to external, false hard-disables reflection.
 *
 * @param {object} config - UBBF config root
 * @param {string[]} output - UCI batch line accumulator
 */
export function redirect_emit_reflection(config, output) {
	let hairpin = ubbf.get(config, 'Device.NAT.X_UBBF_Hairpinning');
	let enabled = ubbf.to_bool(hairpin?.Enable ?? "false");

	if (enabled) {
		uci_set_boolean(output, 'firewall.@redirect[-1].reflection', true);
		uci_set_string(output, 'firewall.@redirect[-1].reflection_src', 'external');
		return;
	}

	uci_set_boolean(output, 'firewall.@redirect[-1].reflection', false);
};

/**
 * Returns the rules of a chain in TR-181 evaluation order: ascending
 * Order, the instance number breaking ties. fw4 matches rules in UCI
 * order, so this is the order they are emitted in.
 *
 * @param {object} rules - Chain.Rule instances keyed by instance number
 * @returns {array} [ instance key, rule object ] pairs
 */
export function chain_rules_ordered(rules) {
	let list = [];
	for (let inst, rule in rules) {
		if (type(rule) != 'object' || !ubbf.is_instance_key(inst))
			continue;
		push(list, { key: inst, inst: ubbf.to_int(inst) ?? 0, order: ubbf.to_int(rule.Order) ?? 0, rule });
	}

	sort(list, (a, b) => (a.order - b.order) || (a.inst - b.inst));
	return map(list, (e) => [ e.key, e.rule ]);
};

// Rule parameters that reference a Device.Firewall.Set, and the direction
// and negation of each.
const SET_REFS = {
	SourceMatchSet: { dir: 'src', exclude: false },
	SourceMatchSetExclude: { dir: 'src', exclude: true },
	DestMatchSet: { dir: 'dest', exclude: false },
	DestMatchSetExclude: { dir: 'dest', exclude: true }
};

function list_items(value) {
	return filter(map(split(value ?? '', ','), (v) => trim(v)), (v) => v != '');
}

function flatten_lists(entries, param) {
	let items = [];
	for (let entry in entries)
		push(items, ...list_items(entry[param]));
	return items;
}

// fw4 takes no port ranges in a set, so a range becomes its ports
function ports_expand(items) {
	let ports = [];

	for (let item in items) {
		let m = match(item, /^([0-9]+)(-([0-9]+))?$/);
		if (!m || index(item, '\n') >= 0)
			return null;

		let lo = +m[1], hi = m[3] ? +m[3] : lo;
		if (lo < 1 || hi > 65535 || hi < lo)
			return null;

		for (let p = lo; p <= hi; p++)
			push(ports, sprintf('%d', p));
	}

	return uniq(ports);
}

/**
 * Resolves a Device.Firewall.Set to the fw4 ipsets that hold it: one per
 * IP family for IPAddresses, one for Ports or MACAddresses.
 *
 * @param {object} config - Configuration tree
 * @param {string} ref - Path of the Set
 * @returns {object|null} `{ type, invert, ipsets: [ { name, family, match,
 *          entries } ] }`, or null for a Set that cannot be rendered:
 *          missing, disabled, or with included and excluded entries, which
 *          would need two set matches in one fw4 rule
 */
export function firewall_set_resolve(config, ref) {
	let m = match(ref ?? '', /^Device\.Firewall\.Set\.([0-9]+)\.?$/);
	let set = m ? ubbf.get(config, `Device.Firewall.Set.${m[1]}`) : null;
	if (type(set) != 'object' || !ubbf.to_bool(set.Enable))
		return null;

	let entries = filter(values(set.Rule ?? {}), (r) => type(r) == 'object');
	let excludes = uniq(map(entries, (r) => ubbf.to_bool(r.Exclude)));
	if (length(excludes) > 1)
		return null;

	let base = `ubbf_set_${m[1]}`;
	let kind = set.Type ?? 'IPAddresses';
	let result = { type: kind, invert: excludes[0] ?? false, ipsets: [] };

	if (kind == 'Ports') {
		let ports = ports_expand(flatten_lists(entries, 'PortList'));
		if (ports == null)
			return null;
		push(result.ipsets, { name: base, family: 'any', match: 'src_port', entries: ports });
	}
	else if (kind == 'MACAddresses') {
		push(result.ipsets, { name: base, family: 'any', match: 'src_mac',
			entries: uniq(map(flatten_lists(entries, 'MACAddressList'), (v) => lc(v))) });
	}
	else {
		let ips = flatten_lists(entries, 'IPAddressList');
		let version = ubbf.to_int(set.IPVersion) ?? -1;

		for (let family in [ 4, 6 ]) {
			if (version != -1 && version != family)
				continue;
			push(result.ipsets, { name: `${base}_v${family}`, family: `ipv${family}`, match: 'src_net',
				entries: filter(ips, (ip) => (index(ip, ':') >= 0) == (family == 6)) });
		}
	}

	return result;
};

/**
 * Returns the Set reference of a rule.
 *
 * @param {object} rule - Rule object
 * @returns {array} [ parameter name, Set path ] pairs of the set references
 */
export function chain_rule_set_refs(rule) {
	let refs = [];
	for (let param in keys(SET_REFS))
		if ((rule?.[param] ?? '') != '')
			push(refs, [ param, rule[param] ]);
	return refs;
};

/**
 * Returns the fw4 ipset matches of a rule, one per IP family of its Set.
 *
 * @param {object} config - Configuration tree
 * @param {object} rule - Rule object
 * @returns {array|null} `[ { family, ipset } ]`, `[ { family: null,
 *          ipset: null } ]` for a rule without a set, or null when the
 *          Set cannot be rendered
 */
export function chain_rule_set_matches(config, rule) {
	let refs = chain_rule_set_refs(rule);
	if (!length(refs))
		return [ { family: null, ipset: null } ];

	let ref = SET_REFS[refs[0][0]];
	let set = firewall_set_resolve(config, refs[0][1]);
	if (!set)
		return null;

	let invert = (ref.exclude != set.invert) ? '!' : '';
	return map(set.ipsets, (s) => ({
		family: (s.family == 'any') ? null : s.family,
		ipset: `${invert}${s.name} ${ref.dir}`
	}));
};

/**
 * Tells why fw4 cannot express a Firewall.Chain.{i}.Rule.{i}. fw4 accepts
 * established and related traffic before the user rules, has no user
 * chains and takes one set match per rule, so ConnectionState, the Return
 * and TargetChain targets and a second Set reference are not supported.
 * A rule with such a value is not rendered, because a rule without the
 * match would be wider.
 *
 * With `config`, the Set a rule references is checked as well: a missing
 * or disabled Set, or one fw4 cannot hold, gives 'MatchSetState'.
 *
 * @param {object} rule - Rule object
 * @param {object} config - Configuration tree, optional
 * @returns {string|null} The parameter that cannot be rendered, or null
 */
export function chain_rule_unsupported(rule, config) {
	let target = lc(rule?.Target ?? '');

	if ((rule?.ConnectionState ?? '') != '')
		return 'ConnectionState';
	if (target == 'return' || target == 'targetchain')
		return 'Target';

	let set_refs = chain_rule_set_refs(rule);
	if (length(set_refs) > 1)
		return 'MatchSet';
	if (config && length(set_refs) && !chain_rule_set_matches(config, rule))
		return 'MatchSetState';

	// fw4 matches a port set only for TCP and UDP
	let proto = ubbf.to_int(rule?.Protocol) ?? -1;
	let port_set = config && length(set_refs) && firewall_set_resolve(config, set_refs[0][1])?.type == 'Ports';
	if (port_set && index([ -1, 6, 17 ], proto) < 0)
		return 'MatchSetState';

	// fw4 refuses a negated protocol together with a port match
	let ports = (ubbf.to_int(rule?.SourcePort) ?? -1) > 0 || (ubbf.to_int(rule?.DestPort) ?? -1) > 0;
	if (ubbf.to_bool(rule?.ProtocolExclude) && proto >= 0 && (ports || port_set))
		return 'ProtocolExclude';

	return null;
};
