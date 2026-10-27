/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Capabilities of a wiphy from its iwinfo/nl80211 description: standards,
 * bandwidths, channels, transmit power and PHY rate per band.
 * `band_idx` indexes `phy.wiphy_bands` as ucode does.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>
#include <sys/param.h>

enum {
	BW_20 = 1 << 0,
	BW_40 = 1 << 1,
	BW_80 = 1 << 2,
	BW_160 = 1 << 3,
	BW_320 = 1 << 4,
};

/* Maximum PHY rate in Mbit/s by width (20MHz upwards) and by spatial
 * streams. 802.11be 320MHz is about twice the 160MHz rate per stream. */
static const int he_rates[WIFI_BANDWIDTHS][9] = {
	{ 0, 86, 172, 258, 344, 516, 688, 774, 860 },
	{ 0, 172, 344, 516, 688, 1032, 1376, 1549, 1721 },
	{ 0, 360, 721, 1081, 1441, 2162, 2882, 3243, 3603 },
	{ 0, 721, 1441, 2162, 2882, 4324, 5765, 6485, 7206 },
	{ 0, 1442, 2882, 4324, 5764, 8648, 11530, 12970, 14412 },
};

static const int vht_rates[4][5] = {
	{ 0, 87, 173, 260, 347 },
	{ 0, 200, 400, 600, 800 },
	{ 0, 433, 867, 1300, 1733 },
	{ 0, 867, 1733, 2600, 3467 },
};

static const int ht_rates[2][5] = {
	{ 0, 72, 144, 217, 289 },
	{ 0, 150, 300, 450, 600 },
};

static bool
flag(uc_value_t *obj, const char *name)
{
	return ucv_is_truish(ucv_object_get(obj, name, NULL));
}

/* Entry `i` of an array when it is an object; ucode would throw on the
 * member access of any other entry. */
static uc_value_t *
entry_get(uc_value_t *arr, size_t i)
{
	uc_value_t *e = ucv_array_get(arr, i);

	return (ucv_type(e) == UC_OBJECT) ? e : NULL;
}

/* `phy?.wiphy_bands?.[band_idx]`, an owned reference when truthy. */
static uc_value_t *
phy_band_get(uc_vm_t *vm, uc_value_t *phy, uc_value_t *band_idx)
{
	uc_value_t *band = ucv_key_get(vm, ucv_object_get(phy, "wiphy_bands", NULL), band_idx);

	if (ucv_is_truish(band))
		return band;

	ucv_put(band);

	return NULL;
}

static uc_value_t *
phy_band_at(uc_vm_t *vm, uc_value_t *phy, int64_t idx)
{
	uc_value_t *key = ucv_int64_new(idx), *band = phy_band_get(vm, phy, key);

	ucv_put(key);

	return band;
}

/* The first iftype_data entry for the AP mode, or NULL. */
static uc_value_t *
band_ap_iftype(uc_value_t *band)
{
	uc_value_t *ifds = ucv_object_get(band, "iftype_data", NULL), *ifd;

	for (size_t i = 0; i < ucv_array_length(ifds); i++) {
		ifd = entry_get(ifds, i);
		if (flag(ucv_object_get(ifd, "iftypes", NULL), "ap"))
			return ifd;
	}

	return NULL;
}

static const char *
band_max_standard(uc_value_t *band)
{
	uc_value_t *ifds = ucv_object_get(band, "iftype_data", NULL), *ifd;

	for (size_t i = 0; i < ucv_array_length(ifds); i++) {
		ifd = entry_get(ifds, i);
		if (!flag(ucv_object_get(ifd, "iftypes", NULL), "ap"))
			continue;
		if (flag(ifd, "eht_cap_phy"))
			return "be";
		if (flag(ifd, "he_cap_phy"))
			return "ax";
	}

	if (flag(band, "vht_mcs_set"))
		return "ac";
	if (flag(band, "ht_capa"))
		return "n";

	return "g";
}

/* The widths that any enabled channel of the band allows, as BW_* bits. */
static unsigned int
band_widths(uc_value_t *band)
{
	uc_value_t *ifds = ucv_object_get(band, "iftype_data", NULL), *ifd;
	uc_value_t *freqs = ucv_object_get(band, "freqs", NULL), *freq;
	unsigned int widths = BW_20;
	bool eht = false;

	for (size_t i = 0; !eht && i < ucv_array_length(ifds); i++) {
		ifd = entry_get(ifds, i);
		eht = flag(ucv_object_get(ifd, "iftypes", NULL), "ap") && flag(ifd, "eht_cap_phy");
	}

	for (size_t i = 0; i < ucv_array_length(freqs); i++) {
		freq = entry_get(freqs, i);
		if (!freq || flag(freq, "disabled"))
			continue;
		if (!flag(freq, "no_ht40_minus") || !flag(freq, "no_ht40_plus"))
			widths |= BW_40;
		if (!flag(freq, "no_80mhz"))
			widths |= BW_80;
		if (!flag(freq, "no_160mhz"))
			widths |= BW_160;
		if (eht && !flag(freq, "no_320mhz"))
			widths |= BW_320;
	}

	return widths;
}

static int
widths_max(unsigned int widths)
{
	return 31 - __builtin_clz(widths);
}

/**
 * ucode: `phy_max_standard(phy, band_idx)`, the highest standard of a
 * wiphy on a band.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       'g', 'n', 'ac', 'ax' or 'be'
 */
uc_value_t *
uc_ubbf_phy_max_standard(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	const char *std = band ? band_max_standard(band) : "g";

	ucv_put(band);

	return ucv_string_new(std);
}

/**
 * ucode: `phy_supported_bandwidths(phy, band_idx)`, the bandwidths that an
 * enabled channel of the band allows.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       comma-separated bandwidths, such as '20MHz,40MHz,80MHz'
 */
uc_value_t *
uc_ubbf_phy_supported_bandwidths(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	unsigned int widths = band ? band_widths(band) : BW_20;
	char buf[64] = "";

	for (int i = 0; i < WIFI_BANDWIDTHS; i++)
		if (widths & (1u << i))
			snprintf(buf + strlen(buf), sizeof(buf) - strlen(buf), "%s%s", i ? "," : "", wifi_bandwidths[i]);

	ucv_put(band);

	return ucv_string_new(buf);
}

/**
 * ucode: `phy_max_bandwidth(phy, band_idx)`, the widest of
 * phy_supported_bandwidths().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       '20MHz' to '320MHz'
 */
uc_value_t *
uc_ubbf_phy_max_bandwidth(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	int max = band ? widths_max(band_widths(band)) : 0;

	ucv_put(band);

	return ucv_string_new(wifi_bandwidths[max]);
}

/**
 * ucode: `phy_max_ssids(phy)`, the number of AP interfaces of the first
 * interface combination limit that allows the AP mode.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: phy)
 * @return       the `max` of that limit, or 0
 */
uc_value_t *
uc_ubbf_phy_max_ssids(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *combos = ucv_object_get(uc_fn_arg(0), "interface_combinations", NULL);
	uc_value_t *limits, *limit, *max;

	for (size_t i = 0; i < ucv_array_length(combos); i++) {
		limits = ucv_object_get(entry_get(combos, i), "limits", NULL);

		for (size_t j = 0; j < ucv_array_length(limits); j++) {
			limit = entry_get(limits, j);
			if (!flag(ucv_object_get(limit, "types", NULL), "ap"))
				continue;

			max = ucv_object_get(limit, "max", NULL);

			return max ? ucv_get(max) : ucv_int64_new(0);
		}
	}

	return ucv_int64_new(0);
}

/**
 * ucode: `phy_max_bitrate(phy, band_idx)`, the maximum PHY rate of a band
 * from its highest standard, its widest bandwidth and the transmit
 * antennas of the wiphy.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       rate in Mbit/s, 0 for an unknown band
 */
uc_value_t *
uc_ubbf_phy_max_bitrate(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *phy = uc_fn_arg(0), *band = phy_band_get(vm, phy, uc_fn_arg(1));
	int nss, bw, rate;
	const char *std;

	if (!band)
		return ucv_int64_new(0);

	nss = wifi_antenna_count(ucv_object_get(phy, "wiphy_antenna_tx", NULL));
	bw = widths_max(band_widths(band));
	std = band_max_standard(band);

	if (!strcmp(std, "be") || !strcmp(std, "ax"))
		rate = he_rates[bw][MIN(nss, 8)];
	else if (!strcmp(std, "ac"))
		rate = vht_rates[(bw < 4) ? bw : 0][MIN(nss, 4)];
	else if (!strcmp(std, "n"))
		rate = ht_rates[bw ? 1 : 0][MIN(nss, 4)];
	else
		rate = 54;

	ucv_put(band);

	return ucv_int64_new(rate);
}

/**
 * ucode: `phy_max_txpower(phy, band_idx)`, the highest max_tx_power of
 * the enabled channels of a band, in dBm. An integer divides as ucode
 * integers do.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       transmit power, or null for an unknown band
 */
uc_value_t *
uc_ubbf_phy_max_txpower(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	uc_value_t *freqs = ucv_object_get(band, "freqs", NULL), *freq, *power;
	bool is_double = false;
	int64_t imax = 0;
	double dmax = 0, cur;

	if (!band)
		return NULL;

	for (size_t i = 0; i < ucv_array_length(freqs); i++) {
		freq = entry_get(freqs, i);
		if (!freq || flag(freq, "disabled"))
			continue;

		power = ucv_object_get(freq, "max_tx_power", NULL);
		cur = is_double ? dmax : (double)imax;

		if (ucv_type(power) == UC_INTEGER &&
		    (is_double ? ucv_int64_get(power) > dmax : ucv_int64_get(power) > imax)) {
			imax = ucv_int64_get(power);
			is_double = false;
		} else if (ucv_type(power) == UC_DOUBLE && ucv_double_get(power) > cur) {
			dmax = ucv_double_get(power);
			is_double = true;
		}
	}

	ucv_put(band);

	return is_double ? ucv_double_new(dmax / 100) : ucv_int64_new(imax / 100);
}

/**
 * ucode: `phy_supported_bands(phy)`, the TR-181 names of the bands with an
 * enabled channel.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: phy)
 * @return       comma-separated bands, such as '2.4GHz,5GHz'
 */
uc_value_t *
uc_ubbf_phy_supported_bands(uc_vm_t *vm, size_t nargs)
{
	static const struct {
		int idx;
		const char *name;
	} slots[] = { { 0, "2.4GHz" }, { 1, "5GHz" }, { 3, "6GHz" } };
	uc_value_t *band, *freqs, *freq;
	char buf[32] = "";

	for (size_t s = 0; s < ARRAY_SIZE(slots); s++) {
		band = phy_band_at(vm, uc_fn_arg(0), slots[s].idx);
		freqs = ucv_object_get(band, "freqs", NULL);

		for (size_t i = 0; i < ucv_array_length(freqs); i++) {
			freq = entry_get(freqs, i);
			if (!freq || flag(freq, "disabled"))
				continue;

			snprintf(buf + strlen(buf), sizeof(buf) - strlen(buf), "%s%s", *buf ? "," : "", slots[s].name);
			break;
		}

		ucv_put(band);
	}

	return ucv_string_new(buf);
}

static bool
index_is(uc_value_t *band_idx, int64_t n)
{
	uc_value_t *num = ucv_int64_new(n);
	bool eq = loose_equal(band_idx, num);

	ucv_put(num);

	return eq;
}

/**
 * ucode: `phy_supported_standards(phy, band_idx)`, the standards of a
 * band. The 6 GHz band has no legacy or HT operation.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index 0, 1 or 3)
 * @return       comma-separated standards, such as 'b,g,n,ax'
 */
uc_value_t *
uc_ubbf_phy_supported_standards(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band_idx = uc_fn_arg(1), *band = phy_band_get(vm, uc_fn_arg(0), band_idx), *ifd;
	char buf[32] = "";

	if (!band)
		return ucv_string_new("");

	if (index_is(band_idx, 0))
		strcat(buf, ",b,g");
	else if (index_is(band_idx, 1))
		strcat(buf, ",a");

	if (!index_is(band_idx, 3) && flag(band, "ht_capa"))
		strcat(buf, ",n");

	if (index_is(band_idx, 1) && flag(band, "vht_mcs_set"))
		strcat(buf, ",ac");

	ifd = band_ap_iftype(band);
	if (flag(ifd, "he_cap_phy"))
		strcat(buf, ",ax");
	if (flag(ifd, "eht_cap_phy"))
		strcat(buf, ",be");

	ucv_put(band);

	return ucv_string_new(*buf ? buf + 1 : buf);
}

/**
 * ucode: `phy_possible_channels(phy, band_idx)`, the channel numbers of
 * the enabled channels of a band.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: phy, band index)
 * @return       comma-separated channels, such as '1,6,11'
 */
uc_value_t *
uc_ubbf_phy_possible_channels(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	uc_value_t *freqs = ucv_object_get(band, "freqs", NULL), *freq;
	uc_stringbuf_t *buf = ucv_stringbuf_new();
	const char *sep = "";
	int64_t ch;

	for (size_t i = 0; i < ucv_array_length(freqs); i++) {
		freq = entry_get(freqs, i);
		if (!freq || flag(freq, "disabled"))
			continue;

		ch = wifi_freq_channel(ucv_object_get(freq, "freq", NULL));
		if (ch <= 0)
			continue;

		ucv_stringbuf_printf(buf, "%s%" PRId64, sep, ch);
		sep = ",";
	}

	ucv_put(band);

	return ucv_stringbuf_finish(buf);
}

/**
 * ucode: `channel_valid_for_bandwidth(phy, band_idx, channel, bandwidth)`,
 * whether the first enabled channel of the band with that number allows
 * the bandwidth.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected)
 * @return       boolean; true for 20MHz and for a bandwidth without a flag
 */
uc_value_t *
uc_ubbf_channel_valid_for_bandwidth(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *bandwidth = uc_fn_arg(3), *band, *freqs, *freq, *chan = NULL, *ch;
	bool ok = true;

	if (value_loose_is(bandwidth, "20MHz"))
		return ucv_boolean_new(true);

	band = phy_band_get(vm, uc_fn_arg(0), uc_fn_arg(1));
	freqs = ucv_object_get(band, "freqs", NULL);

	for (size_t i = 0; !chan && i < ucv_array_length(freqs); i++) {
		freq = entry_get(freqs, i);
		if (!freq || flag(freq, "disabled"))
			continue;

		ch = ucv_int64_new(wifi_freq_channel(ucv_object_get(freq, "freq", NULL)));
		if (loose_equal(ch, uc_fn_arg(2)))
			chan = freq;
		ucv_put(ch);
	}

	if (!chan)
		ok = false;
	else if (value_is(bandwidth, "40MHz"))
		ok = !flag(chan, "no_ht40_minus") || !flag(chan, "no_ht40_plus");
	else if (value_is(bandwidth, "80MHz"))
		ok = !flag(chan, "no_80mhz");
	else if (value_is(bandwidth, "160MHz"))
		ok = !flag(chan, "no_160mhz");
	else if (value_is(bandwidth, "320MHz"))
		ok = !flag(chan, "no_320mhz");

	ucv_put(band);

	return ucv_boolean_new(ok);
}
