'use strict';

import * as ubbf from 'ubbf';

// Router.1 is the main table. Every other Router row is a table of its own
// (TR-181 2.20 Router.{i}.ID), numbered below the tables the kernel keeps
// (253 default, 254 main, 255 local).
export const MAIN_TABLE = 254;
const TABLE_BASE = 100;
const TABLE_MAX = 199;

// Linux has no IPv4 route with a source condition, so the IPv4Forwarding rows
// with SourceIPAddress (TR-181 2.20) go into a table of their own, one per
// router and source, and an ip rule sends the traffic from that source there.
// The table also holds the routes of the router that apply to that source
// too, so that a packet from the source still reaches every destination.
export const SOURCE_TABLE_BASE = 200;
export const SOURCE_TABLE_MAX = 252;

// Each enabled Policy row gets a block of rule priorities, in the order of
// Priority: the rules to the source tables of its router first, then its
// own rule last. The blocks start above the local table rule at 0 and end
// below the source rules of the main table, which come right before the
// main table lookup (32766).
const POLICY_BLOCK = 64;
const MAIN_SOURCE_PRIORITY = 32000;
const POLICY_MAX = MAIN_SOURCE_PRIORITY / POLICY_BLOCK - 1;

/**
 * Returns the routing table of a Router row.
 *
 * @param {number|string} instance - Router instance number
 * @returns {number|null} Table ID, or null when the number has no table
 */
export function router_table_id(instance) {
	let n = +instance;
	if (n == 1)
		return MAIN_TABLE;

	let id = TABLE_BASE + n - 1;
	return (n >= 2 && id <= TABLE_MAX) ? id : null;
};

/**
 * Tells whether a route or policy names a ForwardingPolicy. It is the class
 * that a QoS classification gives to traffic; ubbf classifies no traffic
 * this way, so such a row cannot match and is not written.
 *
 * @param {object} row - Forwarding or Policy row
 * @returns {boolean} True when ForwardingPolicy is set
 */
export function forwarding_policy_set(row) {
	return (ubbf.to_int(row?.ForwardingPolicy) ?? -1) >= 0;
};

/**
 * Converts an IPv4 address to an integer.
 *
 * @param {string} addr - Dotted IPv4 address
 * @returns {number|null} The address, or null when it is not IPv4
 */
function ipv4_int(addr) {
	let b = iptoarr(addr ?? '');
	if (type(b) != 'array' || length(b) != 4)
		return null;

	return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

/**
 * Returns the netmask of a prefix length.
 *
 * @param {number} len - Prefix length, 0 to 32
 * @returns {number} Netmask as an integer
 */
function ipv4_mask(len) {
	return len ? ((0xffffffff << (32 - len)) & 0xffffffff) : 0;
}

/**
 * Parses an IPv4 prefix in CIDR notation.
 *
 * @param {string} prefix - Prefix like 192.168.1.0/24
 * @returns {object|null} { net, len }, or null when it is not IPv4
 */
function ipv4_prefix_parse(prefix) {
	let m = match(prefix ?? '', /^([0-9.]+)\/([0-9]+)$/);
	let net = m ? ipv4_int(m[1]) : null;
	if (net == null || +m[2] > 32)
		return null;

	return { net: net & ipv4_mask(+m[2]), len: +m[2] };
}

/**
 * Returns the prefix of an address and a netmask.
 *
 * @param {string} addr - Dotted IPv4 address
 * @param {string} mask - Dotted netmask, '' for a host prefix
 * @returns {string|null} The prefix in CIDR notation, or null when the
 *                        address or the mask is not valid
 */
function ipv4_prefix_from(addr, mask) {
	let net = ipv4_int(addr);
	let bits = (mask == '') ? 0xffffffff : ipv4_int(mask);
	if (net == null || bits == null)
		return null;

	let len = 0;
	while (len < 32 && (bits & (1 << (31 - len))))
		len++;
	if (bits != ipv4_mask(len))
		return null;

	net &= ipv4_mask(len);
	return sprintf('%s/%d', arrtoip([ (net >> 24) & 255, (net >> 16) & 255, (net >> 8) & 255, net & 255 ]), len);
}

/**
 * Returns the source prefix of an IPv4Forwarding row (TR-181 2.20): the
 * SourceIPAddress ANDed with the SourceSubnetMask, or a host prefix when
 * the mask is empty.
 *
 * @param {object} route - IPv4Forwarding row
 * @returns {string|null} '' without a source, the prefix, or null when the
 *                        address or the mask is not valid
 */
export function source_prefix(route) {
	let addr = route?.SourceIPAddress ?? '';
	let mask = route?.SourceSubnetMask ?? '';
	if (addr == '')
		return (mask == '') ? '' : null;

	return ipv4_prefix_from(addr, mask);
};

/**
 * Returns the destination prefix of an IPv4Forwarding row; an empty
 * DestIPAddress is the default route.
 *
 * @param {object} route - IPv4Forwarding row
 * @returns {string|null} The prefix in CIDR notation, or null when not valid
 */
export function route_dest(route) {
	let addr = route?.DestIPAddress ?? '';
	if (addr == '')
		return '0.0.0.0/0';

	return ipv4_prefix_from(addr, route?.DestSubnetMask ?? '');
};

/**
 * Returns the narrower of two IPv4 prefixes when one holds the other.
 *
 * @param {string} a - Prefix, '' for any source
 * @param {string} b - Prefix, '' for any source
 * @returns {string|null} The prefix both match, or null when they share
 *                        no address
 */
export function prefix_intersect(a, b) {
	if (!a)
		return b;
	if (!b)
		return a;

	let pa = ipv4_prefix_parse(a), pb = ipv4_prefix_parse(b);
	if (!pa || !pb)
		return null;

	let wide = (pa.len <= pb.len) ? pa : pb;
	let narrow = (wide == pa) ? pb : pa;

	return ((narrow.net & ipv4_mask(wide.len)) == wide.net) ? ((narrow == pa) ? a : b) : null;
};

/**
 * Returns the length of a source prefix.
 *
 * @param {string} prefix - Prefix, '' for any source
 * @returns {number} Prefix length, -1 for any source
 */
function source_len(prefix) {
	return prefix ? ipv4_prefix_parse(prefix).len : -1;
}

/**
 * Lists the instance keys of a table of the configuration in order.
 *
 * @param {object|null} table - Table object keyed by instance
 * @returns {array} Instance keys, ascending
 */
function instance_keys(table) {
	return sort(filter(keys(table ?? {}), (k) => match(k, /^[0-9]+$/)), (a, b) => +a - +b);
}

/**
 * Lists the IPv4Forwarding rows of a router that the render writes, with
 * their source and destination prefixes.
 *
 * @param {object} root - Configuration root with Device
 * @param {string} router - Router instance
 * @returns {array} { route, src, dest }
 */
function router_routes(root, router) {
	let rows = root?.Device?.Routing?.Router?.[router]?.IPv4Forwarding;
	let found = [];

	for (let i in instance_keys(rows)) {
		let route = rows[i];
		let src = source_prefix(route);
		let dest = route_dest(route);
		if (src == null || dest == null || !ubbf.to_bool(route.Enable) || forwarding_policy_set(route))
			continue;

		push(found, { route, src, dest });
	}

	return found;
}

/**
 * Gives each pair of router and source prefix of an enabled IPv4Forwarding
 * row its source table. The handler and the render both call it on the same
 * configuration, so they agree on which rows got a table.
 *
 * @param {object} root - Configuration root with Device
 * @returns {object} '<router>|<prefix>' to table ID
 */
export function source_tables(root) {
	let routers = root?.Device?.Routing?.Router;
	let tables = {};
	let next = SOURCE_TABLE_BASE;

	for (let n in instance_keys(routers)) {
		for (let entry in (router_table_id(n) != null) ? router_routes(root, n) : []) {
			let key = `${n}|${entry.src}`;
			if (entry.src && !(key in tables) && next <= SOURCE_TABLE_MAX)
				tables[key] = next++;
		}
	}

	return tables;
};

/**
 * Lists what each source table holds from the configuration: the routes of
 * its router whose source holds the source of the table, and for a router
 * other than Router.1 also the routes without a source. Of the routes to
 * one destination, only those of the most specific source stay, as a
 * source route wins over a route to the same destination for a wider
 * source. ubbf-device copies the routes of the main table, which netifd and
 * the DHCP clients maintain, into the source tables of Router.1.
 *
 * @param {object} root - Configuration root with Device
 * @returns {array} { router, src, table, routes: [IPv4Forwarding row],
 *                  dests: [prefix] }, in the order of the tables
 */
export function source_table_contents(root) {
	let tables = source_tables(root);
	let contents = [];

	for (let key in sort(keys(tables), (a, b) => tables[a] - tables[b])) {
		let parts = split(key, '|');
		let router = parts[0], src = parts[1];
		let best = {};

		for (let entry in router_routes(root, router)) {
			if (entry.src == '' && router == '1')
				continue;
			if (prefix_intersect(entry.src, src) != src)
				continue;

			let len = source_len(entry.src);
			let cur = best[entry.dest];
			if (!cur || len > cur.len)
				best[entry.dest] = { len, routes: [ entry.route ] };
			else if (len == cur.len)
				push(cur.routes, entry.route);
		}

		let routes = [];
		for (let dest, b in best)
			push(routes, ...b.routes);

		push(contents, { router, src, table: tables[key], routes, dests: keys(best) });
	}

	return contents;
};

/**
 * Returns the rules from the sources of a router to their tables, the most
 * specific source first.
 *
 * @param {object} tables - Result of source_tables()
 * @param {string} router - Router instance
 * @returns {array} { src, table }
 */
export function source_rules(tables, router) {
	let found = [];

	for (let key, table in tables) {
		let parts = split(key, '|');
		if (parts[0] == router)
			push(found, { src: parts[1], table });
	}

	return sort(found, (a, b) => (source_len(b.src) - source_len(a.src)) || (a.table - b.table));
};

/**
 * Returns the rules that send the sources of the main table to their
 * tables, with their kernel priorities.
 *
 * @param {object} tables - Result of source_tables()
 * @returns {array} { src, table, priority }
 */
export function main_source_rules(tables) {
	let rules = source_rules(tables, '1');

	for (let i = 0; i < length(rules); i++)
		rules[i].priority = MAIN_SOURCE_PRIORITY + i;

	return rules;
};

/**
 * Returns the place of a Policy row among the enabled rows, in the order of
 * Priority and then of the instance number.
 *
 * @param {object} root - Configuration root with Device
 * @param {string} instance - Policy instance
 * @returns {number} Rank from 0
 */
function policy_rank(root, instance) {
	let policies = root?.Device?.Routing?.Policy;
	let enabled = filter(instance_keys(policies), (k) => ubbf.to_bool(policies[k]?.Enable));
	let order = sort(enabled, (a, b) =>
		((ubbf.to_int(policies[a]?.Priority) ?? 0) - (ubbf.to_int(policies[b]?.Priority) ?? 0)) || (+a - +b));

	return index(order, `${instance}`);
}

/**
 * Returns the IP version of a prefix in CIDR notation.
 *
 * @param {string} prefix - Prefix, may be empty
 * @returns {number|null} 4 or 6, 0 for an empty prefix, null when not valid
 */
function prefix_family(prefix) {
	if (prefix == null || prefix == '')
		return 0;

	let m = match(prefix, /^([^\/]+)\/([0-9]+)$/);
	let bytes = m ? iptoarr(m[1]) : null;
	if (type(bytes) != 'array' || +m[2] > length(bytes) * 8)
		return null;

	return (length(bytes) == 4) ? 4 : 6;
}

/**
 * Returns the netifd port match of a start and an end port.
 *
 * @param {string} start - Port, -1 for none
 * @param {string} end - Last port of the range, -1 for none
 * @returns {string|null} '' for no match, 'N' or 'N-M', null when not valid
 */
function port_match(start, end) {
	let from = ubbf.to_int(start) ?? -1;
	let to = ubbf.to_int(end) ?? -1;

	if (from < 0)
		return (to < 0) ? '' : null;
	if (to < 0)
		return sprintf('%d', from);

	return (to >= from) ? sprintf('%d-%d', from, to) : null;
}

/**
 * Resolves a Device.Routing.Policy.{i} row (TR-181 2.20) to what netifd
 * needs for its rule sections, or says why the row is misconfigured.
 *
 * @param {object} root - Configuration root with Device
 * @param {string} instance - Policy instance
 * @returns {object} { error } or { router, table, families, in, out, src,
 *                   dest, proto, sport, dport, source_priority, priority },
 *                   the last two as kernel rule priorities: the first rule
 *                   to a source table and the rule of the row
 */
export function policy_resolve(root, instance) {
	let policy = root?.Device?.Routing?.Policy?.[instance];
	if (forwarding_policy_set(policy))
		return { error: 'ForwardingPolicy needs a QoS class, which ubbf does not set' };

	let router = '1';
	let ref = policy?.RouterRef ?? '';
	if (ref != '') {
		let m = match(ref, /^Device\.Routing\.Router\.([0-9]+)\.?$/);
		router = (m && root?.Device?.Routing?.Router?.[m[1]] && router_table_id(m[1]) != null) ? m[1] : null;
		if (router == null)
			return { error: 'RouterRef names no Router row with a table' };
	}

	let in_name = policy.SourceInterface ? ubbf.interface_to_name(root, policy.SourceInterface) : '';
	let out_name = policy.DestInterface ? ubbf.interface_to_name(root, policy.DestInterface) : '';
	if (in_name == null || out_name == null)
		return { error: 'SourceInterface or DestInterface names no IP.Interface' };

	let src = prefix_family(policy.SourceIPPrefix);
	let dest = prefix_family(policy.DestIPPrefix);
	let version = ubbf.to_int(policy.IPVersion) ?? -1;
	let families = filter(uniq([ version, src, dest ]), (f) => f > 0);
	if (src == null || dest == null || length(families) > 1)
		return { error: 'the prefixes and IPVersion do not agree' };

	let sport = port_match(policy.SourcePort, policy.SourcePortRangeMax);
	let dport = port_match(policy.DestPort, policy.DestPortRangeMax);
	if (sport == null || dport == null)
		return { error: 'a port range ends below its start' };

	let rank = policy_rank(root, instance);
	if (rank < 0)
		return { error: 'the row is not enabled' };
	if (rank >= POLICY_MAX)
		return { error: sprintf('more than %d Policy rows are enabled', POLICY_MAX) };

	return {
		router,
		table: router_table_id(router),
		families: length(families) ? families : [ 4, 6 ],
		in: in_name,
		out: out_name,
		src: policy.SourceIPPrefix ?? '',
		dest: policy.DestIPPrefix ?? '',
		proto: ubbf.to_int(policy.Protocol) ?? -1,
		sport,
		dport,
		source_priority: POLICY_BLOCK * rank + 1,
		priority: POLICY_BLOCK * (rank + 1)
	};
};
