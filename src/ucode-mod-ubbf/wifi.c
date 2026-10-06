/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <math.h>

#define UBBF_TXPOWER_MIN_DBM 1

/**
 * Converts a 2.4/5/6 GHz WiFi centre frequency (MHz) to a channel number.
 *
 * Returns 0 for zero/negative input or out-of-range frequencies.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       channel number, or 0 when the frequency is not mappable
 */
uc_value_t *
uc_ubbf_freq_to_channel(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	long long f;

	if (ucv_type(val) == UC_INTEGER)
		f = ucv_int64_get(val);
	else if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		char *endp;
		if (!s || !*s) return ucv_int64_new(0);
		f = strtoll(s, &endp, 10);
		if (*endp != '\0') return ucv_int64_new(0);
	} else {
		return ucv_int64_new(0);
	}

	if (f <= 0)
		return ucv_int64_new(0);

	if (f >= 2412 && f <= 2484) {
		if (f == 2484) return ucv_int64_new(14);
		return ucv_int64_new((f - 2407) / 5);
	}
	if (f >= 5180 && f <= 5885)
		return ucv_int64_new((f - 5000) / 5);
	if (f >= 5955 && f <= 7115)
		return ucv_int64_new((f - 5950) / 5);

	return ucv_int64_new(0);
}

/**
 * Returns the number of set bits in a small antenna mask.
 *
 * Mirrors the ucode helper: a zero mask yields 1 (callers treat "no mask"
 * as a single implicit antenna).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       popcount, minimum 1
 */
uc_value_t *
uc_ubbf_antenna_count(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	unsigned long long mask = 0;
	int count;

	if (ucv_type(val) == UC_INTEGER)
		mask = (unsigned long long)ucv_int64_get(val);
	else if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		char *endp;
		if (s && *s) {
			mask = strtoull(s, &endp, 10);
			if (*endp != '\0')
				mask = 0;
		}
	}

	count = __builtin_popcountll(mask);
	return ucv_int64_new(count > 0 ? count : 1);
}

/**
 * Maps an htmode string (HT20, VHT80, HE160, EHT320, ...) to a TR-181
 * `Standard` value.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       TR-181 standard string; `"g"` when no prefix matches
 */
uc_value_t *
uc_ubbf_htmode_to_standard(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;

	if (ucv_type(val) != UC_STRING)
		return ucv_string_new("");

	s = ucv_string_get(val);
	if (!s || !*s)
		return ucv_string_new("");

	if (strncmp(s, "EHT", 3) == 0) return ucv_string_new("be");
	if (strncmp(s, "HE", 2) == 0)  return ucv_string_new("ax");
	if (strncmp(s, "VHT", 3) == 0) return ucv_string_new("ac");
	if (strncmp(s, "HT", 2) == 0)  return ucv_string_new("n");

	return ucv_string_new("g");
}

/**
 * Maps an htmode string to its bandwidth label (`"20MHz"`, `"320MHz"`, ...).
 *
 * Matches the width suffix found anywhere in the string; the `80+80` case
 * is detected ahead of the plain `80` match.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected)
 * @return       bandwidth label, `"20MHz"` when no larger width is seen,
 *               or `""` on non-string input
 */
uc_value_t *
uc_ubbf_htmode_to_bandwidth(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	const char *s;

	if (ucv_type(val) != UC_STRING)
		return ucv_string_new("");

	s = ucv_string_get(val);
	if (!s || !*s)
		return ucv_string_new("");

	if (strstr(s, "320"))     return ucv_string_new("320MHz");
	if (strstr(s, "160"))     return ucv_string_new("160MHz");
	if (strstr(s, "80+80"))   return ucv_string_new("80+80MHz");
	if (strstr(s, "80"))      return ucv_string_new("80MHz");
	if (strstr(s, "40"))      return ucv_string_new("40MHz");

	return ucv_string_new("20MHz");
}

/**
 * Converts a transmit power percentage to a dBm value.
 *
 * Implements the historical TR-181 formula
 * `target = max_dbm - (-10 * log10(pct/100))`, with the result clamped
 * to a floor of UBBF_TXPOWER_MIN_DBM. Returns null when the percentage
 * is missing, out of (0, 100), the cap is missing, or the result does
 * not reduce the power below the cap.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: percentage, max_dbm)
 * @return       integer dBm value, or null
 */
uc_value_t *
uc_ubbf_txpower_pct_to_dbm(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pct_val = uc_fn_arg(0);
	uc_value_t *max_val = uc_fn_arg(1);
	int64_t pct, max_dbm, target;
	double reduction;

	if (ucv_type(pct_val) != UC_INTEGER || ucv_type(max_val) != UC_INTEGER)
		return NULL;

	pct = ucv_int64_get(pct_val);
	max_dbm = ucv_int64_get(max_val);

	if (pct <= 0 || pct >= 100 || max_dbm <= 0)
		return NULL;

	reduction = -10.0 * log10((double)pct / 100.0);
	target = (int64_t)((double)max_dbm - reduction);

	// A regulatory cap lower than the reduction the percentage asks for,
	// 12 dBm on 6 GHz against the 20 dB of 1%, would otherwise yield no
	// value at all and leave the radio at full power, the opposite of the
	// request. mac80211.sh reads a txpower of 0 as "auto", so the floor is
	// the lowest value that still reduces the power.
	if (target < UBBF_TXPOWER_MIN_DBM)
		target = UBBF_TXPOWER_MIN_DBM;

	if (target >= max_dbm)
		return NULL;

	return ucv_int64_new(target);
}

/**
 * Determines the WiFi operating standard from a station rate-flag list.
 *
 * Walks the array of rate-tag strings (`tx.flags` / `rx.flags` from
 * iwinfo) and returns the highest-generation tag prefix found.
 *
 * Match order: `EHT-` -> `"be"`, `HE-` -> `"ax"`, `VHT-` -> `"ac"`,
 * `MCS` -> `"n"`, otherwise `""`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: array of strings)
 * @return       standard string
 */
uc_value_t *
uc_ubbf_wifi_operating_standard(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *flags = uc_fn_arg(0);
	size_t n, i;

	if (ucv_type(flags) != UC_ARRAY)
		return ucv_string_new("");

	n = ucv_array_length(flags);
	for (i = 0; i < n; i++) {
		uc_value_t *ev = ucv_array_get(flags, i);
		const char *s;

		if (ucv_type(ev) != UC_STRING)
			continue;
		s = ucv_string_get(ev);
		if (!s) continue;
		if (strncmp(s, "EHT-", 4) == 0) return ucv_string_new("be");
		if (strncmp(s, "HE-", 3) == 0)  return ucv_string_new("ax");
		if (strncmp(s, "VHT-", 4) == 0) return ucv_string_new("ac");
		if (strncmp(s, "MCS", 3) == 0)  return ucv_string_new("n");
	}

	return ucv_string_new("");
}
