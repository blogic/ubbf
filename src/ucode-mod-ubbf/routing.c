/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Routing tables and rules of Device.Routing: the table of each Router
 * row, the source tables of the IPv4Forwarding rows with a source
 * (TR-181 2.20), and the netifd rules of the Policy rows.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>
#include <arpa/inet.h>

/* Router.1 is the main table. Every other Router row is a table of its own
 * (TR-181 2.20 Router.{i}.ID), numbered below the tables the kernel keeps
 * (253 default, 254 main, 255 local). */
#define MAIN_TABLE	254
#define TABLE_BASE	100
#define TABLE_MAX	199

/* Linux has no IPv4 route with a source condition, so the IPv4Forwarding
 * rows with SourceIPAddress go into a table of their own, one per router and
 * source, and an ip rule sends the traffic from that source there. The
 * table also holds the routes of the router that apply to that source too,
 * so that a packet from the source still reaches every destination. */
#define SOURCE_TABLE_BASE	200
#define SOURCE_TABLE_MAX	252

/* Each enabled Policy row gets a block of rule priorities, in the order of
 * Priority: the rules to the source tables of its router first, then its
 * own rule last. The blocks start above the local table rule at 0 and end
 * below the source rules of the main table, which come right before the
 * main table lookup (32766). */
#define POLICY_BLOCK		64
#define MAIN_SOURCE_PRIORITY	32000
#define POLICY_MAX		(MAIN_SOURCE_PRIORITY / POLICY_BLOCK - 1)

const struct constval routing_vals[] = {
	{ "MAIN_TABLE", MAIN_TABLE },
	{ "SOURCE_TABLE_BASE", SOURCE_TABLE_BASE },
	{ "SOURCE_TABLE_MAX", SOURCE_TABLE_MAX },
};

const size_t routing_vals_count = ARRAY_SIZE(routing_vals);

static int64_t
int_or(uc_value_t *val, int64_t def)
{
	int64_t n;

	return value_to_int(val, &n) ? n : def;
}

static bool
value_blank(uc_value_t *val)
{
	uc_value_t *empty = ucv_string_new("");
	bool blank = loose_equal(val ? val : empty, empty);

	ucv_put(empty);

	return blank;
}

static int64_t
router_table(int64_t n)
{
	if (n == 1)
		return MAIN_TABLE;

	return (n >= 2 && TABLE_BASE + n - 1 <= TABLE_MAX) ? TABLE_BASE + n - 1 : -1;
}

static bool
forwarding_policy_set(uc_value_t *row)
{
	return int_or(ucv_object_get(row, "ForwardingPolicy", NULL), -1) >= 0;
}

static uint32_t
ipv4_mask(int len)
{
	return len ? (uint32_t)(0xffffffffu << (32 - len)) : 0;
}

static bool
ipv4_value(uc_value_t *val, uint32_t *out)
{
	return ucv_type(val) == UC_STRING && ipv4_parse(ucv_string_get(val), out);
}

/* Reads `a.b.c.d/len`. */
static bool
ipv4_prefix_parse(const char *s, uint32_t *net, int *len)
{
	const char *slash = s ? strchr(s, '/') : NULL;
	char addr[INET_ADDRSTRLEN];
	unsigned long n;
	char *endp;

	if (!slash || slash == s || (size_t)(slash - s) >= sizeof(addr) ||
	    strspn(s, "0123456789.") != (size_t)(slash - s) ||
	    !slash[1] || strspn(slash + 1, "0123456789") != strlen(slash + 1))
		return false;

	memcpy(addr, s, slash - s);
	addr[slash - s] = '\0';

	errno = 0;
	n = strtoul(slash + 1, &endp, 10);
	if (errno == ERANGE || n > 32 || !ipv4_parse(addr, net))
		return false;

	*len = n;
	*net &= ipv4_mask(n);

	return true;
}

/**
 * Returns the prefix of an address and a netmask, '' for a host prefix.
 *
 * @return  new string in CIDR notation, or NULL when the address or the
 *          mask is not valid
 */
static char *
ipv4_prefix_from(uc_value_t *addr, uc_value_t *mask)
{
	char text[INET_ADDRSTRLEN], *out;
	uint32_t net, bits;
	struct in_addr a;
	int len = 0;

	if (!ipv4_value(addr, &net))
		return NULL;

	if (value_blank(mask))
		bits = 0xffffffffu;
	else if (!ipv4_value(mask, &bits))
		return NULL;

	while (len < 32 && (bits & (1u << (31 - len))))
		len++;
	if (bits != ipv4_mask(len))
		return NULL;

	a.s_addr = htonl(net & ipv4_mask(len));
	inet_ntop(AF_INET, &a, text, sizeof(text));
	xasprintf(&out, "%s/%d", text, len);

	return out;
}

/* The source prefix of an IPv4Forwarding row: "" without a source, or
 * NULL when the address or the mask is not valid. */
static char *
route_source(uc_value_t *route)
{
	uc_value_t *addr = ucv_object_get(route, "SourceIPAddress", NULL);
	uc_value_t *mask = ucv_object_get(route, "SourceSubnetMask", NULL);

	if (value_blank(addr))
		return value_blank(mask) ? xstrdup("") : NULL;

	return ipv4_prefix_from(addr, mask);
}

/* The destination prefix of an IPv4Forwarding row; an empty DestIPAddress
 * is the default route. */
static char *
route_dest(uc_value_t *route)
{
	uc_value_t *addr = ucv_object_get(route, "DestIPAddress", NULL);

	if (value_blank(addr))
		return xstrdup("0.0.0.0/0");

	return ipv4_prefix_from(addr, ucv_object_get(route, "DestSubnetMask", NULL));
}

/**
 * Returns the narrower of two prefixes when one holds the other.
 *
 * @return  a or b, or NULL when they share no address; an empty prefix
 *          holds every address
 */
static const char *
prefix_intersect(const char *a, const char *b)
{
	uint32_t na, nb;
	int la, lb;

	if (!*a)
		return b;
	if (!*b)
		return a;

	if (!ipv4_prefix_parse(a, &na, &la) || !ipv4_prefix_parse(b, &nb, &lb))
		return NULL;

	if (la <= lb)
		return ((nb & ipv4_mask(la)) == na) ? b : NULL;

	return ((na & ipv4_mask(lb)) == nb) ? a : NULL;
}

static int
source_len(const char *prefix)
{
	uint32_t net;
	int len;

	return (*prefix && ipv4_prefix_parse(prefix, &net, &len)) ? len : -1;
}

struct route_entry {
	uc_value_t *route;
	char *src;
	char *dest;
};

struct routes {
	size_t count;
	struct route_entry *list;
};

static void
routes_free(struct routes *r)
{
	for (size_t i = 0; i < r->count; i++) {
		free(r->list[i].src);
		free(r->list[i].dest);
	}
	free(r->list);
}

static uc_value_t *
routing_node(uc_vm_t *vm, uc_value_t *root, const char *name)
{
	char *path;
	uc_value_t *node;

	xasprintf(&path, "Device.Routing.%s", name);
	node = navigate_by_path(vm, root, path);
	free(path);

	return node;
}

/* The IPv4Forwarding rows of a router that the render writes, with their
 * source and destination prefixes. */
static void
router_routes(uc_vm_t *vm, uc_value_t *root, const char *router, struct routes *out)
{
	uc_value_t *routers = routing_node(vm, root, "Router");
	uc_value_t *rows = ucv_object_get(ucv_object_get(routers, router, NULL), "IPv4Forwarding", NULL);
	uc_value_t *route;
	struct numkeys keys;
	char *src, *dest;

	out->count = 0;
	out->list = NULL;
	numkeys_sorted(rows, &keys);

	for (size_t i = 0; i < keys.count; i++) {
		route = ucv_object_get(rows, keys.list[i].name, NULL);
		src = route_source(route);
		dest = route_dest(route);

		if (!src || !dest || !value_to_bool(ucv_object_get(route, "Enable", NULL)) ||
		    forwarding_policy_set(route)) {
			free(src);
			free(dest);
			continue;
		}

		out->list = xrealloc(out->list, (out->count + 1) * sizeof(*out->list));
		out->list[out->count++] = (struct route_entry){ route, src, dest };
	}

	free(keys.list);
}

/**
 * Gives each pair of router and source prefix of an enabled IPv4Forwarding
 * row its source table. The handler and the render both call it on the
 * same configuration, so they agree on which rows got a table.
 *
 * @return  new object '<router>|<prefix>' to table ID
 */
static uc_value_t *
source_tables_new(uc_vm_t *vm, uc_value_t *root)
{
	uc_value_t *tables = ucv_object_new(vm);
	uc_value_t *routers = routing_node(vm, root, "Router");
	int64_t next = SOURCE_TABLE_BASE;
	struct routes routes;
	struct numkeys keys;
	char *key;

	numkeys_sorted(routers, &keys);

	for (size_t i = 0; i < keys.count; i++) {
		if (router_table(keys.list[i].n) < 0)
			continue;

		router_routes(vm, root, keys.list[i].name, &routes);

		for (size_t j = 0; j < routes.count; j++) {
			if (!*routes.list[j].src)
				continue;

			xasprintf(&key, "%s|%s", keys.list[i].name, routes.list[j].src);
			if (!ucv_object_get(tables, key, NULL) && next <= SOURCE_TABLE_MAX)
				ucv_object_add(tables, key, ucv_int64_new(next++));
			free(key);
		}

		routes_free(&routes);
	}

	free(keys.list);

	return tables;
}

/**
 * ucode: `router_table_id(instance)`, the routing table of a Router row.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: Router instance number)
 * @return       table ID, or null when the number has no table
 */
uc_value_t *
uc_ubbf_router_table_id(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *num = ucv_to_number(uc_fn_arg(0));
	int64_t id = -1;
	double d;

	if (ucv_type(num) == UC_INTEGER) {
		id = router_table(ucv_int64_get(num));
		ucv_put(num);
		return (id < 0) ? NULL : ucv_int64_new(id);
	}

	/* the number of a key with a fraction, as `+instance` gives it */
	d = ucv_double_get(num);
	ucv_put(num);

	if (d == 1)
		return ucv_int64_new(MAIN_TABLE);

	return (d >= 2 && TABLE_BASE + d - 1 <= TABLE_MAX) ? ucv_double_new(TABLE_BASE + d - 1) : NULL;
}

/**
 * ucode: `forwarding_policy_set(row)`, whether a route or policy names a
 * ForwardingPolicy. It is the class that a QoS classification gives to
 * traffic; ubbf classifies no traffic this way, so such a row cannot match
 * and is not written.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: Forwarding or Policy row)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_forwarding_policy_set(uc_vm_t *vm, size_t nargs)
{
	return ucv_boolean_new(forwarding_policy_set(uc_fn_arg(0)));
}

static uc_value_t *
string_take(char *s)
{
	uc_value_t *val = s ? ucv_string_new(s) : NULL;

	free(s);

	return val;
}

/**
 * ucode: `source_prefix(route)`, the source prefix of an IPv4Forwarding
 * row: SourceIPAddress ANDed with SourceSubnetMask, or a host prefix when
 * the mask is empty.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: IPv4Forwarding row)
 * @return       '' without a source, the prefix, or null when the address
 *               or the mask is not valid
 */
uc_value_t *
uc_ubbf_source_prefix(uc_vm_t *vm, size_t nargs)
{
	return string_take(route_source(uc_fn_arg(0)));
}

/**
 * ucode: `route_dest(route)`, the destination prefix of an
 * IPv4Forwarding row.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: IPv4Forwarding row)
 * @return       the prefix in CIDR notation, or null when not valid
 */
uc_value_t *
uc_ubbf_route_dest(uc_vm_t *vm, size_t nargs)
{
	return string_take(route_dest(uc_fn_arg(0)));
}

/**
 * ucode: `prefix_intersect(a, b)`, the narrower of two IPv4 prefixes when
 * one holds the other.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: prefixes, '' for any
 *               source)
 * @return       the prefix both match, or null when they share no address
 */
uc_value_t *
uc_ubbf_prefix_intersect(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *a = uc_fn_arg(0), *b = uc_fn_arg(1);
	const char *r;

	if (!ucv_is_truish(a))
		return ucv_get(b);
	if (!ucv_is_truish(b))
		return ucv_get(a);
	if (ucv_type(a) != UC_STRING || ucv_type(b) != UC_STRING)
		return NULL;

	r = prefix_intersect(ucv_string_get(a), ucv_string_get(b));

	return r ? ucv_string_new(r) : NULL;
}

/**
 * ucode: `source_tables(root)`, see source_tables_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: configuration root)
 * @return       '<router>|<prefix>' to table ID
 */
uc_value_t *
uc_ubbf_source_tables(uc_vm_t *vm, size_t nargs)
{
	return source_tables_new(vm, uc_fn_arg(0));
}

struct table_ref {
	const char *key;
	int64_t table;
};

static int
table_ref_cmp(const void *a, const void *b)
{
	const struct table_ref *ta = a, *tb = b;

	return (ta->table > tb->table) - (ta->table < tb->table);
}

/**
 * Builds the contents of one source table: the routes of its router whose
 * source holds the source of the table, and for a router other than
 * Router.1 also the routes without a source. Of the routes to one
 * destination only those of the most specific source stay, as a source
 * route wins over a route to the same destination for a wider source.
 */
static uc_value_t *
table_contents_new(uc_vm_t *vm, uc_value_t *root, const char *key, int64_t table)
{
	const char *bar = strchr(key, '|');
	uc_value_t *out = ucv_object_new(vm), *best = ucv_object_new(vm), *cur, *list;
	uc_value_t *routes = ucv_array_new(vm), *dests = ucv_array_new(vm);
	char *router = strndup(key, bar - key);
	const char *src = bar + 1, *inter;
	struct routes rr;
	int len;

	router_routes(vm, root, router, &rr);

	for (size_t i = 0; i < rr.count; i++) {
		if (!*rr.list[i].src && !strcmp(router, "1"))
			continue;

		inter = prefix_intersect(rr.list[i].src, src);
		if (!inter || strcmp(inter, src))
			continue;

		len = source_len(rr.list[i].src);
		cur = ucv_object_get(best, rr.list[i].dest, NULL);

		if (!cur || len > ucv_int64_get(ucv_object_get(cur, "len", NULL))) {
			cur = ucv_object_new(vm);
			list = ucv_array_new(vm);
			ucv_array_push(list, ucv_get(rr.list[i].route));
			ucv_object_add(cur, "len", ucv_int64_new(len));
			ucv_object_add(cur, "routes", list);
			ucv_object_add(best, rr.list[i].dest, cur);
		} else if (len == ucv_int64_get(ucv_object_get(cur, "len", NULL))) {
			ucv_array_push(ucv_object_get(cur, "routes", NULL), ucv_get(rr.list[i].route));
		}
	}

	ucv_object_foreach(best, dest, b) {
		list = ucv_object_get(b, "routes", NULL);
		for (size_t i = 0; i < ucv_array_length(list); i++)
			ucv_array_push(routes, ucv_get(ucv_array_get(list, i)));
		ucv_array_push(dests, ucv_string_new(dest));
	}

	ucv_object_add(out, "router", ucv_string_new(router));
	ucv_object_add(out, "src", ucv_string_new(src));
	ucv_object_add(out, "table", ucv_int64_new(table));
	ucv_object_add(out, "routes", routes);
	ucv_object_add(out, "dests", dests);

	routes_free(&rr);
	ucv_put(best);
	free(router);

	return out;
}

/**
 * ucode: `source_table_contents(root)`, what each source table holds from
 * the configuration, see table_contents_new(). ubbf-device copies the
 * routes of the main table, which netifd and the DHCP clients maintain,
 * into the source tables of Router.1.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: configuration root)
 * @return       `{ router, src, table, routes, dests }` in the order of the
 *               tables
 */
uc_value_t *
uc_ubbf_source_table_contents(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *tables = source_tables_new(vm, uc_fn_arg(0));
	uc_value_t *out = ucv_array_new(vm);
	struct table_ref *refs = xcalloc(ucv_object_length(tables) + 1, sizeof(*refs));
	size_t n = 0;

	ucv_object_foreach(tables, key, val) {
		refs[n].key = key;
		refs[n++].table = ucv_int64_get(val);
	}

	qsort(refs, n, sizeof(*refs), table_ref_cmp);

	for (size_t i = 0; i < n; i++)
		ucv_array_push(out, table_contents_new(vm, uc_fn_arg(0), refs[i].key, refs[i].table));

	free(refs);
	ucv_put(tables);

	return out;
}

struct source_rule {
	char *src;
	int64_t table;
	int len;
};

static int
source_rule_cmp(const void *a, const void *b)
{
	const struct source_rule *ra = a, *rb = b;

	if (ra->len != rb->len)
		return rb->len - ra->len;

	return (ra->table > rb->table) - (ra->table < rb->table);
}

/* The rules from the sources of a router to their tables, the most
 * specific source first, with a priority from `priority` on when it is not
 * negative. */
static uc_value_t *
source_rules_new(uc_vm_t *vm, uc_value_t *tables, uc_value_t *router, int64_t priority)
{
	struct source_rule *rules = xcalloc(ucv_object_length(tables) + 1, sizeof(*rules));
	uc_value_t *out = ucv_array_new(vm), *rule, *name;
	const char *bar;
	size_t n = 0;

	ucv_object_foreach(tables, key, val) {
		bar = strchr(key, '|');
		if (!bar)
			bar = key + strlen(key);

		name = ucv_string_new_length(key, bar - key);
		if (loose_equal(name, router)) {
			rules[n].src = xstrdup(*bar ? bar + 1 : "");
			rules[n].table = ucv_to_integer(val);
			rules[n].len = source_len(rules[n].src);
			n++;
		}
		ucv_put(name);
	}

	qsort(rules, n, sizeof(*rules), source_rule_cmp);

	for (size_t i = 0; i < n; i++) {
		rule = ucv_object_new(vm);
		ucv_object_add(rule, "src", ucv_string_new(rules[i].src));
		ucv_object_add(rule, "table", ucv_int64_new(rules[i].table));
		if (priority >= 0)
			ucv_object_add(rule, "priority", ucv_int64_new(priority + i));
		ucv_array_push(out, rule);
		free(rules[i].src);
	}

	free(rules);

	return out;
}

/**
 * ucode: `source_rules(tables, router)`, the rules from the sources of a
 * router to their tables, the most specific source first.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: source_tables() result,
 *               Router instance)
 * @return       `{ src, table }`
 */
uc_value_t *
uc_ubbf_source_rules(uc_vm_t *vm, size_t nargs)
{
	return source_rules_new(vm, uc_fn_arg(0), uc_fn_arg(1), -1);
}

/**
 * ucode: `main_source_rules(tables)`, the rules that send the sources of
 * the main table to their tables, with their kernel priorities.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: source_tables() result)
 * @return       `{ src, table, priority }`
 */
uc_value_t *
uc_ubbf_main_source_rules(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *router = ucv_string_new("1");
	uc_value_t *rules = source_rules_new(vm, uc_fn_arg(0), router, MAIN_SOURCE_PRIORITY);

	ucv_put(router);

	return rules;
}

struct policy_order {
	const char *key;
	int64_t n;
	int64_t priority;
};

static int
policy_order_cmp(const void *a, const void *b)
{
	const struct policy_order *pa = a, *pb = b;

	if (pa->priority != pb->priority)
		return (pa->priority > pb->priority) - (pa->priority < pb->priority);

	return (pa->n > pb->n) - (pa->n < pb->n);
}

/* The place of a Policy row among the enabled rows, in the order of
 * Priority and then of the instance number; -1 when it is not among them. */
static int64_t
policy_rank(uc_value_t *policies, const char *instance)
{
	struct policy_order *order;
	uc_value_t *row;
	struct numkeys keys;
	int64_t rank = -1;
	size_t n = 0;

	numkeys_sorted(policies, &keys);
	order = xcalloc(keys.count + 1, sizeof(*order));

	for (size_t i = 0; i < keys.count; i++) {
		row = ucv_object_get(policies, keys.list[i].name, NULL);
		if (!value_to_bool(ucv_object_get(row, "Enable", NULL)))
			continue;

		order[n].key = keys.list[i].name;
		order[n].n = keys.list[i].n;
		order[n++].priority = int_or(ucv_object_get(row, "Priority", NULL), 0);
	}

	qsort(order, n, sizeof(*order), policy_order_cmp);

	for (size_t i = 0; i < n && rank < 0; i++)
		if (!strcmp(order[i].key, instance))
			rank = i;

	free(order);
	free(keys.list);

	return rank;
}

/* The IP version of a prefix in CIDR notation: 4 or 6, 0 for an empty
 * prefix, -1 when not valid. */
static int
prefix_family(uc_value_t *prefix)
{
	unsigned char buf[sizeof(struct in6_addr)];
	const char *s, *slash;
	unsigned long len;
	char *addr;
	int family = -1;

	if (value_blank(prefix))
		return 0;
	if (ucv_type(prefix) != UC_STRING)
		return -1;

	s = ucv_string_get(prefix);
	slash = strchr(s, '/');
	if (!slash || slash == s || strchr(slash + 1, '/') || !slash[1] ||
	    strspn(slash + 1, "0123456789") != strlen(slash + 1))
		return -1;

	addr = strndup(s, slash - s);
	errno = 0;
	len = strtoul(slash + 1, NULL, 10);

	if (inet_pton(AF_INET, addr, buf) == 1)
		family = (errno != ERANGE && len <= 32) ? 4 : -1;
	else if (inet_pton(AF_INET6, addr, buf) == 1)
		family = (errno != ERANGE && len <= 128) ? 6 : -1;

	free(addr);

	return family;
}

/* The netifd port match of a start and an end port: '' for no match, 'N'
 * or 'N-M', or NULL when the range ends below its start. */
static char *
port_match(uc_value_t *start, uc_value_t *end)
{
	int64_t from = int_or(start, -1), to = int_or(end, -1);
	char *out;

	if (from < 0)
		return (to < 0) ? xstrdup("") : NULL;
	if (to < 0) {
		xasprintf(&out, "%" PRId64, from);
		return out;
	}
	if (to < from)
		return NULL;

	xasprintf(&out, "%" PRId64 "-%" PRId64, from, to);
	return out;
}

static uc_value_t *
policy_error(uc_vm_t *vm, const char *msg)
{
	uc_value_t *out = ucv_object_new(vm);

	ucv_object_add(out, "error", ucv_string_new(msg));

	return out;
}

/* The router that a Policy row names: "1" without RouterRef, or NULL when
 * RouterRef names no Router row with a table. */
static char *
policy_router(uc_vm_t *vm, uc_value_t *root, uc_value_t *policy)
{
	static const char prefix[] = "Device.Routing.Router.";
	uc_value_t *ref = ucv_object_get(policy, "RouterRef", NULL);
	const char *s, *digits;
	char *router;
	size_t len;

	if (value_blank(ref))
		return xstrdup("1");
	if (ucv_type(ref) != UC_STRING)
		return NULL;

	s = ucv_string_get(ref);
	if (strncmp(s, prefix, sizeof(prefix) - 1))
		return NULL;

	digits = s + sizeof(prefix) - 1;
	len = strspn(digits, "0123456789");
	if (!len || (digits[len] && strcmp(digits + len, ".")))
		return NULL;

	router = strndup(digits, len);
	if (!ucv_is_truish(ucv_object_get(routing_node(vm, root, "Router"), router, NULL)) ||
	    router_table(strtoll(router, NULL, 10)) < 0) {
		free(router);
		return NULL;
	}

	return router;
}

static uc_value_t *
policy_name(uc_vm_t *vm, uc_value_t *root, uc_value_t *ref, bool *ok)
{
	uc_value_t *name;

	if (!ucv_is_truish(ref))
		return ucv_string_new("");

	name = interface_name_get(vm, root, ref);
	*ok = *ok && name;

	return ucv_get(name);
}

static uc_value_t *
value_or_empty(uc_value_t *val)
{
	return val ? ucv_get(val) : ucv_string_new("");
}

static void
family_add(int64_t list[], size_t *n, int64_t f)
{
	for (size_t i = 0; i < *n; i++)
		if (list[i] == f)
			return;

	if (f > 0)
		list[(*n)++] = f;
}

/**
 * ucode: `policy_resolve(root, instance)`, a Device.Routing.Policy.{i} row
 * (TR-181 2.20) in the form netifd needs for its rule sections, or why the
 * row is misconfigured.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: configuration root,
 *               Policy instance)
 * @return       `{ error }` or `{ router, table, families, in, out, src,
 *               dest, proto, sport, dport, source_priority, priority }`,
 *               the last two as kernel rule priorities: the first rule to a
 *               source table and the rule of the row
 */
uc_value_t *
uc_ubbf_policy_resolve(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *root = uc_fn_arg(0), *inst = uc_fn_arg(1);
	uc_value_t *policies = routing_node(vm, root, "Policy");
	uc_value_t *policy, *in, *out_name, *res, *fams;
	char *instance = ucv_to_string(vm, inst), *router = NULL, *sport = NULL, *dport = NULL;
	int64_t families[3], rank;
	size_t nfam = 0;
	bool names_ok = true;
	int src, dest;

	policy = ucv_object_get(policies, instance, NULL);
	res = NULL;

	if (forwarding_policy_set(policy)) {
		res = policy_error(vm, "ForwardingPolicy needs a QoS class, which ubbf does not set");
		goto out;
	}

	router = policy_router(vm, root, policy);
	if (!router) {
		res = policy_error(vm, "RouterRef names no Router row with a table");
		goto out;
	}

	in = policy_name(vm, root, ucv_object_get(policy, "SourceInterface", NULL), &names_ok);
	out_name = policy_name(vm, root, ucv_object_get(policy, "DestInterface", NULL), &names_ok);
	if (!names_ok) {
		ucv_put(in);
		ucv_put(out_name);
		res = policy_error(vm, "SourceInterface or DestInterface names no IP.Interface");
		goto out;
	}

	src = prefix_family(ucv_object_get(policy, "SourceIPPrefix", NULL));
	dest = prefix_family(ucv_object_get(policy, "DestIPPrefix", NULL));
	family_add(families, &nfam, int_or(ucv_object_get(policy, "IPVersion", NULL), -1));
	family_add(families, &nfam, src);
	family_add(families, &nfam, dest);

	sport = port_match(ucv_object_get(policy, "SourcePort", NULL),
			   ucv_object_get(policy, "SourcePortRangeMax", NULL));
	dport = port_match(ucv_object_get(policy, "DestPort", NULL),
			   ucv_object_get(policy, "DestPortRangeMax", NULL));
	rank = policy_rank(policies, instance);

	if (src < 0 || dest < 0 || nfam > 1)
		res = policy_error(vm, "the prefixes and IPVersion do not agree");
	else if (!sport || !dport)
		res = policy_error(vm, "a port range ends below its start");
	else if (rank < 0)
		res = policy_error(vm, "the row is not enabled");

	if (!res && rank >= POLICY_MAX) {
		char *msg;

		xasprintf(&msg, "more than %d Policy rows are enabled", POLICY_MAX);
		res = policy_error(vm, msg);
		free(msg);
	}

	if (res) {
		ucv_put(in);
		ucv_put(out_name);
		goto out;
	}

	fams = ucv_array_new(vm);
	if (!nfam) {
		ucv_array_push(fams, ucv_int64_new(4));
		ucv_array_push(fams, ucv_int64_new(6));
	} else {
		ucv_array_push(fams, ucv_int64_new(families[0]));
	}

	res = ucv_object_new(vm);
	ucv_object_add(res, "router", ucv_string_new(router));
	ucv_object_add(res, "table", ucv_int64_new(router_table(strtoll(router, NULL, 10))));
	ucv_object_add(res, "families", fams);
	ucv_object_add(res, "in", in);
	ucv_object_add(res, "out", out_name);
	ucv_object_add(res, "src", value_or_empty(ucv_object_get(policy, "SourceIPPrefix", NULL)));
	ucv_object_add(res, "dest", value_or_empty(ucv_object_get(policy, "DestIPPrefix", NULL)));
	ucv_object_add(res, "proto", ucv_int64_new(int_or(ucv_object_get(policy, "Protocol", NULL), -1)));
	ucv_object_add(res, "sport", ucv_string_new(sport));
	ucv_object_add(res, "dport", ucv_string_new(dport));
	ucv_object_add(res, "source_priority", ucv_int64_new(POLICY_BLOCK * rank + 1));
	ucv_object_add(res, "priority", ucv_int64_new(POLICY_BLOCK * (rank + 1)));

out:
	free(sport);
	free(dport);
	free(router);
	free(instance);

	return res;
}
