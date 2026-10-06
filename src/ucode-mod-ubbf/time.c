/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Formats a Unix timestamp as ISO 8601 in UTC with second precision.
 *
 * Falls back to the current time when the argument is not an integer.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (0-1 expected: optional timestamp)
 * @return       string in `YYYY-MM-DDTHH:MM:SSZ` form
 */
uc_value_t *
uc_ubbf_iso8601_format(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ts_val = uc_fn_arg(0);
	time_t ts;
	struct tm tm;
	char buf[80];

	if (ucv_type(ts_val) == UC_INTEGER)
		ts = (time_t)ucv_int64_get(ts_val);
	else
		ts = time(NULL);

	gmtime_r(&ts, &tm);
	snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
		 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		 tm.tm_hour, tm.tm_min, tm.tm_sec);

	return ucv_string_new(buf);
}

/**
 * Casts a numeric ucode value to int64, truncating doubles.
 * Non-numeric values yield 0.
 *
 * ucv_cast_number() would also cover numeric strings, but libucode
 * 0.0.20250529 does not export it, so stick to the exported primitives.
 */
static int64_t
num_arg_get(uc_value_t *val)
{
	switch (ucv_type(val)) {
	case UC_INTEGER:
		return ucv_int64_get(val);
	case UC_DOUBLE:
		return (int64_t)ucv_double_get(val);
	default:
		return 0;
	}
}

/**
 * Formats seconds plus microseconds as ISO 8601 in UTC.
 *
 * Both arguments accept integers or doubles (truncated); anything else
 * counts as 0. Callers pass fractional seconds via the usec argument.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: seconds, microseconds)
 * @return       string in `YYYY-MM-DDTHH:MM:SS.uuuuuuZ` form
 */
uc_value_t *
uc_ubbf_iso8601_format_usec(uc_vm_t *vm, size_t nargs)
{
	time_t ts;
	int64_t usec;
	struct tm tm;
	char buf[80];

	ts = (time_t)num_arg_get(uc_fn_arg(0));
	usec = num_arg_get(uc_fn_arg(1));
	if (usec < 0 || usec > 999999)
		usec = 0;

	gmtime_r(&ts, &tm);
	snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d.%06ldZ",
		 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		 tm.tm_hour, tm.tm_min, tm.tm_sec, (long)usec);

	return ucv_string_new(buf);
}
