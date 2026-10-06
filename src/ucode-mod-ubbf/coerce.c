/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Coerces a TR-181 value to a boolean.
 *
 * Booleans pass through; strings yield true only for `"true"` or `"1"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       boolean conversion result
 */
uc_value_t *
uc_ubbf_to_bool(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);

	if (ucv_type(val) == UC_BOOLEAN)
		return ucv_boolean_new(ucv_boolean_get(val));

	if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);

		return ucv_boolean_new(strcmp(s, "true") == 0 || strcmp(s, "1") == 0);
	}

	return ucv_boolean_new(false);
}

/**
 * Coerces a TR-181 value to a signed 64-bit integer.
 *
 * Integers pass through; strings are parsed as base-10 and rejected if any
 * trailing non-digit characters remain.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       integer value, or null when the input is not convertible
 */
uc_value_t *
uc_ubbf_to_int(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);

	if (ucv_type(val) == UC_INTEGER)
		return ucv_get(val);

	if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		char *endp;
		long long n;

		if (!s || !*s)
			return NULL;

		n = strtoll(s, &endp, 10);
		if (*endp != '\0')
			return NULL;

		return ucv_int64_new(n);
	}

	return NULL;
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
	const char *csv, *filter_str;
	uc_value_t *arr;
	char *buf, *tok;

	if (ucv_type(csv_val) != UC_STRING)
		return ucv_array_new(vm);

	csv = ucv_string_get(csv_val);
	if (!csv || !*csv)
		return ucv_array_new(vm);

	filter_str = (ucv_type(filter_val) == UC_STRING)
		? ucv_string_get(filter_val) : "-1";

	arr = ucv_array_new(vm);
	buf = xstrdup(csv);

	for (tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
		while (*tok == ' ' || *tok == '\t')
			tok++;

		char *end = tok + strlen(tok) - 1;
		while (end > tok && (*end == ' ' || *end == '\t'))
			*end-- = '\0';

		if (*tok && strcmp(tok, filter_str) != 0)
			ucv_array_push(arr, ucv_string_new(tok));
	}

	free(buf);
	return arr;
}
