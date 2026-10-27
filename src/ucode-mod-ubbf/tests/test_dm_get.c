/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * The read and write path of the ubbf.dm resource in dm.c: the slots
 * (register, register_operations, register_hidden, load, runtime,
 * runtime_reload, digest), get_subtree(), path_known(), names(),
 * get_subtree_with_state(), params_get(), params_set() and
 * refresh_instances(). The static dispatcher subtree_dispatch() and the
 * path checks of params_set() are tested through these methods. The models
 * carry object schemas; the schema tables are covered by test_schema.c.
 */

#include "harness.h"
#include "ubbf.h"

#include <syslog.h>
#include <libubox/ulog.h>

#include <unistd.h>

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

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static const char *
eval_capture(uc_vm_t *vm, const char *code, const char *expected)
{
	const char *err;

	stderr_capture_begin();
	eval_expect(vm, code, expected);
	err = stderr_capture_end();

	return err;
}

static void
file_put(const char *path, const char *text)
{
	FILE *f = fopen(path, "w");

	assert_non_null(f);
	fputs(text, f);
	fclose(f);
}

static void
test_slots(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"let r = [ d.digest(), d.runtime(), d.runtime_reload(), d.config() ];"
		"push(r, d.register(null), d.register([]), d.register({}));"
		"push(r, d.register_operations('x'), d.register_operations({ 'Device.X.Go()': {} }));"
		"push(r, d.register_hidden({}), d.register_hidden([ 'Device.A', 5, null ]));"
		"push(r, d.set_digest('abc'), d.digest(), d.get_digest());"
		"push(r, d.set_digest(), d.digest());"
		"push(r, d.get_subtree_with_state('Device'), d.params_get({}));"
		"push(r, d.set_config('x'), d.set_config({ Device: { X: '1' } }), d.runtime(),"
		"  d.get_subtree('Device'), d.get_subtree_with_state('Device'));"
		"push(r, d.runtime_reload(), keys(d.runtime()), d.runtime().Device.X);"
		"let rt = d.runtime();"
		"rt.Device.X = '2';"
		"push(r, d.config().Device.X, d.runtime().Device.X);"
		"d.runtime_reload();"
		"push(r, d.runtime().Device.X, d.runtime() === d.config());"
		"return r;",
		"[ null, null, false, null, false, false, true, false, true, false, true, "
		"true, \"abc\", \"abc\", true, null, { }, -1, false, true, null, { }, { }, true, "
		"[ \"Device\" ], \"1\", \"1\", \"2\", \"1\", false ]");
}

static void
test_not_a_dm(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"let w = {};"
		"for (let k in [ 'register', 'register_operations', 'register_hidden', 'load',"
		"  'config', 'runtime', 'runtime_reload', 'digest', 'set_digest',"
		"  'params_get', 'params_set', 'get_subtree',"
		"  'get_subtree_with_state', 'names', 'path_known', 'refresh_instances' ])"
		"  w[k] = d[k];"
		"return [ w.register({}), w.register_operations({}), w.register_hidden([]),"
		"  w.load('/tmp/ubbf/x.json'), w.config(),"
		"  w.runtime(), w.runtime_reload(), w.digest(), w.set_digest('x'), w.params_get({}),"
		"  w.params_set({}), w.get_subtree('Device'), w.get_subtree_with_state('Device'),"
		"  w.names('Device.'), w.path_known('Device.'), w.refresh_instances('Device') ];",
		"[ false, false, false, false, null, null, false, null, null, "
		"-1, -1, { }, { }, null, 0, [ ] ]");
}

#define LOAD_FILE	"/tmp/ubbf/load.json"

static void
test_load(void **state)
{
	uc_vm_t *vm = *state;

	unlink(LOAD_FILE);
	eval_expect(vm,
		"global.dl = ubbf.create();"
		"return [ dl.load('" LOAD_FILE "'), dl.load(5) ];",
		"[ false, false ]");

	file_put(LOAD_FILE, "");
	eval_expect(vm, "return dl.load('" LOAD_FILE "');", "false");
	file_put(LOAD_FILE, "{ \"Device\": ");
	eval_expect(vm, "return dl.load('" LOAD_FILE "');", "false");

	/* load() keeps the pins and the digest, unlike config_load() */
	file_put(LOAD_FILE, "{ \"Device\": { \"X\": \"1\" }, \"_instances\": { \"Device.E\": { \"2\": \"k\" } } }");
	eval_expect(vm,
		"dl.set_digest('h');"
		"return [ dl.load('" LOAD_FILE "'), dl.config(), dl.runtime(), dl.config() === dl.runtime(),"
		"  dl.digest() ];",
		"[ true, { \"Device\": { \"X\": \"1\" }, \"_instances\": { \"Device.E\": { \"2\": \"k\" } } }, "
		"{ \"Device\": { \"X\": \"1\" }, \"_instances\": { \"Device.E\": { \"2\": \"k\" } } }, false, \"h\" ]");

	eval_expect(vm, "delete global.dl; return null;", "null");
}

static void
test_get_subtree(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"let r = [ d.get_subtree('Device') ];"
		"d.set_config({ Device: { T: { '1': { Name: 'a', Alias: 'lan' } }, S: 'str' } });"
		"d.runtime_reload();"
		"push(r, d.get_subtree('Device.T.1'), d.get_subtree('Device.T.1.Name'), d.get_subtree('Device.Nope'),"
		"  d.get_subtree(''), d.get_subtree(1), d.get_subtree('Device.T') === d.runtime().Device.T);"
		"return r;",
		"[ { }, { \"Name\": \"a\", \"Alias\": \"lan\" }, \"a\", { }, { }, { }, true ]");
}

static const char NAMES_MODEL[] =
	"let d = ubbf.create();"
	"d.register({"
	"  'Device.N': { schema: { schema: { Enable: dm_type.BOOL | dm_type.WRITABLE,"
	"    Status: dm_type.STRING, TNumberOfEntries: dm_type.UINT } } },"
	"  'Device.N.T': {},"
	"  'Device.N.T.{i}': { schema: { schema: { Name: dm_type.STRING | dm_type.WRITABLE,"
	"    Alias: dm_type.STRING | dm_type.WRITABLE } } },"
	"  'Device.N.T.{i}.Sub': { schema: { schema: { V: dm_type.STRING } } },"
	"  'Device.N.R': {},"
	"  'Device.N.R.{i}': { addable: false, get: (ctx) => ctx.instance ? null : { '1': { Z: 'z' } },"
	"    schema: { schema: { Z: dm_type.STRING } } },"
	"  'Device.N.Empty': {},"
	"  'Device.N.Empty.{i}': { schema: { schema: { Q: dm_type.STRING } } },"
	"  'Device.N.Obj': { schema: { schema: { O: dm_type.STRING | dm_type.WRITABLE,"
	"    'Go()': { type: 'sync' } } } },"
	"});"
	"d.set_config({ Device: { N: { Enable: 'true', T: { '1': { Name: 'a' } } } } });"
	"d.runtime_reload();"
	"let long = 'Device.N.';"
	"while (length(long) < 600) long += 'X';"
	"let names = (p, next) => map(d.names(p, next) ?? [], (e) => e.path + (e.writable ? ' w' : ''));";

static void
model_expect(uc_vm_t *vm, const char *model, const char *code, const char *expected)
{
	char *src;

	assert_true(asprintf(&src, "%s%s", model, code) > 0);
	eval_expect(vm, src, expected);
	free(src);
}

static void
test_path_known(void **state)
{
	uc_vm_t *vm = *state;

	model_expect(vm, NAMES_MODEL,
		"return [ d.path_known('Device.N.'), d.path_known('Device.N'), d.path_known('Device.N.Enable'),"
		"  d.path_known('Device.N.T.1.Name'), d.path_known('Device.N.T.1.'), d.path_known('Device.N.T.1'),"
		"  d.path_known('Device.N.T.'), d.path_known('Device.N.T.1.Sub.V'),"
		"  d.path_known('Device.N.Obj.Go()'), d.path_known('Device.N.Nope'),"
		"  d.path_known('Device.N.Nope.'), d.path_known('Device.N.T.x.Name'),"
		"  d.path_known('Device.N.T.0.Name'), d.path_known('Device.N.Enable.'), d.path_known(''),"
		"  d.path_known(null), d.path_known(long), ubbf.create().path_known('Device.N.') ];",
		"[ 1, 1, 2, 2, 1, 1, 1, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0 ]");
}

static void
test_names(void **state)
{
	uc_vm_t *vm = *state;

	model_expect(vm, NAMES_MODEL,
		"return names('Device.N.', false);",
		"[ \"Device.N.\", \"Device.N.Enable w\", \"Device.N.T. w\", \"Device.N.T.1.\", "
		"\"Device.N.T.1.Name w\", \"Device.N.T.1.Alias w\", \"Device.N.T.1.Sub.\", "
		"\"Device.N.T.1.Sub.V\", \"Device.N.R.\", \"Device.N.R.1.\", \"Device.N.R.1.Z\", "
		"\"Device.N.Status\", \"Device.N.TNumberOfEntries\", \"Device.N.Empty. w\", "
		"\"Device.N.Obj.\", \"Device.N.Obj.O w\" ]");

	model_expect(vm, NAMES_MODEL,
		"return [ names('Device.N.T.', false), names('Device.N.Obj.', false) ];",
		"[ [ \"Device.N.T. w\", \"Device.N.T.1.\", \"Device.N.T.1.Name w\", \"Device.N.T.1.Alias w\", "
		"\"Device.N.T.1.Sub.\", \"Device.N.T.1.Sub.V\" ], [ \"Device.N.Obj.\", \"Device.N.Obj.O w\" ] ]");
}

static void
test_names_next_level(void **state)
{
	uc_vm_t *vm = *state;

	model_expect(vm, NAMES_MODEL,
		"return [ names('Device.N.', true), names('Device.N.R.', 1), names('Device.N.T.1.', true) ];",
		"[ [ \"Device.N.Enable w\", \"Device.N.T. w\", \"Device.N.R.\", \"Device.N.Status\", "
		"\"Device.N.TNumberOfEntries\", \"Device.N.Empty. w\", \"Device.N.Obj.\" ], "
		"[ \"Device.N.R.1.\" ], "
		"[ \"Device.N.T.1.Name w\", \"Device.N.T.1.Alias w\", \"Device.N.T.1.Sub.\" ] ]");
}

static void
test_names_refused(void **state)
{
	uc_vm_t *vm = *state;

	model_expect(vm, NAMES_MODEL,
		"return [ d.names('Device.N', false), d.names('', false), d.names(5), d.names('Device.Nope.'),"
		"  d.names('Device.N.Enable.'), d.names(long + '.'), ubbf.create().names('Device.N.') ];",
		"[ null, null, null, null, null, null, null ]");
}

static void
test_subtree_defaults(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.A': { schema: { schema: { X: dm_type.STRING, Y: dm_type.STRING },"
		"    defaults: { X: 'dx', Y: 'dy' } } },"
		"  'Device.A.B.{i}': { schema: { schema: { N: dm_type.STRING }, defaults: { N: 'n0' } } },"
		"  'Device.C': { schema: { schema: { K: dm_type.STRING }, defaults: { K: 'k0' } } },"
		"  'Device.Z': { schema: { schema: { Q: dm_type.STRING } } },"
		"  'Device.W': 'not an entry',"
		"});"
		"d.set_config({ Device: { A: { X: 'set', B: { '1': {}, '2': { N: 'two' } } } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device.A'), d.get_subtree_with_state('Device'),"
		"  d.get_subtree('Device'), d.get_subtree_with_state(null),"
		"  d.get_subtree_with_state('Device.A.B.2'), d.get_subtree_with_state('Device.A.B.3') ];",
		"[ { \"X\": \"set\", \"B\": { \"1\": { \"N\": \"n0\" }, \"2\": { \"N\": \"two\" } }, \"Y\": \"dy\" }, "
		"{ \"A\": { \"X\": \"set\", \"B\": { \"1\": { \"N\": \"n0\" }, \"2\": { \"N\": \"two\" } }, "
		"\"Y\": \"dy\" }, \"C\": { \"K\": \"k0\" } }, "
		"{ \"A\": { \"X\": \"set\", \"B\": { \"1\": { }, \"2\": { \"N\": \"two\" } } } }, { }, "
		"{ \"N\": \"two\" }, { } ]");
}

static void
test_subtree_instance_mode(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let calls = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.T.{i}': { get: (ctx) => {"
		"      push(calls, [ 'row', ctx.instance, ctx.instances, ctx.config, ctx.parent, type(ctx.root) ]);"
		"      return { Seen: 'y' }; },"
		"    schema: { schema: { Name: dm_type.STRING, Seen: dm_type.STRING, Extra: dm_type.STRING },"
		"      defaults: { Name: 'dn', Extra: 'de' } } },"
		"  'Device.T.{i}.Stats': { get: (ctx) => {"
		"      push(calls, [ 'stats', ctx.instance, ctx.instances, ctx.config, ctx.parent?.Name ]);"
		"      return { Bytes: ctx.instance * 10 }; },"
		"    schema: { schema: { Bytes: dm_type.UINT } } },"
		"  'Device.T.{i}.Sub.{i}': { get: (ctx) => {"
		"      push(calls, [ 'sub', ctx.instance, ctx.instances, ctx.config, ctx.parent?.Name ]);"
		"      return { V: 'v' + ctx.instance }; },"
		"    schema: { schema: { V: dm_type.STRING, W: dm_type.STRING } } },"
		"});"
		"d.set_config({ Device: { T: { '1': { Name: 'a', Sub: { '3': { W: 'w' } } }, '2': {} } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device.T'), calls ];",
		"[ { \"1\": { \"Name\": \"a\", \"Sub\": { \"3\": { \"W\": \"w\", \"V\": \"v3\" } }, \"Seen\": \"y\", "
		"\"Stats\": { \"Bytes\": 10 } }, \"2\": { \"Seen\": \"y\", \"Stats\": { \"Bytes\": 20 } } }, "
		"[ [ \"row\", 1, [ 1 ], { \"Name\": \"a\", \"Sub\": { \"3\": { \"W\": \"w\" } }, \"Extra\": \"de\" }, "
		"null, \"object\" ], "
		"[ \"row\", 2, [ 2 ], { \"Name\": \"dn\", \"Extra\": \"de\" }, null, \"object\" ], "
		"[ \"stats\", 1, [ 1 ], null, \"a\" ], [ \"stats\", 2, [ 2 ], null, null ], "
		"[ \"sub\", 3, [ 1, 3 ], { \"W\": \"w\" }, \"a\" ] ] ]");
}

static void
test_subtree_project(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"global.dp = ubbf.create();"
		"dp.register({"
		"  'Device.P': { get: () => ({ A: '1', Bogus: '2', '.meta': 3, Kid: { K: 'k', Junk: 'j' },"
		"      Gone: { z: 1 }, Hid: { h: 1 }, HidT: { '1': {} }, Rows: { '1': { R: 'r', Bad: 'b' } } }),"
		"    schema: { schema: { A: dm_type.STRING } } },"
		"  'Device.P.Kid': { schema: { schema: { K: dm_type.STRING } } },"
		"  'Device.P.Rows.{i}': { schema: { schema: { R: dm_type.STRING } } },"
		"  'Device.Q': { get: () => ({ Free: 'f', Obj: { x: 1 } }) },"
		"});"
		"dp.register_hidden([ 'Device.P.Hid', 'Device.P.HidT.{i}' ]);"
		"dp.set_config({ Device: { P: {} } });"
		"dp.runtime_reload();"
		"return [ dp.get_subtree_with_state('Device.P'), dp.get_subtree_with_state('Device.Q') ];",
		"[ { \"A\": \"1\", \".meta\": 3, \"Kid\": { \"K\": \"k\" }, \"Rows\": { \"1\": { \"R\": \"r\" } } }, "
		"{ \"Free\": \"f\", \"Obj\": { \"x\": 1 } } ]");
	assert_string_equal(err,
		"ubbf.dm: Device.P.Kid: get handler returned Junk, which the schema does not declare\n"
		"ubbf.dm: Device.P.Rows.{i}: get handler returned Bad, which the schema does not declare\n"
		"ubbf.dm: Device.P: get handler returned Bogus, which the schema does not declare\n"
		"ubbf.dm: Device.P: get handler returned Gone, which the model does not register\n");

	/* each removed key is logged once */
	err = eval_capture(vm,
		"let r = dp.get_subtree_with_state('Device.P');"
		"delete global.dp;"
		"return r;",
		"{ \"A\": \"1\", \".meta\": 3, \"Kid\": { \"K\": \"k\" }, \"Rows\": { \"1\": { \"R\": \"r\" } } }");
	assert_string_equal(err, "");
}

static void
test_subtree_status_derive(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.E.{i}': { enable_status_derive: true,"
		"    schema: { schema: { Enable: dm_type.BOOL, Status: dm_type.STRING } } },"
		"  'Device.F.{i}': { enable_status_derive: 'true', get: () => ({ Status: 'Bogus', X: 'x' }),"
		"    schema: { schema: { Enable: dm_type.BOOL, Status: dm_type.STRING, X: dm_type.STRING } } },"
		"  'Device.G.{i}': { enable_status_derive: true, get: () => 'not an object',"
		"    schema: { schema: { Status: dm_type.STRING } } },"
		"  'Device.H.{i}': { enable_status_derive: false, schema: { schema: { Status: dm_type.STRING } } },"
		"});"
		"d.set_config({ Device: {"
		"  E: { '1': { Enable: 'true' }, '2': { Enable: false }, '3': { Enable: '1' }, '4': { Enable: 'yes' } },"
		"  F: { '1': { Enable: true } }, G: { '1': {} }, H: { '1': { Enable: 'true' } } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device'), d.get_subtree_with_state('Device.E.9'),"
		"  d.get_subtree_with_state('Device.F.5') ];",
		"[ { \"E\": { \"1\": { \"Enable\": \"true\", \"Status\": \"Enabled\" }, "
		"\"2\": { \"Enable\": false, \"Status\": \"Disabled\" }, "
		"\"3\": { \"Enable\": \"1\", \"Status\": \"Enabled\" }, "
		"\"4\": { \"Enable\": \"yes\", \"Status\": \"Disabled\" } }, "
		"\"F\": { \"1\": { \"Enable\": true, \"X\": \"x\", \"Status\": \"Enabled\" } }, "
		"\"G\": { \"1\": { \"Status\": \"Disabled\" } }, \"H\": { \"1\": { \"Enable\": \"true\" } } }, "
		"{ }, { \"X\": \"x\", \"Status\": \"Disabled\" } ]");
}

static void
test_subtree_ancestor(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let calls = 0, ctxs = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.IP.Interface.{i}': { get: (ctx) => {"
		"      calls++;"
		"      push(ctxs, [ ctx.instance, ctx.instances, ctx.config, ctx.parent ]);"
		"      return { Name: 'if' + ctx.instance, IPv6Address: { '1': { IPAddress: 'a1', Junk: 'j' },"
		"        '2': { IPAddress: 'a2' } } }; },"
		"    schema: { schema: { Name: dm_type.STRING, Enable: dm_type.BOOL }, defaults: { Enable: 'false' } } },"
		"  'Device.IP.Interface.{i}.IPv6Address.{i}': { schema: { schema: { IPAddress: dm_type.STRING } } },"
		"});"
		"d.set_config({ Device: { IP: { Interface: { '1': { Name: 'stored' } } } } });"
		"d.runtime_reload();"
		"let below = d.get_subtree_with_state('Device.IP.Interface.1.IPv6Address');"
		"let n1 = calls;"
		"let row = d.get_subtree_with_state('Device.IP.Interface.1');"
		"let p = { 'Device.IP.Interface.1.IPv6Address.1.IPAddress': null,"
		"  'Device.IP.Interface.1.IPv6Address.2.IPAddress': null,"
		"  'Device.IP.Interface.1.IPv6Address.3.IPAddress': 'keep' };"
		"calls = 0;"
		"let rc = d.params_get(p);"
		"let n2 = calls;"
		"let below7 = d.get_subtree_with_state('Device.IP.Interface.7.IPv6Address');"
		"return [ below['1'].IPAddress, below['2'], n1, row, rc, p, n2, below7['2'], ctxs[0], ctxs[-1] ];",
		"[ \"a1\", { \"IPAddress\": \"a2\" }, 1, "
		"{ \"Name\": \"if1\", \"IPv6Address\": { \"1\": { \"IPAddress\": \"a1\" }, \"2\": { \"IPAddress\": \"a2\" } } }, "
		"0, { \"Device.IP.Interface.1.IPv6Address.1.IPAddress\": \"a1\", "
		"\"Device.IP.Interface.1.IPv6Address.2.IPAddress\": \"a2\", "
		"\"Device.IP.Interface.1.IPv6Address.3.IPAddress\": \"keep\" }, 1, { \"IPAddress\": \"a2\" }, "
		"[ 1, [ 1 ], { \"Name\": \"stored\", \"Enable\": \"false\" }, null ], "
		"[ 7, [ 7 ], { \"Enable\": \"false\" }, null ] ]");
	assert_string_equal(err,
		"ubbf.dm: Device.IP.Interface.{i}.IPv6Address.{i}: get handler returned Junk, "
		"which the schema does not declare\n");

	eval_expect(vm,
		"let seen = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.P2.{i}.C.{i}': { get: (ctx) => {"
		"    push(seen, [ ctx.instance, ctx.instances, ctx.config, ctx.parent ]);"
		"    return { Sub: { Val: 'v' }, Name: 'n' }; } },"
		"});"
		"d.set_config({ Device: { P2: { '1': { Tag: 't', C: { '2': {} } } } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device.P2.1.C.2.Sub'), d.get_subtree_with_state('Device.P2.1.C.2.Name'),"
		"  d.get_subtree_with_state('Device.P2.1.C.2.Name.X'), seen[0] ];",
		"[ { \"Val\": \"v\" }, { }, { }, "
		"[ 2, [ 1, 2 ], { }, { \"Tag\": \"t\", \"C\": { \"2\": { } } } ] ]");
}

static void
test_subtree_enumerate(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let seen = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.Hosts': { schema: { schema: { HostNumberOfEntries: dm_type.UINT, Other: dm_type.STRING },"
		"    defaults: { HostNumberOfEntries: '9' } } },"
		"  'Device.Hosts.Host.{i}': { get: (ctx) => {"
		"      push(seen, [ ctx.instance, ctx.instances, ctx.config, ctx.parent ]);"
		"      if (ctx.instance) return ctx.instance == 7 ? { Name: 'h7' } : null;"
		"      return { '1': { Name: 'h1' }, '2': { Name: 'h2', Bad: 1 }, 'x': { Name: 'nope' } }; },"
		"    schema: { schema: { Name: dm_type.STRING } } },"
		"});"
		"d.set_config({ Device: { Hosts: {} } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device'), d.get_subtree_with_state('Device.Hosts'),"
		"  d.get_subtree_with_state('Device.Hosts.Host'), d.get_subtree_with_state('Device.Hosts.Host.7'),"
		"  d.get_subtree_with_state('Device.Hosts.Host.8'), seen ];",
		"[ { \"Hosts\": { \"HostNumberOfEntries\": \"2\", \"Host\": { \"1\": { \"Name\": \"h1\" }, "
		"\"2\": { \"Name\": \"h2\" } } } }, "
		"{ \"HostNumberOfEntries\": \"2\", \"Host\": { \"1\": { \"Name\": \"h1\" }, \"2\": { \"Name\": \"h2\" } } }, "
		"{ \"1\": { \"Name\": \"h1\" }, \"2\": { \"Name\": \"h2\" } }, { \"Name\": \"h7\" }, { }, "
		"[ [ null, [ ], null, null ], [ null, [ ], null, null ], [ null, [ ], null, null ], "
		"[ 7, [ 7 ], null, null ], [ 8, [ 8 ], null, null ] ] ]");
	assert_string_equal(err,
		"ubbf.dm: Device.Hosts.Host.{i}: get handler returned Bad, which the schema does not declare\n");
}

static void
test_subtree_entries_count(void **state)
{
	uc_vm_t *vm = *state;

	/* An empty table leaves its count parked, a parent that is not in
	 * the response gets none, and a parent without a schema entry no
	 * count at all. */
	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.Hosts': { schema: { schema: { HostNumberOfEntries: dm_type.UINT },"
		"    defaults: { HostNumberOfEntries: '9' } } },"
		"  'Device.Hosts.Host.{i}': { get: (ctx) => ctx.instance ? null : {},"
		"    schema: { schema: { Name: dm_type.STRING } } },"
		"  'Device.L': { schema: { schema: { LedNumberOfEntries: dm_type.UINT } } },"
		"  'Device.L.Led.{i}': { get: () => ({}), schema: { schema: { Name: dm_type.STRING } } },"
		"  'Device.M.Row.{i}': { get: () => ({ '1': {} }) },"
		"});"
		"d.set_config({ Device: { Hosts: {} } });"
		"d.runtime_reload();"
		"return d.get_subtree_with_state('Device');",
		"{ \"Hosts\": { \"HostNumberOfEntries\": \"0\" }, \"M\": { \"Row\": { \"1\": { } } } }");

	eval_expect(vm,
		"let seen = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.T.{i}': { schema: { schema: { Name: dm_type.STRING, SubNumberOfEntries: dm_type.UINT } } },"
		"  'Device.T.{i}.Sub.{i}': { get: (ctx) => {"
		"      push(seen, [ ctx.instance, ctx.instances, ctx.parent?.Name ]);"
		"      return ctx.instance ? null : { [ '' + (ctx.instances[0] * 10) ]: { V: 'x' } }; },"
		"    schema: { schema: { V: dm_type.STRING } } },"
		"});"
		"d.set_config({ Device: { T: { '1': { Name: 'a' }, '2': { Name: 'b' } } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device'), seen ];",
		"[ { \"T\": { \"1\": { \"Name\": \"a\", \"Sub\": { \"10\": { \"V\": \"x\" } }, \"SubNumberOfEntries\": \"1\" }, "
		"\"2\": { \"Name\": \"b\", \"Sub\": { \"20\": { \"V\": \"x\" } }, \"SubNumberOfEntries\": \"1\" } } }, "
		"[ [ null, [ 1 ], \"a\" ], [ null, [ 2 ], \"b\" ] ] ]");
}

static void
test_subtree_runtime_instances(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.NAT': { schema: { schema: { PortMappingNumberOfEntries: dm_type.UINT } } },"
		"  'Device.NAT.PortMapping.{i}': { runtime_instances: true,"
		"    get: (ctx) => ctx.instance ? { Origin: 'Controller' } : { '10000': { Origin: 'UPnP' } },"
		"    schema: { schema: { Origin: dm_type.STRING, Description: dm_type.STRING | dm_type.WRITABLE } } },"
		"});"
		"d.set_config({ Device: { NAT: { PortMapping: { '1': { Description: 'd' } } } } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device.NAT'), d.get_subtree_with_state('Device.NAT.PortMapping.1') ];",
		"[ { \"PortMapping\": { \"1\": { \"Description\": \"d\", \"Origin\": \"Controller\" }, "
		"\"10000\": { \"Origin\": \"UPnP\" } }, \"PortMappingNumberOfEntries\": \"2\" }, "
		"{ \"Description\": \"d\", \"Origin\": \"Controller\" } ]");
}

static void
test_subtree_below_runtime_rows(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let seen = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.L.LED.{i}': { addable: false,"
		"    get: (ctx) => ctx.instance ? { Color: 'c' + ctx.instance } : { '1': { Color: 'red' }, '2': { Color: 'blue' } },"
		"    schema: { schema: { Color: dm_type.STRING } } },"
		"  'Device.L.LED.{i}.Cycle': { get: (ctx) => {"
		"      push(seen, [ ctx.instance, ctx.instances, ctx.parent ]);"
		"      return { Of: ctx.instance }; },"
		"    schema: { schema: { Of: dm_type.UINT } } },"
		"});"
		"d.set_config({ Device: { L: {} } });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state('Device.L'), d.get_subtree_with_state('Device.L.LED.1'), seen ];",
		"[ { \"LED\": { \"1\": { \"Color\": \"red\", \"Cycle\": { \"Of\": 1 } }, "
		"\"2\": { \"Color\": \"blue\", \"Cycle\": { \"Of\": 2 } } } }, "
		"{ \"Color\": \"c1\", \"Cycle\": { \"Of\": 1 } }, "
		"[ [ 1, [ 1 ], null ], [ 2, [ 2 ], null ], [ 1, [ 1 ], null ] ] ]");
}

static void
test_subtree_root_pattern(void **state)
{
	uc_vm_t *vm = *state;

	/* A table at the root has no container to merge its rows into, so its
	 * handler does not run. */
	eval_expect(vm,
		"let calls = 0;"
		"let d = ubbf.create();"
		"d.register({ '{i}': { get: () => { calls++; return { '1': { A: 1 } }; } } });"
		"d.set_config({ Device: {} });"
		"d.runtime_reload();"
		"return [ d.get_subtree_with_state(''), calls ];",
		"[ { }, 0 ]");
}

static void
test_params_get(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.Q': { get: (ctx) => ({ Live: 'l' }),"
		"    schema: { schema: { Live: dm_type.STRING, Stored: dm_type.STRING, Def: dm_type.STRING,"
		"      NoDef: dm_type.STRING }, defaults: { Def: 'd' } } },"
		"  'Device.T.{i}': { get: (ctx) => ({}),"
		"    schema: { schema: { Name: dm_type.STRING, Extra: dm_type.STRING }, defaults: { Extra: 'e' } } },"
		"  'Device.Odd': 'not an entry',"
		"});"
		"d.set_config({ Device: { Q: { Stored: 's' }, T: { '3': { Alias: 'lan', Name: 'n3' } } } });"
		"let early = d.params_get({ 'Device.Q.Live': null });"
		"d.runtime_reload();"
		"let p = { 'Device.Q.Live': null, 'Device.Q.Stored': null, 'Device.Q.Def': null,"
		"  'Device.Q.NoDef': 'keep', 'Device.Q.Nope': 'keep2', 'Device.T.3.Name': null,"
		"  'Device.T.lan.Name': null, 'Device.T.[lan].Extra': null, 'Device.T.3.Extra': null,"
		"  'Device.T.9.Extra': 'keep3', 'Device': null, '': 'empty', '...': 'dots' };"
		"let rc = d.params_get(p);"
		"return [ early, rc, p, d.params_get('x'), d.params_get(null), ubbf.create().params_get({}) ];",
		"[ -1, 0, { \"Device.Q.Live\": \"l\", \"Device.Q.Stored\": \"s\", \"Device.Q.Def\": \"d\", "
		"\"Device.Q.NoDef\": \"keep\", \"Device.Q.Nope\": \"keep2\", \"Device.T.3.Name\": \"n3\", "
		"\"Device.T.lan.Name\": \"n3\", \"Device.T.[lan].Extra\": \"e\", \"Device.T.3.Extra\": \"e\", "
		"\"Device.T.9.Extra\": \"keep3\", \"Device\": { \"Q\": { \"Stored\": \"s\" }, "
		"\"T\": { \"3\": { \"Alias\": \"lan\", \"Name\": \"n3\" } } }, \"\": \"empty\", \"...\": \"dots\" }, "
		"-1, -1, -1 ]");
}

static void
test_params_set_paths(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.T': {},"
		"  'Device.T.{i}': { schema: { schema: { Name: dm_type.STRING | dm_type.WRITABLE,"
		"    Alias: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.T.{i}.Sub.{i}': { schema: { schema: { V: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.X': { schema: { schema: { Y: dm_type.STRING | dm_type.WRITABLE } } },"
		"});"
		"d.set_config({ Device: { T: { '1': { Name: 'a' }, '3': { Alias: 'lan' }, 'Medium': { Name: 'm' } } } });"
		"let e = ubbf.create();"
		"e.register({});"
		"return [ d.params_set({ 'Device.X.Y': 'y' }), d.params_set({ 'Device.T.1.Name': 'b' }),"
		"  d.params_set({ 'Device.T.lan.Name': 'l' }), d.params_set({ 'Device.T.[lan].Alias': 'lan2' }),"
		"  d.params_set({ 'Device.T.Medium.Name': 'mm' }), d.params_set({ 'Device.T.7.Name': 'x' }),"
		"  d.params_set({ 'Device.T.junk.Name': 'x' }), d.params_set({ 'Device.Nope.Name': 'x' }),"
		"  d.params_set({ 'Device.T.1.Sub.4.V': 'v' }),"
		"  d.params_set({ 'Device.T.1.Name': 'c', 'Device.T.8.Name': 'x', 'Device.T.junk.Name': 'y' }),"
		"  d.params_set({ '': 'x' }), d.params_set('x'), d.params_set(null),"
		"  ubbf.create().params_set({ 'Device.X.Y': '1' }), e.params_set({ 'Device.X.Y': '1' }),"
		"  d.config() ];",
		"[ 0, 0, 0, 0, 0, -2, -1, -1, 0, -2, 0, -1, -1, -1, -1, "
		"{ \"Device\": { \"T\": { \"1\": { \"Name\": \"c\", \"Sub\": { \"4\": { \"V\": \"v\" } } }, "
		"\"3\": { \"Alias\": \"lan2\", \"Name\": \"l\" }, \"Medium\": { \"Name\": \"mm\" } }, "
		"\"X\": { \"Y\": \"y\" } } } ]");
	assert_string_equal(err,
		"ubbf.dm.params_set: no such instance for Device.T.7.Name\n"
		"ubbf.dm.params_set: rejecting invalid path Device.T.junk.Name\n"
		"ubbf.dm.params_set: rejecting invalid path Device.Nope.Name\n"
		"ubbf.dm.params_set: no such instance for Device.T.8.Name\n"
		"ubbf.dm.params_set: rejecting invalid path Device.T.junk.Name\n");
}

static void
test_params_set_handlers(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let log = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.S.{i}': { set: (ctx) => {"
		"      push(log, [ ctx.path, ctx.param, ctx.value, ctx.instance, ctx.config.Name, ctx.config.New,"
		"        ctx.root === d.config() ]);"
		"      return ctx.value == 'bad' ? -USP_ERR_INVALID_VALUE : (ctx.value == 'pos' ? 5 : null); },"
		"    schema: { schema: { Name: dm_type.STRING | dm_type.WRITABLE, New: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.S2': { set: (ctx) => { push(log, [ ctx.path, ctx.instance, ctx.config.V ]); return -1; },"
		"    schema: { schema: { V: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.S3': { set: 'not a function', schema: { schema: { V: dm_type.STRING | dm_type.WRITABLE } } },"
		"});"
		"d.set_config({ Device: { S: { '1': { Name: 'old' } } } });"
		"let at = (p) => ubbf.navigate_data(d.config(), ubbf.path_to_parts(p));"
		"let r = [];"
		"push(r, d.params_set({ 'Device.S.1.Name': 'bad' }), at('Device.S.1.Name'));"
		"push(r, d.params_set({ 'Device.S.1.New': 'bad' }), exists(d.config().Device.S['1'], 'New'));"
		"push(r, d.params_set({ 'Device.S.1.Name': 'good' }), at('Device.S.1.Name'));"
		"push(r, d.params_set({ 'Device.S.1.Name': 'pos' }));"
		"push(r, d.params_set({ 'Device.S2.V': 'v' }), at('Device.S2.V'));"
		"push(r, d.params_set({ 'Device.S3.V': 'v' }), at('Device.S3.V'));"
		"push(r, d.params_set({ 'Device.S.1.Name': 'bad', 'Device.S.1.New': 'n' }), at('Device.S.1'));"
		"d.trans_start();"
		"push(r, d.params_set({ 'Device.S.1.Name': 'ws' }), at('Device.S.1.Name'));"
		"d.trans_abort();"
		"push(r, at('Device.S.1.Name'));"
		"return [ r, log ];",
		"[ [ -7012, \"old\", -7012, false, 0, \"good\", 0, -1, null, 0, \"v\", -7012, "
		"{ \"Name\": \"pos\", \"New\": \"n\" }, 0, \"ws\", \"pos\" ], "
		"[ [ \"Device.S.1.Name\", \"Name\", \"bad\", 1, \"bad\", null, true ], "
		"[ \"Device.S.1.New\", \"New\", \"bad\", 1, \"old\", \"bad\", true ], "
		"[ \"Device.S.1.Name\", \"Name\", \"good\", 1, \"good\", null, true ], "
		"[ \"Device.S.1.Name\", \"Name\", \"pos\", 1, \"pos\", null, true ], "
		"[ \"Device.S2.V\", null, \"v\" ], "
		"[ \"Device.S.1.Name\", \"Name\", \"bad\", 1, \"bad\", null, true ], "
		"[ \"Device.S.1.New\", \"New\", \"n\", 1, \"pos\", \"n\", true ], "
		"[ \"Device.S.1.Name\", \"Name\", \"ws\", 1, \"ws\", \"n\", true ] ] ]");
}

static void
test_params_set_runtime_rows(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let seen = [];"
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.NAT.PortMapping.{i}': { runtime_instances: true, get: () => null,"
		"    schema: { schema: { Description: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.UP.Row.{i}': { runtime_instances: true, writable_rows: true,"
		"    get: (ctx) => { push(seen, [ ctx.instance, ctx.instances, ctx.config, ctx.parent ]);"
		"      return ctx.instance == 5 ? { X: 'live' } : null; },"
		"    schema: { schema: { X: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.UP.Row.{i}.Sub.{i}': { schema: { schema: { Y: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.L.LED.{i}': { addable: false, get: () => ({}),"
		"    schema: { schema: { Color: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.L.LED.{i}.Cfg': { schema: { schema: { Z: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.K.Key.{i}': { addable: false, get: () => ({}), set: () => null,"
		"    schema: { schema: { Name: dm_type.STRING | dm_type.WRITABLE } } },"
		"  'Device.M.Max.{i}': { maxInstances: 0, get: () => ({}),"
		"    schema: { schema: { Name: dm_type.STRING | dm_type.WRITABLE } } },"
		"});"
		"d.set_config({ Device: { NAT: { PortMapping: { '1': {} } }, L: {} } });"
		"return [ d.params_set({ 'Device.NAT.PortMapping.1.Description': 'a' }),"
		"  d.params_set({ 'Device.NAT.PortMapping.10000.Description': 'b' }),"
		"  d.params_set({ 'Device.UP.Row.5.X': 'w' }), d.params_set({ 'Device.UP.Row.6.X': 'w' }),"
		"  d.params_set({ 'Device.UP.Row.5.Sub.1.Y': 'y' }), d.params_set({ 'Device.UP.Row.6.Sub.1.Y': 'y' }),"
		"  d.params_set({ 'Device.L.LED.1.Color': 'red' }), d.params_set({ 'Device.L.LED.1.Cfg.Z': 'z' }),"
		"  d.params_set({ 'Device.K.Key.1.Name': 'n' }), d.params_set({ 'Device.M.Max.1.Name': 'n' }),"
		"  d.config(), seen ];",
		"[ 0, -2, 0, -2, 0, -2, -3, -3, 0, -3, "
		"{ \"Device\": { \"NAT\": { \"PortMapping\": { \"1\": { \"Description\": \"a\" } } }, \"L\": { }, "
		"\"UP\": { \"Row\": { \"5\": { \"X\": \"w\", \"Sub\": { \"1\": { \"Y\": \"y\" } } } } }, "
		"\"K\": { \"Key\": { \"1\": { \"Name\": \"n\" } } } } }, "
		"[ [ 5, [ 5 ], null, null ], [ 6, [ 6 ], null, null ], [ 6, [ 6 ], null, null ] ] ]");
	assert_string_equal(err,
		"ubbf.dm.params_set: no such instance for Device.NAT.PortMapping.10000.Description\n"
		"ubbf.dm.params_set: no such instance for Device.UP.Row.6.X\n"
		"ubbf.dm.params_set: no such instance for Device.UP.Row.6.Sub.1.Y\n"
		"ubbf.dm.params_set: Device.L.LED.1.Color is in a row the device makes, nothing stores it\n"
		"ubbf.dm.params_set: Device.L.LED.1.Cfg.Z is in a row the device makes, nothing stores it\n"
		"ubbf.dm.params_set: Device.M.Max.1.Name is in a row the device makes, nothing stores it\n");
}

static void
test_params_set_values(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let d = ubbf.create();"
		"d.register({"
		"  'Device.V': { schema: { schema: { B: dm_type.BOOL | dm_type.WRITABLE, U: dm_type.UINT | dm_type.WRITABLE,"
		"    S: dm_type.STRING | dm_type.WRITABLE }, constraints: { U: { max: 10 } } } },"
		"  'Device.T.{i}': { schema: { schema: { N: dm_type.UINT | dm_type.WRITABLE } } },"
		"});"
		"d.set_config({ Device: { V: {}, T: { '2': { Alias: 'a2' } } } });"
		"return [ d.params_set({ 'Device.V.U': '11' }), d.params_set({ 'Device.V.S': 'ok', 'Device.V.B': 'maybe' }),"
		"  d.params_set({ 'Device.V.U': 10, 'Device.V.B': true }), d.params_set({ 'Device.T.a2.N': 'x' }),"
		"  d.params_set({ 'Device.T.2.N': '7' }), d.params_set({ 'Device.V.Unknown': 'x' }), d.config() ];",
		"[ -4, -4, 0, -4, 0, 0, { \"Device\": { \"V\": { \"U\": 10, \"B\": true, \"Unknown\": \"x\" }, "
		"\"T\": { \"2\": { \"Alias\": \"a2\", \"N\": \"7\" } } } } ]");
	assert_string_equal(err,
		"ubbf.dm.params_set: rejecting Device.V.U: above the maximum of 10\n"
		"ubbf.dm.params_set: rejecting Device.V.B: not a boolean\n"
		"ubbf.dm.params_set: rejecting Device.T.a2.N: not an integer\n");
}

/* 20 segments of 28 characters below Device: 586 bytes */
static const char DEEP_PATH[] =
	"let deep = 'Device';"
	"for (let i = 0; i < 20; i++) deep += '.Segment_with_a_long_name_000';";

static void
test_path_long(void **state)
{
	uc_vm_t *vm = *state;

	model_expect(vm, DEEP_PATH,
		"let d = ubbf.create(), m = {}, w = {}, p = {};"
		"m[deep] = { get: (ctx) => ({ Live: 'l' }), schema: { schema: { Live: dm_type.STRING,"
		"  W: dm_type.STRING | dm_type.WRITABLE, Def: dm_type.STRING }, defaults: { Def: 'd' } } };"
		"d.register(m);"
		"d.set_config({ Device: {} });"
		"w[deep + '.W'] = 'v';"
		"let rc = d.params_set(w);"
		"d.runtime_reload();"
		"p[deep + '.W'] = null; p[deep + '.Live'] = null; p[deep + '.Def'] = null;"
		"d.params_get(p);"
		"let s = d.get_subtree_with_state(deep + '.');"
		"return [ length(deep), rc, values(p), s.W, s.Live, d.path_known(deep + '.'),"
		"  d.path_known(deep + '.W'), sort(map(d.names(deep + '.', true), (e) => substr(e.path, length(deep)))) ];",
		"[ 586, 0, [ \"v\", \"l\", \"d\" ], \"v\", \"l\", 1, 2, [ \".Def\", \".Live\", \".W\" ] ]");
}

/* 71 segments: the first 64 of them name a parameter of Device.A...A */
static const char MANY_PATH[] =
	"let many = 'Device', pre = 'Device';"
	"for (let i = 0; i < 70; i++) many += '.A';"
	"for (let i = 0; i < 62; i++) pre += '.A';";

static void
test_path_too_many_segments(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;
	char *src;

	assert_true(asprintf(&src, "%s%s", MANY_PATH,
		"let d = ubbf.create(), m = {}, w = {}, p = {};"
		"m[pre] = { get: (ctx) => ({ A: 'cut' }), schema: { schema: { A: dm_type.STRING | dm_type.WRITABLE } } };"
		"d.register(m);"
		"d.set_config({ Device: {} });"
		"d.runtime_reload();"
		"w[many] = 'x';"
		"p[many] = 'keep';"
		"let rc = d.params_set(w);"
		"d.params_get(p);"
		"return [ rc, d.config(), values(p), d.get_subtree_with_state(many), d.path_known(many),"
		"  d.names(many + '.') ];") > 0);
	err = eval_capture(vm, src,
		"[ -1, { \"Device\": { } }, [ \"keep\" ], { }, 0, null ]");
	free(src);

	assert_non_null(strstr(err, "ubbf.dm.params_set: rejecting invalid path Device.A.A."));
}

static void
test_path_empty_segment(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	err = eval_capture(vm,
		"let d = ubbf.create();"
		"d.register({ 'Device.Q': { get: (ctx) => ({ Live: 'l' }),"
		"  schema: { schema: { Live: dm_type.STRING, W: dm_type.STRING | dm_type.WRITABLE } } } });"
		"d.set_config({ Device: { Q: { W: 'w' } } });"
		"d.runtime_reload();"
		"let p = { 'Device..Q.Live': 'keep1', 'Device.Q..Live': 'keep2', 'Device.Q.Live..': 'keep3',"
		"  'Device.Q.Live': null };"
		"d.params_get(p);"
		"return [ p, d.params_set({ 'Device.Q..W': 'x' }), d.params_set({ 'Device.Q.W..': 'x' }), d.config(),"
		"  d.get_subtree_with_state('Device..Q'), d.get_subtree_with_state('Device.Q..'),"
		"  d.path_known('Device..Q.Live'), d.path_known('Device.Q.Live..'), d.path_known('Device.Q.Live'),"
		"  d.names('Device..Q.') ];",
		"[ { \"Device..Q.Live\": \"keep1\", \"Device.Q..Live\": \"keep2\", \"Device.Q.Live..\": \"keep3\", "
		"\"Device.Q.Live\": \"l\" }, -1, -1, { \"Device\": { \"Q\": { \"W\": \"w\" } } }, "
		"{ }, { }, 0, 0, 2, null ]");
	assert_string_equal(err,
		"ubbf.dm.params_set: rejecting invalid path Device.Q..W\n"
		"ubbf.dm.params_set: rejecting invalid path Device.Q.W..\n");
}

static void
test_refresh_instances(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({ 'Device.H.{i}': { get: (ctx) => ctx.instance ? null : { '5': {} } } });"
		"d.set_config({ Device: { T: { '1': { Sub: { '2': {} } }, '3': {} }, X: {} } });"
		"d.runtime_reload();"
		"return [ d.refresh_instances('Device.T.'), d.refresh_instances('Device'),"
		"  d.refresh_instances('..Device.T..'), d.refresh_instances('Device.Nope'), d.refresh_instances(5) ];",
		"[ [ \"Device.T.1\", \"Device.T.1.Sub.2\", \"Device.T.3\" ], "
		"[ \"Device.T.1\", \"Device.T.1.Sub.2\", \"Device.T.3\", \"Device.H.5\" ], "
		"[ ], [ ], [ ] ]");
}

static void
test_handler_exceptions(void **state)
{
	uc_vm_t *vm = *state;
	const char *err;

	ulog_open(ULOG_STDIO, LOG_DAEMON, "t");

	/* a throwing set handler refuses its write, whether a call follows or
	 * not, and the exception goes to the log */
	err = eval_capture(vm,
		"let d = ubbf.create();"
		"d.register({ 'Device.S': { set: (ctx) => { if (ctx.param == 'Bad') die('set broken'); },"
		"  schema: { schema: { Good: dm_type.STRING | dm_type.WRITABLE, Bad: dm_type.STRING | dm_type.WRITABLE } } } });"
		"d.set_config({ Device: { S: { Bad: 'old' } } });"
		"let last = d.params_set({ 'Device.S.Bad': 'new' });"
		"let first = d.params_set({ 'Device.S.Bad': 'x', 'Device.S.Good': 'g' });"
		"return [ last, first, d.config().Device.S ];",
		"[ -1, -1, { \"Bad\": \"old\", \"Good\": \"g\" } ]");
	assert_non_null(strstr(err, "set broken"));

	/* a throwing get handler leaves its row without data, first or last */
	err = eval_capture(vm,
		"let rows = [];"
		"for (let bad in [ 1, 2 ]) {"
		"  let d = ubbf.create();"
		"  d.register({ 'Device.G': {}, 'Device.G.{i}': {"
		"    get: (ctx) => ctx.instance == bad ? die('get broken') : { Name: 'n' + ctx.instance },"
		"    schema: { schema: { Name: dm_type.STRING } } } });"
		"  d.set_config({ Device: { G: { '1': {}, '2': {} } } });"
		"  d.runtime_reload();"
		"  push(rows, d.get_subtree_with_state('Device.G.'));"
		"}"
		"return rows;",
		"[ { \"1\": { }, \"2\": { \"Name\": \"n2\" } }, { \"1\": { \"Name\": \"n1\" }, \"2\": { } } ]");
	assert_non_null(strstr(err, "get broken"));
}

static void
test_ancestor_projection(void **state)
{
	uc_vm_t *vm = *state;

	/* a row that an ancestor handler makes passes the same projection as
	 * one its own handler makes */
	eval_capture(vm,
		"let d = ubbf.create();"
		"d.register({ 'Device': {}, 'Device.IP': {}, 'Device.IP.Interface': {},"
		"  'Device.IP.Interface.{i}': { get: (ctx) => ({ Name: 'x',"
		"    IPv6Address: { '1': { IPAddress: 'a', Junk: 'j' } } }),"
		"    schema: { schema: { Name: dm_type.STRING } } },"
		"  'Device.IP.Interface.{i}.IPv6Address': {},"
		"  'Device.IP.Interface.{i}.IPv6Address.{i}': { schema: { schema: { IPAddress: dm_type.STRING } } } });"
		"d.set_config({ Device: { IP: { Interface: { '1': { IPv6Address: { '1': {} } } } } } });"
		"d.runtime_reload();"
		"let leaves = { 'Device.IP.Interface.1.IPv6Address.1.Junk': null,"
		"  'Device.IP.Interface.1.IPv6Address.1.IPAddress': null };"
		"d.params_get(leaves);"
		"return [ d.get_subtree_with_state('Device.IP.Interface.1.IPv6Address'), leaves,"
		"  d.path_known('Device'), d.path_known('Device.'), d.path_known('Nope') ];",
		"[ { \"1\": { \"IPAddress\": \"a\" } },"
		" { \"Device.IP.Interface.1.IPv6Address.1.Junk\": null,"
		" \"Device.IP.Interface.1.IPv6Address.1.IPAddress\": \"a\" },"
		" 1, 1, 0 ]");

	/* a path of one segment names no parameter of an object */
	eval_expect(vm,
		"let d = ubbf.create();"
		"d.register({ 'Device': { schema: { schema: { X: dm_type.STRING | dm_type.WRITABLE } } } });"
		"d.set_config({ Device: {} });"
		"return d.params_set({ 'Device': 'x' });",
		"-1");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_slots),
		cmocka_unit_test(test_not_a_dm),
		cmocka_unit_test(test_load),
		cmocka_unit_test(test_get_subtree),
		cmocka_unit_test(test_path_known),
		cmocka_unit_test(test_names),
		cmocka_unit_test(test_names_next_level),
		cmocka_unit_test(test_names_refused),
		cmocka_unit_test(test_subtree_defaults),
		cmocka_unit_test(test_subtree_instance_mode),
		cmocka_unit_test(test_subtree_project),
		cmocka_unit_test(test_subtree_status_derive),
		cmocka_unit_test(test_subtree_ancestor),
		cmocka_unit_test(test_subtree_enumerate),
		cmocka_unit_test(test_subtree_entries_count),
		cmocka_unit_test(test_subtree_runtime_instances),
		cmocka_unit_test(test_subtree_below_runtime_rows),
		cmocka_unit_test(test_subtree_root_pattern),
		cmocka_unit_test(test_params_get),
		cmocka_unit_test(test_params_set_paths),
		cmocka_unit_test(test_params_set_handlers),
		cmocka_unit_test(test_params_set_runtime_rows),
		cmocka_unit_test(test_params_set_values),
		cmocka_unit_test(test_path_long),
		cmocka_unit_test(test_path_too_many_segments),
		cmocka_unit_test(test_path_empty_segment),
		cmocka_unit_test(test_refresh_instances),
		cmocka_unit_test(test_handler_exceptions),
		cmocka_unit_test(test_ancestor_projection),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
