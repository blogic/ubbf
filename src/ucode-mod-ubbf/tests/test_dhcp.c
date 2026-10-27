/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * dhcp.c: leases_parse() on the dnsmasq lease file /tmp/dhcp.leases, the
 * pool numbering keys, the odhcpd leases by MAC and by pool, the
 * StaticAddress states and the option helpers. Runs isolated
 * (run-isolated.sh), so the cases write the lease file on a private tmpfs.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define LEASE_FILE "/tmp/dhcp.leases"

static void
leases_write(const char *text)
{
	FILE *fp = fopen(LEASE_FILE, "w");

	assert_non_null(fp);
	assert_int_equal(fwrite(text, 1, strlen(text), fp), strlen(text));
	assert_int_equal(fclose(fp), 0);
}

static void
leases_expect(uc_vm_t *vm, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_leases_parse, 0);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_no_file(void **state)
{
	unlink(LEASE_FILE);
	leases_expect(*state, "[ ]");
}

static void
test_empty_file(void **state)
{
	leases_write("");
	leases_expect(*state, "[ ]");

	leases_write("\n  \t\n\n");
	leases_expect(*state, "[ ]");
}

static void
test_dnsmasq_leases(void **state)
{
	leases_write(
		"1700000000 aa:bb:cc:dd:ee:01 192.168.1.100 laptop 01:aa:bb:cc:dd:ee:01\n"
		"1700000100 AA:bb:CC:dd:EE:02 192.168.1.101 * *\n"
		"0 aa:bb:cc:dd:ee:03 10.0.0.3 phone\n");
	leases_expect(*state,
		"[ { \"expiry\": 1700000000, \"mac\": \"AA:BB:CC:DD:EE:01\", \"ip\": \"192.168.1.100\","
		" \"hostname\": \"laptop\", \"client_id\": \"01:aa:bb:cc:dd:ee:01\", \"ip_int\": 3232235876 },"
		" { \"expiry\": 1700000100, \"mac\": \"AA:BB:CC:DD:EE:02\", \"ip\": \"192.168.1.101\","
		" \"hostname\": \"\", \"client_id\": \"*\", \"ip_int\": 3232235877 },"
		" { \"expiry\": 0, \"mac\": \"AA:BB:CC:DD:EE:03\", \"ip\": \"10.0.0.3\","
		" \"hostname\": \"phone\", \"client_id\": \"\", \"ip_int\": 167772163 } ]");
}

static void
test_malformed_lines(void **state)
{
	leases_write(
		"duid 00:01:00:01:2a:2b:2c:2d:aa:bb:cc:dd:ee:ff\n"
		"1700000000 aa:bb:cc:dd:ee:01\n"
		"1700000000 aa:bb:cc:dd:ee:02 10.0.0.2\n"
		"\n"
		"  \t1700000000\taa:bb:cc:dd:ee:04\t10.0.0.4\t**\n"
		"soon aa:bb:cc:dd:ee:05 1.2.3 h5 c5 extra\n"
		"7 aa:bb:cc:dd:ee:06 255.255.255.255 h6\n"
		"8 aa:bb:cc:dd:ee:07 256.1.1.1 h7");
	leases_expect(*state,
		"[ { \"expiry\": 1700000000, \"mac\": \"AA:BB:CC:DD:EE:04\", \"ip\": \"10.0.0.4\","
		" \"hostname\": \"**\", \"client_id\": \"\", \"ip_int\": 167772164 },"
		" { \"expiry\": 0, \"mac\": \"AA:BB:CC:DD:EE:05\", \"ip\": \"1.2.3\","
		" \"hostname\": \"h5\", \"client_id\": \"c5\", \"ip_int\": 0 },"
		" { \"expiry\": 7, \"mac\": \"AA:BB:CC:DD:EE:06\", \"ip\": \"255.255.255.255\","
		" \"hostname\": \"h6\", \"client_id\": \"\", \"ip_int\": 4294967295 },"
		" { \"expiry\": 8, \"mac\": \"AA:BB:CC:DD:EE:07\", \"ip\": \"256.1.1.1\","
		" \"hostname\": \"h7\", \"client_id\": \"\", \"ip_int\": 0 } ]");
}

static void
test_long_client_id(void **state)
{
	uc_vm_t *vm = *state;
	char line[1200], cid[1000];
	uc_value_t *res, *lease, *val;
	size_t i;

	for (i = 0; i + 1 < sizeof(cid); i++)
		cid[i] = "0123456789abcdef"[i % 16];
	cid[i] = '\0';

	snprintf(line, sizeof(line), "1 aa:bb:cc:dd:ee:01 10.0.0.1 h %s\n2 aa:bb:cc:dd:ee:02 10.0.0.2 g\n", cid);
	leases_write(line);

	res = vm_call(vm, uc_ubbf_leases_parse, 0);
	assert_int_equal(ucv_array_length(res), 2);

	lease = ucv_array_get(res, 0);
	val = ucv_object_get(lease, "client_id", NULL);
	assert_string_equal(ucv_string_get(val), cid);

	lease = ucv_array_get(res, 1);
	val = ucv_object_get(lease, "hostname", NULL);
	assert_string_equal(ucv_string_get(val), "g");
	ucv_put(res);
}

static void
test_many_leases(void **state)
{
	uc_vm_t *vm = *state;
	char buf[64 * 300];
	size_t off = 0;
	uc_value_t *res;

	/* more than one stdio buffer of leases, so that no read cap drops any */
	for (int i = 0; i < 300; i++)
		off += snprintf(buf + off, sizeof(buf) - off,
				"%d aa:bb:cc:dd:%02x:%02x 10.1.%d.%d host%d\n",
				i, i / 256, i % 256, i / 256, i % 256, i);
	leases_write(buf);

	res = vm_call(vm, uc_ubbf_leases_parse, 0);
	assert_int_equal(ucv_array_length(res), 300);
	assert_json_equal(vm, ucv_array_get(res, 299),
		"{ \"expiry\": 299, \"mac\": \"AA:BB:CC:DD:01:2B\", \"ip\": \"10.1.1.43\","
		" \"hostname\": \"host299\", \"client_id\": \"\", \"ip_int\": 167837995 }");
	ucv_put(res);
}

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_pool_keys(void **state)
{
	leases_write("100 aa:bb:cc:dd:ee:01 192.168.1.20 a *\n"
		     "300 aa:bb:cc:dd:ee:01 192.168.1.10 a *\n"
		     "200 aa:bb:cc:dd:ee:02 192.168.1.30 b *\n"
		     "400 aa:bb:cc:dd:ee:03 10.0.0.1 c *\n");

	eval_expect(*state,
		"return [ map(values(ubbf.pool_leases_by_key({ MinAddress: '192.168.1.2', MaxAddress: '192.168.1.250' })), (l) => l.ip),"
		"  keys(ubbf.pool_leases_by_key({ MinAddress: '192.168.1.2', MaxAddress: '192.168.1.250' })),"
		"  ubbf.pool_leases_by_key({ MinAddress: '', MaxAddress: '192.168.1.250' }) ];",
		"[ [ \"192.168.1.10\", \"192.168.1.30\", \"192.168.1.20\" ], "
		"[ \"aa:bb:cc:dd:ee:01\", \"aa:bb:cc:dd:ee:02\", \"aa:bb:cc:dd:ee:01/192.168.1.20\" ], { } ]");
}

static void
test_ipv6_leases(void **state)
{
	eval_expect(*state,
		"let raw = { device: { 'br-lan': { leases: ["
		"  { mac: 'aa:bb:cc:dd:ee:ff', duid: 'd1', hostname: 'h', 'ipv6-addr': [ { address: '2001:db8::1' } ] },"
		"  { duid: '00030001020000000001', 'ipv6-addr': [ { address: '2001:db8::2' } ], 'ipv6-prefix': [ { address: '2001:db8:1::' } ] },"
		"  { duid: 'd1', 'ipv6-addr': [ { address: '2001:db8::3' } ] }, { mac: '' } ] } } };"
		"return [ ubbf.ipv6_leases_by_mac(raw), map(ubbf.ipv6_pool_clients_build({ device: 'br-lan' }, raw),"
		"  (c) => [ c.duid, c.mac, length(c.addresses), length(c.prefixes) ]),"
		"  ubbf.ipv6_pool_clients_build({ l3_device: 'eth9', device: 'br-lan' }, raw), ubbf.ipv6_leases_by_mac(null) ];",
		"[ { \"AA:BB:CC:DD:EE:FF\": [ \"2001:db8::1\" ], \"02:00:00:00:00:01\": [ \"2001:db8::2\" ] }, "
		"[ [ \"d1\", \"AA:BB:CC:DD:EE:FF\", 2, 0 ], [ \"00030001020000000001\", \"02:00:00:00:00:01\", 1, 1 ] ], [ ], { } ]");
}

static void
test_static_states(void **state)
{
	eval_expect(*state,
		"let row = (mac, ip) => ({ Enable: 'true', Chaddr: mac, Yiaddr: ip });"
		"let root = { Device: { DHCPv4: { Server: { Pool: {"
		"  '1': { Enable: 'true', MinAddress: '192.168.1.2', SubnetMask: '255.255.255.0', StaticAddress: {"
		"    '1': row('02:00:00:00:00:01', '192.168.1.10'), '2': row('02:00:00:00:00:01', '192.168.1.11'),"
		"    '3': row('02:00:00:00:00:03', '192.168.1.255'), '4': row('02:00:00:00:00:04', '192.168.1.12') } },"
		"  '2': { Enable: 'false', StaticAddress: { '1': row('02:00:00:00:00:04', '192.168.1.12') } },"
		"  '3': { Enable: 'true', StaticAddress: { '1': row('02:00:00:00:00:05', '192.168.1.12') } } } } } } };"
		"return ubbf.static_address_states(root);",
		"{ \"1\": { \"1\": \"Error_DuplicateAddress\", \"2\": \"Error_DuplicateAddress\", \"3\": \"Error_Misconfigured\", "
		"\"4\": \"Error_DuplicateAddress\" }, \"2\": { \"1\": \"Disabled\" }, \"3\": { \"1\": \"Error_DuplicateAddress\" } }");
}

static void
test_options(void **state)
{
	eval_expect(*state,
		"let opts = [ { tag: 60, value: '4d53465420352e30' }, { tag: 12, value: '686f7374' } ];"
		"return [ ubbf.dhcp_option_value(opts, 12), ubbf.dhcp_option_value(opts, '60'), ubbf.dhcp_option_value(opts, 1),"
		"  ubbf.dhcp_option_value(null, 12), ubbf.hex_to_printable('686F7374'), ubbf.hex_to_printable('68011f'),"
		"  ubbf.hex_to_printable('686'), ubbf.hex_to_printable('zz') ];",
		"[ \"686f7374\", \"4d53465420352e30\", \"\", \"\", \"host\", \"\", \"\", \"\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_no_file),
		cmocka_unit_test(test_empty_file),
		cmocka_unit_test(test_dnsmasq_leases),
		cmocka_unit_test(test_malformed_lines),
		cmocka_unit_test(test_long_client_id),
		cmocka_unit_test(test_many_leases),
		cmocka_unit_test(test_pool_keys),
		cmocka_unit_test(test_ipv6_leases),
		cmocka_unit_test(test_static_states),
		cmocka_unit_test(test_options),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
