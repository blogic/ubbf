/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "harness.h"
#include "util.h"

#include <string.h>

static void
test_hex_nibble(void **state)
{
	(void)state;

	assert_int_equal(hex_nibble('0'), 0);
	assert_int_equal(hex_nibble('9'), 9);
	assert_int_equal(hex_nibble('a'), 10);
	assert_int_equal(hex_nibble('F'), 15);
	assert_int_equal(hex_nibble('g'), -1);
	assert_int_equal(hex_nibble(':'), -1);
}

static void
test_hex_bytes_parse(void **state)
{
	uint8_t out[6];

	(void)state;

	assert_int_equal(hex_bytes_parse("02:aB:00:ff:10:01", ':', out, 6), 0);
	assert_memory_equal(out, ((uint8_t[]){ 0x02, 0xab, 0x00, 0xff, 0x10, 0x01 }), 6);

	assert_int_equal(hex_bytes_parse("02ab00ff1001", 0, out, 6), 0);
	assert_int_equal(out[1], 0xab);

	assert_int_equal(hex_bytes_parse("02-ab-00-ff-10-01", ':', out, 6), -1);
	assert_int_equal(hex_bytes_parse("02:ab:00:ff:10:01:", ':', out, 6), -1);
	assert_int_equal(hex_bytes_parse("02:ab:00:ff:10", ':', out, 6), -1);
	assert_int_equal(hex_bytes_parse("02:ab:00:ff:10:0", ':', out, 6), -1);
	assert_int_equal(hex_bytes_parse("02:ab:00:fx:10:01", ':', out, 6), -1);
}

static void
test_alias_from_name(void **state)
{
	char buf[65];

	(void)state;

	alias_from_name("lan port_1-a", buf, sizeof(buf));
	assert_string_equal(buf, "cpe-lan_port_1-a");

	alias_from_name("", buf, sizeof(buf));
	assert_string_equal(buf, "");

	alias_from_name(NULL, buf, sizeof(buf));
	assert_string_equal(buf, "");

	alias_from_name("abc", buf, 4);
	assert_string_equal(buf, "");

	alias_from_name("abcdef", buf, 7);
	assert_string_equal(buf, "cpe-ab");
}

static void
test_alias_from_name_length(void **state)
{
	char name[100], buf[65];

	(void)state;

	memset(name, 'x', sizeof(name) - 1);
	name[sizeof(name) - 1] = '\0';

	alias_from_name(name, buf, sizeof(buf));
	assert_int_equal(strlen(buf), 64);
	assert_memory_equal(buf, "cpe-xxxx", 8);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_hex_nibble),
		cmocka_unit_test(test_hex_bytes_parse),
		cmocka_unit_test(test_alias_from_name),
		cmocka_unit_test(test_alias_from_name_length),
	};

	return cmocka_run_group_tests(tests, NULL, NULL);
}
