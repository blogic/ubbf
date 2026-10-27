/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"

#include <ctype.h>

/**
 * Coerces a TR-181 value to a C bool.
 *
 * Booleans pass through; strings yield true only for `"true"` or `"1"`.
 *
 * @param val  value to test (may be NULL)
 * @return     boolean conversion result
 */
bool
value_to_bool(uc_value_t *val)
{
	const char *s;

	if (ucv_type(val) == UC_BOOLEAN)
		return ucv_boolean_get(val);

	if (ucv_type(val) != UC_STRING)
		return false;

	s = ucv_string_get(val);

	return strcmp(s, "true") == 0 || strcmp(s, "1") == 0;
}

/**
 * Coerces a TR-181 value to a boolean, as value_to_bool().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       boolean conversion result
 */
uc_value_t *
uc_ubbf_to_bool(uc_vm_t *vm, size_t nargs)
{
	return ucv_boolean_new(value_to_bool(uc_fn_arg(0)));
}

/**
 * The equality of the ucode `==` operator: strings compare bytewise, the
 * same non-scalar value equals itself, anything else compares as numbers,
 * and a value that is not a number equals nothing.
 *
 * @param a  first value (may be NULL)
 * @param b  second value (may be NULL)
 * @return   true when the values are equal
 */
bool
loose_equal(uc_value_t *a, uc_value_t *b)
{
	uc_value_t *na, *nb;
	bool eq;

	if (!a || !b)
		return a == b;

	if (ucv_type(a) == UC_STRING && ucv_type(b) == UC_STRING)
		return ucv_string_length(a) == ucv_string_length(b) &&
		       !memcmp(ucv_string_get(a), ucv_string_get(b), ucv_string_length(a));

	if (ucv_type(a) == ucv_type(b) && !ucv_is_scalar(a))
		return a == b;

	na = ucv_to_number(a);
	nb = ucv_to_number(b);

	if (!na || !nb)
		eq = false;
	else if (ucv_type(na) == UC_DOUBLE || ucv_type(nb) == UC_DOUBLE)
		eq = ucv_double_get(na) == ucv_double_get(nb);
	else
		eq = ucv_int64_get(na) == ucv_int64_get(nb) &&
		     ucv_uint64_get(na) == ucv_uint64_get(nb);

	ucv_put(na);
	ucv_put(nb);

	return eq;
}

/**
 * Whether a value is the string `s`, under ucode `===`.
 *
 * @param val  value (may be NULL)
 * @param s    string
 * @return     true for a string equal to `s`
 */
bool
value_is(uc_value_t *val, const char *s)
{
	return ucv_type(val) == UC_STRING && !strcmp(ucv_string_get(val), s);
}

/**
 * Whether a value equals the string `s` under ucode `==`.
 *
 * @param val  value (may be NULL)
 * @param s    string
 * @return     true when `val == s` holds in ucode
 */
bool
value_loose_is(uc_value_t *val, const char *s)
{
	uc_value_t *str = ucv_string_new(s);
	bool eq = loose_equal(val, str);

	ucv_put(str);

	return eq;
}

/**
 * The integer of ucode `int(val)`: a string gives its leading base-10
 * number, any other value its numeric value cut to an integer.
 *
 * @param val  value (may be NULL)
 * @param out  receives the integer
 * @return     false where `int()` gives NaN
 */
bool
value_int_cut(uc_value_t *val, int64_t *out)
{
	const char *s;
	char *end;

	errno = 0;

	if (ucv_type(val) == UC_STRING) {
		s = ucv_string_get(val);
		*out = strtoll(s, &end, 10);
		if (end == s)
			return false;
	} else {
		*out = ucv_to_integer(val);
	}

	return errno != EINVAL && errno != ERANGE;
}

/**
 * Coerces a TR-181 value to a signed 64-bit integer. Integers pass
 * through; a string is read as base 10 and refused when text follows the
 * number or the number does not fit.
 *
 * @param val  value to convert (may be NULL)
 * @param out  receives the number
 * @return     false when the value is not convertible
 */
bool
value_to_int(uc_value_t *val, int64_t *out)
{
	const char *s;
	char *endp;
	long long n;

	if (ucv_type(val) == UC_INTEGER) {
		*out = ucv_int64_get(val);
		return true;
	}

	if (ucv_type(val) != UC_STRING)
		return false;

	s = ucv_string_get(val);
	if (!*s)
		return false;

	errno = 0;
	n = strtoll(s, &endp, 10);
	if (*endp != '\0' || errno == ERANGE)
		return false;

	*out = n;
	return true;
}

/**
 * Coerces a TR-181 value to a signed 64-bit integer, as value_to_int().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       integer value, or null when the input is not convertible
 */
uc_value_t *
uc_ubbf_to_int(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	int64_t n;

	if (ucv_type(val) == UC_INTEGER)
		return ucv_get(val);

	return value_to_int(val, &n) ? ucv_int64_new(n) : NULL;
}

/**
 * Splits a comma-separated string into an array of trimmed entries.
 *
 * Whitespace surrounding each entry is removed. Entries equal to the
 * optional filter string are dropped; the default filter is `"-1"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: csv, optional filter)
 * @return       array of strings, possibly empty
 */
uc_value_t *
uc_ubbf_csv_to_list(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *csv_val = uc_fn_arg(0);
	uc_value_t *filter_val = uc_fn_arg(1);

	if (ucv_type(csv_val) != UC_STRING)
		return ucv_array_new(vm);

	return csv_list_new(vm, ucv_string_get(csv_val),
			    (ucv_type(filter_val) == UC_STRING)
				? ucv_string_get(filter_val) : "-1");
}

/**
 * Splits a comma-separated string into an array of trimmed entries, as
 * csv_to_list() does.
 *
 * @param vm          ucode VM context
 * @param csv         the string
 * @param filter_str  entries equal to it are dropped
 * @return            new array of strings, possibly empty
 */
uc_value_t *
csv_list_new(uc_vm_t *vm, const char *csv, const char *filter_str)
{
	uc_value_t *arr = ucv_array_new(vm);
	char *buf, *tok;

	if (!csv || !*csv)
		return arr;

	buf = xstrdup(csv);

	for (tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
		while (isspace((unsigned char)*tok))
			tok++;

		char *end = tok + strlen(tok) - 1;
		while (end > tok && isspace((unsigned char)*end))
			*end-- = '\0';

		if (*tok && strcmp(tok, filter_str) != 0)
			ucv_array_push(arr, ucv_string_new(tok));
	}

	free(buf);
	return arr;
}
