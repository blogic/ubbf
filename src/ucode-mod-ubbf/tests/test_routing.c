/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * routing.c: the table of a Router row, the prefixes of IPv4Forwarding
 * rows, the source tables and their rules, and the resolution of Policy
 * rows.
 */

#include "harness.h"
#include "ubbf.h"

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_router_table_id(void **state)
{
	eval_expect(*state,
		"return [ map([ 1, '1', '2', 2, '100', '101', '0', '', null, 'x', -1, 2.5 ],"
		"  (n) => ubbf.router_table_id(n)), ubbf.MAIN_TABLE, ubbf.SOURCE_TABLE_BASE,"
		"  ubbf.SOURCE_TABLE_MAX ];",
		"[ [ 254, 254, 101, 101, 199, null, null, null, null, null, null, 101.5 ], 254, 200, 252 ]");
}

static void
test_prefixes(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"return map([ {}, { SourceIPAddress: '192.168.1.77', SourceSubnetMask: '255.255.255.0' },"
		"  { SourceIPAddress: '192.168.1.77' }, { SourceSubnetMask: '255.0.0.0' },"
		"  { SourceIPAddress: '10.0.0.1', SourceSubnetMask: '255.0.255.0' },"
		"  { SourceIPAddress: '2001:db8::1' } ], (r) => ubbf.source_prefix(r));",
		"[ \"\", \"192.168.1.0/24\", \"192.168.1.77/32\", null, null, null ]");
	eval_expect(vm,
		"return map([ {}, { DestIPAddress: '10.1.2.3', DestSubnetMask: '255.255.0.0' },"
		"  { DestIPAddress: '10.1.2.3' }, { DestIPAddress: 'x' } ], (r) => ubbf.route_dest(r));",
		"[ \"0.0.0.0/0\", \"10.1.0.0/16\", \"10.1.2.3/32\", null ]");
	eval_expect(vm,
		"return [ ubbf.prefix_intersect('', '10.0.0.0/8'), ubbf.prefix_intersect('10.1.0.0/16', ''),"
		"  ubbf.prefix_intersect('10.0.0.0/8', '10.1.0.0/16'), ubbf.prefix_intersect('10.1.0.0/16', '10.0.0.0/8'),"
		"  ubbf.prefix_intersect('10.0.0.0/8', '192.168.0.0/16'), ubbf.prefix_intersect('10.0.0.0/33', '10.0.0.0/8') ];",
		"[ \"10.0.0.0/8\", \"10.1.0.0/16\", \"10.1.0.0/16\", \"10.1.0.0/16\", null, null ]");
	eval_expect(vm,
		"return map([ {}, { ForwardingPolicy: '-1' }, { ForwardingPolicy: '0' }, { ForwardingPolicy: 'x' } ],"
		"  (r) => ubbf.forwarding_policy_set(r));",
		"[ false, false, true, false ]");
}

static const char root_js[] =
	"let route = (src, mask, dest, dmask) => ({ Enable: 'true', SourceIPAddress: src,"
	"  SourceSubnetMask: mask, DestIPAddress: dest, DestSubnetMask: dmask });"
	"let root = { Device: { Routing: { Router: {"
	"  '1': { IPv4Forwarding: {"
	"    '1': route(null, null, '10.9.0.0', '255.255.0.0'),"
	"    '2': route('192.168.1.0', '255.255.255.0', '10.1.0.0', '255.255.0.0'),"
	"    '3': route('192.168.0.0', '255.255.0.0', '10.1.0.0', '255.255.0.0'),"
	"    '4': route('192.168.0.0', '255.255.0.0', '10.2.0.0', '255.255.0.0'),"
	"    '5': { ...route('172.16.0.0', '255.240.0.0', null, null), Enable: 'false' } } },"
	"  '2': { IPv4Forwarding: {"
	"    '1': route(null, null, '10.5.0.0', '255.255.0.0'),"
	"    '2': route('192.168.1.0', '255.255.255.0', '10.6.0.0', '255.255.0.0') } },"
	"  '200': { IPv4Forwarding: { '1': route('10.0.0.0', '255.0.0.0', null, null) } } },"
	"  Policy: {"
	"    '1': { Enable: 'true', Priority: '2', SourceInterface: 'Device.IP.Interface.2',"
	"      SourceIPPrefix: '192.168.1.0/24', DestPort: '443', Protocol: '6' },"
	"    '2': { Enable: 'true', Priority: '1', RouterRef: 'Device.Routing.Router.2.', IPVersion: '6' },"
	"    '3': { Enable: 'true', RouterRef: 'Device.Routing.Router.9' },"
	"    '4': { Enable: 'true', SourceIPPrefix: '192.168.1.0/24', DestIPPrefix: '2001:db8::/32' },"
	"    '5': { Enable: 'true', SourcePort: '90', SourcePortRangeMax: '80' },"
	"    '6': { Enable: 'false' },"
	"    '7': { Enable: 'true', ForwardingPolicy: '1' },"
	"    '8': { Enable: 'true', DestInterface: 'Device.IP.Interface.9' } } },"
	"  IP: { Interface: { '2': { Name: 'lan' } } } } };";

static void
test_source_tables(void **state)
{
	uc_vm_t *vm = *state;
	char code[4096];

	snprintf(code, sizeof(code), "%s"
		"let t = ubbf.source_tables(root);"
		"return [ t, map(ubbf.source_table_contents(root), (c) => [ c.router, c.src, c.table, c.dests,"
		"  length(c.routes) ]), ubbf.source_rules(t, '1'), ubbf.main_source_rules(t) ];", root_js);

	eval_expect(vm, code,
		"[ { \"1|192.168.1.0/24\": 200, \"1|192.168.0.0/16\": 201, \"2|192.168.1.0/24\": 202 }, "
		"[ [ \"1\", \"192.168.1.0/24\", 200, [ \"10.1.0.0/16\", \"10.2.0.0/16\" ], 2 ], "
		"[ \"1\", \"192.168.0.0/16\", 201, [ \"10.1.0.0/16\", \"10.2.0.0/16\" ], 2 ], "
		"[ \"2\", \"192.168.1.0/24\", 202, [ \"10.5.0.0/16\", \"10.6.0.0/16\" ], 2 ] ], "
		"[ { \"src\": \"192.168.1.0/24\", \"table\": 200 }, { \"src\": \"192.168.0.0/16\", \"table\": 201 } ], "
		"[ { \"src\": \"192.168.1.0/24\", \"table\": 200, \"priority\": 32000 }, "
		"{ \"src\": \"192.168.0.0/16\", \"table\": 201, \"priority\": 32001 } ] ]");
}

static void
test_policy_resolve(void **state)
{
	uc_vm_t *vm = *state;
	char code[4096];

	/* the rank counts every enabled row: 3, 4, 5, 7 and 8 have Priority 0
	 * and come first, then 2 (Priority 1) and 1 (Priority 2) */
	snprintf(code, sizeof(code), "%s"
		"return map([ '1', '2', 3, '4', '5', '6', '7', '8', '9' ], (i) => ubbf.policy_resolve(root, i));",
		root_js);

	eval_expect(vm, code,
		"[ { \"router\": \"1\", \"table\": 254, \"families\": [ 4 ], \"in\": \"lan\", \"out\": \"\", "
		"\"src\": \"192.168.1.0/24\", \"dest\": \"\", \"proto\": 6, \"sport\": \"\", \"dport\": \"443\", "
		"\"source_priority\": 385, \"priority\": 448 }, "
		"{ \"router\": \"2\", \"table\": 101, \"families\": [ 6 ], \"in\": \"\", \"out\": \"\", "
		"\"src\": \"\", \"dest\": \"\", \"proto\": -1, \"sport\": \"\", \"dport\": \"\", "
		"\"source_priority\": 321, \"priority\": 384 }, "
		"{ \"error\": \"RouterRef names no Router row with a table\" }, "
		"{ \"error\": \"the prefixes and IPVersion do not agree\" }, "
		"{ \"error\": \"a port range ends below its start\" }, "
		"{ \"error\": \"the row is not enabled\" }, "
		"{ \"error\": \"ForwardingPolicy needs a QoS class, which ubbf does not set\" }, "
		"{ \"error\": \"SourceInterface or DestInterface names no IP.Interface\" }, "
		"{ \"error\": \"the row is not enabled\" } ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_router_table_id),
		cmocka_unit_test(test_prefixes),
		cmocka_unit_test(test_source_tables),
		cmocka_unit_test(test_policy_resolve),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
