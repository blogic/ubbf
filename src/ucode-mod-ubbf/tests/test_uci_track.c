/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * uci_track.c, and deviceinfo_get() in sys.c. Runs isolated
 * (run-isolated.sh): the state file lives in /tmp/ubbf.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <sys/stat.h>

#define SHADOW	"/tmp/ubbf/shadow"
#define STATE	"/tmp/ubbf/uci-last-changed.json"

static void
file_put(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	assert_non_null(f);
	fputs(text, f);
	fclose(f);
}

static uc_value_t *
state_read(uc_vm_t *vm)
{
	uc_value_t *state = json_file_load(vm, STATE);

	assert_non_null(state);

	return state;
}

static bool
field_is(uc_value_t *state, const char *name, const char *key, const char *expected)
{
	uc_value_t *val = ucv_object_get(ucv_object_get(state, name, NULL), key, NULL);

	return ucv_type(val) == UC_STRING && !strcmp(ucv_string_get(val), expected);
}

static size_t
field_len(uc_value_t *state, const char *name, const char *key)
{
	return ucv_string_length(ucv_object_get(ucv_object_get(state, name, NULL), key, NULL));
}

static void
test_update(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *st, *res;

	mkdir(SHADOW, 0755);
	mkdir(SHADOW "/sub", 0755);
	file_put(SHADOW "/firewall", "a\n");
	file_put(SHADOW "/network", "bb");

	ucv_put(vm_call(vm, uc_ubbf_uci_change_update, 2,
			ucv_string_new(SHADOW), ucv_string_new(STATE)));

	st = state_read(vm);
	assert_int_equal(ucv_object_length(st), 2);
	assert_true(field_is(st, "firewall", "md5", "60b725f10c9c85c70d97880dfe8191b3"));
	assert_true(field_is(st, "network", "md5", "21ad0bd836b90d08f4cf640b4c298e7c"));
	assert_int_equal(field_len(st, "network", "lastchanged"), 20);
	ucv_put(st);

	/* an unchanged file keeps its time, a changed one gets a new time */
	file_put(STATE,
		"{ \"firewall\": { \"md5\": \"60b725f10c9c85c70d97880dfe8191b3\", \"lastchanged\": \"keep\" },"
		"  \"network\": { \"md5\": \"x\", \"lastchanged\": \"old\" },"
		"  \"gone\": { \"md5\": \"y\", \"lastchanged\": \"old\" } }");
	ucv_put(vm_call(vm, uc_ubbf_uci_change_update, 2,
			ucv_string_new(SHADOW), ucv_string_new(STATE)));

	st = state_read(vm);
	assert_true(field_is(st, "firewall", "lastchanged", "keep"));
	assert_int_equal(field_len(st, "network", "lastchanged"), 20);
	assert_true(field_is(st, "gone", "lastchanged", "old"));
	ucv_put(st);

	res = vm_call(vm, uc_ubbf_uci_last_changed, 1, ucv_string_new("firewall"));
	assert_string_equal(ucv_string_get(res), "keep");
	ucv_put(res);

	assert_null(vm_call(vm, uc_ubbf_uci_last_changed, 1, ucv_string_new("nope")));
	assert_null(vm_call(vm, uc_ubbf_uci_last_changed, 1, NULL));

	/* a state file that is not JSON starts over */
	file_put(STATE, "garbage");
	ucv_put(vm_call(vm, uc_ubbf_uci_change_update, 2,
			ucv_string_new(SHADOW), ucv_string_new(STATE)));
	st = state_read(vm);
	assert_int_equal(ucv_object_length(st), 2);
	ucv_put(st);

	/* a missing directory changes nothing */
	ucv_put(vm_call(vm, uc_ubbf_uci_change_update, 2,
			ucv_string_new("/tmp/ubbf/none"), ucv_string_new("/tmp/ubbf/other.json")));
	assert_null(json_file_load(vm, "/tmp/ubbf/other.json"));
}

static void
test_deviceinfo(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *a, *b;
	struct stat st;

	if (stat("/etc/usp/deviceinfo.json", &st) == 0)
		skip();

	a = vm_call(vm, uc_ubbf_deviceinfo_get, 0);
	b = vm_call(vm, uc_ubbf_deviceinfo_get, 0);
	assert_json_equal(vm, a, "{ }");
	assert_ptr_equal(a, b);
	ucv_put(a);
	ucv_put(b);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_update),
		cmocka_unit_test(test_deviceinfo),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
