/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include "bindings.h"
#include <ctype.h>
#include <math.h>
#include <sys/param.h>

#define UBBF_TXPOWER_MIN_DBM 1

/**
 * Converts a 2.4/5/6 GHz WiFi centre frequency (MHz) to a channel number.
 *
 * Returns 0 for zero/negative input or out-of-range frequencies. ucode:
 * `freq_to_channel(freq)`.
 *
 * @param val  frequency, an integer or a decimal string
 * @return     channel number, or 0 when the frequency is not mappable
 */
int64_t
wifi_freq_channel(uc_value_t *val)
{
	long long f;

	if (ucv_type(val) == UC_INTEGER)
		f = ucv_int64_get(val);
	else if (ucv_type(val) == UC_STRING) {
		const char *s = ucv_string_get(val);
		char *endp;
		if (!s || !*s) return 0;
		f = strtoll(s, &endp, 10);
		if (*endp != '\0') return 0;
	} else {
		return 0;
	}

	if (f <= 0)
		return 0;

	if (f >= 2412 && f <= 2484) {
		if (f == 2484) return 14;
		return (f - 2407) / 5;
	}
	if (f >= 5180 && f <= 5885)
		return (f - 5000) / 5;
	/* 6 GHz channel 2 lies off the 5950 + 5n grid (802.11-2024 Annex E) */
	if (f == 5935)
		return 2;
	if (f >= 5955 && f <= 7115)
		return (f - 5950) / 5;

	return 0;
}

uc_value_t *
uc_ubbf_freq_to_channel(uc_vm_t *vm, size_t nargs)
{
	return ucv_int64_new(wifi_freq_channel(uc_fn_arg(0)));
}

/**
 * Returns the number of set bits in a small antenna mask.
 *
 * A zero mask yields 1 (callers treat "no mask" as a single implicit
 * antenna). ucode: `antenna_count(mask)`.
 *
 * @param val  mask, an integer or a decimal string
 * @return     popcount, minimum 1
 */
int
wifi_antenna_count(uc_value_t *val)
{
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
	return count > 0 ? count : 1;
}

uc_value_t *
uc_ubbf_antenna_count(uc_vm_t *vm, size_t nargs)
{
	return ucv_int64_new(wifi_antenna_count(uc_fn_arg(0)));
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
	static const struct {
		const char *prefix;
		const char *standard;
	} tags[] = {
		{ "EHT-", "be" }, { "HE-", "ax" }, { "VHT-", "ac" }, { "MCS", "n" },
	};
	uc_value_t *flags = uc_fn_arg(0);
	size_t best = ARRAY_SIZE(tags);

	for (size_t i = 0; i < ucv_array_length(flags); i++) {
		uc_value_t *ev = ucv_array_get(flags, i);

		if (ucv_type(ev) != UC_STRING)
			continue;

		for (size_t t = 0; t < best; t++)
			if (!strncmp(ucv_string_get(ev), tags[t].prefix, strlen(tags[t].prefix)))
				best = t;
	}

	return ucv_string_new(best < ARRAY_SIZE(tags) ? tags[best].standard : "");
}

const char *const wifi_bandwidths[WIFI_BANDWIDTHS] = { "20MHz", "40MHz", "80MHz", "160MHz", "320MHz" };

static const char *const standard_order[] = { "g", "n", "ac", "ax", "be" };

/* The htmode of each standard by the width in wifi_bandwidths[]; NULL
 * where the standard has no mode of that width. */
static const struct {
	const char *standard;
	const char *modes[WIFI_BANDWIDTHS];
} htmodes[] = {
	{ "be", { "EHT20", "EHT40", "EHT80", "EHT160", "EHT320" } },
	{ "ax", { "HE20", "HE40", "HE80", "HE160", NULL } },
	{ "ac", { "VHT20", "VHT40", "VHT80", "VHT160", NULL } },
	{ "n", { "HT20", "HT40", NULL, NULL, NULL } },
};

static const struct {
	const char *uci;
	const char *tr181;
	int index;
	int address_offset;
} bands[] = {
	{ "2g", "2.4GHz", 0, 0 },
	{ "5g", "5GHz", 1, 1 },
	{ "6g", "6GHz", 3, 2 },
	{ "60g", "60GHz", 2, 3 },
};

static const struct {
	const char *name;
	int value;
} dscp_names[] = {
	{ "MIN", 0 }, { "DF", 0 }, { "CS0", 0 }, { "LE", 1 }, { "CS1", 8 },
	{ "AF11", 10 }, { "AF12", 12 }, { "AF13", 14 }, { "CS2", 16 },
	{ "AF21", 18 }, { "AF22", 20 }, { "AF23", 22 }, { "CS3", 24 },
	{ "AF31", 26 }, { "AF32", 28 }, { "AF33", 30 }, { "CS4", 32 },
	{ "AF41", 34 }, { "AF42", 36 }, { "AF43", 38 }, { "CS5", 40 },
	{ "VA", 44 }, { "EF", 46 }, { "CS6", 48 }, { "CS7", 56 },
};

/* Index of a string value in a list under ucode index(), or -1. */
static int
list_index(const char *const *list, size_t n, uc_value_t *val)
{
	for (size_t i = 0; i < n; i++)
		if (value_is(val, list[i]))
			return i;

	return -1;
}

/**
 * The highest standard named in a standards value such as 'b/g/n/ac'.
 *
 * @param vm         ucode VM context
 * @param standards  standards value
 * @return           'g', 'n', 'ac', 'ax' or 'be'
 */
const char *
wifi_standard_highest(uc_vm_t *vm, uc_value_t *standards)
{
	static const char *const tags[] = { "be", "ax", "ac", "n" };
	const char *highest = "g";
	char *std;

	if (!ucv_is_truish(standards))
		return highest;

	std = ucv_to_string(vm, standards);
	for (char *p = std; *p; p++)
		*p = tolower((unsigned char)*p);

	for (size_t i = 0; i < ARRAY_SIZE(tags); i++) {
		if (strstr(std, tags[i])) {
			highest = tags[i];
			break;
		}
	}

	free(std);

	return highest;
}

/* A standard without the width gets its widest mode below it, as n has
 * no 80MHz. */
static const char *
htmode_get(uc_vm_t *vm, uc_value_t *standards, uc_value_t *bandwidth)
{
	const char *std;
	size_t t;
	int i;

	if (!ucv_is_truish(standards))
		return "NOHT";

	std = wifi_standard_highest(vm, standards);
	for (t = 0; t < ARRAY_SIZE(htmodes); t++)
		if (!strcmp(htmodes[t].standard, std))
			break;

	if (t == ARRAY_SIZE(htmodes))
		return "NOHT";

	i = bandwidth ? list_index(wifi_bandwidths, WIFI_BANDWIDTHS, bandwidth) : 0;
	for (; i >= 0; i--)
		if (htmodes[t].modes[i])
			return htmodes[t].modes[i];

	return htmodes[t].modes[0];
}

/**
 * ucode: `standards_to_highest(standards)`, the highest standard named in
 * a standards string.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: standards string)
 * @return       'g', 'n', 'ac', 'ax' or 'be'
 */
uc_value_t *
uc_ubbf_standards_to_highest(uc_vm_t *vm, size_t nargs)
{
	return ucv_string_new(wifi_standard_highest(vm, uc_fn_arg(0)));
}

/**
 * ucode: `standards_bandwidth_to_htmode(standards, bandwidth)`, the
 * htmode of the highest standard at a bandwidth (20MHz without one).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: standards, bandwidth)
 * @return       htmode such as 'HE80', or 'NOHT'
 */
uc_value_t *
uc_ubbf_standards_bandwidth_to_htmode(uc_vm_t *vm, size_t nargs)
{
	return ucv_string_new(htmode_get(vm, uc_fn_arg(0), uc_fn_arg(1)));
}

/**
 * ucode: `clamp_htmode(requested_std, requested_bw, max_std, max_bw)`, the
 * htmode of the requested standard and bandwidth, each cut to the maximum
 * of the radio. The wifi stack has no 80+80 htmode, so 80+80MHz counts as
 * its contiguous 160MHz equivalent.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected)
 * @return       htmode string
 */
uc_value_t *
uc_ubbf_clamp_htmode(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *std = uc_fn_arg(0), *bw = uc_fn_arg(1);
	uc_value_t *max_std = uc_fn_arg(2), *max_bw = uc_fn_arg(3);
	uc_value_t *bw_160 = ucv_string_new("160MHz");
	int std_idx, max_std_idx, bw_idx, max_bw_idx;
	const char *mode;

	if (value_loose_is(bw, "80+80MHz"))
		bw = bw_160;
	if (value_loose_is(max_bw, "80+80MHz"))
		max_bw = bw_160;

	std_idx = list_index(standard_order, ARRAY_SIZE(standard_order), std);
	max_std_idx = list_index(standard_order, ARRAY_SIZE(standard_order), max_std);
	bw_idx = list_index(wifi_bandwidths, WIFI_BANDWIDTHS, bw);
	max_bw_idx = list_index(wifi_bandwidths, WIFI_BANDWIDTHS, max_bw);

	mode = htmode_get(vm, (MAX(std_idx, 0) <= MAX(max_std_idx, 0)) ? std : max_std,
			  (MAX(bw_idx, 0) <= MAX(max_bw_idx, 0)) ? bw : max_bw);

	ucv_put(bw_160);

	return ucv_string_new(mode);
}

/**
 * ucode: `channel_width_to_bandwidth(width)`, the bandwidth of an
 * NL80211_CHAN_WIDTH_* value.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: width)
 * @return       bandwidth string, or '' for an unknown width
 */
uc_value_t *
uc_ubbf_channel_width_to_bandwidth(uc_vm_t *vm, size_t nargs)
{
	/* indexed by NL80211_CHAN_WIDTH_*: 8-12 are the S1G widths, 320MHz is 13 */
	static const char *const widths[] = {
		"20MHz", "20MHz", "40MHz", "80MHz", "80+80MHz", "160MHz", "5MHz",
		"10MHz", "1MHz", "2MHz", "4MHz", "8MHz", "16MHz", "320MHz",
	};
	uc_value_t *list = ucv_array_new(vm), *res;

	/* ucv_key_get() reads the index as ucode does, negative from the end */
	for (size_t i = 0; i < ARRAY_SIZE(widths); i++)
		ucv_array_push(list, ucv_string_new(widths[i]));

	res = ucv_key_get(vm, list, uc_fn_arg(0));
	ucv_put(list);

	return res ? res : ucv_string_new("");
}

/**
 * ucode: `band_to_uci(band)`, the UCI band of a TR-181 band name.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: '2.4GHz', '5GHz', '6GHz')
 * @return       '2g', '5g' or '6g'; '2g' for any other value
 */
uc_value_t *
uc_ubbf_band_to_uci(uc_vm_t *vm, size_t nargs)
{
	for (size_t i = 0; i < ARRAY_SIZE(bands); i++)
		if (bands[i].index != 2 && value_is(uc_fn_arg(0), bands[i].tr181))
			return ucv_string_new(bands[i].uci);

	return ucv_string_new("2g");
}

/**
 * ucode: `band_to_index(band)`, the wiphy_bands index of a band. The
 * array is positioned by the kernel nl80211 band enum (DF_TYPEIDX in the
 * ucode nl80211 module): 0=2.4GHz, 1=5GHz, 2=60GHz, 3=6GHz.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: UCI or TR-181 band name)
 * @return       band index, 0 for an unknown band
 */
uc_value_t *
uc_ubbf_band_to_index(uc_vm_t *vm, size_t nargs)
{
	for (size_t i = 0; i < ARRAY_SIZE(bands); i++)
		if (value_is(uc_fn_arg(0), bands[i].uci) || value_is(uc_fn_arg(0), bands[i].tr181))
			return ucv_int64_new(bands[i].index);

	return ucv_int64_new(0);
}

/* Bytes of a MAC address string under ucode hexdec(mac, ':'). */
static bool
mac_hexdec(uc_value_t **mac, uint8_t out[6])
{
	const char *s = ucv_string_get(*mac);
	size_t len = ucv_string_length(*mac), n = 0;
	int nibble;

	for (size_t i = 0; i < len; i++) {
		/* hexdec() skips a NUL byte like a separator */
		if (s[i] == ':' || !s[i])
			continue;

		nibble = hex_nibble(s[i]);
		if (nibble < 0 || n == 12)
			return false;

		out[n / 2] = (n & 1) ? (out[n / 2] | nibble) : (nibble << 4);
		n++;
	}

	return n == 12;
}

/**
 * ucode: `radio_address_derive(phy_mac, band)`, the unique identifier of
 * a radio from the MAC address of its wiphy.
 *
 * The radios of one wiphy share its MAC address, so each band past 2.4 GHz
 * takes a locally administered address with the offset of the band in the
 * last byte. The scheme is umapd's (derive_radio_address() in
 * rrmd/opclass.uc), so a radio keeps its identifier with and without
 * EasyMesh.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: wiphy MAC, UCI band)
 * @return       radio identifier, or null without a valid MAC
 */
uc_value_t *
uc_ubbf_radio_address_derive(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *mac = uc_fn_arg(0);
	char *lower, buf[18];
	int offset = 0;
	uint8_t o[6];
	uc_value_t *res;

	if (ucv_type(mac) != UC_STRING || !ucv_is_truish(mac) || !mac_hexdec(&mac, o))
		return NULL;

	for (size_t i = 0; i < ARRAY_SIZE(bands); i++)
		if (value_is(uc_fn_arg(1), bands[i].uci))
			offset = bands[i].address_offset;

	if (offset) {
		o[0] |= 0x02;
		o[5] += offset;
		snprintf(buf, sizeof(buf), "%02x:%02x:%02x:%02x:%02x:%02x",
			 o[0], o[1], o[2], o[3], o[4], o[5]);

		return ucv_string_new(buf);
	}

	lower = xalloc(ucv_string_length(mac) + 1);
	for (size_t i = 0; i < ucv_string_length(mac); i++)
		lower[i] = tolower((unsigned char)ucv_string_get(mac)[i]);

	res = ucv_string_new_length(lower, ucv_string_length(mac));
	free(lower);

	return res;
}

/* A DSCP name (any case) or a number 0..63, after trimming; -1 when it is
 * neither. */
static int
dscp_parse(uc_vm_t *vm, uc_value_t *token)
{
	char *text, *t, *end;
	uc_value_t *num;
	int64_t n;
	int res = -1;
	bool ok;

	if (!token)
		return -1;

	text = ucv_to_string(vm, token);
	t = text + strspn(text, " \t\r\n");
	for (end = t + strlen(t); end > t && strchr(" \t\r\n", end[-1]); end--)
		;
	*end = '\0';

	if (!*t)
		goto out;

	num = ucv_string_new(t);
	ok = value_to_int(num, &n);
	ucv_put(num);

	str_to_upper(t);
	for (size_t i = 0; i < ARRAY_SIZE(dscp_names); i++) {
		if (!strcmp(t, dscp_names[i].name)) {
			res = dscp_names[i].value;
			goto out;
		}
	}

	if (ok && n >= 0 && n <= 63)
		res = n;

out:
	free(text);

	return res;
}

/* The set of codepoints of a comma-separated DSCP list, bit n for n. */
static uint64_t
dscp_list_parse(uc_vm_t *vm, uc_value_t *csv)
{
	uc_value_t *token;
	uint64_t set = 0;
	char *text, *p, *comma;
	int v;

	if (!ucv_is_truish(csv))
		return 0;

	text = ucv_to_string(vm, csv);
	for (p = text; p; p = comma ? comma + 1 : NULL) {
		comma = strchr(p, ',');
		token = ucv_string_new_length(p, comma ? (size_t)(comma - p) : strlen(p));
		v = dscp_parse(vm, token);
		ucv_put(token);

		if (v >= 0)
			set |= 1ULL << v;
	}

	free(text);

	return set;
}

/**
 * ucode: `dscp_parse(token)`, one DSCP token as its codepoint.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: DSCP name, any case, or
 *               a number 0..63)
 * @return       codepoint, or null
 */
uc_value_t *
uc_ubbf_dscp_parse(uc_vm_t *vm, size_t nargs)
{
	int v = dscp_parse(vm, uc_fn_arg(0));

	return (v < 0) ? NULL : ucv_int64_new(v);
}

/**
 * ucode: `qos_map_set_render(entries)`, the 16 bytes of the hostapd
 * qos_map_set of the WiFi.X_UBBF_QoSMap.{i} rows. Each enabled row maps
 * its UserPriority (0..7) to the range from the lowest to the highest DSCP
 * of its DSCPList; a UserPriority without a row stays at 255,255 (no
 * claim). The 802.11u exception pairs are not written.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: array of rows)
 * @return       comma-separated decimal bytes, or '' without an enabled row
 */
uc_value_t *
uc_ubbf_qos_map_set_render(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *entries = uc_fn_arg(0), *e;
	int low[8], high[8];
	char buf[8 * 8 + 1];
	size_t pos = 0;
	bool any = false;
	uint64_t set;
	int64_t up;

	for (int i = 0; i < 8; i++)
		low[i] = high[i] = 255;

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		e = ucv_array_get(entries, i);
		if (!value_to_bool(ucv_object_get(e, "Enable", NULL)))
			continue;

		if (!value_int_cut(ucv_object_get(e, "UserPriority", NULL), &up) || up < 0 || up > 7)
			continue;

		set = dscp_list_parse(vm, ucv_object_get(e, "DSCPList", NULL));
		if (!set)
			continue;

		low[up] = __builtin_ctzll(set);
		high[up] = 63 - __builtin_clzll(set);
		any = true;
	}

	if (!any)
		return ucv_string_new("");

	for (int i = 0; i < 8; i++)
		pos += snprintf(buf + pos, sizeof(buf) - pos, "%s%d,%d", i ? "," : "", low[i], high[i]);

	return ucv_string_new(buf);
}
