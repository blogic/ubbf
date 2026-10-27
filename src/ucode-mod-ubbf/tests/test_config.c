/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * config.c, spawn_output() in proc.c and ethernet_interface_path() in
 * tree.c.
 */

#include "harness.h"
#include "ubbf.h"

#include <sys/stat.h>

static void
path_check_expect(uc_vm_t *vm, const char *path, const char *reason)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_config_path_check, 1,
				  path ? ucv_string_new(path) : NULL);

	if (reason)
		assert_string_equal(ucv_string_get(res), reason);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_config_path_check(void **state)
{
	const char *absolute = "file path must be absolute";
	const char *dots = "file path must not contain . or ..";
	uc_vm_t *vm = *state;

	path_check_expect(vm, NULL, absolute);
	path_check_expect(vm, "", absolute);
	path_check_expect(vm, "tmp/a.json", absolute);
	path_check_expect(vm, "/", NULL);
	path_check_expect(vm, "/tmp/a.json", NULL);
	path_check_expect(vm, "/tmp//a.json/", NULL);
	path_check_expect(vm, "/tmp/.a/..b/a..", NULL);
	path_check_expect(vm, "/tmp/../etc/shadow", dots);
	path_check_expect(vm, "/tmp/./a", dots);
	path_check_expect(vm, "/tmp/..", dots);
	path_check_expect(vm, "/.", dots);
}

static void
test_spawn_output(void **state)
{
	char *ok[] = { "/bin/sh", "-c", "echo out; echo err >&2; exit 3", NULL };
	char *missing[] = { "/nonexistent/ubbf-test", NULL };
	char *sig[] = { "/bin/sh", "-c", "kill -9 $$", NULL };
	char *out;
	int status;

	(void)state;

	out = spawn_output(ok, &status);
	assert_string_equal(out, "out\nerr\n");
	assert_int_equal(status, 3);
	free(out);

	assert_null(spawn_output(missing, &status));
	assert_int_equal(status, -1);

	out = spawn_output(sig, &status);
	assert_string_equal(out, "");
	assert_int_equal(status, -1);
	free(out);
}

static void
test_spawn_output_large(void **state)
{
	char *argv[] = { "/bin/sh", "-c", "head -c 100000 /dev/zero | tr '\\0' x", NULL };
	char *out;
	int status;

	(void)state;

	out = spawn_output(argv, &status);
	assert_int_equal(status, 0);
	assert_int_equal(strlen(out), 100000);
	assert_int_equal(strspn(out, "x"), 100000);
	free(out);
}

static void
test_spawn_output_signals(void **state)
{
	char *argv[] = { "/bin/grep", "-E", "^Sig(Blk|Ign)", "/proc/self/status", NULL };
	struct sigaction ign = { .sa_handler = SIG_IGN }, old_act;
	unsigned long long blk = ~0ULL, ignored = ~0ULL;
	sigset_t block, old_mask;
	char *out;
	int status;

	(void)state;

	sigemptyset(&block);
	sigaddset(&block, SIGUSR1);
	assert_int_equal(sigprocmask(SIG_BLOCK, &block, &old_mask), 0);
	assert_int_equal(sigaction(SIGUSR2, &ign, &old_act), 0);

	out = spawn_output(argv, &status);

	assert_int_equal(sigaction(SIGUSR2, &old_act, NULL), 0);
	assert_int_equal(sigprocmask(SIG_SETMASK, &old_mask, NULL), 0);

	assert_int_equal(status, 0);
	assert_int_equal(sscanf(out, "SigBlk: %llx SigIgn: %llx", &blk, &ignored), 2);
	free(out);

	/* the standard signals only, as in test_module_spawn() of test_proc.c */
	assert_int_equal(blk & 0x7fffffffULL, 0);
	assert_int_equal(ignored & 0x7fffffffULL, 0);
}

static void
test_config_validate_no_apply(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	struct stat st;

	if (stat("/usr/libexec/ubbf/apply", &st) == 0)
		skip();

	res = vm_call(vm, uc_ubbf_config_validate, 1, ucv_string_new("/tmp/x.json"));
	assert_json_equal(vm, res,
		"{ \"success\": false, \"output\": \"Failed to execute ubbf-apply\" }");
	ucv_put(res);
}

static void
test_config_restore(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_eval(vm,
		"ubbf.config_restore_hook_set(null);"
		"return ubbf.config_restore('/x', null);");
	assert_json_equal(vm, res,
		"{ \"success\": false, \"error\": \"No data model to restore into\" }");
	ucv_put(res);

	res = vm_eval(vm,
		"ubbf.config_restore_hook_set((path, done) => ({ path, done: done() }));"
		"return ubbf.config_restore('/x', () => 7);");
	assert_json_equal(vm, res, "{ \"path\": \"/x\", \"done\": 7 }");
	ucv_put(res);

	res = vm_eval(vm,
		"ubbf.config_restore_hook_set((path, done) => null);"
		"return ubbf.config_restore('/x', () => 7);");
	assert_null(res);

	res = vm_eval(vm,
		"ubbf.config_restore_hook_set((path, done) => die('broken'));"
		"try { ubbf.config_restore('/x', null); } catch (e) { return e.message; }");
	assert_string_equal(ucv_string_get(res), "broken");
	ucv_put(res);

	ucv_put(vm_eval(vm, "ubbf.config_restore_hook_set(null);"));
}

static void
ethernet_path_expect(uc_vm_t *vm, uc_value_t *root, uc_value_t *netdev,
		     const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_ethernet_interface_path, 2,
				  ucv_get(root), netdev);

	assert_string_equal(ucv_string_get(res), expected);
	ucv_put(res);
}

static void
test_ethernet_interface_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *root = vm_json(vm,
		"{ \"Device\": { \"Ethernet\": { \"Interface\": {"
		"  \"Alias\": { \"Name\": \"lan9\" },"
		"  \"1\": { \"Name\": \"lan1\" },"
		"  \"2\": \"lan2\","
		"  \"3\": { \"Name\": 5 },"
		"  \"4\": { \"Name\": \"lan2\" } } } } }");
	uc_value_t *empty = vm_json(vm, "{ \"Device\": {} }");

	ethernet_path_expect(vm, root, ucv_string_new("lan1"), "Device.Ethernet.Interface.1");
	ethernet_path_expect(vm, root, ucv_string_new("lan2"), "Device.Ethernet.Interface.4");
	ethernet_path_expect(vm, root, ucv_string_new("lan9"), "");
	ethernet_path_expect(vm, root, ucv_string_new("5"), "");
	ethernet_path_expect(vm, root, ucv_string_new(""), "");
	ethernet_path_expect(vm, root, NULL, "");
	ethernet_path_expect(vm, empty, ucv_string_new("lan1"), "");
	ethernet_path_expect(vm, NULL, ucv_string_new("lan1"), "");

	ucv_put(root);
	ucv_put(empty);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_config_path_check),
		cmocka_unit_test(test_spawn_output),
		cmocka_unit_test(test_spawn_output_large),
		cmocka_unit_test(test_spawn_output_signals),
		cmocka_unit_test(test_config_validate_no_apply),
		cmocka_unit_test(test_config_restore),
		cmocka_unit_test(test_ethernet_interface_path),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
