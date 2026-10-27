/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The shared helpers: text_clamp() and cmd_build() in string.c,
 * datetime_format() in
 * time.c, upstream_interface_ref(), lower_layers_wifi() and port_snooped()
 * in tree.c, transfer_complete() in protocol.c, and schema_extract() and
 * schema_param_info() for an object schema in schema.c.
 */

#include "harness.h"
#include "ubbf.h"

static void
clamp_expect(uc_vm_t *vm, uc_value_t *val, int64_t max, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_text_clamp, 2, val, ucv_int64_new(max));

	assert_string_equal(ucv_string_get(res), expected);
	ucv_put(res);
}

static void
test_text_clamp(void **state)
{
	uc_vm_t *vm = *state;

	clamp_expect(vm, NULL, 5, "");
	clamp_expect(vm, ucv_int64_new(5), 5, "");
	clamp_expect(vm, ucv_string_new("abc"), 5, "abc");
	clamp_expect(vm, ucv_string_new("abcdef"), 3, "abc");
	clamp_expect(vm, ucv_string_new("a\nb\tc\x7f" "d"), 3, "abc");
	clamp_expect(vm, ucv_string_new("abc"), 0, "");
	clamp_expect(vm, ucv_string_new("abc"), -1, "");
	/* "h\xc3\xa9" is "hé": a cut inside the two-byte sequence drops it */
	clamp_expect(vm, ucv_string_new("h\xc3\xa9llo"), 2, "h");
	clamp_expect(vm, ucv_string_new("h\xc3\xa9llo"), 3, "h\xc3\xa9");
	clamp_expect(vm, ucv_string_new("\xe6\x97\xa5\xe6\x9c\xac"), 5, "\xe6\x97\xa5");
}

static void
cmd_expect(uc_vm_t *vm, const char *parts, const char *expected)
{
	uc_value_t *res = vm_eval(vm, parts);
	uc_value_t *cmd = vm_call(vm, uc_ubbf_cmd_build, 1, res);

	assert_string_equal(ucv_string_get(cmd), expected);
	ucv_put(cmd);
}

static void
test_cmd_build(void **state)
{
	uc_vm_t *vm = *state;

	cmd_expect(vm, "return null;", "");
	cmd_expect(vm, "return [];", "");
	cmd_expect(vm, "return [ null, null ];", "");
	cmd_expect(vm, "return [ 'ls', '-l' ];", "'ls' '-l'");
	cmd_expect(vm, "return [ 'echo', \"it's\", '', '$(x) `y`' ];",
		   "'echo' 'it'\\''s' '' '$(x) `y`'");
	cmd_expect(vm, "return [ 5, 3.7, -2, -0.5, 1e3 ];", "5 3 -2 0 1000");
	cmd_expect(vm, "return [ true, false ];", "'true' 'false'");
	cmd_expect(vm, "return [ 'a', null, { raw: '2>&1' }, { raw: 5 }, 'b' ];",
		   "'a' 2>&1 5 'b'");
	cmd_expect(vm, "return [ { raw: null }, { x: 1 }, [ 1 ] ];",
		   "'{ \"raw\": null }' '{ \"x\": 1 }' '[ 1 ]'");
}

static void
datetime_expect(uc_vm_t *vm, uc_value_t *ts, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_datetime_format, 1, ts);

	if (expected)
		assert_string_equal(ucv_string_get(res), expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_datetime_format(void **state)
{
	uc_vm_t *vm = *state;

	datetime_expect(vm, NULL, "0001-01-01T00:00:00Z");
	datetime_expect(vm, ucv_int64_new(0), "0001-01-01T00:00:00Z");
	datetime_expect(vm, ucv_string_new(""), "0001-01-01T00:00:00Z");
	datetime_expect(vm, ucv_int64_new(1), "1970-01-01T00:00:01Z");
	datetime_expect(vm, ucv_int64_new(1700000000), "2023-11-14T22:13:20Z");
	datetime_expect(vm, ucv_string_new("1700000000"), NULL);
}

static void
upstream_expect(uc_vm_t *vm, const char *root, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_upstream_interface_ref, 1,
				  root ? vm_json(vm, root) : NULL);

	if (expected)
		assert_string_equal(ucv_string_get(res), expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_upstream_interface_ref(void **state)
{
	uc_vm_t *vm = *state;

	upstream_expect(vm, NULL, NULL);
	upstream_expect(vm, "{ }", NULL);
	upstream_expect(vm, "{ \"Device\": { \"IP\": { \"Interface\": { \"1\": { \"Upstream\": \"false\" } } } } }", NULL);
	upstream_expect(vm, "{ \"Device\": { \"IP\": { \"Interface\": { \"1\": { \"Upstream\": \"true\" } } } } }",
			"Device.IP.Interface.1");

	/* xsd:boolean also writes true as "1" and false as "0" */
	upstream_expect(vm, "{ \"Device\": { \"IP\": { \"Interface\": {"
			"  \"1\": { \"Upstream\": \"1\", \"Enable\": \"0\" }, \"2\": { \"Upstream\": \"1\" } } },"
			"  \"NAT\": { \"InterfaceSetting\": { \"1\": { \"Enable\": \"1\","
			"    \"Interface\": \"Device.IP.Interface.2\" } } } } }",
			"Device.IP.Interface.2");

	/* NAT wins over the first upstream interface; a disabled one is skipped */
	upstream_expect(vm,
		"{ \"Device\": { \"IP\": { \"Interface\": {"
		"  \"1\": { \"Upstream\": \"true\", \"Enable\": \"false\" },"
		"  \"2\": { \"Upstream\": \"true\" }, \"3\": { \"Upstream\": \"true\" } } },"
		"  \"NAT\": { \"InterfaceSetting\": { \"1\": { \"Enable\": \"true\","
		"    \"Interface\": \"Device.IP.Interface.3\" } } } } }",
		"Device.IP.Interface.3");

	/* NAT rows that are disabled, malformed or point at nothing do not count */
	upstream_expect(vm,
		"{ \"Device\": { \"IP\": { \"Interface\": {"
		"  \"2\": { \"Upstream\": \"true\", \"Enable\": true }, \"3\": { \"Upstream\": \"true\" } } },"
		"  \"NAT\": { \"InterfaceSetting\": {"
		"    \"1\": { \"Enable\": \"false\", \"Interface\": \"Device.IP.Interface.3\" },"
		"    \"2\": { \"Enable\": \"true\", \"Interface\": \"Device.IP.Interface.3x\" },"
		"    \"3\": { \"Enable\": \"true\", \"Interface\": \"Device.IP.Interface.\" },"
		"    \"4\": { \"Enable\": \"true\", \"Interface\": \"Device.IP.Interface.9\" },"
		"    \"5\": \"broken\" } } } }",
		"Device.IP.Interface.2");
}

static void
wifi_expect(uc_vm_t *vm, uc_value_t *layers, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_lower_layers_wifi, 1, layers);

	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_lower_layers_wifi(void **state)
{
	uc_vm_t *vm = *state;

	wifi_expect(vm, NULL, false);
	wifi_expect(vm, ucv_string_new(""), false);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID.1"), true);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID.1, Device.WiFi.SSID.22"), true);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID.1,-1"), true);
	wifi_expect(vm, ucv_string_new(","), true);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID.1,Device.Ethernet.Interface.1"), false);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID."), false);
	wifi_expect(vm, ucv_string_new("Device.WiFi.SSID.1a"), false);
}

static void
snooped_expect(uc_vm_t *vm, const char *port, bool expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_port_snooped, 1, port ? vm_json(vm, port) : NULL);

	assert_int_equal(ucv_boolean_get(res), expected);
	ucv_put(res);
}

static void
test_port_snooped(void **state)
{
	uc_vm_t *vm = *state;

	snooped_expect(vm, NULL, true);
	snooped_expect(vm, "{ }", true);
	snooped_expect(vm, "{ \"IGMP\": \"true\", \"MLD\": \"1\" }", true);
	snooped_expect(vm, "{ \"IGMP\": true }", true);
	snooped_expect(vm, "{ \"IGMP\": \"false\" }", false);
	snooped_expect(vm, "{ \"MLD\": \"0\" }", false);
	snooped_expect(vm, "{ \"MLD\": false }", false);
	snooped_expect(vm, "{ \"IGMP\": 5 }", false);
}

static void
test_transfer_complete(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_eval(vm,
		"let calls = [];"
		"global.usp_datamodel_event = (path, args) => push(calls, [ path, args ]);"
		"let ctx = { command: 'Device.X.Upload()', transfer_type: 'Upload',"
		"  obj_path: 'Device.X.1', url: 'http://h/f', start_time: 1, instance: 4 };"
		"ctx.complete = function(...args) { push(calls, [ this == ctx, ...args ]); };"
		"ubbf.transfer_complete(ctx, null);"
		"ctx.command_key = 'k';"
		"ubbf.transfer_complete(ctx, 'Upload failed');"
		"for (let c in calls) for (let v in c) if (type(v) == 'object') {"
		"  if (v.CompleteTime) v.CompleteTime = 'now'; }"
		"delete global.usp_datamodel_event;"
		"return calls;");
	assert_json_equal(vm, res,
		"[ [ \"Device.LocalAgent.TransferComplete!\", { \"Command\": \"Device.X.Upload()\", "
		"\"CommandKey\": \"\", \"Requestor\": \"\", \"TransferType\": \"Upload\", "
		"\"Affected\": \"Device.X.1\", \"TransferURL\": \"http://h/f\", "
		"\"StartTime\": \"1970-01-01T00:00:01Z\", \"CompleteTime\": \"now\", "
		"\"FaultCode\": 0, \"FaultString\": \"\" } ], "
		"[ true, 4, 0, null, { \"MaxRetries\": \"0\", \"StartTime\": \"1970-01-01T00:00:01Z\", "
		"\"CompleteTime\": \"now\" } ], "
		"[ \"Device.LocalAgent.TransferComplete!\", { \"Command\": \"Device.X.Upload()\", "
		"\"CommandKey\": \"k\", \"Requestor\": \"\", \"TransferType\": \"Upload\", "
		"\"Affected\": \"Device.X.1\", \"TransferURL\": \"http://h/f\", "
		"\"StartTime\": \"1970-01-01T00:00:01Z\", \"CompleteTime\": \"now\", "
		"\"FaultCode\": 7000, \"FaultString\": \"Upload failed\" } ], "
		"[ true, 4, 7022, \"Upload failed\", { \"MaxRetries\": \"0\", "
		"\"StartTime\": \"1970-01-01T00:00:01Z\", \"CompleteTime\": \"now\" } ] ]");
	ucv_put(res);

	res = vm_eval(vm,
		"try { ubbf.transfer_complete({ complete: () => null }, null); }"
		"catch (e) { return e.message; }");
	assert_string_equal(ucv_string_get(res), "usp_datamodel_event is not a function");
	ucv_put(res);

	res = vm_eval(vm,
		"global.usp_datamodel_event = () => die('event broken');"
		"let done = false;"
		"try { ubbf.transfer_complete({ complete: () => { done = true; } }, null); }"
		"catch (e) { delete global.usp_datamodel_event; return [ e.message, done ]; }");
	assert_json_equal(vm, res, "[ \"event broken\", false ]");
	ucv_put(res);
}

static const char model_json[] =
	"{ \"Device.A\": { \"schema\": { \"schema\": { \"X\": %d, \"Y\": %d,"
	"    \"Go()\": { \"type\": \"command\", \"input\": [ \"a\" ], \"output\": [ \"b\" ] } },"
	"    \"constraints\": { \"X\": { \"max\": 5, \"writable\": false } } } },"
	"  \"Device.B\": { \"schema\": { \"schema\": { \"Ev!\": { \"type\": \"event\", \"input\": [ \"q\" ] },"
	"    \"Ev2!\": { \"type\": \"event\" }, \"Z\": %d } } } }";

static uc_value_t *
model_new(uc_vm_t *vm)
{
	char buf[1024];

	snprintf(buf, sizeof(buf), model_json, DM_STRING | DM_WRITABLE, DM_UINT, DM_BOOL);

	return vm_json(vm, buf);
}

static void
test_schema_param_info_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *model = model_new(vm);
	uc_value_t *schema = ucv_object_get(ucv_object_get(model, "Device.A", NULL), "schema", NULL);
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_get(schema), ucv_string_new("X"));
	assert_json_equal(vm, res, "{ \"max\": 5, \"writable\": true, \"type\": \"DM_STRING\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_get(schema), ucv_string_new("Y"));
	assert_json_equal(vm, res, "{ \"writable\": false, \"type\": \"DM_UINT\" }");
	ucv_put(res);

	res = vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_get(schema), ucv_string_new("Go()"));
	assert_json_equal(vm, res,
		"{ \"command\": true, \"type\": \"command\", \"input\": [ \"a\" ], \"output\": [ \"b\" ] }");
	ucv_put(res);

	assert_null(vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_get(schema), ucv_string_new("nope")));
	assert_null(vm_call(vm, uc_ubbf_schema_param_info, 2, NULL, ucv_string_new("X")));
	assert_null(vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_get(schema), NULL));

	ucv_put(model);
}

static void
test_schema_extract(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	char buf[1024], code[1400];

	snprintf(buf, sizeof(buf), model_json, DM_STRING | DM_WRITABLE, DM_UINT, DM_BOOL);
	snprintf(code, sizeof(code),
		"let seen = [];"
		"let s = ubbf.schema_extract(%s, (entry, pattern) => {"
		"  push(seen, pattern); return entry.schema.schema; });"
		"return [ seen, s ];", buf);

	res = vm_eval(vm, code);
	snprintf(buf, sizeof(buf),
		"[ [ \"Device.A\", \"Device.B\" ], { \"objects\": { "
		"\"Device.A\": { \"X\": %d, \"Y\": %d, \"Go()\": { \"type\": \"command\", "
		"\"input\": [ \"a\" ], \"output\": [ \"b\" ] } }, "
		"\"Device.B\": { \"Z\": %d } }, "
		"\"events\": { \"Device.B.Ev!\": [ \"q\" ], \"Device.B.Ev2!\": [ ] } } ]",
		DM_STRING | DM_WRITABLE, DM_UINT, DM_BOOL);
	assert_json_equal(vm, res, buf);
	ucv_put(res);

	res = vm_eval(vm,
		"return ubbf.schema_extract({ \"Device.A\": {} }, () => null);");
	assert_json_equal(vm, res, "{ \"objects\": { \"Device.A\": { } }, \"events\": { } }");
	ucv_put(res);

	res = vm_eval(vm,
		"try { ubbf.schema_extract({ \"Device.A\": {} }, () => die('members broken')); }"
		"catch (e) { return e.message; }");
	assert_string_equal(ucv_string_get(res), "members broken");
	ucv_put(res);
}

static void
test_tree_leaves(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm,
		"let out = { 'Device.Old': 1 };"
		"ubbf.tree_leaves({ A: '1', '.meta': 2, B: { C: null, D: [ 1 ], '.x': 3, E: {} } }, 'Device.X.', out);"
		"ubbf.tree_leaves(null, 'p.', out);"
		"ubbf.tree_leaves({ Z: 1 }, 'p.', null);"
		"return out;");

	assert_json_equal(vm, res,
		"{ \"Device.Old\": 1, \"Device.X.A\": \"1\", \"Device.X.B.C\": null, \"Device.X.B.D\": [ 1 ] }");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_text_clamp),
		cmocka_unit_test(test_cmd_build),
		cmocka_unit_test(test_tree_leaves),
		cmocka_unit_test(test_datetime_format),
		cmocka_unit_test(test_upstream_interface_ref),
		cmocka_unit_test(test_lower_layers_wifi),
		cmocka_unit_test(test_port_snooped),
		cmocka_unit_test(test_transfer_complete),
		cmocka_unit_test(test_schema_param_info_object),
		cmocka_unit_test(test_schema_extract),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
