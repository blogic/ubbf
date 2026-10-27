/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * instance.c: the instance key checks, the instance counts, the next free
 * instance, the pattern expansion, the NumberOfEntries update, and
 * enumerate_instances() and get_by_instance(); pattern_matches_path(),
 * tr181_ref_parse() and tr181_ref_instance() of path.c.
 */

#include "harness.h"
#include "ubbf.h"

static void
bool_expect(uc_vm_t *vm, uc_cfn_ptr_t fn, uc_value_t *a, uc_value_t *b, bool expected)
{
	uc_value_t *res = vm_call(vm, fn, 2, a, b);

	assert_int_equal(ucv_type(res), UC_BOOLEAN);
	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_is_instance_key(void **state)
{
	uc_vm_t *vm = *state;

	bool_expect(vm, uc_ubbf_is_instance_key, ucv_int64_new(1), NULL, true);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_int64_new(4096), NULL, true);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_int64_new(0), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_int64_new(-3), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("7"), NULL, true);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("0"), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new(""), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("+1"), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("01"), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("1.5"), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_string_new("Alias"), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_double_new(1.0), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, ucv_boolean_new(true), NULL, false);
	bool_expect(vm, uc_ubbf_is_instance_key, NULL, NULL, false);
}

static void
count_expect(uc_vm_t *vm, uc_value_t *obj, int64_t expected)
{
	uc_value_t *res = vm_method(vm, vm_module(vm), "instance_count", 1, obj);

	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
test_instance_count(void **state)
{
	uc_vm_t *vm = *state;

	count_expect(vm, vm_json(vm, "{ \"1\": { }, \"2\": \"x\", \"10\": null, \"Alias\": { }, \"0\": { }, \"-1\": { } }"), 3);
	count_expect(vm, vm_json(vm, "{ }"), 0);
	count_expect(vm, vm_json(vm, "[ 1, 2 ]"), 0);
	count_expect(vm, ucv_string_new("1"), 0);
	count_expect(vm, NULL, 0);
}

static void
next_expect(uc_vm_t *vm, uc_value_t *obj, int64_t expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_find_next_instance, 1, obj);

	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
test_find_next_instance(void **state)
{
	uc_vm_t *vm = *state;

	next_expect(vm, vm_json(vm, "{ }"), 1);
	next_expect(vm, vm_json(vm, "{ \"1\": { }, \"2\": { }, \"4\": { } }"), 3);
	next_expect(vm, vm_json(vm, "{ \"2\": { }, \"3\": { } }"), 1);
	next_expect(vm, vm_json(vm, "{ \"1\": \"x\", \"2\": { }, \"Alias\": { } }"), 3);
	next_expect(vm, vm_json(vm, "{ \"01\": { }, \"02\": { } }"), 1);
	next_expect(vm, vm_json(vm, "[ 1 ]"), 1);
	next_expect(vm, NULL, 1);

	/* a key with a null value is held */
	next_expect(vm, vm_json(vm, "{ \"1\": null, \"2\": { } }"), 3);

	assert_int_equal(instance_next_free(NULL), 1);
}

static void
collect_expect(uc_vm_t *vm, const char *pattern, const char *data, uc_value_t *idx,
	       uc_value_t *path, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_collect_instances_for_pattern, 4,
				  pattern ? vm_json(vm, pattern) : NULL,
				  data ? vm_json(vm, data) : NULL, idx, path);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static const char tree_json[] =
	"{ \"Device\": { \"IP\": { \"Interface\": {"
	"  \"1\": { \"Name\": \"lan\", \"IPv4Address\": { \"1\": { }, \"2\": { } } },"
	"  \"Alias\": { \"IPv4Address\": { \"5\": { } } },"
	"  \"3\": { \"Name\": \"wan\", \"IPv4Address\": { } },"
	"  \"4\": \"broken\" } } } }";

static void
test_collect_instances_for_pattern(void **state)
{
	uc_vm_t *vm = *state;

	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\" ]", tree_json, NULL, NULL,
		       "[ \"Device.IP.Interface.1\", \"Device.IP.Interface.3\", \"Device.IP.Interface.4\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\", \"IPv4Address\", \"{i}\" ]",
		       tree_json, NULL, NULL,
		       "[ \"Device.IP.Interface.1.IPv4Address.1\", \"Device.IP.Interface.1.IPv4Address.2\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\", \"Stats\" ]", tree_json, NULL, NULL,
		       "[ \"Device.IP.Interface.1.Stats\", \"Device.IP.Interface.3.Stats\", "
		       "\"Device.IP.Interface.4.Stats\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\" ]", tree_json, NULL, NULL,
		       "[ \"Device.IP.Interface\" ]");
	collect_expect(vm, "[ \"Device\", \"DNS\", \"Client\" ]", tree_json, NULL, NULL,
		       "[ \"Device.DNS.Client\" ]");
	collect_expect(vm, "[ \"Device\", \"DNS\", \"Client\", \"Server\", \"{i}\" ]", tree_json, NULL, NULL,
		       "[ ]");
	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\", \"Name\", \"X\" ]", tree_json,
		       NULL, NULL,
		       "[ \"Device.IP.Interface.1.Name.X\", \"Device.IP.Interface.3.Name.X\", "
		       "\"Device.IP.Interface.4.Name.X\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\", \"Name\", \"{i}\" ]", tree_json,
		       NULL, NULL, "[ ]");
	collect_expect(vm, "[ \"{i}\" ]", "{ \"2\": 5, \"x\": { }, \"1\": { } }", NULL, NULL,
		       "[ \"2\", \"1\" ]");
	collect_expect(vm, "[ \"{i}\" ]", "[ 1 ]", NULL, NULL, "[ ]");
	collect_expect(vm, "[ \"A\", \"B\" ]", "\"leaf\"", NULL, NULL, "[ \"A.B\" ]");
	collect_expect(vm, "[ \"A\", \"{i}\" ]", "\"leaf\"", NULL, NULL, "[ ]");
	collect_expect(vm, "[ \"A\", 5, \"B\" ]", "{ \"A\": { } }", NULL, NULL, "[ ]");
	collect_expect(vm, "[ ]", "{ }", NULL, NULL, "[ \"\" ]");

	collect_expect(vm, "[ \"Device\", \"IP\", \"Interface\", \"{i}\", \"IPv4Address\", \"{i}\" ]",
		       "{ \"Interface\": { \"3\": { \"IPv4Address\": { \"9\": { } } } } }",
		       ucv_int64_new(2), ucv_string_new("Device.IP"),
		       "[ \"Device.IP.Interface.3.IPv4Address.9\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\" ]", "{ }", ucv_int64_new(7), ucv_string_new("Device.X"),
		       "[ \"Device.X\" ]");
	collect_expect(vm, "[ \"Device\", \"IP\" ]", "{ }", ucv_string_new("1"), ucv_int64_new(5),
		       "[ \"Device.IP\" ]");

	collect_expect(vm, NULL, tree_json, NULL, NULL, "[ ]");
	collect_expect(vm, "{ \"0\": \"Device\" }", tree_json, NULL, NULL, "[ ]");
}

static void
test_do_collect_instances(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *result = ucv_array_new(vm);
	uc_value_t *parts = vm_json(vm, "[ \"Device\", \"Hosts\", \"Host\", \"{i}\" ]");
	uc_value_t *data = vm_json(vm, "{ \"Hosts\": { \"Host\": { \"2\": { }, \"7\": { } } } }");

	instances_collect(result, parts, data, 1, "Device", vm);
	instances_collect(result, parts, NULL, 3, "Device.Hosts.Host", vm);
	assert_json_equal(vm, result, "[ \"Device.Hosts.Host.2\", \"Device.Hosts.Host.7\" ]");

	ucv_put(result);
	ucv_put(parts);
	ucv_put(data);
}

#define LONG_SEGMENT	"Segment_with_a_long_name_000"

/*
 * Pattern [ Device, 20 x LONG_SEGMENT, {i}, Stats, Leaf ] over a tree with
 * row 3, whose Stats object is missing: 599 bytes for the singleton path
 * of the row.
 */
static void
test_collect_instances_long_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *parts = ucv_array_new(vm), *data = ucv_object_new(vm);
	uc_value_t *node = data, *child, *result;
	char *expected = xstrdup("Device"), *next;

	ucv_array_push(parts, ucv_string_new("Device"));
	child = ucv_object_new(vm);
	ucv_object_add(node, "Device", child);
	node = child;

	for (int i = 0; i < 20; i++) {
		ucv_array_push(parts, ucv_string_new(LONG_SEGMENT));
		child = ucv_object_new(vm);
		ucv_object_add(node, LONG_SEGMENT, child);
		node = child;

		xasprintf(&next, "%s." LONG_SEGMENT, expected);
		free(expected);
		expected = next;
	}

	ucv_array_push(parts, ucv_string_new("{i}"));
	ucv_array_push(parts, ucv_string_new("Stats"));
	ucv_array_push(parts, ucv_string_new("Leaf"));
	ucv_object_add(node, "3", ucv_object_new(vm));

	xasprintf(&next, "%s.3.Stats.Leaf", expected);
	free(expected);
	expected = next;
	assert_int_equal(strlen(expected), 599);

	result = vm_call(vm, uc_ubbf_collect_instances_for_pattern, 2, ucv_get(parts), ucv_get(data));
	assert_int_equal(ucv_array_length(result), 1);
	child = ucv_array_get(result, 0);
	assert_string_equal(ucv_string_get(child), expected);

	ucv_put(result);
	ucv_put(parts);
	ucv_put(data);
	free(expected);
}

/* A base path of 1100 bytes, above the 1024 of the earlier buffer */
static void
test_find_nested_instances_long_path(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *result = ucv_array_new(vm);
	uc_value_t *data = vm_json(vm, "{ \"T\": { \"1\": { \"Sub\": { \"2\": { } } } } }");
	char *base = xalloc(1101), *expected;
	uc_value_t *last;

	memset(base, 'B', 1100);

	nested_instances_find(result, base, data, vm);
	assert_int_equal(ucv_array_length(result), 2);

	xasprintf(&expected, "%s.T.1.Sub.2", base);
	last = ucv_array_get(result, 1);
	assert_string_equal(ucv_string_get(last), expected);

	ucv_put(result);
	ucv_put(data);
	free(expected);
	free(base);
}

static void
test_do_find_nested_instances(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *result = ucv_array_new(vm);
	uc_value_t *data = vm_json(vm,
		"{ \"Device\": { \"1\": { \"DeviceInformation\": { \"VendorSpecific\": {"
		"    \"1\": { }, \"2\": { \"Sub\": { \"3\": { } } } } } },"
		"  \"2\": \"leaf\", \"Alias\": { \"4\": { } } } }");
	uc_value_t *single = vm_json(vm, "{ \"1\": { } }");
	uc_value_t *last;

	nested_instances_find(result, "Device.LLDP.Discovery", data, vm);
	assert_json_equal(vm, result,
		"[ \"Device.LLDP.Discovery.Device.1\", "
		"\"Device.LLDP.Discovery.Device.1.DeviceInformation.VendorSpecific.1\", "
		"\"Device.LLDP.Discovery.Device.1.DeviceInformation.VendorSpecific.2\", "
		"\"Device.LLDP.Discovery.Device.1.DeviceInformation.VendorSpecific.2.Sub.3\", "
		"\"Device.LLDP.Discovery.Device.Alias.4\" ]");

	nested_instances_find(result, "X", NULL, vm);
	nested_instances_find(result, "X", single, vm);
	assert_int_equal(ucv_array_length(result), 6);
	last = ucv_array_get(result, 5);
	assert_string_equal(ucv_string_get(last), "X.1");

	ucv_put(result);
	ucv_put(data);
	ucv_put(single);
}

static void
test_entries_count_update(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *parent = vm_json(vm, "{ \"HostNumberOfEntries\": \"9\" }");
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_entries_count_update, 3, ucv_get(parent), ucv_string_new("Host"),
		      vm_json(vm, "{ \"1\": { }, \"3\": { }, \"Alias\": { } }"));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_entries_count_update, 3, ucv_get(parent), ucv_string_new("Server"),
		      NULL);
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	assert_json_equal(vm, parent, "{ \"HostNumberOfEntries\": \"2\", \"ServerNumberOfEntries\": \"0\" }");

	assert_null(vm_call(vm, uc_ubbf_entries_count_update, 3, ucv_get(parent), ucv_int64_new(1),
			    vm_json(vm, "{ \"1\": { } }")));
	assert_null(vm_call(vm, uc_ubbf_entries_count_update, 3, vm_json(vm, "[ ]"), ucv_string_new("Host"),
			    vm_json(vm, "{ \"1\": { } }")));
	assert_null(vm_call(vm, uc_ubbf_entries_count_update, 0));
	assert_json_equal(vm, parent, "{ \"HostNumberOfEntries\": \"2\", \"ServerNumberOfEntries\": \"0\" }");

	ucv_put(parent);
}

static uc_value_t *
convert_pair(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pair = ucv_array_new(vm);

	ucv_array_push(pair, ucv_get(uc_fn_arg(0)));
	ucv_array_push(pair, ucv_get(uc_fn_arg(1)));
	ucv_array_push(pair, ucv_int64_new(nargs));

	return pair;
}

static uc_value_t *
convert_fail_odd(uc_vm_t *vm, size_t nargs)
{
	if (ucv_int64_get(uc_fn_arg(1)) % 2) {
		uc_vm_raise_exception(vm, EXCEPTION_USER, "odd item");
		return NULL;
	}

	return ucv_get(uc_fn_arg(0));
}

static void
enumerate_expect(uc_vm_t *vm, uc_value_t *items, uc_value_t *converter, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_enumerate_instances, 2, items, converter);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_enumerate_instances(void **state)
{
	uc_vm_t *vm = *state;

	enumerate_expect(vm, vm_json(vm, "[ \"a\", { \"b\": 1 }, null ]"),
			 ucv_cfunction_new("convert_pair", convert_pair),
			 "{ \"1\": [ \"a\", 0, 2 ], \"2\": [ { \"b\": 1 }, 1, 2 ], \"3\": [ null, 2, 2 ] }");
	enumerate_expect(vm, vm_json(vm, "[ ]"), ucv_cfunction_new("convert_pair", convert_pair), "{ }");
	enumerate_expect(vm, vm_json(vm, "[ \"a\", \"b\", \"c\" ]"),
			 ucv_cfunction_new("convert_fail_odd", convert_fail_odd),
			 "{ \"1\": \"a\", \"3\": \"c\" }");
	enumerate_expect(vm, vm_json(vm, "[ \"a\", \"b\" ]"),
			 ucv_cfunction_new("convert_fail_odd", convert_fail_odd),
			 "{ \"1\": \"a\" }");
	enumerate_expect(vm, vm_json(vm, "{ \"1\": \"a\" }"), ucv_cfunction_new("convert_pair", convert_pair),
			 "{ }");
	enumerate_expect(vm, vm_json(vm, "[ \"a\" ]"), ucv_string_new("convert_pair"), "{ }");
	enumerate_expect(vm, vm_json(vm, "[ \"a\" ]"), NULL, "{ }");
	enumerate_expect(vm, NULL, NULL, "{ }");
}

static void
by_instance_expect(uc_vm_t *vm, uc_value_t *items, uc_value_t *inst, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_get_by_instance, 2, items, inst);

	if (expected)
		assert_json_equal(vm, res, expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_get_by_instance(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *items = vm_json(vm, "[ \"a\", { \"b\": 2 }, \"c\" ]");

	by_instance_expect(vm, ucv_get(items), ucv_int64_new(1), "\"a\"");
	by_instance_expect(vm, ucv_get(items), ucv_int64_new(2), "{ \"b\": 2 }");
	by_instance_expect(vm, ucv_get(items), ucv_int64_new(3), "\"c\"");
	by_instance_expect(vm, ucv_get(items), ucv_int64_new(4), NULL);
	by_instance_expect(vm, ucv_get(items), ucv_int64_new(0), NULL);
	by_instance_expect(vm, ucv_get(items), ucv_int64_new(-1), NULL);
	by_instance_expect(vm, ucv_get(items), ucv_string_new("1"), NULL);
	by_instance_expect(vm, ucv_get(items), ucv_double_new(1.0), NULL);
	by_instance_expect(vm, ucv_get(items), NULL, NULL);
	by_instance_expect(vm, vm_json(vm, "{ \"1\": \"a\" }"), ucv_int64_new(1), NULL);
	by_instance_expect(vm, vm_json(vm, "[ ]"), ucv_int64_new(1), NULL);

	ucv_put(items);
}

static void
test_pattern_matches_path(void **state)
{
	uc_vm_t *vm = *state;
	const char *pattern = "Device.IP.Interface.{i}.IPv4Address.{i}.";

	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern), ucv_string_new(""), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern), ucv_string_new("Device"), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new("Device.X"), ucv_string_new("Device"), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.IP."), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.IP.Interface.3"), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new(".Device.IP.Interface.3.IPv4Address.1."), true);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.IP.Interface.3.IPv4Address.1.IPAddress"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.IP.Interface.3.IPv6Address"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.DNS"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new("Device.IP.Interface.1"),
		    ucv_string_new("Device.IP.Interface.2"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(""),
		    ucv_string_new("Device.IP"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, NULL, ucv_string_new("Device.IP"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern), NULL, false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern), ucv_int64_new(1), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("Device.IP..Interface"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new(pattern),
		    ucv_string_new("..Device.IP"), false);
	bool_expect(vm, uc_ubbf_pattern_matches_path, ucv_string_new("Device..IP.Interface"),
		    ucv_string_new("Device.IP"), false);
}

static void
ref_expect(uc_vm_t *vm, const char *path, const char *prefix, int64_t expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_tr181_ref_parse, 2,
				  path ? ucv_string_new(path) : NULL,
				  prefix ? ucv_string_new(prefix) : NULL);

	if (path && prefix)
		assert_int_equal(tr181_ref_instance(path, prefix), expected > 0 ? expected : -1);

	if (expected > 0) {
		assert_int_equal(ucv_type(res), UC_INTEGER);
		assert_int_equal(ucv_int64_get(res), expected);
	} else {
		assert_null(res);
	}

	ucv_put(res);
}

static void
test_tr181_ref_parse(void **state)
{
	const char *prefix = "Device.IP.Interface";
	uc_vm_t *vm = *state;

	ref_expect(vm, "Device.IP.Interface.3", prefix, 3);
	ref_expect(vm, "Device.IP.Interface.3.", prefix, 3);
	ref_expect(vm, "Device.IP.Interface.2147483647", prefix, 2147483647LL);

	/* the instance part follows the rule of an instance key */
	ref_expect(vm, "Device.IP.Interface.2147483648", prefix, -1);
	ref_expect(vm, "Device.IP.Interface. 3", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.+3", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.03", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.99999999999999999999999", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.3.Name", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.3..", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.3x", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.0", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.-2", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.x", prefix, -1);
	ref_expect(vm, "Device.IP.Interface..", prefix, -1);
	ref_expect(vm, "Device.IP.Interface.", prefix, -1);
	ref_expect(vm, "Device.IP.Interface", prefix, -1);
	ref_expect(vm, "Device.IP.InterfaceX3", prefix, -1);
	ref_expect(vm, "Device.IP.Interfaces.3", prefix, -1);
	ref_expect(vm, "Device.PPP.Interface.3", prefix, -1);
	ref_expect(vm, "", prefix, -1);
	ref_expect(vm, "1", "", -1);
	ref_expect(vm, ".1", "", 1);
	ref_expect(vm, NULL, prefix, -1);
	ref_expect(vm, "Device.IP.Interface.3", NULL, -1);
	assert_null(vm_call(vm, uc_ubbf_tr181_ref_parse, 2, ucv_int64_new(3), ucv_string_new(prefix)));
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_is_instance_key),
		cmocka_unit_test(test_instance_count),
		cmocka_unit_test(test_find_next_instance),
		cmocka_unit_test(test_collect_instances_for_pattern),
		cmocka_unit_test(test_do_collect_instances),
		cmocka_unit_test(test_do_find_nested_instances),
		cmocka_unit_test(test_collect_instances_long_path),
		cmocka_unit_test(test_find_nested_instances_long_path),
		cmocka_unit_test(test_entries_count_update),
		cmocka_unit_test(test_enumerate_instances),
		cmocka_unit_test(test_get_by_instance),
		cmocka_unit_test(test_pattern_matches_path),
		cmocka_unit_test(test_tr181_ref_parse),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
