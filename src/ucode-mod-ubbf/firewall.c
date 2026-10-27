/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <ctype.h>
#include <inttypes.h>

/**
 * Formats a UCI port-range string from start/end port numbers.
 *
 * Returns null when the start port is missing or non-positive. Returns
 * just the start port as a decimal string when the end port is missing,
 * non-positive, or not strictly greater than the start. Otherwise returns
 * `"<p>-<pe>"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: port, port_end)
 * @return       formatted port range string, or null when invalid
 */
uc_value_t *
uc_ubbf_port_range_format(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *p_val = uc_fn_arg(0);
	uc_value_t *pe_val = uc_fn_arg(1);
	long long p = 0, pe = 0;
	bool pe_ok = false;
	char buf[32];

	if (ucv_type(p_val) == UC_INTEGER) {
		p = ucv_int64_get(p_val);
	} else if (ucv_type(p_val) == UC_STRING) {
		const char *s = ucv_string_get(p_val);
		char *endp;
		if (!s || !*s) return NULL;
		p = strtoll(s, &endp, 10);
		if (*endp != '\0') return NULL;
	} else {
		return NULL;
	}

	if (p <= 0 || p > 65535)
		return NULL;

	if (ucv_type(pe_val) == UC_INTEGER) {
		pe = ucv_int64_get(pe_val);
		pe_ok = true;
	} else if (ucv_type(pe_val) == UC_STRING) {
		const char *s = ucv_string_get(pe_val);
		char *endp;
		if (s && *s) {
			pe = strtoll(s, &endp, 10);
			pe_ok = (*endp == '\0');
		}
	}

	if (!pe_ok || pe <= 0 || pe > 65535 || pe <= p)
		snprintf(buf, sizeof(buf), "%lld", p);
	else
		snprintf(buf, sizeof(buf), "%lld-%lld", p, pe);

	return ucv_string_new(buf);
}

/**
 * Converts a TR-181 protocol number or name to its UCI token.
 *
 * Integer/numeric strings map -1 to `all`, 6 to `tcp`, 17 to `udp`, 1 to
 * `icmp`, 58 to `icmpv6`, other positive values to their decimal form.
 * Strings `tcp`, `udp`, `icmp`, `icmpv6` (case-insensitive) pass through
 * lower-cased. Anything else yields null.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       UCI protocol token string, or null
 */
uc_value_t *
uc_ubbf_protocol_to_uci(uc_vm_t *vm, size_t nargs)
{
	static const char *const names[] = { "tcp", "udp", "icmp", "icmpv6" };
	uc_value_t *val = uc_fn_arg(0);
	char buf[16];
	int64_t n;

	if (value_to_int(val, &n)) {
		switch (n) {
		case -1: return ucv_string_new("all");
		case 6:  return ucv_string_new("tcp");
		case 17: return ucv_string_new("udp");
		case 1:  return ucv_string_new("icmp");
		case 58: return ucv_string_new("icmpv6");
		}

		if (n < 1 || n > 255)
			return NULL;

		snprintf(buf, sizeof(buf), "%" PRId64, n);
		return ucv_string_new(buf);
	}

	if (ucv_type(val) != UC_STRING)
		return NULL;

	for (size_t i = 0; i < ARRAY_SIZE(names); i++)
		if (!strcasecmp(ucv_string_get(val), names[i]))
			return ucv_string_new(names[i]);

	return NULL;
}

struct rule_order {
	const char *key;
	int64_t inst;
	int64_t order;
	uc_value_t *rule;
};

static int
rule_order_cmp(const void *a, const void *b)
{
	const struct rule_order *ra = a, *rb = b;

	if (ra->order != rb->order)
		return (ra->order < rb->order) ? -1 : 1;

	return (ra->inst > rb->inst) - (ra->inst < rb->inst);
}

static int64_t
int_or(uc_value_t *val, int64_t def)
{
	int64_t n;

	return value_to_int(val, &n) ? n : def;
}

/**
 * Returns the rules of a chain in TR-181 evaluation order: ascending
 * Order, the instance number breaking ties. fw4 matches rules in UCI
 * order, so this is the order they are emitted in.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: Chain.Rule instances by
 *               instance number)
 * @return       array of [ instance key, rule ] pairs
 */
uc_value_t *
uc_ubbf_chain_rules_ordered(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *rules = uc_fn_arg(0);
	uc_value_t *out = ucv_array_new(vm), *pair;
	size_t n = 0, len = ucv_object_length(rules);
	struct rule_order *list = xcalloc(len ? len : 1, sizeof(*list));
	char *endp;

	ucv_object_foreach(rules, key, rule) {
		if (ucv_type(rule) != UC_OBJECT || !key_is_instance(key))
			continue;

		errno = 0;
		list[n].inst = strtoll(key, &endp, 10);
		if (errno == ERANGE)
			list[n].inst = 0;

		list[n].key = key;
		list[n].order = int_or(ucv_object_get(rule, "Order", NULL), 0);
		list[n++].rule = rule;
	}

	qsort(list, n, sizeof(*list), rule_order_cmp);

	for (size_t i = 0; i < n; i++) {
		pair = ucv_array_new(vm);
		ucv_array_push(pair, ucv_string_new(list[i].key));
		ucv_array_push(pair, ucv_get(list[i].rule));
		ucv_array_push(out, pair);
	}

	free(list);

	return out;
}

/* Rule parameters that reference a Device.Firewall.Set, and the direction
 * and negation of each, in the order a rule names them. */
static const struct {
	const char *param;
	const char *dir;
	bool exclude;
} set_refs[] = {
	{ "SourceMatchSet", "src", false },
	{ "SourceMatchSetExclude", "src", true },
	{ "DestMatchSet", "dest", false },
	{ "DestMatchSetExclude", "dest", true },
};

/* A value that is null or equals '' under ucode ==. */
static bool
value_blank(uc_value_t *val)
{
	uc_value_t *empty = ucv_string_new("");
	bool blank = !val || loose_equal(val, empty);

	ucv_put(empty);

	return blank;
}

/**
 * Collects the Set references of a rule.
 *
 * @param rule  Rule object
 * @param idx   receives the index into set_refs[] of each reference
 * @param refs  receives the referenced paths (borrowed)
 * @return      the number of references
 */
static size_t
rule_set_refs(uc_value_t *rule, size_t idx[], uc_value_t *refs[])
{
	uc_value_t *val;
	size_t n = 0;

	for (size_t i = 0; i < ARRAY_SIZE(set_refs); i++) {
		val = ucv_object_get(rule, set_refs[i].param, NULL);
		if (value_blank(val))
			continue;

		idx[n] = i;
		refs[n++] = val;
	}

	return n;
}

/**
 * Parses one port or port range of a PortList entry, `N` or `N-M`.
 *
 * @return  false for text that is no range of ports 1 to 65535
 */
static bool
port_range_parse(const char *s, unsigned int *lo, unsigned int *hi)
{
	unsigned long a, b;
	char *endp;

	if (!isdigit((unsigned char)*s))
		return false;

	errno = 0;
	a = strtoul(s, &endp, 10);
	b = a;

	if (*endp == '-') {
		s = endp + 1;
		if (!isdigit((unsigned char)*s))
			return false;
		b = strtoul(s, &endp, 10);
	}

	if (*endp || errno == ERANGE || a < 1 || b > 65535 || b < a)
		return false;

	*lo = a;
	*hi = b;

	return true;
}

/**
 * Expands the port lists of the set entries into single ports, as fw4
 * takes no ranges in a set; each port once, in order.
 *
 * @return  new array of port strings, or NULL when an item is no port range
 */
static uc_value_t *
ports_expand(uc_vm_t *vm, uc_value_t *items)
{
	uc_value_t *ports = ucv_array_new(vm);
	uint8_t *seen = xcalloc(65536 / 8, 1);
	unsigned int lo, hi;
	char buf[8];

	for (size_t i = 0; i < ucv_array_length(items); i++) {
		uc_value_t *item = ucv_array_get(items, i);

		if (!port_range_parse(ucv_string_get(item), &lo, &hi)) {
			ucv_put(ports);
			ports = NULL;
			break;
		}

		for (unsigned int p = lo; p <= hi; p++) {
			if (seen[p / 8] & (1 << (p % 8)))
				continue;

			seen[p / 8] |= 1 << (p % 8);
			snprintf(buf, sizeof(buf), "%u", p);
			ucv_array_push(ports, ucv_string_new(buf));
		}
	}

	free(seen);

	return ports;
}

/**
 * Collects the list parameter of every set entry into one array of the
 * trimmed, non-empty items.
 */
static uc_value_t *
entries_list_new(uc_vm_t *vm, uc_value_t *entries, const char *param)
{
	uc_value_t *items = ucv_array_new(vm), *list, *val;

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		val = ucv_object_get(ucv_array_get(entries, i), param, NULL);
		if (ucv_type(val) != UC_STRING)
			continue;

		list = csv_list_new(vm, ucv_string_get(val), "");
		for (size_t j = 0; j < ucv_array_length(list); j++)
			ucv_array_push(items, ucv_get(ucv_array_get(list, j)));
		ucv_put(list);
	}

	return items;
}

static uc_value_t *
ipset_new(uc_vm_t *vm, const char *name, const char *family, const char *match,
	  uc_value_t *entries)
{
	uc_value_t *ipset = ucv_object_new(vm);

	ucv_object_add(ipset, "name", ucv_string_new(name));
	ucv_object_add(ipset, "family", ucv_string_new(family));
	ucv_object_add(ipset, "match", ucv_string_new(match));
	ucv_object_add(ipset, "entries", entries);

	return ipset;
}

static uc_value_t *
macs_new(uc_vm_t *vm, uc_value_t *items)
{
	uc_value_t *macs = ucv_array_new(vm), *seen = ucv_object_new(vm);
	char *mac;

	for (size_t i = 0; i < ucv_array_length(items); i++) {
		uc_value_t *item = ucv_array_get(items, i);

		mac = xstrdup(ucv_string_get(item));
		for (char *p = mac; *p; p++)
			*p = tolower((unsigned char)*p);

		if (!ucv_object_get(seen, mac, NULL)) {
			ucv_object_add(seen, mac, ucv_boolean_new(true));
			ucv_array_push(macs, ucv_string_new(mac));
		}

		free(mac);
	}

	ucv_put(seen);

	return macs;
}

static void
ip_ipsets_add(uc_vm_t *vm, uc_value_t *ipsets, uc_value_t *set, const char *base,
	      uc_value_t *ips)
{
	int64_t version = int_or(ucv_object_get(set, "IPVersion", NULL), -1);
	uc_value_t *entries;
	char name[64];

	for (int family = 4; family <= 6; family += 2) {
		if (version != -1 && version != family)
			continue;

		entries = ucv_array_new(vm);
		for (size_t i = 0; i < ucv_array_length(ips); i++) {
			uc_value_t *ip = ucv_array_get(ips, i);

			if ((strchr(ucv_string_get(ip), ':') != NULL) == (family == 6))
				ucv_array_push(entries, ucv_get(ip));
		}

		snprintf(name, sizeof(name), "%s_v%d", base, family);
		ucv_array_push(ipsets, ipset_new(vm, name, family == 6 ? "ipv6" : "ipv4",
						 "src_net", entries));
	}
}

/**
 * Reads the instance number of a Device.Firewall.Set reference, with or
 * without a trailing dot.
 *
 * @return  new string of the digits, or NULL
 */
static char *
set_ref_instance(uc_value_t *ref)
{
	static const char prefix[] = "Device.Firewall.Set.";
	const char *s, *digits;
	size_t len;

	if (ucv_type(ref) != UC_STRING)
		return NULL;

	s = ucv_string_get(ref);
	if (strncmp(s, prefix, sizeof(prefix) - 1))
		return NULL;

	digits = s + sizeof(prefix) - 1;
	len = strspn(digits, "0123456789");
	if (!len || (digits[len] && strcmp(digits + len, ".")))
		return NULL;

	return strndup(digits, len);
}

/**
 * Resolves a Device.Firewall.Set to the fw4 ipsets that hold it: one per
 * IP family for IPAddresses, one for Ports or MACAddresses.
 *
 * @return  new `{ type, invert, ipsets }`, or NULL for a Set that cannot be
 *          rendered: missing, disabled, or with included and excluded
 *          entries, which would need two set matches in one fw4 rule
 */
static uc_value_t *
set_resolve(uc_vm_t *vm, uc_value_t *config, uc_value_t *ref)
{
	uc_value_t *set, *entries, *rows, *kind, *result, *ipsets, *items, *ports;
	bool excludes[2] = { false, false };
	char *inst, *path, *base;

	inst = set_ref_instance(ref);
	if (!inst)
		return NULL;

	xasprintf(&path, "Device.Firewall.Set.%s", inst);
	xasprintf(&base, "ubbf_set_%s", inst);
	set = navigate_by_path(vm, config, path);
	free(path);
	free(inst);

	if (ucv_type(set) != UC_OBJECT || !value_to_bool(ucv_object_get(set, "Enable", NULL))) {
		free(base);
		return NULL;
	}

	entries = ucv_array_new(vm);
	rows = ucv_object_get(set, "Rule", NULL);
	ucv_object_foreach(rows, key, row) {
		(void)key;
		if (ucv_type(row) != UC_OBJECT)
			continue;

		excludes[value_to_bool(ucv_object_get(row, "Exclude", NULL))] = true;
		ucv_array_push(entries, ucv_get(row));
	}

	if (excludes[0] && excludes[1]) {
		ucv_put(entries);
		free(base);
		return NULL;
	}

	kind = ucv_object_get(set, "Type", NULL);
	result = ucv_object_new(vm);
	ipsets = ucv_array_new(vm);

	ucv_object_add(result, "type", kind ? ucv_get(kind) : ucv_string_new("IPAddresses"));
	ucv_object_add(result, "invert", ucv_boolean_new(excludes[1]));
	ucv_object_add(result, "ipsets", ipsets);

	if (value_is(kind, "Ports")) {
		items = entries_list_new(vm, entries, "PortList");
		ports = ports_expand(vm, items);
		ucv_put(items);

		if (ports) {
			ucv_array_push(ipsets, ipset_new(vm, base, "any", "src_port", ports));
		} else {
			ucv_put(result);
			result = NULL;
		}
	} else if (value_is(kind, "MACAddresses")) {
		items = entries_list_new(vm, entries, "MACAddressList");
		ucv_array_push(ipsets, ipset_new(vm, base, "any", "src_mac", macs_new(vm, items)));
		ucv_put(items);
	} else {
		items = entries_list_new(vm, entries, "IPAddressList");
		ip_ipsets_add(vm, ipsets, set, base, items);
		ucv_put(items);
	}

	free(base);
	ucv_put(entries);

	return result;
}

/**
 * Resolves a Device.Firewall.Set to the fw4 ipsets that hold it, see
 * set_resolve().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, Set path)
 * @return       `{ type, invert, ipsets: [ { name, family, match,
 *               entries } ] }`, or null for a Set that cannot be rendered
 */
uc_value_t *
uc_ubbf_firewall_set_resolve(uc_vm_t *vm, size_t nargs)
{
	return set_resolve(vm, uc_fn_arg(0), uc_fn_arg(1));
}

static uc_value_t *
set_match_new(uc_vm_t *vm, uc_value_t *family, uc_value_t *ipset)
{
	uc_value_t *match = ucv_object_new(vm);

	ucv_object_add(match, "family", family);
	ucv_object_add(match, "ipset", ipset);

	return match;
}

/**
 * Returns the fw4 ipset matches of a rule, one per IP family of its Set.
 *
 * @return  new array `[ { family, ipset } ]`, one entry with both null for
 *          a rule without a set, or NULL when the Set cannot be rendered
 */
static uc_value_t *
set_matches_new(uc_vm_t *vm, uc_value_t *config, uc_value_t *rule)
{
	size_t idx[ARRAY_SIZE(set_refs)];
	uc_value_t *refs[ARRAY_SIZE(set_refs)];
	uc_value_t *out = ucv_array_new(vm), *set, *ipsets, *ipset, *family, *name;
	bool invert;
	char *text;

	if (!rule_set_refs(rule, idx, refs)) {
		ucv_array_push(out, set_match_new(vm, NULL, NULL));
		return out;
	}

	set = set_resolve(vm, config, refs[0]);
	if (!set) {
		ucv_put(out);
		return NULL;
	}

	invert = set_refs[idx[0]].exclude != ucv_boolean_get(ucv_object_get(set, "invert", NULL));
	ipsets = ucv_object_get(set, "ipsets", NULL);

	for (size_t i = 0; i < ucv_array_length(ipsets); i++) {
		ipset = ucv_array_get(ipsets, i);
		family = ucv_object_get(ipset, "family", NULL);
		name = ucv_object_get(ipset, "name", NULL);

		xasprintf(&text, "%s%s %s", invert ? "!" : "",
			  ucv_string_get(name), set_refs[idx[0]].dir);
		ucv_array_push(out, set_match_new(vm,
			strcmp(ucv_string_get(family), "any") ? ucv_get(family) : NULL,
			ucv_string_new(text)));
		free(text);
	}

	ucv_put(set);

	return out;
}

/**
 * Returns the fw4 ipset matches of a rule, see set_matches_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, rule)
 * @return       `[ { family, ipset } ]`, `[ { family: null, ipset: null } ]`
 *               for a rule without a set, or null when the Set cannot be
 *               rendered
 */
uc_value_t *
uc_ubbf_chain_rule_set_matches(uc_vm_t *vm, size_t nargs)
{
	return set_matches_new(vm, uc_fn_arg(0), uc_fn_arg(1));
}

static bool
string_is(uc_value_t *val, const char *s)
{
	return ucv_type(val) == UC_STRING && !strcasecmp(ucv_string_get(val), s);
}

/**
 * Tells why fw4 cannot express a Firewall.Chain.{i}.Rule.{i}. fw4 accepts
 * established and related traffic before the user rules, has no user
 * chains and takes one set match per rule, so ConnectionState, the Return
 * and TargetChain targets and a second Set reference are not supported.
 * A rule with such a value is not rendered, because a rule without the
 * match would be wider. With a config, the referenced Set is checked as
 * well: a missing or disabled Set, or one fw4 cannot hold, or a port set
 * on a protocol other than TCP or UDP, gives MatchSetState.
 */
static const char *
rule_unsupported(uc_vm_t *vm, uc_value_t *rule, uc_value_t *config)
{
	size_t idx[ARRAY_SIZE(set_refs)];
	uc_value_t *refs[ARRAY_SIZE(set_refs)];
	uc_value_t *state = ucv_object_get(rule, "ConnectionState", NULL);
	uc_value_t *target = ucv_object_get(rule, "Target", NULL);
	uc_value_t *matches, *set;
	bool with_config = ucv_is_truish(config), port_set = false, ports;
	size_t nrefs = rule_set_refs(rule, idx, refs);
	int64_t proto;

	if (!value_blank(state))
		return "ConnectionState";

	if (string_is(target, "return") || string_is(target, "targetchain"))
		return "Target";

	if (nrefs > 1)
		return "MatchSet";

	if (with_config && nrefs) {
		matches = set_matches_new(vm, config, rule);
		ucv_put(matches);
		if (!matches)
			return "MatchSetState";

		set = set_resolve(vm, config, refs[0]);
		port_set = set && value_is(ucv_object_get(set, "type", NULL), "Ports");
		ucv_put(set);
	}

	/* fw4 matches a port set only for TCP and UDP */
	proto = int_or(ucv_object_get(rule, "Protocol", NULL), -1);
	if (port_set && proto != -1 && proto != 6 && proto != 17)
		return "MatchSetState";

	/* fw4 refuses a negated protocol together with a port match */
	ports = int_or(ucv_object_get(rule, "SourcePort", NULL), -1) > 0 ||
		int_or(ucv_object_get(rule, "DestPort", NULL), -1) > 0;
	if (value_to_bool(ucv_object_get(rule, "ProtocolExclude", NULL)) && proto >= 0 &&
	    (ports || port_set))
		return "ProtocolExclude";

	return NULL;
}

/**
 * Tells why fw4 cannot express a Firewall.Chain.{i}.Rule.{i}, see
 * rule_unsupported().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: rule, optional config
 *               tree)
 * @return       the parameter that cannot be rendered, or null
 */
uc_value_t *
uc_ubbf_chain_rule_unsupported(uc_vm_t *vm, size_t nargs)
{
	const char *reason = rule_unsupported(vm, uc_fn_arg(0), uc_fn_arg(1));

	return reason ? ucv_string_new(reason) : NULL;
}

/* TR-181 Device.Firewall.Chain.{i}.Rule.{i}.ExpiryDate: when a rule
 * expires, the device terminates it and deletes the Rule entry. fw4
 * stop_date ends the match; these find the entries to delete. */
#define EXPIRY_NEVER	"9999-12-31T23:59:59Z"
#define EXPIRY_UNKNOWN	"0001-01-01T00:00:00Z"

static bool
rule_expiry(uc_value_t *rule, int64_t *t)
{
	uc_value_t *val = ucv_object_get(rule, "ExpiryDate", NULL);
	const char *s;

	if (ucv_type(val) != UC_STRING)
		return false;

	s = ucv_string_get(val);
	if (!*s || !strcmp(s, EXPIRY_NEVER) || !strcmp(s, EXPIRY_UNKNOWN))
		return false;

	return datetime_parse(s, t) && *t > 0;
}

/**
 * Walks the rules with an expiry: the expired ones go into `expired`, the
 * others give `next`, the earliest expiry after `now`.
 */
static void
rules_expiry_scan(uc_vm_t *vm, uc_value_t *config, int64_t now, uc_value_t *expired,
		  int64_t *next)
{
	uc_value_t *chains = navigate_by_path(vm, config, "Device.Firewall.Chain");
	char *path;
	int64_t t;

	ucv_object_foreach(chains, chain_key, chain) {
		ucv_object_foreach(ucv_object_get(chain, "Rule", NULL), rule_key, rule) {
			if (!rule_expiry(rule, &t))
				continue;

			if (t > now) {
				if (*next < 0 || t < *next)
					*next = t;
				continue;
			}

			if (!expired)
				continue;

			xasprintf(&path, "Device.Firewall.Chain.%s.Rule.%s.", chain_key, rule_key);
			ucv_array_push(expired, ucv_string_new(path));
			free(path);
		}
	}
}

/**
 * Lists the rules whose ExpiryDate has passed.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, Unix time)
 * @return       object paths of the expired rules
 */
uc_value_t *
uc_ubbf_firewall_rules_expired(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *expired = ucv_array_new(vm);
	int64_t next = -1;

	rules_expiry_scan(vm, uc_fn_arg(0), ucv_to_integer(uc_fn_arg(1)), expired, &next);

	return expired;
}

/**
 * Returns the next time a rule expires.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, Unix time)
 * @return       Unix time, or null when no rule expires later
 */
uc_value_t *
uc_ubbf_firewall_expiry_next(uc_vm_t *vm, size_t nargs)
{
	int64_t next = -1;

	rules_expiry_scan(vm, uc_fn_arg(0), ucv_to_integer(uc_fn_arg(1)), NULL, &next);

	return (next < 0) ? NULL : ucv_int64_new(next);
}
