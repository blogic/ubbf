/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include <inttypes.h>

/**
 * Builds a TR-181 Alias from a free-form name; see alias_from_name() in
 * util.c.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: name string)
 * @return       alias string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_alias_from_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name_val = uc_fn_arg(0);
	char buf[65];

	if (ucv_type(name_val) != UC_STRING)
		return ucv_string_new("");

	alias_from_name(ucv_string_get(name_val), buf, sizeof(buf));

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

	out = xalloc(len + 1);
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

static char *
control_strip(const char *s, size_t len)
{
	char *out = xalloc(len + 1);
	size_t i, j;

	for (i = 0, j = 0; i < len; i++) {
		unsigned char c = (unsigned char)s[i];
		if ((c >= 0x01 && c <= 0x1f) || c == 0x7f)
			continue;
		out[j++] = (char)c;
	}
	out[j] = '\0';

	return out;
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
	uc_value_t *r;
	char *out;

	if (ucv_type(val) != UC_STRING)
		return ucv_get(val);

	out = control_strip(ucv_string_get(val), ucv_string_length(val));
	r = ucv_string_new(out);
	free(out);

	return r;
}

/**
 * Makes a string from another device fit a TR-181 string(:N) parameter:
 * removes control bytes as uci_value_sanitise() does and cuts the string
 * to max_length bytes, without splitting a UTF-8 sequence.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: value, maximum length in
 *               bytes)
 * @return       the clamped string; '' for a value that is not a string
 */
uc_value_t *
uc_ubbf_text_clamp(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	int64_t max = ucv_int64_get(uc_fn_arg(1));
	uc_value_t *r;
	size_t len, n;
	char *out;

	if (ucv_type(val) != UC_STRING)
		return ucv_string_new("");

	out = control_strip(ucv_string_get(val), ucv_string_length(val));
	len = strlen(out);

	n = (max < 0) ? 0 : (size_t)max;
	if (n < len) {
		while (n > 0 && ((unsigned char)out[n] & 0xc0) == 0x80)
			n--;
		len = n;
	}

	r = ucv_string_new_length(out, len);
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

void
shell_quote_append(uc_vm_t *vm, uc_stringbuf_t *sb, uc_value_t *val)
{
	char *s = ucv_to_string(vm, val);

	_ucv_stringbuf_append(sb, "'", 1);

	for (const char *p = s ? s : ""; *p; p++) {
		if (*p == '\'')
			_ucv_stringbuf_append(sb, "'\\''", 4);
		else
			_ucv_stringbuf_append(sb, p, 1);
	}

	_ucv_stringbuf_append(sb, "'", 1);
	free(s);
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
	uc_stringbuf_t *sb;

	if (!arg || ucv_type(arg) == UC_NULL)
		return ucv_string_new("''");

	sb = ucv_stringbuf_new();
	shell_quote_append(vm, sb, arg);

	return ucv_stringbuf_finish(sb);
}

/**
 * Builds a shell command string from an argv-style list, so a value from
 * a caller cannot inject shell syntax. By element type:
 *
 *   string         shell-escaped as shell_escape() does
 *   int / double   formatted as an integer, not escaped; a fractional
 *                  double is truncated
 *   null           skipped, so a conditional flag reads
 *                  `cond ? '--flag' : null, value`
 *   { raw: text }  inserted verbatim, for shell syntax such as '2>&1'
 *   other          converted to a string, then shell-escaped; a boolean
 *                  gives 'true' or 'false'
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: list of fragments)
 * @return       the command string
 */
uc_value_t *
uc_ubbf_cmd_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *parts = uc_fn_arg(0);
	uc_stringbuf_t *sb = ucv_stringbuf_new();
	uc_value_t *part, *raw;
	bool first = true;
	char *s;

	for (size_t i = 0; i < ucv_array_length(parts); i++) {
		part = ucv_array_get(parts, i);
		raw = ucv_object_get(part, "raw", NULL);

		if (!part)
			continue;

		if (!first)
			_ucv_stringbuf_append(sb, " ", 1);
		first = false;

		switch (ucv_type(part)) {
		case UC_INTEGER:
		case UC_DOUBLE:
			ucv_stringbuf_printf(sb, "%" PRId64, ucv_to_integer(part));
			break;

		case UC_OBJECT:
			if (raw) {
				s = ucv_to_string(vm, raw);
				ucv_stringbuf_addstr(sb, s, strlen(s));
				free(s);
				break;
			}
			/* fall through */

		default:
			shell_quote_append(vm, sb, part);
			break;
		}
	}

	return ucv_stringbuf_finish(sb);
}

/**
 * Converts the lowercase ASCII letters of a string to uppercase, in place.
 * Other bytes, UTF-8 sequences among them, stay as they are.
 *
 * @param s  NUL-terminated string to modify
 */
void
str_to_upper(char *s)
{
	for (; *s; s++)
		if (*s >= 'a' && *s <= 'z')
			*s -= 'a' - 'A';
}
