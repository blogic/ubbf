/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * string.c: name_sanitise(), uci_value_sanitise(), shell_escape(),
 * transfer_url_validate() and alias_from_name(), with the C function
 * alias_from_name() of util.c behind it, and the C function
 * str_to_upper().
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
test_name_sanitise(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("lan_1")), "lan_1");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("AZaz09_")), "AZaz09_");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("wan-6 rd.x")), "wan_6_rd_x");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("a'b;c\nd")), "a_b_c_d");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("h\xc3\xa9")), "h__");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new_length("a\0b", 3)), "a_b");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_string_new("")), "");
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, ucv_int64_new(5)), NULL);
	string_expect(vm_call(vm, uc_ubbf_name_sanitise, 1, NULL), NULL);
}

static void
test_uci_value_sanitise(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *obj, *res;

	string_expect(vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_string_new("plain value")),
		      "plain value");
	string_expect(vm_call(vm, uc_ubbf_uci_value_sanitise, 1,
			      ucv_string_new("a\nset x.y=z\r\tb\x01" "c\x1f" "d\x7f" "e")),
		      "aset x.y=zbcde");
	string_expect(vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_string_new(" ~h\xc3\xa9\xff")),
		      " ~h\xc3\xa9\xff");
	string_expect(vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_string_new("\n\t")), "");
	string_expect(vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_string_new("")), "");

	res = vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_int64_new(42));
	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), 42);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_boolean_new(true));
	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	obj = vm_json(vm, "{ \"a\": \"x\\ny\" }");
	res = vm_call(vm, uc_ubbf_uci_value_sanitise, 1, ucv_get(obj));
	assert_ptr_equal(res, obj);
	assert_json_equal(vm, res, "{ \"a\": \"x\\ny\" }");
	ucv_put(res);
	ucv_put(obj);

	assert_null(vm_call(vm, uc_ubbf_uci_value_sanitise, 1, NULL));
	assert_null(vm_call(vm, uc_ubbf_uci_value_sanitise, 0));
}

static void
test_shell_escape(void **state)
{
	uc_vm_t *vm = *state;

	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("abc")), "'abc'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("it's")), "'it'\\''s'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("''")),
		      "''\\'''\\'''");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("$(rm -rf /) `x` \"y\" \\z;&|")),
		      "'$(rm -rf /) `x` \"y\" \\z;&|'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("a\nb")), "'a\nb'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_string_new("")), "''");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_int64_new(-5)), "'-5'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_double_new(1.5)), "'1.5'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, ucv_boolean_new(false)), "'false'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, vm_json(vm, "{ \"k\": \"it's\" }")),
		      "'{ \"k\": \"it'\\''s\" }'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, vm_json(vm, "[ 1, \"a\" ]")),
		      "'[ 1, \"a\" ]'");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 1, NULL), "''");
	string_expect(vm_call(vm, uc_ubbf_shell_escape, 0), "''");
}

static void
url_expect(uc_vm_t *vm, uc_value_t *url, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_transfer_url_validate, 1, url);

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_transfer_url_validate(void **state)
{
	uc_vm_t *vm = *state;

	url_expect(vm, ucv_string_new("http://192.168.1.10/fw.bin"), true);
	url_expect(vm, ucv_string_new("https://acs.example.com:8443/upload"), true);
	url_expect(vm, ucv_string_new("ftp://user:pw@host/file"), true);
	url_expect(vm, ucv_string_new("ftps://host/file"), true);
	url_expect(vm, ucv_string_new("http://"), true);
	url_expect(vm, ucv_string_new("ftps://"), true);
	url_expect(vm, ucv_string_new("file:///etc/shadow"), false);
	url_expect(vm, ucv_string_new("tftp://host/file"), false);
	url_expect(vm, ucv_string_new("httpx://host"), false);
	url_expect(vm, ucv_string_new("http:/host"), false);
	url_expect(vm, ucv_string_new("http:"), false);
	url_expect(vm, ucv_string_new("https:/"), false);
	url_expect(vm, ucv_string_new(" http://host"), false);
	url_expect(vm, ucv_string_new("host/http://x"), false);
	url_expect(vm, ucv_string_new(""), false);
	url_expect(vm, ucv_int64_new(1), false);
	url_expect(vm, NULL, false);
}

static void
test_alias_from_name(void **state)
{
	uc_vm_t *vm = *state;
	char long_name[101], expected[65];
	uc_value_t *res;

	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new("lan")), "cpe-lan");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new("Guest_Net-2")),
		      "cpe-Guest_Net-2");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new("my wifi.5g!")),
		      "cpe-my_wifi_5g_");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new("caf\xc3\xa9")),
		      "cpe-caf__");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new("")), "");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_int64_new(5)), "");
	string_expect(vm_call(vm, uc_ubbf_alias_from_name, 1, NULL), "");

	/* TR-181 Alias is string(:64), so 60 name characters fit after "cpe-" */
	memset(long_name, 'n', 100);
	long_name[100] = '\0';
	memcpy(expected, "cpe-", 4);
	memset(expected + 4, 'n', 60);
	expected[64] = '\0';

	res = vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new(long_name));
	assert_int_equal(ucv_string_length(res), 64);
	assert_string_equal(ucv_string_get(res), expected);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_alias_from_name, 1, ucv_string_new(expected + 4));
	assert_string_equal(ucv_string_get(res), expected);
	ucv_put(res);
}

static void
test_alias_from_name_buf(void **state)
{
	char buf[16];

	(void)state;

	memset(buf, 'x', sizeof(buf));
	alias_from_name("lan", buf, 0);
	assert_int_equal(buf[0], 'x');

	alias_from_name("lan", buf, 4);
	assert_string_equal(buf, "");

	alias_from_name("lan", buf, 5);
	assert_string_equal(buf, "cpe-");

	alias_from_name("lan", buf, 6);
	assert_string_equal(buf, "cpe-l");

	alias_from_name("lan", buf, 8);
	assert_string_equal(buf, "cpe-lan");

	alias_from_name("a b", buf, sizeof(buf));
	assert_string_equal(buf, "cpe-a_b");

	memset(buf, 'x', sizeof(buf));
	alias_from_name(NULL, buf, sizeof(buf));
	assert_string_equal(buf, "");

	memset(buf, 'x', sizeof(buf));
	alias_from_name("", buf, sizeof(buf));
	assert_string_equal(buf, "");
}

static void
test_str_to_upper(void **state)
{
	char mac[] = "02:ab:cd:ef:0a:9f";
	char other[] = "az AZ 09 @[`{ \xc3\xa4";
	char empty[] = "";

	(void)state;

	str_to_upper(mac);
	assert_string_equal(mac, "02:AB:CD:EF:0A:9F");

	str_to_upper(other);
	assert_string_equal(other, "AZ AZ 09 @[`{ \xc3\xa4");

	str_to_upper(empty);
	assert_string_equal(empty, "");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_name_sanitise),
		cmocka_unit_test(test_uci_value_sanitise),
		cmocka_unit_test(test_shell_escape),
		cmocka_unit_test(test_transfer_url_validate),
		cmocka_unit_test(test_alias_from_name),
		cmocka_unit_test(test_alias_from_name_buf),
		cmocka_unit_test(test_str_to_upper),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
