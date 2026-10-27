/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * inet.c: the IPv4 conversions ip_to_int(), int_to_ip(), cidr_to_netmask()
 * and netmask_to_cidr(), ipv4_parse(), ip_prefix_match() and
 * the TR-181 row builders ipv4_addr_to_object(), ipv6_addr_to_object() and
 * ipv6_prefix_to_object().
 */

#include "harness.h"
#include "ubbf.h"

#define FOREVER "9999-12-31T23:59:59Z"

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
int_expect(uc_value_t *res, int64_t expected)
{
	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
test_ip_to_int(void **state)
{
	uc_vm_t *vm = *state;

	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("192.168.1.1")), 3232235777LL);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("10.0.0.1")), 167772161LL);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("0.0.0.0")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("255.255.255.255")), 4294967295LL);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("1.2.3")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("256.1.1.1")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("1.2.3.4.5")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_string_new("host")), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, ucv_int64_new(5)), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 1, NULL), 0);
	int_expect(vm_call(vm, uc_ubbf_ip_to_int, 0), 0);
}

static void
test_int_to_ip(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_int64_new(3232235777LL)), "192.168.1.1");
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_int64_new(167772161LL)), "10.0.0.1");
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_int64_new(0)), "0.0.0.0");
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_int64_new(4294967295LL)), "255.255.255.255");
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_double_new(1.0)), NULL);
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, ucv_string_new("1")), NULL);
	string_expect(vm_call(vm, uc_ubbf_int_to_ip, 1, NULL), NULL);
}

static void
test_cidr_to_netmask(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(0)), "0.0.0.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(1)), "128.0.0.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(8)), "255.0.0.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(16)), "255.255.0.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(23)), "255.255.254.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(24)), "255.255.255.0");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(25)), "255.255.255.128");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(31)), "255.255.255.254");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(32)), "255.255.255.255");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(33)), "");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_int64_new(-1)), "");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_string_new("24")), "");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, ucv_double_new(24.0)), "");
	string_expect(vm_call(vm, uc_ubbf_cidr_to_netmask, 1, NULL), "");
}

static void
test_netmask_to_cidr(void **state)
{
	uc_vm_t *vm = *state;

	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("0.0.0.0")), 0);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("128.0.0.0")), 1);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255.254.0")), 23);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255.255.0")), 24);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255.255.252")), 30);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255.255.255")), 32);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255.255.256")), 0);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.0.255.0")), 8);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("255.255")), 0);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_string_new("")), 0);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, ucv_int64_new(24)), 0);
	int_expect(vm_call(vm, uc_ubbf_netmask_to_cidr, 1, NULL), 0);
}

static void
test_ipv4_parse(void **state)
{
	uint32_t n = 0;

	(void)state;

	assert_true(ipv4_parse("192.0.2.1", &n));
	assert_int_equal(n, 0xc0000201);
	assert_true(ipv4_parse("255.255.255.255", &n));
	assert_int_equal(n, 0xffffffff);

	/* each part a decimal 0-255 and nothing after the fourth */
	assert_false(ipv4_parse("256.1.1.1", &n));
	assert_false(ipv4_parse("1.2.3.4.5", &n));
	assert_false(ipv4_parse("-1.0.0.0", &n));
	assert_false(ipv4_parse("1.2.3", &n));
	assert_false(ipv4_parse("1.2.3.4 ", &n));
	assert_false(ipv4_parse("", &n));
	assert_false(ipv4_parse(NULL, &n));
}

static void
test_ip_prefix_match(void **state)
{
	(void)state;

	assert_true(ip_prefix_match("192.0.2.130", "192.0.2.1", 24));
	assert_false(ip_prefix_match("192.0.3.1", "192.0.2.1", 24));
	assert_true(ip_prefix_match("192.0.2.130", "192.0.2.129", 25));
	assert_false(ip_prefix_match("192.0.2.127", "192.0.2.129", 25));
	assert_true(ip_prefix_match("10.1.2.3", "192.0.2.1", 0));
	assert_true(ip_prefix_match("192.0.2.1", "192.0.2.1", 32));
	assert_false(ip_prefix_match("192.0.2.1", "192.0.2.2", 32));

	/* the RFC 4291 2.2 text forms of one address are equal */
	assert_true(ip_prefix_match("2001:DB8::8:800:200C:417A", "2001:db8:0:0:8:800:200c:417a", 128));
	assert_true(ip_prefix_match("::ffff:192.0.2.1", "::ffff:c000:201", 128));
	assert_true(ip_prefix_match("2001:db8:1:2::1", "2001:db8:1:3::5", 63));
	assert_false(ip_prefix_match("2001:db8:1:2::1", "2001:db8:1:3::5", 64));
	assert_true(ip_prefix_match("fe80::1", "fe80::2", 64));

	/* out of range or not an address of the family */
	assert_false(ip_prefix_match("192.0.2.1", "192.0.2.1", 33));
	assert_false(ip_prefix_match("192.0.2.1", "192.0.2.1", -1));
	assert_false(ip_prefix_match("::1", "::1", 129));
	assert_false(ip_prefix_match("256.0.2.1", "192.0.2.1", 8));
	assert_false(ip_prefix_match("fe80::1", "192.0.2.1", 8));
}

static void
test_ipv4_addr_to_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": \"192.168.1.1\", \"mask\": 24 }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"192.168.1.1\", "
		"\"SubnetMask\": \"255.255.255.0\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 2,
		      vm_json(vm, "{ \"address\": \"10.0.0.1\", \"mask\": 32 }"), ucv_string_new("Static"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"10.0.0.1\", "
		"\"SubnetMask\": \"255.255.255.255\", \"AddressingType\": \"Static\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 2,
		      vm_json(vm, "{ \"address\": \"10.0.0.1\", \"mask\": 1 }"), ucv_int64_new(1));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"10.0.0.1\", "
		"\"SubnetMask\": \"128.0.0.0\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1, vm_json(vm, "{ }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"\", "
		"\"SubnetMask\": \"0.0.0.0\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": 5, \"mask\": \"24\" }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"\", "
		"\"SubnetMask\": \"0.0.0.0\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": \"\", \"mask\": 33 }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"\", "
		"\"SubnetMask\": \"\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": \"1.1.1.1\", \"mask\": -1 }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddress\": \"1.1.1.1\", "
		"\"SubnetMask\": \"\", \"AddressingType\": \"DHCP\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 1, ucv_string_new("192.168.1.1"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv4_addr_to_object, 0);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);
}

static void
datetime_utc(time_t t, char *buf, size_t len)
{
	struct tm tm;

	gmtime_r(&t, &tm);
	strftime(buf, len, "%Y-%m-%dT%H:%M:%SZ", &tm);
}

/*
 * A finite lifetime is relative to time(NULL) in the call, so the result
 * may name the second before or after the one the test reads.
 */
static void
lifetime_expect(uc_value_t *obj, const char *key, time_t t0, time_t t1, int64_t seconds)
{
	uc_value_t *v = ucv_object_get(obj, key, NULL);
	char a[32], b[32];

	assert_int_equal(ucv_type(v), UC_STRING);
	datetime_utc(t0 + seconds, a, sizeof(a));
	datetime_utc(t1 + seconds, b, sizeof(b));

	if (strcmp(ucv_string_get(v), a) && strcmp(ucv_string_get(v), b))
		fail_msg("%s: %s is neither %s nor %s", key, ucv_string_get(v), a, b);
}

static void
field_expect(uc_value_t *obj, const char *key, const char *expected)
{
	uc_value_t *v = ucv_object_get(obj, key, NULL);

	assert_int_equal(ucv_type(v), UC_STRING);
	assert_string_equal(ucv_string_get(v), expected);
}

static void
test_ipv6_addr_to_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	time_t t0, t1;

	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": \"2001:db8::1\" }"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddressStatus\": \"Preferred\", "
		"\"Alias\": \"\", \"IPAddress\": \"2001:db8::1\", \"Origin\": \"DHCPv6\", "
		"\"PreferredLifetime\": \"" FOREVER "\", \"ValidLifetime\": \"" FOREVER "\", "
		"\"Anycast\": \"false\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 2,
		      vm_json(vm, "{ \"address\": \"2001:db8::2\", \"preferred\": 4294967295, "
				  "\"valid\": 4294967295 }"),
		      ucv_string_new("AutoConfigured"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddressStatus\": \"Preferred\", "
		"\"Alias\": \"\", \"IPAddress\": \"2001:db8::2\", \"Origin\": \"AutoConfigured\", "
		"\"PreferredLifetime\": \"" FOREVER "\", \"ValidLifetime\": \"" FOREVER "\", "
		"\"Anycast\": \"false\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 3,
		      vm_json(vm, "{ \"address\": \"fe80::1\", \"preferred\": 0, \"valid\": 0 }"),
		      ucv_string_new("WellKnown"), ucv_boolean_new(true));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"IPAddressStatus\": \"Preferred\", "
		"\"Alias\": \"\", \"IPAddress\": \"fe80::1\", \"Origin\": \"WellKnown\", "
		"\"PreferredLifetime\": \"" FOREVER "\", \"ValidLifetime\": \"" FOREVER "\", "
		"\"Anycast\": \"false\" }");
	ucv_put(res);

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 3,
		      vm_json(vm, "{ \"address\": \"2001:db8::3\", \"preferred\": 3600, \"valid\": 7200 }"),
		      ucv_int64_new(1), ucv_boolean_new(false));
	t1 = time(NULL);
	field_expect(res, "IPAddressStatus", "Preferred");
	field_expect(res, "Origin", "DHCPv6");
	field_expect(res, "IPAddress", "2001:db8::3");
	lifetime_expect(res, "PreferredLifetime", t0, t1, 3600);
	lifetime_expect(res, "ValidLifetime", t0, t1, 7200);
	ucv_put(res);

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 1,
		      vm_json(vm, "{ \"address\": 7, \"preferred\": 0, \"valid\": 60 }"));
	t1 = time(NULL);
	field_expect(res, "IPAddressStatus", "Deprecated");
	field_expect(res, "IPAddress", "");
	lifetime_expect(res, "PreferredLifetime", t0, t1, 0);
	lifetime_expect(res, "ValidLifetime", t0, t1, 60);
	ucv_put(res);

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 1,
		      vm_json(vm, "{ \"preferred\": 4294967294, \"valid\": 4294967294 }"));
	t1 = time(NULL);
	field_expect(res, "IPAddressStatus", "Invalid");
	field_expect(res, "IPAddress", "");
	lifetime_expect(res, "PreferredLifetime", t0, t1, 0);
	lifetime_expect(res, "ValidLifetime", t0, t1, 0);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 1, ucv_string_new("2001:db8::1"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_addr_to_object, 0);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);
}

static void
prefix_flags_expect(uc_vm_t *vm, uc_value_t *origin, const char *expected)
{
	char buf[512];
	uc_value_t *res = vm_call(vm, uc_ubbf_ipv6_prefix_to_object, 2,
				  vm_json(vm, "{ \"address\": \"2001:db8:1::\", \"mask\": 48 }"),
				  origin);

	snprintf(buf, sizeof(buf),
		"{ \"Enable\": \"true\", \"Status\": \"Enabled\", \"PrefixStatus\": \"Preferred\", "
		"\"Alias\": \"\", \"Prefix\": \"2001:db8:1::/48\", %s, "
		"\"PreferredLifetime\": \"" FOREVER "\", \"ValidLifetime\": \"" FOREVER "\" }",
		expected);
	assert_json_equal(vm, res, buf);
	ucv_put(res);
}

static void
test_ipv6_prefix_to_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	time_t t0, t1;

	prefix_flags_expect(vm, NULL,
		"\"Origin\": \"PrefixDelegation\", \"StaticType\": \"Inapplicable\", "
		"\"OnLink\": \"false\", \"Autonomous\": \"false\"");
	prefix_flags_expect(vm, ucv_int64_new(3),
		"\"Origin\": \"PrefixDelegation\", \"StaticType\": \"Inapplicable\", "
		"\"OnLink\": \"false\", \"Autonomous\": \"false\"");
	prefix_flags_expect(vm, ucv_string_new("PrefixDelegation"),
		"\"Origin\": \"PrefixDelegation\", \"StaticType\": \"Inapplicable\", "
		"\"OnLink\": \"false\", \"Autonomous\": \"false\"");
	prefix_flags_expect(vm, ucv_string_new("RouterAdvertisement"),
		"\"Origin\": \"RouterAdvertisement\", \"StaticType\": \"Inapplicable\", "
		"\"OnLink\": \"true\", \"Autonomous\": \"true\"");
	prefix_flags_expect(vm, ucv_string_new("Child"),
		"\"Origin\": \"Child\", \"StaticType\": \"Inapplicable\", "
		"\"OnLink\": \"true\", \"Autonomous\": \"true\"");
	prefix_flags_expect(vm, ucv_string_new("Static"),
		"\"Origin\": \"Static\", \"StaticType\": \"Static\", "
		"\"OnLink\": \"false\", \"Autonomous\": \"false\"");

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_ipv6_prefix_to_object, 1,
		      vm_json(vm, "{ \"address\": \"2001:db8:2::\", \"mask\": 56, "
				  "\"preferred\": 0, \"valid\": 600 }"));
	t1 = time(NULL);
	field_expect(res, "PrefixStatus", "Deprecated");
	field_expect(res, "Prefix", "2001:db8:2::/56");
	lifetime_expect(res, "PreferredLifetime", t0, t1, 0);
	lifetime_expect(res, "ValidLifetime", t0, t1, 600);
	ucv_put(res);

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_ipv6_prefix_to_object, 1,
		      vm_json(vm, "{ \"address\": \"2001:db8:3::\", \"mask\": 64, "
				  "\"preferred\": 1800, \"valid\": 0 }"));
	t1 = time(NULL);
	field_expect(res, "PrefixStatus", "Invalid");
	field_expect(res, "Prefix", "2001:db8:3::/64");
	lifetime_expect(res, "PreferredLifetime", t0, t1, 1800);
	lifetime_expect(res, "ValidLifetime", t0, t1, 0);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_prefix_to_object, 1, vm_json(vm, "[ ]"));
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_ipv6_prefix_to_object, 0);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_ip_to_int),
		cmocka_unit_test(test_int_to_ip),
		cmocka_unit_test(test_cidr_to_netmask),
		cmocka_unit_test(test_netmask_to_cidr),
		cmocka_unit_test(test_ipv4_parse),
		cmocka_unit_test(test_ip_prefix_match),
		cmocka_unit_test(test_ipv4_addr_to_object),
		cmocka_unit_test(test_ipv6_addr_to_object),
		cmocka_unit_test(test_ipv6_prefix_to_object),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
