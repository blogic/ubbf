/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * acl.c. Runs isolated (run-isolated.sh): the load case writes a role
 * ACL file to /etc/ubbf/acl, a tmpfs there.
 */

#include "harness.h"
#include "ubbf.h"

#include <stdio.h>
#include <sys/stat.h>

static const char ACL[] =
	"{ \"methods\": [ \"get\", \"set\" ], \"diagnostics\": [ \"IPPing\" ],"
	"  \"read\": {"
	"    \"Device.DeviceInfo\": true,"
	"    \"Device.Hosts.Host.*\": [ \"PhysAddress\", \"HostName\" ],"
	"    \"Device.WiFi.SSID.*\": { \"properties\": [ \"SSID\", \"Enable\" ], \"filter\": { \"Guest\": \"true\" } },"
	"    \"Device.WiFi.SSID.1\": true,"
	"    \"Device.Off\": false"
	"  },"
	"  \"write\": {"
	"    \"Device.Users.User.*\": true,"
	"    \"Device.WiFi.SSID.*\": { \"properties\": [ \"SSID\" ], \"filter\": { \"Guest\": \"true\" } },"
	"    \"Device.Hosts.Host.*\": [ \"HostName\" ],"
	"    \"Device.NAT.PortMapping.1\": true"
	"  } }";

static const char TREE[] =
	"{ \"Device\": { \"WiFi\": { \"SSID\": {"
	"  \"1\": { \"SSID\": \"main\", \"Enable\": \"1\", \"Guest\": \"false\", \"Key\": \"k\" },"
	"  \"2\": { \"SSID\": \"guest\", \"Enable\": \"1\", \"Guest\": \"true\", \"Key\": \"k\" },"
	"  \"3\": { \"SSID\": \"other\", \"Guest\": \"false\" } } } } }";

static bool
check(uc_vm_t *vm, uc_cfn_ptr_t fn, const char *path, bool with_tree)
{
	uc_value_t *res = vm_call(vm, fn, 3, vm_json(vm, ACL), ucv_string_new(path),
				  with_tree ? vm_json(vm, TREE) : NULL);
	bool b = ucv_boolean_get(res);

	ucv_put(res);

	return b;
}

static void
filter_expect(uc_vm_t *vm, const char *tree, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_acl_filter_tree, 3, vm_json(vm, ACL),
				  vm_json(vm, tree), NULL);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_read(void **state)
{
	uc_vm_t *vm = *state;

	/* a true rule grants the subtree; no rule and a false rule deny */
	filter_expect(vm,
		"{ \"Device\": { \"DeviceInfo\": { \"SerialNumber\": \"s\", \"X\": \"x\" },"
		"  \"Device\": { \"A\": \"a\" }, \"Off\": { \"X\": \"x\" } } }",
		"{ \"Device\": { \"DeviceInfo\": { \"SerialNumber\": \"s\", \"X\": \"x\" } } }");

	/* a property list grants the listed properties of each row */
	filter_expect(vm,
		"{ \"Device\": { \"Hosts\": { \"Host\": { \"4\": { \"HostName\": \"h\", \"IPAddress\": \"i\" } } } } }",
		"{ \"Device\": { \"Hosts\": { \"Host\": { \"4\": { \"HostName\": \"h\" } } } } }");

	/* of two patterns of the same length the first listed wins, so
	 * SSID.1 falls under the filtered SSID.* rule */
	filter_expect(vm, TREE,
		"{ \"Device\": { \"WiFi\": { \"SSID\": { \"2\": { \"SSID\": \"guest\", \"Enable\": \"1\" } } } } }");
}

static void
test_write_and_add(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	assert_true(check(vm, uc_ubbf_acl_can_write, "Device.Users.User.3.Password", false));
	assert_true(check(vm, uc_ubbf_acl_can_write, "Device.WiFi.SSID.2.SSID", true));
	assert_false(check(vm, uc_ubbf_acl_can_write, "Device.WiFi.SSID.2.Enable", true));
	assert_false(check(vm, uc_ubbf_acl_can_write, "Device.WiFi.SSID.1.SSID", true));

	/* a property list does not grant the object itself for a write */
	assert_false(check(vm, uc_ubbf_acl_can_write, "Device.Hosts.Host.4", false));
	assert_true(check(vm, uc_ubbf_acl_can_write, "Device.Hosts.Host.4.HostName", false));
	assert_false(check(vm, uc_ubbf_acl_can_write, "Device.DeviceInfo.X", false));

	/* a path above PATH_PARTS_MAX segments matches no rule */
	char path[256] = "Device.Users.User.3";

	for (int i = 0; i < 60; i++)
		strcat(path, ".P");

	assert_true(check(vm, uc_ubbf_acl_can_write, path, false));
	strcat(path, ".P");
	assert_false(check(vm, uc_ubbf_acl_can_write, path, false));

	/* an add needs the whole instance of any row */
	res = vm_call(vm, uc_ubbf_acl_can_add, 2, vm_json(vm, ACL), ucv_string_new("Device.Users.User"));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_acl_can_add, 2, vm_json(vm, ACL), ucv_string_new("Device.WiFi.SSID"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_acl_can_add, 2, vm_json(vm, ACL), ucv_string_new("Device.NAT.PortMapping"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
}

static void
test_lists(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_acl_can_diagnose, 2, vm_json(vm, ACL), ucv_string_new("TraceRoute"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_acl_can_diagnose, 2, vm_json(vm, ACL), ucv_string_new("IPPing"));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_acl_can_diagnose, 2, NULL, ucv_string_new("IPPing"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
}

static void
test_filter_tree(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *tree = vm_json(vm, TREE);
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_acl_filter_tree, 3, vm_json(vm, ACL),
		      ucv_get(ucv_object_get(ucv_object_get(tree, "Device", NULL), "WiFi", NULL)),
		      ucv_string_new("Device.WiFi"));
	assert_json_equal(vm, res, "{ \"SSID\": { \"2\": { \"SSID\": \"guest\", \"Enable\": \"1\" } } }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_acl_filter_tree, 3, NULL, ucv_get(tree), NULL);
	assert_json_equal(vm, res, "{ }");
	ucv_put(res);

	ucv_put(tree);
}

static void
acl_file_put(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	assert_non_null(f);
	fputs(text, f);
	fclose(f);
}

static void
test_load(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *a, *b;

	assert_int_equal(mkdir("/etc/ubbf/acl", 0755), 0);
	acl_file_put("/etc/ubbf/acl/tester.json", ACL);

	/* the parsed file is kept while the file stays the same */
	a = vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("tester"));
	b = vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("tester"));
	assert_non_null(a);
	assert_ptr_equal(a, b);
	ucv_put(a);
	ucv_put(b);

	/* a rewritten file is read again */
	acl_file_put("/etc/ubbf/acl/tester.json.new", "{ \"methods\": [ \"other\" ] }");
	assert_int_equal(rename("/etc/ubbf/acl/tester.json.new", "/etc/ubbf/acl/tester.json"), 0);
	a = vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("tester"));
	assert_json_equal(vm, a, "{ \"methods\": [ \"other\" ] }");
	ucv_put(a);

	assert_null(vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("nobody")));
	assert_null(vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("../tmp/acl")));
	assert_null(vm_call(vm, uc_ubbf_acl_role_load, 1, ucv_string_new("Admin")));
	assert_null(vm_call(vm, uc_ubbf_acl_role_load, 1,
			    ucv_string_new("abcdefghijabcdefghijabcdefghijabc")));
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_read),
		cmocka_unit_test(test_write_and_add),
		cmocka_unit_test(test_lists),
		cmocka_unit_test(test_filter_tree),
		cmocka_unit_test(test_load),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
