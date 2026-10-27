/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * time.c: iso8601_format(), iso8601_format_usec() and
 * iso8601_local_format(), and the globals usp_unix_to_datetime() and
 * usp_datetime_to_unix() that ubbf.c puts into the scope.
 */

#include "harness.h"
#include "ubbf.h"

#define CET "CET-1CEST,M3.5.0,M10.5.0/3"

static void
tz_set(const char *tz)
{
	setenv("TZ", tz, 1);
	tzset();
}

static void
string_expect(uc_value_t *res, const char *expected)
{
	if (expected) {
		assert_int_equal(ucv_type(res), UC_STRING);
		assert_string_equal(ucv_string_get(res), expected);
	} else {
		assert_null(res);
	}

	ucv_put(res);
}

static void
utc_expect(uc_vm_t *vm, int64_t ts, const char *expected)
{
	string_expect(vm_call(vm, uc_ubbf_iso8601_format, 1, ucv_int64_new(ts)), expected);
}

/*
 * Without a timestamp the functions read the clock, so the result may
 * name the second before or after the one the test reads.
 */
static void
now_expect(uc_value_t *res, time_t t0, time_t t1, const char *fmt)
{
	char a[64], b[64];
	struct tm tm;

	gmtime_r(&t0, &tm);
	strftime(a, sizeof(a), fmt, &tm);
	gmtime_r(&t1, &tm);
	strftime(b, sizeof(b), fmt, &tm);

	assert_int_equal(ucv_type(res), UC_STRING);
	if (strcmp(ucv_string_get(res), a) && strcmp(ucv_string_get(res), b))
		fail_msg("%s is neither %s nor %s", ucv_string_get(res), a, b);

	ucv_put(res);
}

static void
test_iso8601_format(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *args[] = { NULL, ucv_string_new("1700000000"), ucv_double_new(1700000000.0) };
	time_t t0, t1;

	tz_set(CET);

	utc_expect(vm, 0, "1970-01-01T00:00:00Z");
	utc_expect(vm, 1, "1970-01-01T00:00:01Z");
	utc_expect(vm, 1700000000, "2023-11-14T22:13:20Z");
	utc_expect(vm, 951868799, "2000-02-29T23:59:59Z");
	utc_expect(vm, 1719835200, "2024-07-01T12:00:00Z");
	utc_expect(vm, -1, "1969-12-31T23:59:59Z");
	utc_expect(vm, 253402300799LL, "9999-12-31T23:59:59Z");
	utc_expect(vm, -62135596800LL, "0001-01-01T00:00:00Z");

	/* gmtime_r() cannot express the year of INT64_MAX seconds */
	utc_expect(vm, INT64_MAX, "0001-01-01T00:00:00Z");

	for (size_t i = 0; i < sizeof(args) / sizeof(args[0]); i++) {
		t0 = time(NULL);
		uc_value_t *res = vm_call(vm, uc_ubbf_iso8601_format, 1, args[i]);
		t1 = time(NULL);
		now_expect(res, t0, t1, "%Y-%m-%dT%H:%M:%SZ");
	}

	t0 = time(NULL);
	uc_value_t *res = vm_call(vm, uc_ubbf_iso8601_format, 0);
	t1 = time(NULL);
	now_expect(res, t0, t1, "%Y-%m-%dT%H:%M:%SZ");

	tz_set("UTC");
}

static void
usec_expect(uc_vm_t *vm, uc_value_t *ts, uc_value_t *usec, const char *expected)
{
	string_expect(vm_call(vm, uc_ubbf_iso8601_format_usec, 2, ts, usec), expected);
}

static void
test_iso8601_format_usec(void **state)
{
	uc_vm_t *vm = *state;

	tz_set(CET);

	usec_expect(vm, ucv_int64_new(0), ucv_int64_new(123456), "1970-01-01T00:00:00.123456Z");
	usec_expect(vm, ucv_int64_new(1700000000), ucv_int64_new(0), "2023-11-14T22:13:20.000000Z");
	usec_expect(vm, ucv_int64_new(1700000000), ucv_int64_new(1), "2023-11-14T22:13:20.000001Z");
	usec_expect(vm, ucv_int64_new(1700000000), ucv_int64_new(999999), "2023-11-14T22:13:20.999999Z");
	usec_expect(vm, ucv_int64_new(1700000000), ucv_int64_new(1000000), "2023-11-14T22:13:20.000000Z");
	usec_expect(vm, ucv_int64_new(1700000000), ucv_int64_new(-1), "2023-11-14T22:13:20.000000Z");
	usec_expect(vm, ucv_double_new(1700000000.9), ucv_double_new(5.7), "2023-11-14T22:13:20.000005Z");
	usec_expect(vm, ucv_int64_new(-1), ucv_int64_new(500000), "1969-12-31T23:59:59.500000Z");
	usec_expect(vm, ucv_string_new("1700000000"), ucv_string_new("5"), "1970-01-01T00:00:00.000000Z");
	usec_expect(vm, ucv_int64_new(1700000000), NULL, "2023-11-14T22:13:20.000000Z");
	usec_expect(vm, NULL, NULL, "1970-01-01T00:00:00.000000Z");
	string_expect(vm_call(vm, uc_ubbf_iso8601_format_usec, 0), "1970-01-01T00:00:00.000000Z");

	tz_set("UTC");
}

static void
local_expect(uc_vm_t *vm, const char *tz, int64_t ts, const char *expected)
{
	tz_set(tz);
	string_expect(vm_call(vm, uc_ubbf_iso8601_local_format, 1, ucv_int64_new(ts)), expected);
}

static void
test_iso8601_local_format(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;
	time_t t0, t1;

	local_expect(vm, "UTC", 0, "1970-01-01T00:00:00+00:00");
	local_expect(vm, "UTC", 1700000000, "2023-11-14T22:13:20+00:00");

	local_expect(vm, CET, 0, "1970-01-01T01:00:00+01:00");
	local_expect(vm, CET, 1705320000, "2024-01-15T13:00:00+01:00");
	local_expect(vm, CET, 1719835200, "2024-07-01T14:00:00+02:00");

	/* EU summer time starts 2026-03-29 01:00 UTC and ends 2026-10-25 01:00 UTC */
	local_expect(vm, CET, 1774745999, "2026-03-29T01:59:59+01:00");
	local_expect(vm, CET, 1774746000, "2026-03-29T03:00:00+02:00");
	local_expect(vm, CET, 1792889999, "2026-10-25T02:59:59+02:00");
	local_expect(vm, CET, 1792890000, "2026-10-25T02:00:00+01:00");

	local_expect(vm, "EST5EDT,M3.2.0,M11.1.0", 1705320000, "2024-01-15T07:00:00-05:00");
	local_expect(vm, "EST5EDT,M3.2.0,M11.1.0", 1719835200, "2024-07-01T08:00:00-04:00");
	local_expect(vm, "NST3:30NDT,M3.2.0,M11.1.0", 1705320000, "2024-01-15T08:30:00-03:30");
	local_expect(vm, "IST-5:30", 0, "1970-01-01T05:30:00+05:30");
	local_expect(vm, "<+0545>-5:45", 1705320000, "2024-01-15T17:45:00+05:45");
	local_expect(vm, "<-01>1", 0, "1969-12-31T23:00:00-01:00");

	tz_set("UTC");

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_iso8601_local_format, 1, ucv_string_new("0"));
	t1 = time(NULL);
	now_expect(res, t0, t1, "%Y-%m-%dT%H:%M:%S+00:00");

	t0 = time(NULL);
	res = vm_call(vm, uc_ubbf_iso8601_local_format, 0);
	t1 = time(NULL);
	now_expect(res, t0, t1, "%Y-%m-%dT%H:%M:%S+00:00");
}

static void
eval_string_expect(uc_vm_t *vm, const char *code, const char *expected)
{
	string_expect(vm_eval(vm, code), expected);
}

static void
test_usp_unix_to_datetime(void **state)
{
	uc_vm_t *vm = *state;

	tz_set(CET);

	eval_string_expect(vm, "return usp_unix_to_datetime(0);", "1970-01-01T00:00:00Z");
	eval_string_expect(vm, "return usp_unix_to_datetime(1700000000);", "2023-11-14T22:13:20Z");
	eval_string_expect(vm, "return usp_unix_to_datetime(1719835200);", "2024-07-01T12:00:00Z");
	eval_string_expect(vm, "return usp_unix_to_datetime(-1);", "1969-12-31T23:59:59Z");
	eval_string_expect(vm, "return usp_unix_to_datetime(253402300799);", "9999-12-31T23:59:59Z");
	eval_string_expect(vm, "return usp_unix_to_datetime(-62135596800);", "0001-01-01T00:00:00Z");

	/* gmtime_r() cannot express the year of INT64_MAX seconds */
	eval_string_expect(vm, "return usp_unix_to_datetime(9223372036854775807);",
			   "0001-01-01T00:00:00Z");

	eval_string_expect(vm, "return usp_unix_to_datetime('1700000000');", NULL);
	eval_string_expect(vm, "return usp_unix_to_datetime(1.5);", NULL);
	eval_string_expect(vm, "return usp_unix_to_datetime(null);", NULL);
	eval_string_expect(vm, "return usp_unix_to_datetime();", NULL);

	tz_set("UTC");
}

static void
eval_int_expect(uc_vm_t *vm, const char *code, int64_t expected)
{
	uc_value_t *res = vm_eval(vm, code);

	assert_int_equal(ucv_type(res), UC_INTEGER);
	assert_int_equal(ucv_int64_get(res), expected);
	ucv_put(res);
}

static void
test_usp_datetime_to_unix(void **state)
{
	uc_vm_t *vm = *state;
	uc_value_t *res;

	tz_set(CET);

	eval_int_expect(vm, "return usp_datetime_to_unix('1970-01-01T00:00:00Z');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2023-11-14T22:13:20Z');", 1700000000);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00Z');", 1792281600);
	eval_int_expect(vm, "return usp_datetime_to_unix('2024-07-01T12:00:00Z');", 1719835200);
	eval_int_expect(vm, "return usp_datetime_to_unix('2000-02-29T23:59:59Z');", 951868799);
	eval_int_expect(vm, "return usp_datetime_to_unix('1969-12-31T23:59:59Z');", -1);
	eval_int_expect(vm, "return usp_datetime_to_unix('9999-12-31T23:59:59Z');", 253402300799LL);
	eval_int_expect(vm, "return usp_datetime_to_unix('0001-01-01T00:00:00Z');", -62135596800LL);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00');", 1792281600);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00.999999Z');", 1792281600);

	eval_int_expect(vm, "return usp_datetime_to_unix('garbage');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18 00:00:00');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-13-01T00:00:00Z');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T24:00:00Z');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:60:00Z');", 0);

	/* a date that does not exist; 2100 is no leap year, 2024 is */
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-02-30T00:00:00Z');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2100-02-29T00:00:00Z');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2024-02-29T00:00:00Z');", 1709164800);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-04-31T00:00:00Z');", 0);

	/* an offset gives the UTC time; text after the zone is refused */
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T02:00:00+02:00');", 1792281600);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-17T19:30:00-04:30');", 1792281600);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T02:00:00.5+02:00');", 1792281600);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00Zjunk');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00+2');", 0);
	eval_int_expect(vm, "return usp_datetime_to_unix('2026-10-18T00:00:00.Z');", 0);

	assert_null(vm_eval(vm, "return usp_datetime_to_unix(1700000000);"));
	assert_null(vm_eval(vm, "return usp_datetime_to_unix(null);"));
	assert_null(vm_eval(vm, "return usp_datetime_to_unix();"));

	res = vm_eval(vm,
		"return [ usp_unix_to_datetime(usp_datetime_to_unix('2026-10-25T01:00:00Z')),"
		"  usp_datetime_to_unix(usp_unix_to_datetime(1792890000)) ];");
	assert_json_equal(vm, res, "[ \"2026-10-25T01:00:00Z\", 1792890000 ]");
	ucv_put(res);

	tz_set("UTC");
}

int
main(void)
{
	const struct CMUnitTest tests[] = {
		cmocka_unit_test(test_iso8601_format),
		cmocka_unit_test(test_iso8601_format_usec),
		cmocka_unit_test(test_iso8601_local_format),
		cmocka_unit_test(test_usp_unix_to_datetime),
		cmocka_unit_test(test_usp_datetime_to_unix),
	};

	return cmocka_run_group_tests(tests, vm_setup, vm_teardown);
}
