/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * firewall.c: port_range_format(), protocol_to_uci(), the rule order, the
 * Set resolution and the checks of a rule for fw4, and the rule expiry.
 */

#include "harness.h"
#include "ubbf.h"

static void
string_expect(uc_value_t *res, const char *expected)
{
	if (expected) {
		assert_int_equal(ucv_type(res), UC_STRING);
		assert_string_equal(ucv_string_get(res), expected);
	} else {
		assert_null(res);
	}

	ucv_put(res);
}

static void
range_expect(uc_vm_t *vm, uc_value_t *p, uc_value_t *pe, const char *expected)
{
	string_expect(vm_call(vm, uc_ubbf_port_range_format, 2, p, pe), expected);
}

static void
test_port_range_format(void **state)
{
	uc_vm_t *vm = *state;

	range_expect(vm, ucv_int64_new(80), NULL, "80");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(90), "80-90");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(81), "80-81");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(80), "80");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(79), "80");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(0), "80");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(-1), "80");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(65535), "80-65535");
	range_expect(vm, ucv_int64_new(80), ucv_int64_new(65536), "80");
	range_expect(vm, ucv_int64_new(1), ucv_int64_new(65535), "1-65535");
	range_expect(vm, ucv_int64_new(65535), NULL, "65535");

	range_expect(vm, ucv_string_new("8080"), ucv_string_new("8090"), "8080-8090");
	range_expect(vm, ucv_string_new("8080"), ucv_string_new(""), "8080");
	range_expect(vm, ucv_string_new("8080"), ucv_string_new("90x"), "8080");
	range_expect(vm, ucv_string_new("8080"), ucv_double_new(9000.0), "8080");
	range_expect(vm, ucv_string_new("8080"), ucv_boolean_new(true), "8080");
	range_expect(vm, ucv_int64_new(22), ucv_string_new("23"), "22-23");

	range_expect(vm, ucv_int64_new(0), ucv_int64_new(90), NULL);
	range_expect(vm, ucv_int64_new(-1), NULL, NULL);
	range_expect(vm, ucv_int64_new(65536), NULL, NULL);
	range_expect(vm, ucv_string_new("0"), NULL, NULL);
	range_expect(vm, ucv_string_new("80x"), ucv_int64_new(90), NULL);
	range_expect(vm, ucv_string_new("http"), NULL, NULL);
	range_expect(vm, ucv_string_new(""), ucv_int64_new(90), NULL);
	range_expect(vm, ucv_double_new(80.0), NULL, NULL);
	range_expect(vm, NULL, ucv_int64_new(90), NULL);
}

static void
proto_expect(uc_vm_t *vm, uc_value_t *val, const char *expected)
{
	string_expect(vm_call(vm, uc_ubbf_protocol_to_uci, 1, val), expected);
}

static void
test_protocol_to_uci(void **state)
{
	uc_vm_t *vm = *state;

	/* IANA protocol numbers: 1 ICMP, 6 TCP, 17 UDP, 58 IPv6-ICMP */
	proto_expect(vm, ucv_int64_new(-1), "all");
	proto_expect(vm, ucv_int64_new(1), "icmp");
	proto_expect(vm, ucv_int64_new(6), "tcp");
	proto_expect(vm, ucv_int64_new(17), "udp");
	proto_expect(vm, ucv_int64_new(58), "icmpv6");
	proto_expect(vm, ucv_int64_new(47), "47");
	proto_expect(vm, ucv_int64_new(255), "255");
	proto_expect(vm, ucv_int64_new(0), NULL);
	proto_expect(vm, ucv_int64_new(256), NULL);
	proto_expect(vm, ucv_int64_new(-2), NULL);

	proto_expect(vm, ucv_string_new("-1"), "all");
	proto_expect(vm, ucv_string_new("6"), "tcp");
	proto_expect(vm, ucv_string_new("17"), "udp");
	proto_expect(vm, ucv_string_new("1"), "icmp");
	proto_expect(vm, ucv_string_new("58"), "icmpv6");
	proto_expect(vm, ucv_string_new("50"), "50");
	proto_expect(vm, ucv_string_new("0"), NULL);
	proto_expect(vm, ucv_string_new("300"), NULL);
	proto_expect(vm, ucv_string_new("6a"), NULL);

	proto_expect(vm, ucv_string_new("tcp"), "tcp");
	proto_expect(vm, ucv_string_new("UDP"), "udp");
	proto_expect(vm, ucv_string_new("Icmp"), "icmp");
	proto_expect(vm, ucv_string_new("ICMPv6"), "icmpv6");
	proto_expect(vm, ucv_string_new("icmpv6x"), NULL);
	proto_expect(vm, ucv_string_new("tcpudp"), NULL);
	proto_expect(vm, ucv_string_new("all"), NULL);
	proto_expect(vm, ucv_string_new("esp"), NULL);
	proto_expect(vm, ucv_string_new(""), NULL);
	proto_expect(vm, ucv_double_new(6.0), NULL);
	proto_expect(vm, ucv_boolean_new(true), NULL);
	proto_expect(vm, NULL, NULL);
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_chain_rules_ordered(void **state)
{
	eval_expect(*state,
		"return map(ubbf.chain_rules_ordered({"
		"  '3': { Order: '1' }, '1': { Order: '2' }, '2': { Order: '1' },"
		"  '10': {}, '01': { Order: '0' }, 'x': {}, '4': 'junk', '5': { Order: 'a' } }),"
		"  (e) => e[0]);",
		"[ \"5\", \"10\", \"2\", \"3\", \"1\" ]");
	eval_expect(*state, "return ubbf.chain_rules_ordered(null);", "[ ]");
}

static const char sets_json[] =
	"{ Device: { Firewall: { Set: {"
	"  '1': { Enable: 'true', Type: 'Ports', Rule: {"
	"    '1': { PortList: '80, 22-23' }, '2': { PortList: '23,8080' } } },"
	"  '2': { Enable: 'true', Type: 'MACAddresses', Rule: {"
	"    '1': { MACAddressList: 'AA:BB:CC:DD:EE:FF, aa:bb:cc:dd:ee:ff', Exclude: 'true' } } },"
	"  '3': { Enable: 'true', IPVersion: '4', Rule: {"
	"    '1': { IPAddressList: '192.0.2.1,2001:db8::1' } } },"
	"  '4': { Enable: 'true', Rule: { '1': { IPAddressList: '192.0.2.1,2001:db8::1' } } },"
	"  '5': { Enable: 'false', Rule: {} },"
	"  '6': { Enable: 'true', Rule: { '1': { Exclude: 'true' }, '2': {} } },"
	"  '7': { Enable: 'true', Type: 'Ports', Rule: { '1': { PortList: '0-5' } } },"
	"  '8': { Enable: 'true', Rule: 'junk' } } } } }";

static void
test_firewall_set_resolve(void **state)
{
	uc_vm_t *vm = *state;
	char code[2048];

	snprintf(code, sizeof(code),
		"let c = %s;"
		"return map([ 'Device.Firewall.Set.1', 'Device.Firewall.Set.2.', 'Device.Firewall.Set.3',"
		"  'Device.Firewall.Set.4', 'Device.Firewall.Set.5', 'Device.Firewall.Set.6',"
		"  'Device.Firewall.Set.7', 'Device.Firewall.Set.8', 'Device.Firewall.Set.9',"
		"  'Device.Firewall.Set.1..', 'Device.Firewall.Sets.1', null ],"
		"  (r) => ubbf.firewall_set_resolve(c, r));", sets_json);

	eval_expect(vm, code,
		"[ { \"type\": \"Ports\", \"invert\": false, \"ipsets\": [ { \"name\": \"ubbf_set_1\", "
		"\"family\": \"any\", \"match\": \"src_port\", \"entries\": [ \"80\", \"22\", \"23\", \"8080\" ] } ] }, "
		"{ \"type\": \"MACAddresses\", \"invert\": true, \"ipsets\": [ { \"name\": \"ubbf_set_2\", "
		"\"family\": \"any\", \"match\": \"src_mac\", \"entries\": [ \"aa:bb:cc:dd:ee:ff\" ] } ] }, "
		"{ \"type\": \"IPAddresses\", \"invert\": false, \"ipsets\": [ { \"name\": \"ubbf_set_3_v4\", "
		"\"family\": \"ipv4\", \"match\": \"src_net\", \"entries\": [ \"192.0.2.1\" ] } ] }, "
		"{ \"type\": \"IPAddresses\", \"invert\": false, \"ipsets\": [ { \"name\": \"ubbf_set_4_v4\", "
		"\"family\": \"ipv4\", \"match\": \"src_net\", \"entries\": [ \"192.0.2.1\" ] }, "
		"{ \"name\": \"ubbf_set_4_v6\", \"family\": \"ipv6\", \"match\": \"src_net\", "
		"\"entries\": [ \"2001:db8::1\" ] } ] }, "
		"null, null, null, "
		"{ \"type\": \"IPAddresses\", \"invert\": false, \"ipsets\": [ { \"name\": \"ubbf_set_8_v4\", "
		"\"family\": \"ipv4\", \"match\": \"src_net\", \"entries\": [ ] }, "
		"{ \"name\": \"ubbf_set_8_v6\", \"family\": \"ipv6\", \"match\": \"src_net\", "
		"\"entries\": [ ] } ] }, "
		"null, null, null, null ]");
}

static void
test_chain_rule_set_matches(void **state)
{
	uc_vm_t *vm = *state;
	char code[2048];

	snprintf(code, sizeof(code),
		"let c = %s;"
		"return [ ubbf.chain_rule_set_matches(c, {}),"
		"  ubbf.chain_rule_set_matches(c, { DestMatchSet: 'Device.Firewall.Set.4' }),"
		"  ubbf.chain_rule_set_matches(c, { SourceMatchSetExclude: 'Device.Firewall.Set.2' }),"
		"  ubbf.chain_rule_set_matches(c, { SourceMatchSet: 'Device.Firewall.Set.2' }),"
		"  ubbf.chain_rule_set_matches(c, { SourceMatchSet: '', DestMatchSet: 'Device.Firewall.Set.1' }),"
		"  ubbf.chain_rule_set_matches(c, { SourceMatchSet: 'Device.Firewall.Set.5' }) ];", sets_json);

	eval_expect(vm, code,
		"[ [ { \"family\": null, \"ipset\": null } ], "
		"[ { \"family\": \"ipv4\", \"ipset\": \"ubbf_set_4_v4 dest\" }, "
		"{ \"family\": \"ipv6\", \"ipset\": \"ubbf_set_4_v6 dest\" } ], "
		"[ { \"family\": null, \"ipset\": \"ubbf_set_2 src\" } ], "
		"[ { \"family\": null, \"ipset\": \"!ubbf_set_2 src\" } ], "
		"[ { \"family\": null, \"ipset\": \"ubbf_set_1 dest\" } ], "
		"null ]");
}

static void
test_chain_rule_unsupported(void **state)
{
	uc_vm_t *vm = *state;
	char code[2048];

	snprintf(code, sizeof(code),
		"let c = %s;"
		"return map([ {}, { ConnectionState: 'Established' }, { ConnectionState: '' },"
		"  { Target: 'Return' }, { Target: 'TargetChain' }, { Target: 'Accept' },"
		"  { SourceMatchSet: 'Device.Firewall.Set.1', DestMatchSet: 'Device.Firewall.Set.1' },"
		"  { SourceMatchSet: 'Device.Firewall.Set.5' },"
		"  { SourceMatchSet: 'Device.Firewall.Set.1', Protocol: '1' },"
		"  { SourceMatchSet: 'Device.Firewall.Set.1', Protocol: '6' },"
		"  { ProtocolExclude: 'true', Protocol: '6', DestPort: '22' },"
		"  { ProtocolExclude: 'true', Protocol: '-1', DestPort: '22' },"
		"  { ProtocolExclude: 'true', Protocol: '17', SourceMatchSet: 'Device.Firewall.Set.1' },"
		"  { ProtocolExclude: 'true', Protocol: '17' } ],"
		"  (r) => ubbf.chain_rule_unsupported(r, c));", sets_json);

	eval_expect(vm, code,
		"[ null, \"ConnectionState\", null, \"Target\", \"Target\", null, \"MatchSet\", "
		"\"MatchSetState\", \"MatchSetState\", null, \"ProtocolExclude\", null, "
		"\"ProtocolExclude\", null ]");

	/* without a config the Set is not looked at */
	eval_expect(vm,
		"return ubbf.chain_rule_unsupported({ SourceMatchSet: 'Device.Firewall.Set.5' });",
		"null");
}

static void
test_firewall_expiry(void **state)
{
	uc_vm_t *vm = *state;
	const char *config =
		"let c = { Device: { Firewall: { Chain: {"
		"  '1': { Rule: { '1': { ExpiryDate: '2027-01-01T00:00:00Z' },"
		"    '2': { ExpiryDate: '9999-12-31T23:59:59Z' }, '3': { ExpiryDate: '2026-01-01T00:00:00Z' },"
		"    '4': { ExpiryDate: '0001-01-01T00:00:00Z' }, '5': {}, '6': { ExpiryDate: 'junk' },"
		"    '7': 'junk' } },"
		"  '2': { Rule: { '1': { ExpiryDate: '2026-06-01T12:00:00+02:00' } } },"
		"  '3': 'junk' } } } };"
		"let now = usp_datetime_to_unix('2026-10-18T00:00:00Z');";
	char code[1024];

	snprintf(code, sizeof(code), "%s return [ ubbf.firewall_rules_expired(c, now),"
		 "  ubbf.firewall_expiry_next(c, now) == usp_datetime_to_unix('2027-01-01T00:00:00Z'),"
		 "  ubbf.firewall_expiry_next({ Device: {} }, now), ubbf.firewall_rules_expired(null, now) ];",
		 config);

	eval_expect(vm, code,
		"[ [ \"Device.Firewall.Chain.1.Rule.3.\", \"Device.Firewall.Chain.2.Rule.1.\" ], "
		"true, null, [ ] ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_port_range_format),
		cmocka_unit_test(test_protocol_to_uci),
		cmocka_unit_test(test_chain_rules_ordered),
		cmocka_unit_test(test_firewall_set_resolve),
		cmocka_unit_test(test_chain_rule_set_matches),
		cmocka_unit_test(test_chain_rule_unsupported),
		cmocka_unit_test(test_firewall_expiry),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
