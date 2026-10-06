/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <inttypes.h>

static const char base64_chars[] =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/**
 * Encodes 6 raw bytes as a base64 string (no padding for 6-byte input
 * is impossible since 6 bytes -> 8 chars exactly).
 */
static void
base64_encode_6(const uint8_t *in, char *out)
{
	out[0] = base64_chars[in[0] >> 2];
	out[1] = base64_chars[((in[0] & 0x03) << 4) | (in[1] >> 4)];
	out[2] = base64_chars[((in[1] & 0x0f) << 2) | (in[2] >> 6)];
	out[3] = base64_chars[in[2] & 0x3f];
	out[4] = base64_chars[in[3] >> 2];
	out[5] = base64_chars[((in[3] & 0x03) << 4) | (in[4] >> 4)];
	out[6] = base64_chars[((in[4] & 0x0f) << 2) | (in[5] >> 6)];
	out[7] = base64_chars[in[5] & 0x3f];
	out[8] = '\0';
}

static int
hex_pair(const char *p)
{
	int hi = -1, lo = -1;
	if (p[0] >= '0' && p[0] <= '9')      hi = p[0] - '0';
	else if (p[0] >= 'a' && p[0] <= 'f') hi = p[0] - 'a' + 10;
	else if (p[0] >= 'A' && p[0] <= 'F') hi = p[0] - 'A' + 10;
	if (p[1] >= '0' && p[1] <= '9')      lo = p[1] - '0';
	else if (p[1] >= 'a' && p[1] <= 'f') lo = p[1] - 'a' + 10;
	else if (p[1] >= 'A' && p[1] <= 'F') lo = p[1] - 'A' + 10;
	if (hi < 0 || lo < 0) return -1;
	return (hi << 4) | lo;
}

/**
 * Encodes a colon-separated MAC address as base64.
 *
 * Used per-radio and per-station throughout WiFiDataElements.ObjectData,
 * where it can run thousands of times per `get` on a busy mesh. The
 * encoded form is always 8 ASCII characters since 6 bytes pack
 * exactly into 4 base64 quartets.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: MAC string)
 * @return       base64 string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_mac_to_base64(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *mac_val = uc_fn_arg(0);
	const char *mac;
	uint8_t bytes[6];
	char out[9];
	int i;

	if (ucv_type(mac_val) != UC_STRING)
		return ucv_string_new("");

	mac = ucv_string_get(mac_val);
	if (!mac || !*mac)
		return ucv_string_new("");

	for (i = 0; i < 6; i++) {
		int b = hex_pair(mac);
		if (b < 0)
			return ucv_string_new("");
		bytes[i] = (uint8_t)b;
		mac += 2;
		if (i < 5) {
			if (*mac != ':')
				return ucv_string_new("");
			mac++;
		}
	}

	base64_encode_6(bytes, out);
	return ucv_string_new(out);
}

/**
 * Formats an integer as a zero-padded hex string of `bytes * 2` characters.
 *
 * Mirrors the WiFiDataElements `int_to_hexbin` ucode helper that emits
 * HEXBIN-formatted bitmasks. A null/missing input yields an empty string.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: value, byte count)
 * @return       hex string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_int_to_hexbin(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0);
	uc_value_t *bytes_val = uc_fn_arg(1);
	int64_t v;
	int bytes;
	char fmt[16], buf[64];

	if (ucv_type(val) != UC_INTEGER || ucv_type(bytes_val) != UC_INTEGER)
		return ucv_string_new("");

	v = ucv_int64_get(val);
	bytes = (int)ucv_int64_get(bytes_val);
	if (bytes <= 0 || bytes > 16)
		return ucv_string_new("");

	snprintf(fmt, sizeof(fmt), "%%0%d" PRIx64, bytes * 2);
	snprintf(buf, sizeof(buf), fmt, (uint64_t)v);

	return ucv_string_new(buf);
}

/**
 * Encodes an array of byte values as a contiguous lowercase hex string.
 *
 * Each entry is masked to 8 bits before formatting. Used to emit DSCP
 * mapping tables (typically 64 bytes) from WiFiDataElements.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: array of integers)
 * @return       hex string, or empty string on bad input
 */
uc_value_t *
uc_ubbf_dscp_map_to_hex(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr = uc_fn_arg(0);
	size_t n, i;
	char *out;
	uc_value_t *r;

	if (ucv_type(arr) != UC_ARRAY)
		return ucv_string_new("");

	n = ucv_array_length(arr);
	if (n == 0)
		return ucv_string_new("");

	out = malloc(n * 2 + 1);
	for (i = 0; i < n; i++) {
		uc_value_t *e = ucv_array_get(arr, i);
		uint8_t b = (ucv_type(e) == UC_INTEGER) ? (uint8_t)ucv_int64_get(e) : 0;
		out[i * 2]     = "0123456789abcdef"[b >> 4];
		out[i * 2 + 1] = "0123456789abcdef"[b & 0x0f];
	}
	out[n * 2] = '\0';

	r = ucv_string_new(out);
	free(out);

	return r;
}

/**
 * Builds a BSSID-keyed object from an array of `{ bssid, ... }` entries.
 *
 * Replaces the family of `bss_metrics_find`, `bss_extended_metrics_find`,
 * `bss_config_find`, `bss_backhaul_config_find`, and
 * `bss_assoc_status_find` linear scans in WiFiDataElements.ObjectData.
 * Callers index by BSSID for O(1) lookup instead of O(n) per row.
 *
 * The optional second argument is a sub-key (e.g. `"bss"` for the
 * `bss_config_report` shape that nests `bss[]` arrays inside radio
 * entries); when supplied, the helper iterates that sub-array on each
 * top-level entry and indexes the inner objects.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1-2 expected: array, optional sub-key)
 * @return       object keyed by uppercase BSSID
 */
uc_value_t *
uc_ubbf_bss_index_by_bssid(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr = uc_fn_arg(0);
	uc_value_t *subkey_val = uc_fn_arg(1);
	const char *subkey = NULL;
	uc_value_t *out;
	size_t n, i, j, m;

	out = ucv_object_new(vm);

	if (ucv_type(arr) != UC_ARRAY)
		return out;

	if (ucv_type(subkey_val) == UC_STRING)
		subkey = ucv_string_get(subkey_val);

	n = ucv_array_length(arr);
	for (i = 0; i < n; i++) {
		uc_value_t *e = ucv_array_get(arr, i);
		if (!subkey) {
			uc_value_t *b = ucv_object_get(e, "bssid", NULL);
			const char *bs = ucv_string_get(b);
			if (bs && *bs)
				ucv_object_add(out, bs, ucv_get(e));
			continue;
		}

		uc_value_t *inner = ucv_object_get(e, subkey, NULL);
		if (ucv_type(inner) != UC_ARRAY)
			continue;
		m = ucv_array_length(inner);
		for (j = 0; j < m; j++) {
			uc_value_t *ie = ucv_array_get(inner, j);
			uc_value_t *b = ucv_object_get(ie, "bssid", NULL);
			const char *bs = ucv_string_get(b);
			if (bs && *bs)
				ucv_object_add(out, bs, ucv_get(ie));
		}
	}

	return out;
}
