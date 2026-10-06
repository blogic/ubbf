/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Builds a TR-181 Alias from a free-form name.
 *
 * Replaces every character outside `[A-Za-z0-9_-]` with `_` and prefixes
 * the result with `cpe-`. Output is silently truncated to 254 characters.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: name string)
 * @return       alias string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_alias_from_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	const char *name;
	char buf[256];
	int j;

	if (ucv_type(name_val) != UC_STRING)
		return ucv_string_new("");

	name = ucv_string_get(name_val);
	if (!name || !*name)
		return ucv_string_new("");

	memcpy(buf, "cpe-", 4);
	j = 4;

	for (const char *p = name; *p && j < 254; p++) {
		char c = *p;
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		    (c >= '0' && c <= '9') || c == '_' || c == '-')
			buf[j++] = c;
		else
			buf[j++] = '_';
	}

	buf[j] = '\0';

	return ucv_string_new(buf);
}

/**
 * Replaces every byte outside `[A-Za-z0-9_]` with `_`.
 *
 * Used for UCI section names and any other identifier-shaped field where
 * the input is user/TR-181-supplied.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: string)
 * @return       sanitised string, or null on bad input
 */
uc_value_t *
uc_ubbf_name_sanitise(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;
	size_t len, i;
	char *out;
	uc_value_t *r;

	if (ucv_type(val) != UC_STRING)
		return NULL;

	s = ucv_string_get(val);
	len = ucv_string_length(val);

	out = malloc(len + 1);
	for (i = 0; i < len; i++) {
		char c = s[i];
		bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			  (c >= '0' && c <= '9') || c == '_';
		out[i] = ok ? c : '_';
	}
	out[len] = '\0';

	r = ucv_string_new(out);
	free(out);

	return r;
}

/**
 * Strips ASCII control bytes (0x01-0x1F and 0x7F) from a string.
 *
 * Intended to sanitise TR-181 STRING parameters before they are embedded in
 * `uci batch` lines, where an embedded newline could start a new command.
 * Non-string input passes through unchanged.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       sanitised string, or the original value when not a string
 */
uc_value_t *
uc_ubbf_uci_value_sanitise(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;
	size_t len, i, j;
	char *out;
	uc_value_t *r;

	if (ucv_type(val) != UC_STRING)
		return ucv_get(val);

	s = ucv_string_get(val);
	len = ucv_string_length(val);

	out = malloc(len + 1);
	for (i = 0, j = 0; i < len; i++) {
		unsigned char c = (unsigned char)s[i];
		if ((c >= 0x01 && c <= 0x1f) || c == 0x7f)
			continue;
		out[j++] = (char)c;
	}
	out[j] = '\0';

	r = ucv_string_new(out);
	free(out);

	return r;
}

/**
 * Tests whether a URL starts with an HTTP(S) or FTP(S) scheme.
 *
 * Matches the shared TR-181 transfer-URL pattern `^(https?|ftps?)://`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       boolean indicating scheme match
 */
uc_value_t *
uc_ubbf_transfer_url_validate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;

	if (ucv_type(val) != UC_STRING)
		return ucv_boolean_new(false);

	s = ucv_string_get(val);

	if (strncmp(s, "http://", 7) == 0)   return ucv_boolean_new(true);
	if (strncmp(s, "https://", 8) == 0)  return ucv_boolean_new(true);
	if (strncmp(s, "ftp://", 6) == 0)    return ucv_boolean_new(true);
	if (strncmp(s, "ftps://", 7) == 0)   return ucv_boolean_new(true);

	return ucv_boolean_new(false);
}

/**
 * Quotes a value for safe inclusion in a single-quoted shell argument.
 *
 * Wraps the input in single quotes and replaces every embedded `'` with
 * the canonical `'\''` sequence. Null or empty input becomes `''`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       single-quoted shell-safe string
 */
uc_value_t *
uc_ubbf_shell_escape(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	const char *s;
	uc_stringbuf_t *sb;

	if (!arg || ucv_type(arg) == UC_NULL)
		return ucv_string_new("''");

	s = ucv_to_string(vm, arg);
	if (!s || !*s) {
		free((void *)s);
		return ucv_string_new("''");
	}

	sb = ucv_stringbuf_new();
	_ucv_stringbuf_append(sb, "'", 1);

	for (const char *p = s; *p; p++) {
		if (*p == '\'')
			_ucv_stringbuf_append(sb, "'\\''", 4);
		else
			_ucv_stringbuf_append(sb, p, 1);
	}

	_ucv_stringbuf_append(sb, "'", 1);
	free((void *)s);

	return ucv_stringbuf_finish(sb);
}
