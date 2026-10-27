/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * gate.c, the write gate. The callbacks are ucode closures, so the cases
 * run as scripts.
 */

#include "harness.h"
#include "ubbf.h"

#define FIXTURE								\
	"let t = { busy: false, scheduled: [], errors: [], log: [] };"	\
	"t.gate = ubbf.write_gate_create(() => t.busy,"			\
	"  (gate) => push(t.scheduled, gate),"				\
	"  (what, e) => push(t.errors, [ what, e.message ]));"		\
	"t.job = (name) => () => { push(t.log, name); return { name }; };" \
	"t.run = () => { while (length(t.scheduled)) shift(t.scheduled).drain(); };"

static void
test_free_and_queued(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm, FIXTURE
		"let done = [];"
		"let a = t.gate.write(t.job('a'), (r) => push(done, r.name));"
		"t.busy = true;"
		"let b = t.gate.write(t.job('b'), (r) => push(done, r.name));"
		"let held = length(t.scheduled);"
		"t.busy = false;"
		"t.gate.release();"
		"t.gate.release();"
		"let once = length(t.scheduled);"
		"let gate_passed = (t.scheduled[0] == t.gate);"
		"t.run();"
		"return [ a, b, held, once, gate_passed, t.log, done ];");

	assert_json_equal(vm, res,
		"[ { \"name\": \"a\" }, null, 0, 1, true, [ \"a\", \"b\" ], [ \"b\" ] ]");
	ucv_put(res);
}

static void
test_failures_reported(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm, FIXTURE
		"let done = [];"
		"t.busy = true;"
		"t.gate.write(() => die('boom'), (r) => push(done, r));"
		"t.gate.write(t.job('b'), (r) => die('reply boom'));"
		"t.gate.write(t.job('c'), (r) => push(done, r));"
		"t.busy = false;"
		"t.gate.release();"
		"t.run();"
		"return [ t.log, done, t.errors ];");

	assert_json_equal(vm, res,
		"[ [ \"b\", \"c\" ], "
		"[ { \"success\": false, \"error\": \"Write failed\" }, { \"name\": \"c\" } ], "
		"[ [ \"queued write\", \"boom\" ], [ \"queued write reply\", \"reply boom\" ] ] ]");
	ucv_put(res);
}

static void
test_free_job_throws(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm, FIXTURE
		"let msg;"
		"try { t.gate.write(() => die('direct'), () => null); }"
		"catch (e) { msg = e.message; }"
		"return [ msg, t.errors, t.gate.write(t.job('next'), () => null) ];");

	assert_json_equal(vm, res, "[ \"direct\", [ ], { \"name\": \"next\" } ]");
	ucv_put(res);
}

static void
test_callback_exceptions_propagate(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm,
		"let out = [];"
		"let g = ubbf.write_gate_create(() => die('busy broken'), () => null, () => null);"
		"try { g.write(() => 1, () => null); } catch (e) { push(out, e.message); }"
		"let held = true;"
		"g = ubbf.write_gate_create(() => held, () => die('schedule broken'), () => null);"
		"g.write(() => 1, () => null);"
		"held = false;"
		"try { g.release(); } catch (e) { push(out, e.message); }"
		"held = true;"
		"g = ubbf.write_gate_create(() => held, (gate) => null, () => die('on_error broken'));"
		"g.write(() => die('job broken'), () => null);"
		"g.write(() => 2, (r) => push(out, r));"
		"held = false;"
		"try { g.drain(); } catch (e) { push(out, e.message); }"
		"g.drain();"
		"return out;");

	assert_json_equal(vm, res,
		"[ \"busy broken\", \"schedule broken\", \"on_error broken\", 2 ]");
	ucv_put(res);
}

static void
test_nested_write_runs_at_once(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm, FIXTURE
		"let inner;"
		"t.busy = true;"
		"t.gate.write(() => { inner = t.gate.write(t.job('inner'), () => null);"
		"  return { name: 'outer' }; }, () => null);"
		"t.busy = false;"
		"t.gate.release();"
		"t.run();"
		"return [ inner, t.log ];");

	assert_json_equal(vm, res, "[ { \"name\": \"inner\" }, [ \"inner\" ] ]");
	ucv_put(res);
}

static void
test_drain_stops_when_held(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res = vm_eval(vm, FIXTURE
		"t.busy = true;"
		"t.gate.write(() => { push(t.log, 'a'); t.busy = true; return {}; }, () => null);"
		"t.gate.write(t.job('b'), () => null);"
		"t.busy = false;"
		"t.gate.release();"
		"t.run();"
		"let first = [ ...t.log ];"
		"t.busy = false;"
		"t.gate.release();"
		"t.run();"
		"return [ first, t.log ];");

	assert_json_equal(vm, res, "[ [ \"a\" ], [ \"a\", \"b\" ] ]");
	ucv_put(res);
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_free_and_queued),
		cmocka_unit_test(test_failures_reported),
		cmocka_unit_test(test_free_job_throws),
		cmocka_unit_test(test_callback_exceptions_propagate),
		cmocka_unit_test(test_nested_write_runs_at_once),
		cmocka_unit_test(test_drain_stops_when_held),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
