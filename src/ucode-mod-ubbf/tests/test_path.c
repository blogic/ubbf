/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "harness.h"
#include "ubbf.h"

static void
test_path_split(void **state)
{
	char buf[64], *parts[8];

	(void)state;

	strcpy(buf, ".Device.IP.Interface.1.");
	assert_int_equal(path_split(buf, parts, 8, 0), 4);
	assert_string_equal(parts[0], "Device");
	assert_string_equal(parts[3], "1");

	strcpy(buf, "Device");
	assert_int_equal(path_split(buf, parts, 8, 0), 1);

	strcpy(buf, "a.b");
	assert_int_equal(path_split(buf, parts, 2, 0), 2);
	assert_string_equal(parts[1], "b");

	strcpy(buf, "");
	assert_int_equal(path_split(buf, parts, 8, 0), 0);

	strcpy(buf, ".");
	assert_int_equal(path_split(buf, parts, 8, 0), 0);
}

static void
test_path_split_invalid(void **state)
{
	static const char *const invalid[] = {
		"Device..IP", "Device.IP..", "..Device", "...", "a.b.c.d",
	};
	char buf[64], *parts[8];

	(void)state;

	for (size_t i = 0; i < ARRAY_SIZE(invalid); i++) {
		strcpy(buf, invalid[i]);
		assert_int_equal(path_split(buf, parts, 3, 0), -1);
	}
}

static void
test_path_split_keep_empty(void **state)
{
	char buf[64], *parts[8];

	(void)state;

	strcpy(buf, "Device..m");
	assert_int_equal(path_split(buf, parts, 8, PATH_SPLIT_KEEP_EMPTY), 3);
	assert_string_equal(parts[0], "Device");
	assert_string_equal(parts[1], "");
	assert_string_equal(parts[2], "m");

	strcpy(buf, ".Device.");
	assert_int_equal(path_split(buf, parts, 8, PATH_SPLIT_KEEP_EMPTY), 3);
	assert_string_equal(parts[0], "");
	assert_string_equal(parts[1], "Device");
	assert_string_equal(parts[2], "");

	strcpy(buf, "");
	assert_int_equal(path_split(buf, parts, 8, PATH_SPLIT_KEEP_EMPTY), 1);
	assert_string_equal(parts[0], "");

	strcpy(buf, "a.b.c");
	assert_int_equal(path_split(buf, parts, 2, PATH_SPLIT_KEEP_EMPTY), -1);
}

/* 70 segments of "Segment", 559 bytes: above PATH_PARTS_MAX and 512 */
static char *
long_path_new(void)
{
	char *path = xalloc(70 * 8);

	for (int i = 0; i < 70; i++)
		strcat(strcat(path, i ? "." : ""), "Segment");

	return path;
}

static void
test_path_split_long(void **state)
{
	char *path = long_path_new(), *parts[PATH_PARTS_MAX];

	(void)state;

	assert_int_equal(strlen(path), 559);
	assert_int_equal(path_split(path, parts, PATH_PARTS_MAX, 0), -1);
	free(path);
}

static void
test_pattern_parts_match(void **state)
{
	char *pat[] = { "Device", "X", "{i}", "Y", "{i}" };
	char *num[] = { "Device", "X", "3", "Y", "12" };
	char *named[] = { "Device", "X", "lan", "Y", "12" };
	char *other[] = { "Device", "Z", "3", "Y", "12" };
	char *sign[] = { "Device", "X", "3", "Y", "" };
	int64_t inst = -1;

	(void)state;

	assert_true(pattern_parts_match(pat, num, 5, true, &inst));
	assert_int_equal(inst, 12);

	inst = -1;
	assert_true(pattern_parts_match(pat, num, 2, true, &inst));
	assert_int_equal(inst, 0);

	assert_true(pattern_parts_match(pat, named, 5, false, NULL));
	assert_false(pattern_parts_match(pat, named, 5, true, &inst));
	assert_false(pattern_parts_match(pat, other, 5, false, NULL));
	assert_false(pattern_parts_match(pat, sign, 5, true, NULL));
	assert_true(pattern_parts_match(pat, other, 0, true, NULL));
}

static void
test_path_join(void **state)
{
	char *parts[] = { "Device", "IP", "Interface", "1" };
	char *path, *long_parts[70];

	(void)state;

	path = path_join(parts, 0, 4);
	assert_string_equal(path, "Device.IP.Interface.1");
	free(path);

	path = path_join(parts, 1, 3);
	assert_string_equal(path, "IP.Interface");
	free(path);

	path = path_join(parts, 2, 2);
	assert_string_equal(path, "");
	free(path);

	for (int i = 0; i < 70; i++)
		long_parts[i] = "Segment";

	path = path_join(long_parts, 0, 70);
	assert_int_equal(strlen(path), 559);
	assert_string_equal(path + 551, ".Segment");
	free(path);
}

static void
test_path_parts_new(void **state)
{
	uc_vm_t *vm = *state;
	char *path = long_path_new();
	uc_value_t *arr;

	arr = path_parts_new(vm, path);
	assert_int_equal(ucv_array_length(arr), 70);
	ucv_put(arr);
	free(path);

	arr = path_parts_new(vm, "Device.IP.");
	assert_json_equal(vm, arr, "[ \"Device\", \"IP\" ]");
	ucv_put(arr);

	assert_null(path_parts_new(vm, "Device..IP"));
}

static void
test_key_is_instance(void **state)
{
	(void)state;

	assert_true(key_is_instance("1"));
	assert_true(key_is_instance("2147483647"));
	assert_false(key_is_instance("0"));
	assert_false(key_is_instance("-1"));
	assert_false(key_is_instance(" 1"));
	assert_false(key_is_instance("1a"));
	assert_false(key_is_instance("2147483648"));
	assert_false(key_is_instance("Alias"));
	assert_false(key_is_instance(NULL));
}

static void
test_count_instance_keys(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *obj = vm_json(vm, "{ \"1\": {}, \"3\": {}, \"Alias\": \"x\", \"0\": {} }");

	assert_int_equal(instance_keys_count(obj), 2);
	assert_int_equal(instance_keys_count(NULL), 0);
	ucv_put(obj);
}

static void
test_navigate_by_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *root = vm_json(vm, "{ \"Device\": { \"IP\": { \"Interface\": { \"2\": { \"Name\": \"lan\" } } } } }");

	assert_json_equal(vm, navigate_by_path(vm, root, "Device.IP.Interface.2"), "{ \"Name\": \"lan\" }");
	assert_null(navigate_by_path(vm, root, "Device.IP.Interface.3"));
	assert_null(navigate_by_path(vm, root, "Device.IP.Interface.2.Name.x"));
	assert_null(navigate_by_path(vm, root, ""));
	assert_json_equal(vm, navigate_by_path(vm, root, "Device.IP.Interface.2."), "{ \"Name\": \"lan\" }");
	assert_null(navigate_by_path(vm, root, "Device..IP"));
	assert_null(navigate_by_path(vm, root, "Device.IP.Interface.2.."));
	ucv_put(root);
}

static void
test_path_to_parts(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_path_to_parts, 1, ucv_string_new("Device.WiFi.SSID.1."));
	assert_json_equal(vm, res, "[ \"Device\", \"WiFi\", \"SSID\", \"1\" ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_path_to_parts, 1, ucv_int64_new(5));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_path_to_parts, 1, ucv_string_new("Device..WiFi"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

static void
test_to_int(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_to_int, 1, ucv_string_new("-12"));
	assert_int_equal(ucv_int64_get(res), -12);
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_to_int, 1, ucv_int64_new(7));
	assert_int_equal(ucv_int64_get(res), 7);
	ucv_put(res);

	assert_null(vm_call(vm, uc_ubbf_to_int, 1, ucv_string_new("12x")));
	assert_null(vm_call(vm, uc_ubbf_to_int, 1, ucv_string_new("")));
	assert_null(vm_call(vm, uc_ubbf_to_int, 0));
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_path_split),
		cmocka_unit_test(test_path_split_invalid),
		cmocka_unit_test(test_path_split_keep_empty),
		cmocka_unit_test(test_path_split_long),
		cmocka_unit_test(test_pattern_parts_match),
		cmocka_unit_test(test_path_join),
		cmocka_unit_test(test_path_parts_new),
		cmocka_unit_test(test_key_is_instance),
		cmocka_unit_test(test_count_instance_keys),
		cmocka_unit_test(test_navigate_by_path),
		cmocka_unit_test(test_path_to_parts),
		cmocka_unit_test(test_to_int),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
