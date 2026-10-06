/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Builds a TR-181 Alias from a MAC address.
 *
 * Strips colons, lowercases the hex digits and prefixes the result with
 * `cpe-`. Output is silently truncated to 30 characters.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: MAC string)
 * @return       alias string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_alias_from_mac(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *mac_val = uc_fn_arg(0);
	const char *mac;
	char buf[32];
	int j = 0;

	if (ucv_type(mac_val) != UC_STRING)
		return ucv_string_new("");

	mac = ucv_string_get(mac_val);
	if (!mac || !*mac)
		return ucv_string_new("");

	memcpy(buf, "cpe-", 4);
	j = 4;

	for (const char *p = mac; *p && j < 30; p++) {
		if (*p == ':')
			continue;
		buf[j++] = (*p >= 'A' && *p <= 'Z') ? (*p + 32) : *p;
	}

	buf[j] = '\0';

	return ucv_string_new(buf);
}

/**
 * Tests whether a string is a canonical colon-separated MAC address.
 *
 * Accepts 17 characters, `XX:XX:XX:XX:XX:XX`, hex case-insensitive.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       boolean indicating validity
 */
uc_value_t *
uc_ubbf_mac_is_valid(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;
	size_t len, i;

	if (ucv_type(val) != UC_STRING)
		return ucv_boolean_new(false);

	s = ucv_string_get(val);
	len = ucv_string_length(val);
	if (len != 17)
		return ucv_boolean_new(false);

	for (i = 0; i < 17; i++) {
		char c = s[i];
		if ((i % 3) == 2) {
			if (c != ':')
				return ucv_boolean_new(false);
		} else {
			bool hex = (c >= '0' && c <= '9') ||
				   (c >= 'a' && c <= 'f') ||
				   (c >= 'A' && c <= 'F');
			if (!hex)
				return ucv_boolean_new(false);
		}
	}

	return ucv_boolean_new(true);
}

/**
 * Uppercases a hex string and optionally strips separator characters.
 *
 * Any byte whose code appears in the second argument is dropped; all
 * lowercase ASCII letters are converted to uppercase. Non-string input
 * yields null. Used to normalise TR-181 MAC/OUI strings before hashing,
 * comparison, or display.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: string, optional separators)
 * @return       normalised string, or null on bad input
 */
uc_value_t *
uc_ubbf_mac_normalise(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	uc_value_t *sep_val = uc_fn_arg(1);
	const char *s, *sep = NULL;
	size_t len, i, j;
	char *out;
	uc_value_t *r;

	if (ucv_type(val) != UC_STRING)
		return NULL;

	s = ucv_string_get(val);
	len = ucv_string_length(val);

	if (ucv_type(sep_val) == UC_STRING)
		sep = ucv_string_get(sep_val);

	out = malloc(len + 1);
	for (i = 0, j = 0; i < len; i++) {
		char c = s[i];
		if (sep && strchr(sep, c))
			continue;
		if (c >= 'a' && c <= 'z')
			c -= 32;
		out[j++] = c;
	}
	out[j] = '\0';

	r = ucv_string_new(out);
	free(out);

	return r;
}

/**
 * Converts a hex character to its numeric value, or -1 on invalid.
 */
static int
ubbf_hex_nibble(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/**
 * Extracts a MAC address from a DHCPv6 DUID hex string.
 *
 * Recognises DUID-LL (type 3, hw-type 1) and DUID-LLT (type 1, hw-type 1);
 * other DUID types yield null. Output is uppercase `XX:XX:XX:XX:XX:XX`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: hex DUID string)
 * @return       uppercase MAC, or null when the DUID does not carry one
 */
uc_value_t *
uc_ubbf_mac_from_duid(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;
	size_t len;
	unsigned int duid_type, hw_type;
	size_t offset;
	char mac[18];
	int i;

	if (ucv_type(val) != UC_STRING)
		return NULL;

	s = ucv_string_get(val);
	len = ucv_string_length(val);
	if (len < 16)
		return NULL;

	if (sscanf(s, "%4x%4x", &duid_type, &hw_type) != 2)
		return NULL;
	if (hw_type != 1)
		return NULL;

	if (duid_type == 3)
		offset = 8;
	else if (duid_type == 1)
		offset = 16;
	else
		return NULL;

	if (len < offset + 12)
		return NULL;

	for (i = 0; i < 6; i++) {
		int hi = ubbf_hex_nibble(s[offset + i * 2]);
		int lo = ubbf_hex_nibble(s[offset + i * 2 + 1]);
		if (hi < 0 || lo < 0)
			return NULL;
		mac[i * 3]     = "0123456789ABCDEF"[hi];
		mac[i * 3 + 1] = "0123456789ABCDEF"[lo];
		mac[i * 3 + 2] = (i < 5) ? ':' : '\0';
	}

	return ucv_string_new(mac);
}
