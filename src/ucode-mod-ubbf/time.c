/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <ctype.h>
#include <inttypes.h>

#define DATETIME_UNKNOWN	"0001-01-01T00:00:00Z"

/**
 * Formats a Unix timestamp as a TR-181 dateTime in UTC.
 *
 * @param ts  integer seconds since the epoch
 * @return    new string; the "unknown time" 0001-01-01T00:00:00Z when the
 *            time is out of range; NULL when ts is not an integer
 */
uc_value_t *
unix_to_datetime_new(uc_value_t *ts)
{
	char buf[48];

	if (ucv_type(ts) != UC_INTEGER)
		return NULL;

	if (!datetime_utc_format((time_t)ucv_int64_get(ts), -1, buf, sizeof(buf)))
		return ucv_string_new(DATETIME_UNKNOWN);

	return ucv_string_new(buf);
}

/**
 * Formats a time as an ISO 8601 date and time in UTC, with four year
 * digits: `YYYY-MM-DDTHH:MM:SSZ`, or with the microseconds
 * `YYYY-MM-DDTHH:MM:SS.uuuuuuZ`.
 *
 * @param t     seconds since the epoch
 * @param usec  microseconds 0-999999, or -1 for none
 * @param buf   output, 48 bytes are enough
 * @param len   size of buf
 * @return      false when the time is out of the range of struct tm
 */
bool
datetime_utc_format(time_t t, int64_t usec, char *buf, size_t len)
{
	struct tm tm;
	int n;

	if (!gmtime_r(&t, &tm))
		return false;

	n = snprintf(buf, len, "%04d-%02d-%02dT%02d:%02d:%02d",
		     tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		     tm.tm_hour, tm.tm_min, tm.tm_sec);
	if (usec >= 0)
		snprintf(buf + n, len - n, ".%06" PRId64 "Z", usec);
	else
		snprintf(buf + n, len - n, "Z");

	return true;
}

/**
 * ucode global: `usp_unix_to_datetime(ts)`, see unix_to_datetime_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: seconds since the epoch)
 * @return       dateTime string, or null for a value that is not an
 *               integer
 */
uc_value_t *
uc_usp_unix_to_datetime(uc_vm_t *vm, size_t nargs)
{
	return unix_to_datetime_new(uc_fn_arg(0));
}

static bool
date_valid(int year, int mon, int day)
{
	static const int days[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
	bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

	if (mon < 1 || mon > 12 || day < 1)
		return false;

	return day <= days[mon - 1] + (mon == 2 && leap);
}

/**
 * Parses an ISO 8601 date and time as a TR-106 dateTime carries it:
 * `YYYY-MM-DDTHH:MM:SS`, an optional fraction, and `Z`, an offset
 * `+HH:MM` or `-HH:MM`, or nothing for UTC.
 *
 * @param s    the text
 * @param out  receives the seconds since the epoch
 * @return     false for text that is not such a time, or a date that does
 *             not exist
 */
bool
datetime_parse(const char *s, int64_t *out)
{
	int year, mon, day, hour, min, sec, oh = 0, om = 0, n = 0, sign = 0;
	struct tm tm = { 0 };

	if (sscanf(s, "%4d-%2d-%2dT%2d:%2d:%2d%n", &year, &mon, &day, &hour, &min, &sec, &n) != 6 ||
	    n != 19 || !date_valid(year, mon, day) || hour > 23 || min > 59 || sec > 60)
		return false;

	s += n;
	if (*s == '.' && isdigit((unsigned char)s[1]))
		for (s++; isdigit((unsigned char)*s); s++)
			;

	if (*s == '+' || *s == '-') {
		sign = (*s == '+') ? 1 : -1;
		if (sscanf(s + 1, "%2d:%2d%n", &oh, &om, &n) != 2 || n != 5 || oh > 23 || om > 59)
			return false;
		s += 6;
	} else if (*s == 'Z') {
		s++;
	}

	if (*s)
		return false;

	tm.tm_year = year - 1900;
	tm.tm_mon = mon - 1;
	tm.tm_mday = day;
	tm.tm_hour = hour;
	tm.tm_min = min;
	tm.tm_sec = sec;

	*out = (int64_t)timegm(&tm) - sign * (oh * 3600 + om * 60);

	return true;
}

/**
 * ucode global: `usp_datetime_to_unix(text)`, see datetime_parse().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: dateTime text)
 * @return       seconds since the epoch, 0 for text that does not parse,
 *               null for a value that is not a string
 */
uc_value_t *
uc_usp_datetime_to_unix(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	int64_t t;

	if (ucv_type(arg) != UC_STRING)
		return NULL;

	return ucv_int64_new(datetime_parse(ucv_string_get(arg), &t) ? t : 0);
}

/**
 * Formats a Unix timestamp as a TR-181 dateTime in UTC, with the "unknown
 * time" 0001-01-01T00:00:00Z for a missing or zero time, so a caller can
 * pass a missing field straight through.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: timestamp)
 * @return       dateTime string; null for a timestamp that is not an
 *               integer
 */
uc_value_t *
uc_ubbf_datetime_format(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ts = uc_fn_arg(0);

	if (!ucv_is_truish(ts))
		return ucv_string_new(DATETIME_UNKNOWN);

	return unix_to_datetime_new(ts);
}

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
	char buf[48];

	if (ucv_type(ts_val) == UC_INTEGER)
		ts = (time_t)ucv_int64_get(ts_val);
	else
		ts = time(NULL);

	if (!datetime_utc_format(ts, -1, buf, sizeof(buf)))
		return ucv_string_new(DATETIME_UNKNOWN);

	return ucv_string_new(buf);
}

/**
 * Formats a Unix timestamp as ISO 8601 in the local time zone with its
 * offset from UTC, for parameters that TR-181 defines in local time
 * (TR-069 A.2, dateTime: such a value carries the offset).
 *
 * Falls back to the current time when the argument is not an integer.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (0-1 expected: optional timestamp)
 * @return       string in `YYYY-MM-DDTHH:MM:SS+hh:mm` form
 */
uc_value_t *
uc_ubbf_iso8601_local_format(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ts_val = uc_fn_arg(0);
	time_t ts;
	struct tm tm;
	long offset;
	char buf[80];

	if (ucv_type(ts_val) == UC_INTEGER)
		ts = (time_t)ucv_int64_get(ts_val);
	else
		ts = time(NULL);

	if (!localtime_r(&ts, &tm))
		return ucv_string_new(DATETIME_UNKNOWN);

	offset = tm.tm_gmtoff;
	snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d%c%02ld:%02ld",
		 tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
		 tm.tm_hour, tm.tm_min, tm.tm_sec,
		 offset < 0 ? '-' : '+', labs(offset) / 3600, (labs(offset) % 3600) / 60);

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
	char buf[48];

	ts = (time_t)num_arg_get(uc_fn_arg(0));
	usec = num_arg_get(uc_fn_arg(1));
	if (usec < 0 || usec > 999999)
		usec = 0;

	if (!datetime_utc_format(ts, usec, buf, sizeof(buf)))
		return ucv_string_new(DATETIME_UNKNOWN);

	return ucv_string_new(buf);
}
