/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"

/**
 * Formats a UCI port-range string from start/end port numbers.
 *
 * Returns null when the start port is missing or non-positive. Returns
 * just the start port as a decimal string when the end port is missing,
 * non-positive, or not strictly greater than the start. Otherwise returns
 * `"<p>-<pe>"`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: port, port_end)
 * @return       formatted port range string, or null when invalid
 */
uc_value_t *
uc_ubbf_port_range_format(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *p_val = uc_fn_arg(0);
	uc_value_t *pe_val = uc_fn_arg(1);
	long long p = 0, pe = 0;
	bool pe_ok = false;
	char buf[32];

	if (ucv_type(p_val) == UC_INTEGER) {
		p = ucv_int64_get(p_val);
	} else if (ucv_type(p_val) == UC_STRING) {
		const char *s = ucv_string_get(p_val);
		char *endp;
		if (!s || !*s) return NULL;
		p = strtoll(s, &endp, 10);
		if (*endp != '\0') return NULL;
	} else {
		return NULL;
	}

	if (p <= 0 || p > 65535)
		return NULL;

	if (ucv_type(pe_val) == UC_INTEGER) {
		pe = ucv_int64_get(pe_val);
		pe_ok = true;
	} else if (ucv_type(pe_val) == UC_STRING) {
		const char *s = ucv_string_get(pe_val);
		char *endp;
		if (s && *s) {
			pe = strtoll(s, &endp, 10);
			pe_ok = (*endp == '\0');
		}
	}

	if (!pe_ok || pe <= 0 || pe > 65535 || pe <= p)
		snprintf(buf, sizeof(buf), "%lld", p);
	else
		snprintf(buf, sizeof(buf), "%lld-%lld", p, pe);

	return ucv_string_new(buf);
}

/**
 * Converts a TR-181 protocol number or name to its UCI token.
 *
 * Integer/numeric strings map -1 to `all`, 6 to `tcp`, 17 to `udp`, 1 to
 * `icmp`, 58 to `icmpv6`, other positive values to their decimal form.
 * Strings `tcp`, `udp`, `icmp`, `icmpv6` (case-insensitive) pass through
 * lower-cased. Anything else yields null.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       UCI protocol token string, or null
 */
uc_value_t *
uc_ubbf_protocol_to_uci(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	char buf[16];

	if (ucv_type(val) == UC_INTEGER || ucv_type(val) == UC_STRING) {
		long long n = 0;
		bool is_num = false;

		if (ucv_type(val) == UC_INTEGER) {
			n = ucv_int64_get(val);
			is_num = true;
		} else {
			const char *s = ucv_string_get(val);
			char *endp;
			if (s && *s) {
				n = strtoll(s, &endp, 10);
				if (*endp == '\0')
					is_num = true;
			}
		}

		if (is_num) {
			if (n == -1) return ucv_string_new("all");
			if (n == 6)  return ucv_string_new("tcp");
			if (n == 17) return ucv_string_new("udp");
			if (n == 1)  return ucv_string_new("icmp");
			if (n == 58) return ucv_string_new("icmpv6");
			if (n > 0 && n <= 255) {
				snprintf(buf, sizeof(buf), "%lld", n);
				return ucv_string_new(buf);
			}
			return NULL;
		}
	}

	if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		char lower[8];
		size_t i;
		if (!s) return NULL;
		for (i = 0; i < sizeof(lower) - 1 && s[i]; i++) {
			char c = s[i];
			if (c >= 'A' && c <= 'Z') c += 32;
			lower[i] = c;
		}
		lower[i] = '\0';
		if (!strcmp(lower, "tcp") || !strcmp(lower, "udp") ||
		    !strcmp(lower, "icmp") || !strcmp(lower, "icmpv6"))
			return ucv_string_new(lower);
	}

	return NULL;
}
