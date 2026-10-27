/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * schedule.c: the intervals of schedule rows, their fw4 windows, Status and
 * TimeLeft, and the check and pruning of ScheduleRef. Times are seconds of
 * the week; Monday 00:00 is 0.
 */

#include "harness.h"
#include "ubbf.h"

static void
eval_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_json_equal(vm, res, expected);
	ucv_put(res);
}

static void
test_start_time_valid(void **state)
{
	eval_expect(*state,
		"return map([ null, '', 0, '00:00', '23:59', '24:00', '7:30', '12:60', ' 12:00', 'x' ],"
		"  (v) => ubbf.start_time_valid(v));",
		"[ true, true, true, true, true, false, false, false, false, false ]");
}

static void
test_schedule_intervals(void **state)
{
	uc_vm_t *vm = *state;

	/* every day 08:00 for an hour */
	eval_expect(vm, "return length(ubbf.schedule_intervals({ StartTime: '08:00', Duration: '3600' }));", "7");
	/* Monday and Friday, until midnight */
	eval_expect(vm,
		"return ubbf.schedule_intervals({ StartTime: '22:00', Day: 'Friday, Monday,Funday' });",
		"[ [ 79200, 86400 ], [ 424800, 432000 ] ]");
	/* Sunday 23:00 for two hours wraps into Monday */
	eval_expect(vm,
		"return ubbf.schedule_intervals({ StartTime: '23:00', Day: 'Sunday', Duration: 7200 });",
		"[ [ 0, 3600 ], [ 601200, 604800 ] ]");
	/* InverseMode gives the rest of the week */
	eval_expect(vm,
		"return ubbf.schedule_intervals({ StartTime: '00:00', Day: 'Monday', Duration: '86400',"
		"  InverseMode: 'true' });",
		"[ [ 86400, 604800 ] ]");
	/* a duration of more than a week is a week */
	eval_expect(vm,
		"return ubbf.schedule_intervals({ StartTime: '00:00', Day: 'Monday', Duration: '999999' });",
		"[ [ 0, 604800 ] ]");
	eval_expect(vm,
		"return [ ubbf.schedule_intervals({}), ubbf.schedule_intervals({ StartTime: '25:00' }),"
		"  ubbf.schedule_intervals(null) ];",
		"[ null, null, null ]");
}

static void
test_intervals(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm, "return ubbf.intervals_union([ [ 10, 20 ], [ 0, 5 ], [ 5, 8 ], [ 15, 30 ], 'x' ]);",
		    "[ [ 0, 8 ], [ 10, 30 ] ]");
	eval_expect(vm, "return ubbf.intervals_complement([ [ 0, 8 ], [ 10, 30 ] ]);",
		    "[ [ 8, 10 ], [ 30, 604800 ] ]");
	eval_expect(vm, "return ubbf.intervals_complement([]);", "[ [ 0, 604800 ] ]");
	/* an interval that ends the week continues into one that starts it */
	eval_expect(vm,
		"let iv = [ [ 0, 100 ], [ 604000, 604800 ] ];"
		"return [ ubbf.intervals_active(iv, 50), ubbf.intervals_active(iv, 100),"
		"  ubbf.intervals_active(iv, 604799), ubbf.intervals_active([], 0) ];",
		"[ true, false, true, false ]");
	eval_expect(vm,
		"return ubbf.week_seconds({ wday: 0, hour: 1, min: 2, sec: 3 });",
		"522123");
}

static void
test_windows(void **state)
{
	eval_expect(*state,
		"return ubbf.intervals_to_windows([ [ 28800, 32400 ], [ 115200, 118800 ],"
		"  [ 601200, 604800 ] ]);",
		"[ { \"start_time\": \"08:00:00\", \"stop_time\": \"08:59:59\", "
		"\"weekdays\": [ \"Monday\", \"Tuesday\" ] }, "
		"{ \"start_time\": \"23:00:00\", \"stop_time\": \"23:59:59\", \"weekdays\": [ \"Sunday\" ] } ]");
}

static void
test_schedule_state(void **state)
{
	uc_vm_t *vm = *state;

	eval_expect(vm,
		"let row = { Enable: 'true', StartTime: '08:00', Day: 'Monday', Duration: '3600' };"
		"return [ ubbf.schedule_state(row, true, 28800 + 600), ubbf.schedule_state(row, true, 0),"
		"  ubbf.schedule_state(row, true, 40000), ubbf.schedule_state(row, false, 0),"
		"  ubbf.schedule_state({ ...row, Enable: 'false' }, true, 0),"
		"  ubbf.schedule_state({ Enable: 'true' }, true, 0),"
		"  ubbf.schedule_state({ Enable: 'true', StartTime: '00:00', Duration: '86400' }, true, 5) ];",
		"[ { \"status\": \"Active\", \"time_left\": 3000 }, "
		"{ \"status\": \"Inactive\", \"time_left\": 28800 }, "
		"{ \"status\": \"Inactive\", \"time_left\": 593600 }, "
		"{ \"status\": \"StackDisabled\", \"time_left\": 0 }, "
		"{ \"status\": \"Inactive\", \"time_left\": 0 }, "
		"{ \"status\": \"Error\", \"time_left\": 0 }, "
		"{ \"status\": \"Active\", \"time_left\": 0 } ]");
}

static const char config_js[] =
	"let config = { Device: { Schedules: { Schedule: {"
	"  '1': { Enable: 'true', StartTime: '08:00', Day: 'Monday', Duration: '3600' },"
	"  '2': { Enable: 'true', StartTime: '09:00', Day: 'Monday', Duration: '3600' },"
	"  '3': { Enable: 'false', StartTime: '10:00' },"
	"  '4': { Enable: 'true' } } },"
	"  Firewall: { Pinhole: { '1': { ScheduleRef: 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.9' },"
	"    '2': { ScheduleRef: 'Device.Schedules.Schedule.2.', Deep: { ScheduleRef: 'junk' } } } } } };";

static void
test_refs(void **state)
{
	uc_vm_t *vm = *state;
	char code[2048];

	snprintf(code, sizeof(code), "%s"
		"return [ ubbf.refs_intervals(config, 'Device.Schedules.Schedule.2, Device.Schedules.Schedule.1'),"
		"  ubbf.refs_intervals(config, 'Device.Schedules.Schedule.3,Device.Schedules.Schedule.4'),"
		"  ubbf.refs_intervals({ Device: { Schedules: { ...config.Device.Schedules, Enable: 'false' } } },"
		"    'Device.Schedules.Schedule.1'),"
		"  ubbf.schedule_windows(config, 'Device.Schedules.Schedule.1', null, false),"
		"  length(ubbf.schedule_windows(config, 'Device.Schedules.Schedule.1', null, true)),"
		"  ubbf.schedule_windows(config, '', [ { Enable: 'true', StartTime: '12:00', Day: 'Sunday' } ], false) ];",
		config_js);

	eval_expect(vm, code,
		"[ [ [ 28800, 36000 ] ], null, null, null, 1, "
		"[ { \"start_time\": \"12:00:00\", \"stop_time\": \"23:59:59\", \"weekdays\": [ \"Sunday\" ] } ] ]");
}

static void
test_refs_check_prune(void **state)
{
	uc_vm_t *vm = *state;
	char code[2048];

	snprintf(code, sizeof(code), "%s"
		"let checks = map([ [ '', false ], [ 'Device.Schedules.Schedule.1', false ],"
		"  [ 'Device.Schedules.Schedule.1', true ], [ 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.9', true ],"
		"  [ 'junk', true ] ], (c) => ubbf.schedule_refs_check(c[0], config, c[1]));"
		"let changed = ubbf.schedule_refs_prune(config);"
		"let again = ubbf.schedule_refs_prune(config);"
		"let fw = config.Device.Firewall.Pinhole;"
		"return [ checks, changed, again, fw['1'].ScheduleRef, fw['2'].ScheduleRef, fw['2'].Deep.ScheduleRef ];",
		config_js);

	eval_expect(vm, code,
		"[ [ 0, -7012, 0, -7012, -7012 ], true, false, \"Device.Schedules.Schedule.1\", "
		"\"Device.Schedules.Schedule.2.\", \"\" ]");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_start_time_valid),
		cmocka_unit_test(test_schedule_intervals),
		cmocka_unit_test(test_intervals),
		cmocka_unit_test(test_windows),
		cmocka_unit_test(test_schedule_state),
		cmocka_unit_test(test_refs),
		cmocka_unit_test(test_refs_check_prune),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
