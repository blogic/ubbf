/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The schema lookup of schema.c: schema_get(), schema_defaults(),
 * schema_param_info() for a table name, schema_entry_addable(),
 * schema_tables(), schema_tables_load(), schema_protocol_set(),
 * schema_version_set() and the C functions schema_entry_*(). The tables
 * are process state that a load cannot take back, and the version cannot
 * be cleared once set, so the cases run in a fixed order: first without
 * tables, then with the tables of the build tree, and the version last.
 * Expected values come from the schema sources in
 * files/usr/share/ucode/ubbf/schemas and modules/pty/schema.uc.
 */

#include "harness.h"
#include "ubbf.h"

#include <glob.h>
#include <libgen.h>
#include <limits.h>
#include <unistd.h>

#include <ucode/compiler.h>

#define STAGE_DIR	"/tmp/ubbf/schema-stage"

static char tables_glob[PATH_MAX];
static char ubbf_so[PATH_MAX];
static uc_search_path_t search_saved;

static FILE *capture_file;
static int capture_saved_fd = -1;
static char capture_buf[8192];

static void
stderr_capture_begin(void)
{
	fflush(stderr);
	capture_file = tmpfile();
	assert_non_null(capture_file);
	capture_saved_fd = dup(STDERR_FILENO);
	dup2(fileno(capture_file), STDERR_FILENO);
}

static const char *
stderr_capture_end(void)
{
	size_t len;

	fflush(stderr);
	dup2(capture_saved_fd, STDERR_FILENO);
	close(capture_saved_fd);
	rewind(capture_file);
	len = fread(capture_buf, 1, sizeof(capture_buf) - 1, capture_file);
	capture_buf[len] = '\0';
	fclose(capture_file);

	return capture_buf;
}

static uc_value_t *
call1(uc_vm_t *vm, uc_cfn_ptr_t fn, uc_value_t *arg)
{
	return vm_call(vm, fn, 1, arg);
}

static void
value_expect(uc_vm_t *vm, uc_value_t *entry, const char *name, const char *value,
	     const char *why_expected)
{
	uc_value_t *val = ucv_string_new(value);
	char why[128] = "";
	bool ok = schema_entry_value_ok(vm, entry, name, val, why, sizeof(why));

	ucv_put(val);

	if (!why_expected) {
		assert_true(ok);
		return;
	}

	assert_false(ok);
	assert_string_equal(why, why_expected);
}

static char *
repeat_new(char c, size_t n)
{
	char *s = malloc(n + 1);

	assert_non_null(s);
	memset(s, c, n);
	s[n] = '\0';

	return s;
}

static void
long_value_expect(uc_vm_t *vm, uc_value_t *entry, const char *name, size_t n,
		  const char *why_expected)
{
	char *s = repeat_new('a', n);

	value_expect(vm, entry, name, s, why_expected);
	free(s);
}

static void
test_tables_absent(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_call(vm, uc_ubbf_schema_tables, 0);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	assert_null(call1(vm, uc_ubbf_schema_param_info, NULL));
	assert_null(vm_call(vm, uc_ubbf_schema_param_info, 2, ucv_string_new("IP.Interface"),
			    ucv_string_new("MaxMTUSize")));
}

static void
test_module_export(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	/* Without the core table the export of the schemas/ module comes
	 * back as it is: unprojected, with since, until and constraints. */
	res = vm_eval(vm,
		"let s = ubbf.schema_get('IP.Interface');"
		"let again = ubbf.schema_get('IP.Interface');"
		"return [ s.path, s.schema.MaxMTUSize, s.schema['Reset()'], s.since,"
		"  s.constraints.MaxMTUSize, s.defaults.Type, s === again,"
		"  ubbf.schema_defaults('IP.Interface').IPv4Enable,"
		"  ubbf.schema_get('IP.Nope'), ubbf.schema_defaults('IP.Nope') ];");
	assert_json_equal(vm, res,
		"[ \"Device.IP.Interface.{i}.\", 2147483664, { \"type\": \"sync\", \"input\": [ ] }, "
		"{ \"Description\": \"2.21\" }, { \"min\": 64, \"max\": 65535 }, \"Normal\", true, "
		"\"true\", null, null ]");
	ucv_put(res);

	assert_null(call1(vm, uc_ubbf_schema_get, ucv_string_new("NoDot")));
	assert_null(call1(vm, uc_ubbf_schema_get, ucv_string_new("Bad-Name.X")));
	assert_null(call1(vm, uc_ubbf_schema_get, ucv_string_new(".X")));
	assert_null(call1(vm, uc_ubbf_schema_get, ucv_int64_new(5)));
	assert_null(call1(vm, uc_ubbf_schema_defaults, ucv_string_new("NoDot")));

	res = vm_eval(vm,
		"try { ubbf.schema_get('Nope.X'); return 'no exception'; }"
		"catch (e) { return index(e.message, 'Unable to compile source string') == 0; }");
	assert_json_equal(vm, res, "true");
	ucv_put(res);

	res = vm_eval(vm,
		"let ls = loadstring;"
		"delete global.loadstring;"
		"let r = ubbf.schema_get('Time.Time');"
		"global.loadstring = ls;"
		"return [ r, ubbf.schema_get('Time.Time') != null ];");
	assert_json_equal(vm, res, "[ null, true ]");
	ucv_put(res);
}

static void
test_entry_without_table(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = vm_json(vm, "{ \"schema\": \"IP.Interface\" }");
	uc_value_t *res;
	uint32_t type = 0;
	int64_t max = 0;

	assert_null(schema_entry_defaults(vm, entry));
	assert_null(schema_entry_default(vm, entry, "Type"));
	assert_false(schema_entry_member(entry, "Enable", &type));
	assert_false(schema_entry_hidden(entry, "Enable"));
	assert_true(schema_entry_addable(entry));
	assert_false(schema_entry_max_instances(entry, &max));
	value_expect(vm, entry, "MaxMTUSize", "1", NULL);

	res = schema_entry_params(vm, entry);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
	ucv_put(entry);

	assert_null(schema_entry_defaults(vm, NULL));
	assert_false(schema_entry_member(NULL, "X", &type));
	res = schema_entry_params(vm, NULL);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

static const char legacy_json[] =
	"{ \"schema\": { \"schema\": { \"S\": %u, \"N\": %u, \"B\": %u, \"Go()\": { \"type\": \"sync\" },"
	"    \"I\": %u, \"L\": %u, \"UL\": %u, \"H\": %u, \"T\": %u, \"R\": %u, \"E\": %u, \"LS\": %u },"
	"  \"defaults\": { \"S\": \"s0\", \"N\": \"5\" },"
	"  \"constraints\": { \"S\": { \"min_length\": 2, \"max_length\": 4 },"
	"    \"N\": { \"min\": 1, \"max\": 9 },"
	"    \"R\": { \"ranges\": [ [ 1, 3 ], [ 10, null ] ], \"lengths\": [ [ null, 1 ] ] },"
	"    \"E\": { \"enum\": [ \"x\", \"y\" ], \"lengths\": [ \"bad\" ] },"
	"    \"LS\": { \"list\": true, \"list_min_length\": 1, \"list_max_length\": 9, \"enum\": [ \"a\", \"b\" ] },"
	"    \"T\": { \"min_length\": -3, \"max_length\": 1000 } } } }";

static uc_value_t *
legacy_new(uc_vm_t *vm, const char *extra)
{
	char buf[2048];
	uc_value_t *entry;

	snprintf(buf, sizeof(buf), legacy_json,
		 DM_STRING | DM_WRITABLE, DM_UINT | DM_WRITABLE, DM_BOOL, DM_INT, DM_LONG,
		 DM_ULONG, DM_HEXBIN, DM_STRING, DM_INT, DM_STRING, DM_STRING);
	entry = vm_json(vm, buf);

	if (extra) {
		uc_value_t *more = vm_json(vm, extra);

		ucv_object_foreach(more, key, val)
			ucv_object_add(entry, key, ucv_get(val));
		ucv_put(more);
	}

	return entry;
}

static void
test_entry_object_schema(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = legacy_new(vm, NULL);
	uc_value_t *res;
	uint32_t type = 0;
	int64_t max = 0;

	res = schema_entry_defaults(vm, entry);
	assert_json_equal(vm, res, "{ \"S\": \"s0\", \"N\": \"5\" }");
	ucv_put(res);

	res = schema_entry_default(vm, entry, "N");
	assert_string_equal(ucv_string_get(res), "5");
	ucv_put(res);
	assert_null(schema_entry_default(vm, entry, "B"));

	assert_true(schema_entry_member(entry, "N", &type));
	assert_int_equal(type, DM_UINT | DM_WRITABLE);
	type = 1;
	assert_true(schema_entry_member(entry, "Go()", &type));
	assert_int_equal(type, 0);
	assert_false(schema_entry_member(entry, "Nope", &type));
	assert_false(schema_entry_hidden(entry, "S"));

	res = schema_entry_params(vm, entry);
	assert_json_equal(vm, res,
		"[ \"S\", \"N\", \"B\", \"I\", \"L\", \"UL\", \"H\", \"T\", \"R\", \"E\", \"LS\" ]");
	ucv_put(res);

	assert_true(schema_entry_addable(entry));
	assert_false(schema_entry_max_instances(entry, &max));

	value_expect(vm, entry, "S", "a", "shorter than 2");
	value_expect(vm, entry, "S", "abcde", "longer than 4");
	value_expect(vm, entry, "S", "abcd", NULL);
	value_expect(vm, entry, "N", "0", "below the minimum of 1");
	value_expect(vm, entry, "N", "10", "above the maximum of 9");
	value_expect(vm, entry, "N", "9", NULL);
	value_expect(vm, entry, "N", "-1", "outside the range of its type");
	value_expect(vm, entry, "N", "4294967296", "outside the range of its type");
	value_expect(vm, entry, "N", "", "not an integer");
	value_expect(vm, entry, "N", "-", "not an integer");
	value_expect(vm, entry, "N", "1x", "not an integer");
	value_expect(vm, entry, "B", "1", NULL);
	value_expect(vm, entry, "B", "false", NULL);
	value_expect(vm, entry, "B", "yes", "not a boolean");
	value_expect(vm, entry, "I", "-2147483648", NULL);
	value_expect(vm, entry, "I", "2147483648", "outside the range of its type");
	value_expect(vm, entry, "L", "-9223372036854775808", NULL);
	value_expect(vm, entry, "L", "9223372036854775808", "outside the range of its type");
	value_expect(vm, entry, "UL", "18446744073709551615", NULL);
	value_expect(vm, entry, "UL", "18446744073709551616", "outside the range of its type");
	value_expect(vm, entry, "UL", "-1", "outside the range of its type");
	value_expect(vm, entry, "H", "0aF9", NULL);
	value_expect(vm, entry, "H", "abc", "not an even number of hex digits");
	value_expect(vm, entry, "H", "zz", "not an even number of hex digits");
	value_expect(vm, entry, "R", "2", NULL);
	value_expect(vm, entry, "R", "5", "outside the allowed ranges");
	value_expect(vm, entry, "R", "99999", NULL);
	value_expect(vm, entry, "E", "x", NULL);
	value_expect(vm, entry, "E", "z", "not an allowed value");
	value_expect(vm, entry, "LS", "a, b ,a", NULL);
	value_expect(vm, entry, "LS", "", "shorter than 1 characters");
	value_expect(vm, entry, "LS", "a,b,a,b,a", NULL);
	value_expect(vm, entry, "LS", "a,b,a,b,ab", "longer than 9 characters");
	value_expect(vm, entry, "LS", "a,c", "c: not an allowed value");

	/* a nested list in brackets is one item, its commas separate nothing */
	value_expect(vm, entry, "LS", "[a],b", NULL);
	value_expect(vm, entry, "LS", "[a,b]", "a,b: not an allowed value");
	value_expect(vm, entry, "LS", "[b] , [a]", NULL);
	value_expect(vm, entry, "T", "", NULL);
	long_value_expect(vm, entry, "T", 1000, NULL);
	long_value_expect(vm, entry, "T", 1001, "longer than 1000");
	value_expect(vm, entry, "Go()", "x", NULL);
	value_expect(vm, entry, "Nope", "x", NULL);

	ucv_put(entry);
}

static void
test_entry_object_lengths(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = vm_json(vm,
		"{ \"schema\": { \"schema\": { \"S\": 1, \"I\": 8 }, \"constraints\": {"
		"  \"S\": { \"lengths\": [ [ 0, 0 ], [ 3, 3 ] ] }, \"I\": { \"ranges\": [ [ \"x\", 2 ] ] } } } }");

	value_expect(vm, entry, "S", "", NULL);
	value_expect(vm, entry, "S", "abc", NULL);
	value_expect(vm, entry, "S", "ab", "length outside the allowed lengths");
	value_expect(vm, entry, "I", "-100", NULL);
	value_expect(vm, entry, "I", "3", "outside the allowed ranges");
	ucv_put(entry);
}

static void
addable_expect(uc_vm_t *vm, const char *json, bool addable)
{
	uc_value_t *entry = vm_json(vm, json);
	uc_value_t *res = call1(vm, uc_ubbf_schema_entry_addable, ucv_get(entry));

	assert_int_equal(schema_entry_addable(entry), addable);
	assert_int_equal(ucv_boolean_get(res), addable);
	ucv_put(res);
	ucv_put(entry);
}

static void
max_expect(uc_vm_t *vm, const char *json, bool has, int64_t expected)
{
	uc_value_t *entry = vm_json(vm, json);
	int64_t max = -7;

	assert_int_equal(schema_entry_max_instances(entry, &max), has);
	assert_int_equal(max, has ? expected : -7);
	ucv_put(entry);
}

static void
test_entry_addable_object(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	addable_expect(vm, "{ }", true);
	addable_expect(vm, "{ \"schema\": { \"schema\": { } } }", true);
	addable_expect(vm, "{ \"schema\": { \"addable\": false } }", false);
	addable_expect(vm, "{ \"schema\": { \"addable\": 1 } }", true);
	addable_expect(vm, "{ \"addable\": true, \"schema\": { \"addable\": false } }", true);
	addable_expect(vm, "{ \"addable\": 0, \"schema\": { } }", false);
	addable_expect(vm, "{ \"schema\": { \"max_instances\": 0 } }", false);
	addable_expect(vm, "{ \"maxInstances\": 0 }", false);
	addable_expect(vm, "{ \"maxInstances\": 2, \"schema\": { \"max_instances\": 0 } }", true);

	max_expect(vm, "{ }", false, 0);
	max_expect(vm, "{ \"maxInstances\": 4, \"schema\": { \"max_instances\": 8 } }", true, 4);
	max_expect(vm, "{ \"maxInstances\": \"4\", \"schema\": { \"max_instances\": 8 } }", true, 8);
	max_expect(vm, "{ \"schema\": { \"max_instances\": \"8\" } }", false, 0);

	res = call1(vm, uc_ubbf_schema_entry_addable, NULL);
	assert_true(ucv_boolean_get(res));
	ucv_put(res);
}

static void
info_expect(uc_vm_t *vm, uc_value_t *schema, const char *name, const char *expected)
{
	uc_value_t *res = vm_call(vm, uc_ubbf_schema_param_info, 2, schema,
				  name ? ucv_string_new(name) : NULL);

	if (expected)
		assert_json_equal(vm, res, expected);
	else
		assert_null(res);

	ucv_put(res);
}

static void
test_param_info_type_names(void **state)
{
	uc_vm_t *vm = *state;
	char buf[256];

	snprintf(buf, sizeof(buf), "{ \"schema\": { \"A\": %u, \"B\": %u, \"C\": %u, \"D\": %u } }",
		 DM_STRING | DM_DATETIME, DM_HEXBIN | DM_WRITABLE, DM_DECIMAL, DM_WRITABLE);

	info_expect(vm, vm_json(vm, buf), "A", "{ \"writable\": false, \"type\": \"DM_STRING\" }");
	info_expect(vm, vm_json(vm, buf), "B", "{ \"writable\": true, \"type\": \"DM_HEXBIN\" }");
	info_expect(vm, vm_json(vm, buf), "C", "{ \"writable\": false, \"type\": \"DM_DECIMAL\" }");
	info_expect(vm, vm_json(vm, buf), "D", "{ \"writable\": true, \"type\": \"DM_STRING\" }");
}

static void
test_protocol_version_args(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = call1(vm, uc_ubbf_schema_protocol_set, ucv_string_new("tr069"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
	res = call1(vm, uc_ubbf_schema_protocol_set, ucv_int64_new(1));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
	res = call1(vm, uc_ubbf_schema_protocol_set, ucv_string_new("usp"));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	res = call1(vm, uc_ubbf_schema_version_set, ucv_string_new("20"));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
	res = call1(vm, uc_ubbf_schema_version_set, ucv_int64_new(0));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
	res = call1(vm, uc_ubbf_schema_version_set, ucv_int64_new(256));
	assert_false(ucv_boolean_get(res));
	ucv_put(res);
}

static void
stage_file(const char *name, const char *content)
{
	char path[PATH_MAX];
	FILE *f;

	snprintf(path, sizeof(path), STAGE_DIR "/%s", name);
	f = fopen(path, "w");
	assert_non_null(f);
	fputs(content, f);
	fclose(f);
}

static void
test_tables_load_rejects(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	const char *err;

	assert_null(call1(vm, uc_ubbf_schema_tables_load, NULL));
	assert_null(call1(vm, uc_ubbf_schema_tables_load, ucv_int64_new(1)));

	res = call1(vm, uc_ubbf_schema_tables_load, ucv_string_new(STAGE_DIR "/none-*.so"));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);

	mkdir(STAGE_DIR, 0755);
	stage_file("schema-bogus.so", "not a library");
	stage_file("schema-.so", "");
	stage_file("other.so", "");
	stage_file("schema-x.txt", "");
	unlink(STAGE_DIR "/schema-nosym.so");
	assert_int_equal(symlink(ubbf_so, STAGE_DIR "/schema-nosym.so"), 0);

	stderr_capture_begin();
	res = call1(vm, uc_ubbf_schema_tables_load, ucv_string_new(STAGE_DIR "/*"));
	err = stderr_capture_end();

	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
	assert_non_null(strstr(err, "ubbf: schema table " STAGE_DIR "/schema-bogus.so: "));
	assert_non_null(strstr(err, "ubbf: schema table " STAGE_DIR "/schema-nosym.so has no ubbf_schema_abi\n"));
	assert_non_null(strstr(err, "ubbf: schema table " STAGE_DIR "/schema-nosym.so has no ubbf_schema_enums\n"));
	assert_null(strstr(err, "other.so"));
	assert_null(strstr(err, "schema-.so"));
	assert_null(strstr(err, "schema-x.txt"));

	res = vm_call(vm, uc_ubbf_schema_tables, 0);
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

static void
test_tables_load(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res, *tables, *item;
	bool core = false, pty = false;
	glob_t gl;

	assert_int_equal(glob(tables_glob, 0, NULL, &gl), 0);

	res = call1(vm, uc_ubbf_schema_tables_load, ucv_string_new(tables_glob));
	assert_int_equal(ucv_array_length(res), gl.gl_pathc);
	globfree(&gl);

	for (size_t i = 0; i < ucv_array_length(res); i++) {
		item = ucv_array_get(res, i);
		core |= !strcmp(ucv_string_get(item), "core");
		pty |= !strcmp(ucv_string_get(item), "pty");
	}

	assert_true(core);
	assert_true(pty);

	tables = vm_call(vm, uc_ubbf_schema_tables, 0);
	assert_true(ucv_is_equal(tables, res));
	ucv_put(tables);
	ucv_put(res);

	res = call1(vm, uc_ubbf_schema_tables_load, ucv_string_new(tables_glob));
	assert_json_equal(vm, res, "[ ]");
	ucv_put(res);
}

static void
test_schema_get_table(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	res = vm_eval(vm,
		"let d = ubbf.schema_get('DeviceInfo.DeviceInfo');"
		"return [ d.path, length(d.schema), d.schema.HostName, d.schema.UpTime,"
		"  d.schema.LastFirmwareUpdate, d.schema.ProcessorNumberOfEntries,"
		"  d.defaults.HostName, d.defaults.FirstUseDate, length(d.defaults),"
		"  d.since, d.constraints, keys(d) ];");
	assert_json_equal(vm, res,
		"[ \"Device.DeviceInfo.\", 31, 2147483649, 16, 2, 16, \"OpenWrt\", "
		"\"0001-01-01T00:00:00Z\", 31, null, null, [ \"path\", \"schema\", \"defaults\" ] ]");
	ucv_put(res);

	res = vm_eval(vm,
		"let i = ubbf.schema_get('IP.Interface');"
		"let p = ubbf.schema_get('pty.UPTY');"
		"return [ i.schema['Reset()'], p.path, p.schema['StartSession()'], p.defaults,"
		"  ubbf.schema_get('IP.Nope'), ubbf.schema_get('pty.Nope'), ubbf.schema_get('nosuch.X'),"
		"  ubbf.schema_get('Bad-Name.X'), ubbf.schema_defaults('IP.Nope') ];");
	assert_json_equal(vm, res,
		"[ { \"type\": \"sync\", \"input\": [ ] }, \"Device.X_UBBF.UPTY.\", "
		"{ \"type\": \"sync\", \"input\": [ \"Token\", \"URL\", \"AllowInsecure\", \"CACert\" ], "
		"\"output\": [ \"Status\", \"Message\" ] }, "
		"{ \"Enable\": \"true\", \"Status\": \"Unavailable\", \"LastError\": \"\" }, "
		"null, null, null, null, null ]");
	ucv_put(res);

	res = call1(vm, uc_ubbf_schema_defaults, ucv_string_new("IP.Interface"));
	assert_json_equal(vm, res,
		"{ \"Enable\": \"false\", \"IPv4Enable\": \"true\", \"IPv6Enable\": \"true\", "
		"\"ULAEnable\": \"false\", \"Status\": \"Down\", \"Alias\": \"\", \"Name\": \"\", "
		"\"Description\": \"\", \"LastChange\": \"0\", \"LowerLayers\": \"\", "
		"\"Upstream\": \"false\", \"Type\": \"Normal\", \"Loopback\": \"false\", "
		"\"IPv4AddressNumberOfEntries\": \"0\", \"IPv6AddressNumberOfEntries\": \"0\", "
		"\"IPv6PrefixNumberOfEntries\": \"0\", \"X_UBBF_CarrierLossDelay\": \"0\" }");
	ucv_put(res);
}

static void
test_param_info_table(void **state)
{
	uc_vm_t *vm = *state;

	info_expect(vm, ucv_string_new("IP.Interface"), "MaxMTUSize",
		    "{ \"min\": 64, \"max\": 65535, \"writable\": true, \"type\": \"DM_UINT\" }");
	info_expect(vm, ucv_string_new("IP.Interface"), "LowerLayers",
		    "{ \"list\": true, \"list_max_length\": 1024, \"writable\": true, \"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("IP.Interface"), "Status",
		    "{ \"writable\": false, \"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("IP.Interface"), "Enable",
		    "{ \"writable\": true, \"type\": \"DM_BOOL\" }");
	info_expect(vm, ucv_string_new("IP.Interface"), "Reset()",
		    "{ \"command\": true, \"type\": \"sync\", \"input\": [ ], \"output\": null }");
	info_expect(vm, ucv_string_new("IP.Interface"), "Nope", NULL);
	info_expect(vm, ucv_string_new("IP.Nope"), "Enable", NULL);
	info_expect(vm, ucv_int64_new(3), "Enable", NULL);
	info_expect(vm, ucv_string_new("IP.Interface"), NULL, NULL);

	info_expect(vm, ucv_string_new("IP.Diagnostics_IPLayerCapacityAuthCode"), "AuthenticationKey",
		    "{ \"secured\": true, \"writable\": true, \"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("Firewall.Pinhole"), "IPVersion",
		    "{ \"ranges\": [ [ 4, 4 ], [ 6, 6 ], [ -1, -1 ] ], \"writable\": true, \"type\": \"DM_INT\" }");
	info_expect(vm, ucv_string_new("Routing.Router_IPv4Forwarding"), "MTU",
		    "{ \"ranges\": [ [ -1, -1 ], [ 576, null ] ], \"writable\": true, \"type\": \"DM_UINT\" }");
	info_expect(vm, ucv_string_new("ManagementServer.ManagementServer"), "X_UBBF_InformWatchdogTime",
		    "{ \"lengths\": [ [ 0, 0 ], [ 5, 5 ] ], \"writable\": true, \"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("ManagementServer.ManagementServer"), "X_UBBF_TLSMinVersion",
		    "{ \"enum\": [ \"1.2\", \"1.3\" ], \"writable\": true, \"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("WiFi.AccessPoint_Security"), "KeyPassphrase",
		    "{ \"min_length\": 8, \"max_length\": 63, \"secured\": true, \"writable\": true, "
		    "\"type\": \"DM_STRING\" }");
	info_expect(vm, ucv_string_new("DeviceInfo.TemperatureStatus_TemperatureSensor"), "HighTemperatureAlarm!",
		    "{ \"command\": true, \"type\": \"event\", \"input\": [ \"Value\" ], \"output\": null }");
	info_expect(vm, ucv_string_new("pty.UPTY"), "Status",
		    "{ \"enum\": [ \"Disabled\", \"Unavailable\", \"Idle\", \"Connecting\", \"Connected\", "
		    "\"Active\" ], \"writable\": false, \"type\": \"DM_STRING\" }");
}

static uc_value_t *
table_entry_new(uc_vm_t *vm, const char *name)
{
	uc_value_t *entry = ucv_object_new(vm);

	ucv_object_add(entry, "schema", ucv_string_new(name));

	return entry;
}

static void
test_entry_table(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = table_entry_new(vm, "IP.Interface");
	uc_value_t *res, *expected;
	uint32_t type = 0;
	int64_t max = 0;

	res = schema_entry_defaults(vm, entry);
	expected = call1(vm, uc_ubbf_schema_defaults, ucv_string_new("IP.Interface"));
	assert_true(ucv_is_equal(res, expected));
	ucv_put(expected);
	ucv_put(res);

	res = schema_entry_default(vm, entry, "Type");
	assert_string_equal(ucv_string_get(res), "Normal");
	ucv_put(res);
	assert_null(schema_entry_default(vm, entry, "MaxMTUSize"));
	assert_null(schema_entry_default(vm, entry, "Nope"));

	assert_true(schema_entry_member(entry, "MaxMTUSize", &type));
	assert_int_equal(type, DM_UINT | DM_WRITABLE);
	type = 1;
	assert_true(schema_entry_member(entry, "Reset()", &type));
	assert_int_equal(type, 0);
	assert_false(schema_entry_member(entry, "Nope", &type));
	assert_false(schema_entry_hidden(entry, "Reset()"));
	assert_false(schema_entry_hidden(entry, "Nope"));

	res = schema_entry_params(vm, entry);
	assert_json_equal(vm, res,
		"[ \"Enable\", \"IPv4Enable\", \"IPv6Enable\", \"ULAEnable\", \"Status\", \"Alias\", "
		"\"Name\", \"Description\", \"LastChange\", \"LowerLayers\", \"Upstream\", \"MaxMTUSize\", "
		"\"Type\", \"Loopback\", \"IPv4AddressNumberOfEntries\", \"IPv6AddressNumberOfEntries\", "
		"\"IPv6PrefixNumberOfEntries\", \"X_UBBF_CarrierLossDelay\" ]");
	ucv_put(res);

	assert_true(schema_entry_addable(entry));
	assert_false(schema_entry_max_instances(entry, &max));

	value_expect(vm, entry, "MaxMTUSize", "63", "below the minimum of 64");
	value_expect(vm, entry, "MaxMTUSize", "64", NULL);
	value_expect(vm, entry, "MaxMTUSize", "65536", "above the maximum of 65535");
	value_expect(vm, entry, "MaxMTUSize", "abc", "not an integer");
	value_expect(vm, entry, "Enable", "yes", "not a boolean");
	value_expect(vm, entry, "Enable", "true", NULL);
	value_expect(vm, entry, "LowerLayers", "Device.Ethernet.Link.1, Device.PPP.Interface.2", NULL);
	long_value_expect(vm, entry, "LowerLayers", 1024, NULL);
	long_value_expect(vm, entry, "LowerLayers", 1025, "longer than 1024 characters");
	long_value_expect(vm, entry, "Description", 256, NULL);
	long_value_expect(vm, entry, "Description", 257, "longer than 256");
	value_expect(vm, entry, "Reset()", "x", NULL);
	value_expect(vm, entry, "Nope", "x", NULL);
	ucv_put(entry);

	entry = table_entry_new(vm, "Firewall.Pinhole");
	value_expect(vm, entry, "IPVersion", "4", NULL);
	value_expect(vm, entry, "IPVersion", "-1", NULL);
	value_expect(vm, entry, "IPVersion", "5", "outside the allowed ranges");
	value_expect(vm, entry, "Protocol", "6, 17", NULL);
	value_expect(vm, entry, "Protocol", "", NULL);
	value_expect(vm, entry, "Protocol", "6,256", "256: above the maximum of 255");
	value_expect(vm, entry, "Protocol", "6,-2", "-2: below the minimum of -1");
	value_expect(vm, entry, "SourcePort", "", "not an integer");
	ucv_put(entry);

	entry = table_entry_new(vm, "ManagementServer.ManagementServer");
	value_expect(vm, entry, "X_UBBF_InformWatchdogTime", "", NULL);
	value_expect(vm, entry, "X_UBBF_InformWatchdogTime", "12345", NULL);
	value_expect(vm, entry, "X_UBBF_InformWatchdogTime", "123", "length outside the allowed lengths");
	value_expect(vm, entry, "X_UBBF_TLSMinVersion", "1.3", NULL);
	value_expect(vm, entry, "X_UBBF_TLSMinVersion", "1.4", "not an allowed value");
	value_expect(vm, entry, "PeriodicInformInterval", "4294967295", NULL);
	value_expect(vm, entry, "PeriodicInformInterval", "0", "below the minimum of 1");
	value_expect(vm, entry, "PeriodicInformInterval", "4294967296", "outside the range of its type");
	ucv_put(entry);

	entry = table_entry_new(vm, "WiFi.AccessPoint_Security");
	value_expect(vm, entry, "KeyPassphrase", "short", "shorter than 8");
	long_value_expect(vm, entry, "KeyPassphrase", 63, NULL);
	long_value_expect(vm, entry, "KeyPassphrase", 64, "longer than 63");
	ucv_put(entry);

	entry = table_entry_new(vm, "Bridging.Filter");
	value_expect(vm, entry, "SourceMACFromClientIDFilter", "0a1B", NULL);
	value_expect(vm, entry, "SourceMACFromClientIDFilter", "abc", "not an even number of hex digits");
	value_expect(vm, entry, "DHCPType", "DHCPv6", NULL);
	value_expect(vm, entry, "DHCPType", "DHCPv5", "not an allowed value");
	ucv_put(entry);

	entry = table_entry_new(vm, "Routing.Router_IPv4Forwarding");
	value_expect(vm, entry, "MTU", "576", NULL);
	value_expect(vm, entry, "MTU", "100000", NULL);
	value_expect(vm, entry, "MTU", "575", "outside the allowed ranges");

	/* unsignedInt(-1,576:): the explicit range goes below the type */
	value_expect(vm, entry, "MTU", "-1", NULL);
	value_expect(vm, entry, "MTU", "-2", "outside the range of its type");
	ucv_put(entry);

	entry = table_entry_new(vm, "SSH.SSH");
	value_expect(vm, entry, "X_UBBF_PubkeyAcceptedKeyTypes", "ssh-ed25519,ssh-rsa", NULL);
	value_expect(vm, entry, "X_UBBF_PubkeyAcceptedKeyTypes", "ssh-rsa,ssh-dss",
		     "ssh-dss: not an allowed value");
	ucv_put(entry);

	entry = table_entry_new(vm, "pty.UPTY");
	value_expect(vm, entry, "Status", "Idle", NULL);
	value_expect(vm, entry, "Status", "Busy", "not an allowed value");
	ucv_put(entry);
}

static void
test_entry_table_addable(void **state)
{
	uc_vm_t *vm = *state;

	addable_expect(vm, "{ \"schema\": \"IP.Interface\" }", true);
	addable_expect(vm, "{ \"schema\": \"DeviceInfo.VendorLogFile\" }", false);
	addable_expect(vm, "{ \"addable\": true, \"schema\": \"DeviceInfo.VendorLogFile\" }", true);
	addable_expect(vm, "{ \"addable\": false, \"schema\": \"IP.Interface\" }", false);
	addable_expect(vm, "{ \"maxInstances\": 0, \"schema\": \"IP.Interface\" }", false);
	addable_expect(vm, "{ \"schema\": \"IP.Diagnostics_IPLayerCapacityAuthCode\" }", true);
	addable_expect(vm, "{ \"schema\": \"IP.Nope\" }", true);

	max_expect(vm, "{ \"schema\": \"IP.Diagnostics_IPLayerCapacityAuthCode\" }", true, 256);
	max_expect(vm, "{ \"maxInstances\": 3, \"schema\": \"IP.Diagnostics_IPLayerCapacityAuthCode\" }",
		   true, 3);
	max_expect(vm, "{ \"schema\": \"IP.Interface\" }", false, 0);
}

static void
test_protocol_cwmp(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = table_entry_new(vm, "IP.Interface");
	uc_value_t *res;
	uint32_t type;

	res = vm_eval(vm,
		"let ok = ubbf.schema_protocol_set('cwmp');"
		"let i = ubbf.schema_get('IP.Interface');"
		"let t = ubbf.schema_get('DeviceInfo.TemperatureStatus_TemperatureSensor');"
		"return [ ok, exists(i.schema, 'Reset()'), exists(i.schema, 'Enable'), length(i.defaults),"
		"  exists(t.schema, 'HighTemperatureAlarm!'), exists(t.schema, 'Reset()'),"
		"  ubbf.schema_param_info('IP.Interface', 'Reset()') ];");
	assert_json_equal(vm, res, "[ true, false, true, 17, false, false, null ]");
	ucv_put(res);

	assert_true(schema_entry_hidden(entry, "Reset()"));
	assert_false(schema_entry_hidden(entry, "Enable"));
	assert_false(schema_entry_member(entry, "Reset()", &type));

	res = call1(vm, uc_ubbf_schema_protocol_set, ucv_string_new("usp"));
	assert_true(ucv_boolean_get(res));
	ucv_put(res);

	assert_false(schema_entry_hidden(entry, "Reset()"));
	assert_true(schema_entry_member(entry, "Reset()", &type));
	ucv_put(entry);
}

static void
test_version(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *entry = table_entry_new(vm, "DeviceInfo.DeviceInfo");
	uc_value_t *iface = table_entry_new(vm, "IP.Interface");
	uc_value_t *res;
	uint32_t type;

	res = vm_eval(vm,
		"let ok = ubbf.schema_version_set(20);"
		"let d = ubbf.schema_get('DeviceInfo.DeviceInfo');"
		"let r = ubbf.schema_get('Routing.Router_IPv4Forwarding');"
		"return [ ok, exists(d.schema, 'LastFirmwareUpdate'), exists(d.defaults, 'LastFirmwareUpdate'),"
		"  exists(d.schema, 'LastRebootRef'), exists(d.schema, 'ProcessorNumberOfEntries'),"
		"  length(d.schema), length(d.defaults), exists(r.schema, 'MTU'),"
		"  exists(ubbf.schema_defaults('IP.Interface'), 'Description'),"
		"  ubbf.schema_param_info('IP.Interface', 'Description') ];");
	assert_json_equal(vm, res, "[ true, false, false, false, true, 29, 29, true, false, null ]");
	ucv_put(res);

	assert_null(schema_entry_default(vm, entry, "LastFirmwareUpdate"));
	assert_false(schema_entry_member(entry, "LastFirmwareUpdate", &type));
	assert_true(schema_entry_hidden(entry, "LastFirmwareUpdate"));
	assert_false(schema_entry_hidden(entry, "ProcessorNumberOfEntries"));
	long_value_expect(vm, iface, "Description", 300, NULL);

	res = vm_eval(vm,
		"let ok = ubbf.schema_version_set(21);"
		"let d = ubbf.schema_get('DeviceInfo.DeviceInfo');"
		"return [ ok, exists(d.schema, 'LastFirmwareUpdate'), d.defaults.LastFirmwareUpdate,"
		"  exists(d.schema, 'ProcessorNumberOfEntries'), exists(d.defaults, 'ProcessorNumberOfEntries'),"
		"  length(d.schema) ];");
	assert_json_equal(vm, res, "[ true, true, \"0001-01-01T00:00:00Z\", false, false, 30 ]");
	ucv_put(res);

	assert_true(schema_entry_hidden(entry, "ProcessorNumberOfEntries"));
	long_value_expect(vm, iface, "Description", 257, "longer than 256");

	res = vm_eval(vm,
		"ubbf.schema_version_set(19);"
		"let t = ubbf.schema_get('DeviceInfo.TemperatureStatus_TemperatureSensor');"
		"let r = ubbf.schema_get('Routing.Router_IPv4Forwarding');"
		"return [ exists(t.schema, 'HighTemperatureAlarm!'), exists(t.schema, 'Reset()'),"
		"  exists(r.schema, 'MTU'), exists(r.defaults, 'MTU') ];");
	assert_json_equal(vm, res, "[ false, true, false, false ]");
	ucv_put(res);

	ucv_put(iface);
	ucv_put(entry);
}

static void
paths_init(void)
{
	char exe[1024], src[1024], dir[1024], search[PATH_MAX];
	ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);

	if (len < 0)
		len = 0;
	exe[len] = '\0';

	/* The test binary lives in <build>/tests, the tables in <build>. */
	snprintf(dir, sizeof(dir), "%s", dirname(dirname(exe)));
	snprintf(tables_glob, sizeof(tables_glob), "%s/schema-*.so", dir);
	snprintf(ubbf_so, sizeof(ubbf_so), "%s/ubbf.so", dir);

	snprintf(src, sizeof(src), "%s", __FILE__);
	snprintf(search, sizeof(search), "%s/../../../files/usr/share/ucode/*.uc", dirname(src));
	/* The default search path is a static array of libucode, so the test
	 * puts its own vector in place instead of growing that one. */
	search_saved = uc_default_parse_config.module_search_path;
	memset(&uc_default_parse_config.module_search_path, 0,
	       sizeof(uc_default_parse_config.module_search_path));
	uc_search_path_add(&uc_default_parse_config.module_search_path, search);

	/* obuspa runs its VM in raw mode; loadstring() inherits the mode */
	uc_default_parse_config.raw_mode = true;
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_tables_absent),
		cmocka_unit_test(test_module_export),
		cmocka_unit_test(test_entry_without_table),
		cmocka_unit_test(test_entry_object_schema),
		cmocka_unit_test(test_entry_object_lengths),
		cmocka_unit_test(test_entry_addable_object),
		cmocka_unit_test(test_param_info_type_names),
		cmocka_unit_test(test_protocol_version_args),
		cmocka_unit_test(test_tables_load_rejects),
		cmocka_unit_test(test_tables_load),
		cmocka_unit_test(test_schema_get_table),
		cmocka_unit_test(test_param_info_table),
		cmocka_unit_test(test_entry_table),
		cmocka_unit_test(test_entry_table_addable),
		cmocka_unit_test(test_protocol_cwmp),
		cmocka_unit_test(test_version),
	};
	int rc;

	paths_init();
	rc = cmocka_run_group_tests(tests, vm_setup, vm_teardown);
	uc_search_path_free(&uc_default_parse_config.module_search_path);
	uc_default_parse_config.module_search_path = search_saved;

	return rc;
}
