/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Device.WiFi.DataElements without EasyMesh and over umap: the HT, VHT and
 * HE capabilities of radios and stations, the radio survey and capability
 * from iwinfo, the station list from iwinfo and nl80211, and the merge of
 * the umap replies. utils/wifi-dataelements.uc makes the iwinfo, nl80211
 * and ubus reads and keeps the caches.
 */

#include "ubbf.h"
#include "bindings.h"

#include <libubox/utils.h>

static int64_t
member_int(uc_value_t *obj, const char *name)
{
	return ucv_to_integer(ucv_object_get(obj, name, NULL));
}

static bool
member_flag(uc_value_t *obj, const char *name)
{
	return ucv_is_truish(ucv_object_get(obj, name, NULL));
}

/* `(obj.name ?? def) - 1` of a spatial stream count. */
static int64_t
member_streams(uc_value_t *obj, const char *name)
{
	uc_value_t *val = ucv_object_get(obj, name, NULL);

	return (val ? ucv_to_integer(val) : 1) - 1;
}

/* Byte `i` of a capability array as ucode `arr[i]` reads it in a bit
 * operation: 0 past the end. */
static int64_t
cap_byte(uc_value_t *arr, size_t i)
{
	return ucv_to_integer(ucv_array_get(arr, i));
}

/* ucode b64enc(chr(...)): each value clamped to 0..255. */
static uc_value_t *
bytes_b64_new(const int64_t *vals, size_t n)
{
	char out[B64_ENCODE_LEN(8)];
	uint8_t bytes[8];

	for (size_t i = 0; i < n; i++)
		bytes[i] = (vals[i] < 0) ? 0 : (vals[i] > 255) ? 255 : vals[i];

	b64_encode(bytes, n, out, sizeof(out));

	return ucv_string_new(out);
}

/* The highest stream count in the HT RX MCS indexes; MCS 0-31 map to 1-4
 * streams, 32 and up are duplicate or unequal-modulation rates without
 * stream information. */
static int64_t
ht_rx_streams(uc_value_t *indexes)
{
	uc_value_t *idx;
	int64_t ss, rx = 1;

	for (size_t i = 0; i < ucv_array_length(indexes); i++) {
		idx = ucv_array_get(indexes, i);
		if (ucv_type(idx) == UC_INTEGER && ucv_int64_get(idx) <= 31)
			ss = ucv_int64_get(idx) / 8 + 1;
		else if (ucv_type(idx) == UC_DOUBLE && ucv_double_get(idx) <= 31)
			ss = (int64_t)(ucv_double_get(idx) / 8) + 1;
		else
			continue;

		if (ss > rx)
			rx = ss;
	}

	return rx;
}

/**
 * ucode: `ht_caps_encode(ht_data, band)`, the HT capabilities byte of
 * EasyMesh in base64, from the iwinfo band or else from the EasyMesh data.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: EasyMesh HT data, iwinfo band)
 * @return       base64 string, '' without either
 */
uc_value_t *
uc_ubbf_ht_caps_encode(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ht = uc_fn_arg(0), *band = uc_fn_arg(1), *mcs, *tx_max;
	int64_t capa, tx, rx, byte;

	if (ucv_object_get(band, "ht_capa", NULL)) {
		capa = member_int(band, "ht_capa");
		mcs = ucv_object_get(band, "ht_mcs_set", NULL);
		tx = rx = 1;

		if (ucv_is_truish(mcs)) {
			rx = ht_rx_streams(ucv_object_get(mcs, "rx_mcs_indexes", NULL));
			tx_max = ucv_object_get(mcs, "tx_max_spatial_streams", NULL);
			tx = (member_flag(mcs, "tx_mcs_set_defined") && !member_flag(mcs, "tx_rx_mcs_set_equal"))
				? (tx_max ? ucv_to_integer(tx_max) : rx) : rx;
		}

		byte = ((tx - 1) << 6) | ((rx - 1) << 4) | (!!(capa & 0x20) << 3) |
		       (!!(capa & 0x40) << 2) | (!!(capa & 0x02) << 1);

		return bytes_b64_new(&byte, 1);
	}

	if (!ucv_is_truish(ht))
		return ucv_string_new("");

	byte = (member_streams(ht, "max_supported_tx_spatial_streams") << 6) |
	       (member_streams(ht, "max_supported_rx_spatial_streams") << 4) |
	       (member_flag(ht, "short_gi_support_20mhz") << 3) |
	       (member_flag(ht, "short_gi_support_40mhz") << 2) |
	       (member_flag(ht, "ht_support_40mhz") << 1);

	return bytes_b64_new(&byte, 1);
}

/* The 16-bit VHT MCS map from the rx_mcs_set / tx_mcs_set entries of the
 * nl80211 module; a stream without an entry is not supported (code 3). */
static int64_t
vht_mcs_map_build(uc_value_t *set)
{
	uc_value_t *entry, *streams, *indexes;
	int64_t map = 0xffff, ss, max_idx, code;

	for (size_t i = 0; i < ucv_array_length(set); i++) {
		entry = ucv_array_get(set, i);
		streams = ucv_object_get(entry, "streams", NULL);
		ss = streams ? ucv_to_integer(streams) : 0;
		if (ss < 1 || ss > 8)
			continue;

		indexes = ucv_object_get(entry, "mcs_indexes", NULL);
		max_idx = (ucv_type(indexes) == UC_ARRAY) ? (int64_t)ucv_array_length(indexes) - 1 : -1;
		code = (max_idx >= 9) ? 2 : (max_idx == 8) ? 1 : 0;
		map = (map & ~(3LL << ((ss - 1) * 2))) | (code << ((ss - 1) * 2));
	}

	return map;
}

static int64_t
vht_map_streams(int64_t map)
{
	for (int i = 7; i >= 0; i--)
		if (((map >> (i * 2)) & 0x03) != 0x03)
			return i + 1;

	return 1;
}

/**
 * ucode: `vht_caps_encode(vht_data, band)`, the six VHT capability bytes
 * of EasyMesh in base64, from the iwinfo band or else from the EasyMesh
 * data.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: EasyMesh VHT data, iwinfo band)
 * @return       base64 string, '' without either
 */
uc_value_t *
uc_ubbf_vht_caps_encode(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *vht = uc_fn_arg(0), *band = uc_fn_arg(1), *mcs = ucv_object_get(band, "vht_mcs_set", NULL);
	int64_t capa, rx_map, tx_map, width, bytes[6], tx_mcs, rx_mcs;

	if (ucv_is_truish(mcs) && ucv_object_get(band, "vht_capa", NULL)) {
		capa = member_int(band, "vht_capa");
		rx_map = vht_mcs_map_build(ucv_object_get(mcs, "rx_mcs_set", NULL));
		tx_map = vht_mcs_map_build(ucv_object_get(mcs, "tx_mcs_set", NULL));
		width = (capa >> 2) & 0x03;

		bytes[0] = (tx_map >> 8) & 0xff;
		bytes[1] = tx_map & 0xff;
		bytes[2] = (rx_map >> 8) & 0xff;
		bytes[3] = rx_map & 0xff;
		bytes[4] = ((vht_map_streams(tx_map) - 1) << 5) | ((vht_map_streams(rx_map) - 1) << 2) |
			   (!!(capa & (1 << 5)) << 1) | !!(capa & (1 << 6));
		bytes[5] = ((width >= 2) << 7) | ((width >= 1) << 6) | (!!(capa & (1 << 11)) << 5) |
			   (!!(capa & (1 << 19)) << 4);

		return bytes_b64_new(bytes, 6);
	}

	if (!ucv_is_truish(vht))
		return ucv_string_new("");

	tx_mcs = member_int(vht, "supported_vht_tx_mcs");
	rx_mcs = member_int(vht, "supported_vht_rx_mcs");

	bytes[0] = (tx_mcs >> 8) & 0xff;
	bytes[1] = tx_mcs & 0xff;
	bytes[2] = (rx_mcs >> 8) & 0xff;
	bytes[3] = rx_mcs & 0xff;
	bytes[4] = (member_streams(vht, "max_supported_tx_spatial_streams") << 5) |
		   (member_streams(vht, "max_supported_rx_spatial_streams") << 2) |
		   (member_flag(vht, "short_gi_support_80mhz") << 1) |
		   member_flag(vht, "short_gi_support_160mhz_8080mhz");
	bytes[5] = (member_flag(vht, "vht_support_8080mhz") << 7) | (member_flag(vht, "vht_support_160mhz") << 6) |
		   (member_flag(vht, "su_beamformer_capable") << 5) | (member_flag(vht, "mu_beamformer_capable") << 4);

	return bytes_b64_new(bytes, 6);
}

static void
flag_add(uc_value_t *obj, const char *name, bool flag)
{
	ucv_object_add(obj, name, ucv_boolean_new(flag));
}

static void
zero_add(uc_value_t *obj, const char *name)
{
	ucv_object_add(obj, name, ucv_int64_new(0));
}

/* The HE capabilities of a station from the first HE MAC capability byte
 * and the first five HE PHY capability bytes. */
static uc_value_t *
sta_he_caps_new(uc_vm_t *vm, const int64_t mac[1], const int64_t phy[5], uc_value_t *mcs_nss)
{
	uc_value_t *caps = ucv_object_new(vm);

	flag_add(caps, "he_160", phy[0] & 0x08);
	flag_add(caps, "he_8080", phy[0] & 0x10);
	ucv_object_add(caps, "mcs_nss", mcs_nss ? ucv_get(mcs_nss) : ucv_string_new(""));
	flag_add(caps, "su_beamformer", phy[3] & 0x80);
	flag_add(caps, "su_beamformee", phy[4] & 0x01);
	flag_add(caps, "mu_beamformer_status", phy[4] & 0x02);
	/* B34-B36 and B37-B39, 802.11-2024 Figure 9-900 */
	ucv_object_add(caps, "beamformee_sts_less_80", ucv_int64_new((phy[4] >> 2) & 0x07));
	ucv_object_add(caps, "beamformee_sts_greater_80", ucv_int64_new((phy[4] >> 5) & 0x07));
	flag_add(caps, "ul_mu_mimo", phy[2] & 0x40);
	/* no capability bit: every HE STA supports UL and DL OFDMA
	 * (802.11-2024 27.1.1) */
	flag_add(caps, "ul_ofdma", true);
	flag_add(caps, "dl_ofdma", true);
	zero_add(caps, "max_dl_mu_mimo_tx");
	zero_add(caps, "max_ul_mu_mimo_rx");
	zero_add(caps, "max_dl_ofdma_tx");
	zero_add(caps, "max_ul_ofdma_rx");
	flag_add(caps, "rts", false);
	flag_add(caps, "mu_rts", false);
	flag_add(caps, "multi_bssid", false);
	flag_add(caps, "mu_edca", mac[0] & 0x08);
	flag_add(caps, "twt_requester", mac[0] & 0x02);
	flag_add(caps, "twt_responder", mac[0] & 0x04);
	flag_add(caps, "spatial_reuse", false);
	flag_add(caps, "anticipated_channel_usage", false);

	return caps;
}

static uc_value_t *
sta_he_caps_from_arrays(uc_vm_t *vm, uc_value_t *mac_caps, uc_value_t *phy_caps, uc_value_t *mcs_nss)
{
	int64_t mac[1] = { cap_byte(mac_caps, 0) }, phy[5];

	for (size_t i = 0; i < 5; i++)
		phy[i] = cap_byte(phy_caps, i);

	return sta_he_caps_new(vm, mac, phy, mcs_nss);
}

/**
 * ucode: `sta_he_caps_build(mac_caps, phy_caps, mcs_nss)`, the HE
 * capabilities of a station from its capability bytes.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: HE MAC and PHY capability
 *               byte arrays, MCS/NSS set)
 * @return       HE capabilities object
 */
uc_value_t *
uc_ubbf_sta_he_caps_build(uc_vm_t *vm, size_t nargs)
{
	return sta_he_caps_from_arrays(vm, uc_fn_arg(0), uc_fn_arg(1), uc_fn_arg(2));
}

static uc_value_t *
sta_he_caps_from_info(uc_vm_t *vm, uc_value_t *sta_info)
{
	uc_value_t *he = ucv_object_get(sta_info, "he_cap", NULL);

	if (!ucv_is_truish(sta_info) || !ucv_is_truish(he))
		return NULL;

	return sta_he_caps_from_arrays(vm, ucv_object_get(he, "mac_cap", NULL),
				       ucv_object_get(he, "phy_cap", NULL), ucv_object_get(he, "mcs_nss", NULL));
}

/**
 * ucode: `sta_he_caps_from_nl80211(sta_info)`, the HE capabilities of a
 * station from nl80211 station info.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: sta_info)
 * @return       HE capabilities object, or null without HE capabilities
 */
uc_value_t *
uc_ubbf_sta_he_caps_from_nl80211(uc_vm_t *vm, size_t nargs)
{
	return sta_he_caps_from_info(vm, uc_fn_arg(0));
}

static uc_value_t *
sta_he_caps_from_rate_flags(uc_vm_t *vm, uc_value_t *tx_flags, uc_value_t *rx_flags)
{
	static const int64_t none[5] = { 0 };
	uc_value_t *flags = tx_flags ? tx_flags : rx_flags, *flag;
	bool he = false;

	for (size_t i = 0; !he && i < ucv_array_length(flags); i++) {
		flag = ucv_array_get(flags, i);
		he = ucv_type(flag) == UC_STRING && !strncmp(ucv_string_get(flag), "HE-", 3);
	}

	if (!he)
		return NULL;

	return sta_he_caps_new(vm, none, none, NULL);
}

/**
 * ucode: `sta_he_caps_from_flags(tx_flags, rx_flags)`, minimal HE
 * capabilities of a station whose rate flags show HE.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: TX and RX rate flags)
 * @return       HE capabilities object, or null without HE
 */
uc_value_t *
uc_ubbf_sta_he_caps_from_flags(uc_vm_t *vm, size_t nargs)
{
	return sta_he_caps_from_rate_flags(vm, uc_fn_arg(0), uc_fn_arg(1));
}

/* Whether the elements of a frame body start at `pos`: the first element
 * is the SSID element (ID 0) and the elements end exactly at the end. */
static bool
frame_elements_at(const uint8_t *body, size_t len, size_t pos)
{
	if (pos + 2 > len || body[pos] != 0)
		return false;

	while (pos + 2 <= len)
		pos += 2 + body[pos + 1];

	return pos == len;
}

/**
 * ucode: `sta_he_caps_from_frame_body(frame_body_b64)`, the HE
 * capabilities element of a (Re)Association Request frame body, which
 * EasyMesh gives without a frame type: the elements follow 4 octets of
 * fixed fields in an Association Request and 10 in a Reassociation
 * Request, which adds the Current AP Address (802.11-2024 Tables 9-64 and
 * 9-66).
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: base64 frame body)
 * @return       HE capabilities object, or null without the element
 */
uc_value_t *
uc_ubbf_sta_he_caps_from_frame_body(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *b64 = uc_fn_arg(0), *mcs_nss, *caps = NULL;
	size_t cap, len, pos, elem_len, mcs_len;
	int64_t mac[1], phy[5];
	uint8_t *body;
	int n;

	if (!ucv_is_truish(b64) || ucv_type(b64) != UC_STRING)
		return NULL;

	cap = B64_DECODE_LEN(ucv_string_length(b64));
	body = xalloc(cap);
	n = b64_decode(ucv_string_get(b64), body, cap);
	len = (n > 0) ? (size_t)n : 0;

	pos = frame_elements_at(body, len, 4) ? 4 : frame_elements_at(body, len, 10) ? 10 : 0;

	while (pos && pos + 2 <= len) {
		elem_len = body[pos + 1];
		if (pos + 2 + elem_len > len)
			break;

		/* Element ID Extension 35, HE Capabilities */
		if (body[pos] != 255 || elem_len < 18 || body[pos + 2] != 35) {
			pos += 2 + elem_len;
			continue;
		}

		mac[0] = body[pos + 3];
		for (size_t i = 0; i < 5; i++)
			phy[i] = body[pos + 9 + i];

		mcs_len = elem_len - 18;
		mcs_nss = (mcs_len > 0 && mcs_len <= 12)
			? ucv_string_new_length((char *)body + pos + 20, mcs_len) : ucv_string_new("");
		caps = sta_he_caps_new(vm, mac, phy, mcs_nss);
		ucv_put(mcs_nss);
		break;
	}

	free(body);

	return caps;
}

/**
 * ucode: `chipset_vendor_get(phy_name)`, the vendor of the chipset of a
 * wiphy from its PCI vendor ID in sysfs.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: PHY name, e.g. phy0)
 * @return       vendor name, '' when unknown
 */
uc_value_t *
uc_ubbf_chipset_vendor_get(uc_vm_t *vm, size_t nargs)
{
	static const struct {
		const char *id;
		const char *name;
	} vendors[] = {
		{ "0x14c3", "MediaTek" }, { "0x168c", "Qualcomm Atheros" },
		{ "0x8086", "Intel" }, { "0x14e4", "Broadcom" },
	};
	char *phy = ucv_to_string(vm, uc_fn_arg(0)), *path, *id;
	const char *name = "";

	xasprintf(&path, "/sys/class/ieee80211/%s/device/vendor", phy);
	id = sysfs_read_file(path);

	for (size_t i = 0; id && i < ARRAY_SIZE(vendors); i++)
		if (!strcmp(id, vendors[i].id))
			name = vendors[i].name;

	free(id);
	free(path);
	free(phy);

	return ucv_string_new(name);
}

/* ucode `int((v * 255) / total)`: integer division for two integers. */
static uc_value_t *
survey_share_new(uc_value_t *v, uc_value_t *total)
{
	if (!v)
		return ucv_int64_new(0);

	if (ucv_type(v) == UC_INTEGER && ucv_type(total) == UC_INTEGER)
		return ucv_int64_new(ucv_int64_get(v) * 255 / ucv_int64_get(total));

	return ucv_int64_new((int64_t)(ucv_to_double(v) * 255 / ucv_to_double(total)));
}

/**
 * ucode: `radio_survey_build(iface)`, the survey of a radio from its
 * iwinfo interface. EasyMesh airtime fields are a fraction of the
 * measurement window on a 0-255 scale, not cumulative time, so busy, tx
 * and rx scale against the total time.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: iwinfo.ifaces entry)
 * @return       `{ noise, utilization, transmit, receive_self, receive_other }`,
 *               or an empty object without an interface
 */
uc_value_t *
uc_ubbf_radio_survey_build(uc_vm_t *vm, size_t nargs)
{
	static const struct {
		const char *name;
		const char *field;
	} shares[] = {
		{ "utilization", "busy" }, { "transmit", "time_tx" }, { "receive_self", "time_rx" },
	};
	uc_value_t *iface = uc_fn_arg(0), *result = ucv_object_new(vm), *survey, *total, *noise;
	bool scaled;

	if (!ucv_is_truish(iface))
		return result;

	survey = ucv_object_get(iface, "survey", NULL);
	total = ucv_object_get(survey, "time", NULL);
	scaled = total && ucv_to_double(total) > 0;

	noise = ucv_object_get(survey, "noise", NULL);
	if (!noise)
		noise = ucv_object_get(iface, "noise", NULL);
	ucv_object_add(result, "noise", noise ? ucv_get(noise) : ucv_int64_new(0));

	for (size_t i = 0; i < ARRAY_SIZE(shares); i++)
		ucv_object_add(result, shares[i].name, scaled
			? survey_share_new(ucv_object_get(survey, shares[i].field, NULL), total) : ucv_int64_new(0));

	ucv_object_add(result, "receive_other", ucv_int64_new(0));

	return result;
}

/* The global 20MHz operating class of a channel (802.11-2024 Table E-4):
 * 5GHz splits into 115 (36-48), 118 (52-64), 121 (100-144) and 125 (149+);
 * 6 GHz channel 2 and 2.4 GHz channel 14 have classes of their own, 136
 * and 82. */
static int
opclass_of(double freq, int64_t channel)
{
	if (freq == 5935)
		return 136;
	if (freq > 5935)
		return 131;
	if (freq >= 5180)
		return (channel >= 149) ? 125 : (channel >= 100) ? 121 : (channel >= 52) ? 118 : 115;

	return (freq == 2484) ? 82 : 81;
}

/* `int((max_tx_power ?? 2000) / 100)` of a channel. */
static int64_t
channel_txpower(uc_value_t *power)
{
	if (!power)
		return 20;

	if (ucv_type(power) == UC_INTEGER)
		return ucv_int64_get(power) / 100;

	return (int64_t)(ucv_to_double(power) / 100);
}

static uc_value_t *
opclasses_new(uc_vm_t *vm, uc_value_t *band)
{
	uc_value_t *freqs = ucv_object_get(band, "freqs", NULL), *map = ucv_object_new(vm), *list, *freq, *oc;
	int64_t channel, power;
	char key[8];
	int cls;

	for (size_t i = 0; ucv_is_truish(band) && i < ucv_array_length(freqs); i++) {
		freq = ucv_array_get(freqs, i);
		if (ucv_type(freq) != UC_OBJECT || member_flag(freq, "disabled"))
			continue;

		channel = wifi_freq_channel(ucv_object_get(freq, "freq", NULL));
		power = channel_txpower(ucv_object_get(freq, "max_tx_power", NULL));
		cls = opclass_of(ucv_to_double(ucv_object_get(freq, "freq", NULL)), channel);

		snprintf(key, sizeof(key), "%d", cls);
		oc = ucv_object_get(map, key, NULL);
		if (!oc) {
			oc = ucv_object_new(vm);
			ucv_object_add(oc, "opclass", ucv_int64_new(cls));
			ucv_object_add(oc, "max_txpower_eirp", ucv_int64_new(0));
			ucv_object_add(oc, "channels", ucv_array_new(vm));
			ucv_object_add(map, key, oc);
		}

		if (power > member_int(oc, "max_txpower_eirp"))
			ucv_object_add(oc, "max_txpower_eirp", ucv_int64_new(power));
		ucv_array_push(ucv_object_get(oc, "channels", NULL), ucv_int64_new(channel));
	}

	list = ucv_array_new(vm);
	ucv_object_foreach(map, k, v) {
		(void)k;
		ucv_array_push(list, ucv_get(v));
	}
	ucv_put(map);

	return list;
}

static uc_value_t *
wifi6_role_new(uc_vm_t *vm, uc_value_t *ifd)
{
	uc_value_t *phy = ucv_object_get(ifd, "he_cap_phy", NULL), *mac = ucv_object_get(ifd, "he_cap_mac", NULL);
	uc_value_t *role = ucv_object_new(vm);

	zero_add(role, "agent_role");
	flag_add(role, "he_160", cap_byte(phy, 0) & 0x08);
	flag_add(role, "he_8080", cap_byte(phy, 0) & 0x10);
	flag_add(role, "su_beamformer", cap_byte(phy, 3) & 0x80);
	flag_add(role, "su_beamformee", cap_byte(phy, 4) & 0x01);
	flag_add(role, "mu_beamformer_status", cap_byte(phy, 4) & 0x02);
	flag_add(role, "ul_mu_mimo", cap_byte(phy, 2) & 0x40);
	/* mandatory for an HE AP, 802.11-2024 27.1.1 */
	flag_add(role, "dl_ofdma", true);
	flag_add(role, "ul_ofdma", true);
	flag_add(role, "twt_requester", cap_byte(mac, 0) & 0x02);
	flag_add(role, "twt_responder", cap_byte(mac, 0) & 0x04);
	zero_add(role, "max_dl_mu_mimo_tx");
	zero_add(role, "max_ul_mu_mimo_rx");
	zero_add(role, "max_dl_ofdma_tx");
	zero_add(role, "max_ul_ofdma_rx");

	return role;
}

static uc_value_t *
object_with(uc_vm_t *vm, const char *name, uc_value_t *val)
{
	uc_value_t *obj = ucv_object_new(vm);

	ucv_object_add(obj, name, val);

	return obj;
}

/**
 * ucode: `radio_capability_build(phys, phy_name, band_idx)`, the EasyMesh
 * capabilities of a local radio from its iwinfo wiphy: the operating
 * classes of its enabled channels and the Wi-Fi 6 AP role.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: iwinfo.phys, PHY name,
 *               band index)
 * @return       capabilities object, with the band as `_band` and the HE
 *               iftype data as `_he_ifd`
 */
uc_value_t *
uc_ubbf_radio_capability_build(uc_vm_t *vm, size_t nargs)
{
	static const char *const advanced[] = { "mscs", "scs", "qos_map", "dscp_policy", "scs_traffic_description" };
	uc_value_t *phys = uc_fn_arg(0), *phy = NULL, *band, *ifds, *ifd, *he_ifd = NULL, *roles, *obj, *result;

	for (size_t i = 0; i < ucv_array_length(phys); i++) {
		if (loose_equal(ucv_object_get(ucv_array_get(phys, i), "wiphy_name", NULL), uc_fn_arg(1))) {
			phy = ucv_array_get(phys, i);
			break;
		}
	}

	band = ucv_key_get(vm, ucv_object_get(phy, "wiphy_bands", NULL), uc_fn_arg(2));

	roles = ucv_array_new(vm);
	ifds = ucv_object_get(band, "iftype_data", NULL);
	for (size_t i = 0; i < ucv_array_length(ifds); i++) {
		ifd = ucv_array_get(ifds, i);
		if (!member_flag(ucv_object_get(ifd, "iftypes", NULL), "ap") || !member_flag(ifd, "he_cap_phy"))
			continue;

		he_ifd = ifd;
		ucv_array_push(roles, wifi6_role_new(vm, ifd));
	}

	result = ucv_object_new(vm);

	obj = object_with(vm, "max_bss_supported", ucv_int64_new(8));
	ucv_object_add(obj, "opclasses_supported", opclasses_new(vm, band));
	ucv_object_add(result, "basic_capabilities", obj);

	obj = ucv_object_new(vm);
	for (size_t i = 0; i < ARRAY_SIZE(advanced); i++)
		flag_add(obj, advanced[i], false);
	ucv_object_add(result, "advanced_capabilities", obj);

	obj = object_with(vm, "fronthaul_akm_suite_selectors", ucv_array_new(vm));
	ucv_object_add(obj, "backhaul_akm_suite_selectors", ucv_array_new(vm));
	ucv_object_add(result, "akm_suite_capabilities", obj);

	ucv_object_add(result, "wifi6_capabilities", object_with(vm, "roles", roles));
	ucv_object_add(result, "_band", band);
	ucv_object_add(result, "_he_ifd", ucv_get(he_ifd));

	return result;
}

/* A number `v` (an integer stays an integer) as `(v + add) * mul`. */
static uc_value_t *
number_scaled_new(uc_value_t *v, int64_t add, int64_t mul)
{
	if (ucv_type(v) == UC_DOUBLE)
		return ucv_double_new((ucv_double_get(v) + add) * mul);

	return ucv_int64_new((ucv_to_integer(v) + add) * mul);
}

/* 802.11 RCPI encoding: 2 * (dBm + 110), clamped to 0-220, as the umap
 * link metrics give it. */
static uc_value_t *
rcpi_new(uc_value_t *signal)
{
	uc_value_t *rcpi = signal ? number_scaled_new(signal, 110, 2) : ucv_int64_new(0);
	double d = ucv_to_double(rcpi);

	if (d < 0 || d > 220) {
		ucv_put(rcpi);
		rcpi = ucv_int64_new((d < 0) ? 0 : 220);
	}

	return rcpi;
}

static uc_value_t *
bitrate_new(uc_value_t *rate)
{
	return rate ? number_scaled_new(rate, 0, 100) : ucv_int64_new(0);
}

/* nl80211 reports MACs lower-case and iwinfo upper-case; both match in the
 * separator-stripped upper form. */
static char *
mac_key_new(uc_value_t *mac)
{
	const char *s = ucv_string_get(mac);
	char *key = xalloc(ucv_string_length(mac) + 1), *p = key;

	for (size_t i = 0; i < ucv_string_length(mac); i++)
		if (s[i] != ':' && s[i] != '-')
			*p++ = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];

	return key;
}

static uc_value_t *
sta_entry_new(uc_vm_t *vm, const char *mac, uc_value_t *sta, uc_value_t *sta_info)
{
	uc_value_t *tx = ucv_object_get(sta, "tx", NULL), *rx = ucv_object_get(sta, "rx", NULL);
	uc_value_t *entry = ucv_object_new(vm), *he, *metrics;

	he = sta_he_caps_from_info(vm, sta_info);
	if (!he)
		he = sta_he_caps_from_rate_flags(vm, ucv_object_get(tx, "flags", NULL), ucv_object_get(rx, "flags", NULL));

	ucv_object_add(entry, "mac_address", ucv_string_new(mac));
	ucv_object_add(entry, "he_capabilities", he);
	ucv_object_add(entry, "link_metrics", object_with(vm, "uplink_rcpi", rcpi_new(ucv_object_get(sta, "signal", NULL))));
	ucv_object_add(entry, "traffic_stats", ucv_object_new(vm));

	metrics = object_with(vm, "last_data_downlink_rate", bitrate_new(ucv_object_get(tx, "bitrate_raw", NULL)));
	ucv_object_add(metrics, "last_data_uplink_rate", bitrate_new(ucv_object_get(rx, "bitrate_raw", NULL)));
	ucv_object_add(entry, "extended_metrics", metrics);
	zero_add(entry, "last_association");

	return entry;
}

/**
 * ucode: `local_sta_data_build(assoclist, nl_stations)`, the associated
 * clients of a BSS in the umap topology shape, with the HE capabilities of
 * each client from nl80211, or else from its rate flags.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: iwinfo assoclist, nl80211
 *               station dump or null)
 * @return       array of client objects
 */
uc_value_t *
uc_ubbf_local_sta_data_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *stations = uc_fn_arg(1), *by_mac = ucv_object_new(vm), *result = ucv_array_new(vm);
	uc_value_t *sta, *mac, *key_val;
	char *key;

	for (size_t i = 0; i < ucv_array_length(stations); i++) {
		sta = ucv_array_get(stations, i);
		mac = ucv_object_get(sta, "mac", NULL);
		if (!ucv_is_truish(mac) || ucv_type(mac) != UC_STRING)
			continue;

		key = mac_key_new(mac);
		ucv_object_add(by_mac, key, ucv_get(ucv_object_get(sta, "sta_info", NULL)));
		free(key);
	}

	ucv_object_foreach(uc_fn_arg(0), assoc_mac, assoc) {
		key_val = ucv_string_new(assoc_mac);
		key = mac_key_new(key_val);
		ucv_array_push(result, sta_entry_new(vm, assoc_mac, assoc, ucv_object_get(by_mac, key, NULL)));
		free(key);
		ucv_put(key_val);
	}

	ucv_put(by_mac);

	return result;
}

/**
 * ucode: `radio_band_priority(radio_bss, capability)`, the sort priority
 * of a radio by band: 2.4 GHz 0, 5 GHz 1, 6 GHz 2, unknown 3.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: ap_operational_bss entry,
 *               capability data with radios by RUID)
 * @return       priority
 */
uc_value_t *
uc_ubbf_radio_band_priority(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ruid = ucv_object_get(uc_fn_arg(0), "radio_unique_identifier", NULL);
	uc_value_t *radios = ucv_object_get(uc_fn_arg(1), "radios", NULL), *raw, *ocs, *oc, *cl;
	uc_value_t *empty = ucv_string_new("");
	int64_t prio = 3;
	double c;

	raw = ucv_key_get(vm, radios, ruid ? ruid : empty);
	ocs = ucv_object_get(raw, "operating_classes", NULL);
	if (!ocs)
		ocs = ucv_object_get(ucv_object_get(raw, "basic_capabilities", NULL), "opclasses_supported", NULL);

	for (size_t i = 0; prio == 3 && i < ucv_array_length(ocs); i++) {
		oc = ucv_array_get(ocs, i);
		cl = ucv_object_get(oc, "class", NULL);
		if (!cl)
			cl = ucv_object_get(oc, "opclass", NULL);

		c = cl ? ucv_to_double(cl) : 0;
		if (c >= 81 && c <= 84)
			prio = 0;
		else if (c >= 115 && c <= 130)
			prio = 1;
		else if (c >= 131 && c <= 137)
			prio = 2;
	}

	ucv_put(raw);
	ucv_put(empty);

	return ucv_int64_new(prio);
}

/* Whether a topology device advertises the EasyMesh agent service
 * (supported_service 1). */
static bool
device_is_agent(uc_value_t *dev)
{
	uc_value_t *svcs = ucv_object_get(ucv_object_get(dev, "map", NULL), "supported_services", NULL);
	uc_value_t *one = ucv_int64_new(1);
	bool agent = false;

	for (size_t i = 0; !agent && i < ucv_array_length(svcs); i++)
		agent = loose_equal(ucv_object_get(ucv_array_get(svcs, i), "supported_service", NULL), one);

	ucv_put(one);

	return agent;
}

static void
agents_add(uc_vm_t *vm, uc_value_t *devices, uc_value_t *seen, uc_value_t *topology)
{
	uc_value_t *list = ucv_object_get(topology, "devices", NULL), *dev, *al;
	char *key;

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		dev = ucv_array_get(list, i);
		al = ucv_object_get(dev, "al_address", NULL);
		if (!ucv_is_truish(al))
			continue;

		key = ucv_to_string(vm, al);
		if (!ucv_object_get(seen, key, NULL) && device_is_agent(dev)) {
			ucv_object_add(seen, key, ucv_boolean_new(true));
			ucv_array_push(devices, ucv_get(dev));
		}
		free(key);
	}
}

/**
 * ucode: `topology_devices_build(ctrl, agent)`, the EasyMesh agent devices
 * of the umap controller and then the umap-agent topology, once per AL MAC.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: get_topology replies of
 *               umap and umap-agent)
 * @return       array of device objects
 */
uc_value_t *
uc_ubbf_topology_devices_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *devices = ucv_array_new(vm), *seen = ucv_object_new(vm);

	agents_add(vm, devices, seen, uc_fn_arg(0));
	agents_add(vm, devices, seen, uc_fn_arg(1));
	ucv_put(seen);

	return devices;
}

static uc_value_t *
member_or_new(uc_vm_t *vm, uc_value_t *obj, const char *name)
{
	uc_value_t *val = ucv_object_get(obj, name, NULL);

	return val ? ucv_get(val) : ucv_object_new(vm);
}

/* Merges the local agent (umap-agent get_agent) into the controller view
 * of the same device: its radios, security associations and agent state. */
static void
local_agent_merge(uc_vm_t *vm, uc_value_t *capability, uc_value_t *local)
{
	uc_value_t *radios = ucv_object_get(local, "radios", NULL), *ctrl_radios, *ctrl_radio, *val;

	if (ucv_is_truish(radios)) {
		ctrl_radios = ucv_object_get(capability, "radios", NULL);
		if (!ctrl_radios) {
			ctrl_radios = ucv_object_new(vm);
			ucv_object_add(capability, "radios", ctrl_radios);
		}

		ucv_object_foreach(radios, ruid, local_radio) {
			ctrl_radio = ucv_object_get(ctrl_radios, ruid, NULL);
			if (!ucv_is_truish(ctrl_radio)) {
				ucv_object_add(ctrl_radios, ruid, ucv_get(local_radio));
				continue;
			}

			ucv_object_foreach(local_radio, key, v)
				ucv_object_add(ctrl_radio, key, ucv_get(v));
		}
	}

	val = ucv_object_get(local, "security_associations", NULL);
	if (ucv_is_truish(val))
		ucv_object_add(capability, "security_associations", ucv_get(val));

	val = ucv_object_get(local, "agent_state", NULL);
	if (ucv_is_truish(val))
		ucv_object_add(capability, "agent_state", ucv_get(val));
}

static bool
agent_is_local(uc_value_t *al_mac, uc_value_t *local)
{
	uc_value_t *local_mac = ucv_object_get(local, "al_mac", NULL);

	return ucv_is_truish(local_mac) && loose_equal(al_mac, local_mac);
}

/**
 * ucode: `device_api_data_build(al_mac, controller_enabled, replies)`, the
 * DataElements API data of a device from the umap replies: with the
 * controller its get_agent view with the local agent merged in when the
 * device is this one, without it the local agent of this device only.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: AL MAC, controller flag,
 *               `{ agent, local, policy, scan }` replies)
 * @return       API data object
 */
uc_value_t *
uc_ubbf_device_api_data_build(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *al_mac = uc_fn_arg(0), *replies = uc_fn_arg(2), *capability, *policy, *local, *res, *obj, *val;
	bool controller = ucv_is_truish(uc_fn_arg(1));

	local = member_or_new(vm, replies, "local");

	if (controller) {
		capability = member_or_new(vm, replies, "agent");
		if (agent_is_local(al_mac, local))
			local_agent_merge(vm, capability, local);
		policy = member_or_new(vm, replies, "policy");
	} else {
		capability = agent_is_local(al_mac, local) ? ucv_get(local) : ucv_object_new(vm);
		policy = ucv_object_new(vm);
	}

	res = ucv_object_new(vm);
	ucv_object_add(res, "_ubus_object", ucv_string_new(controller ? "umap" : "umap-agent"));
	ucv_object_add(res, "policy", policy);
	ucv_object_add(res, "backhaul", member_or_new(vm, capability, "backhaul_info"));
	ucv_object_add(res, "capability", ucv_get(capability));
	ucv_object_add(res, "survey", member_or_new(vm, capability, "radio_survey"));
	ucv_object_add(res, "traffic_sep", member_or_new(vm, ucv_object_get(policy, "policy", NULL), "traffic_separation"));
	ucv_object_add(res, "scan_results", member_or_new(vm, replies, "scan"));
	ucv_object_add(res, "service_prio", member_or_new(vm, capability, "service_prioritization"));

	val = ucv_object_get(capability, "security_associations", NULL);
	ucv_object_add(res, "security_1905", object_with(vm, "associations", val ? ucv_get(val) : ucv_array_new(vm)));

	val = ucv_object_get(capability, "anticipated_channel_usage", NULL);
	ucv_object_add(res, "anticipated_channel_usage", val ? ucv_get(val) : ucv_array_new(vm));
	ucv_object_add(res, "ap_mld", member_or_new(vm, capability, "ap_mld"));

	obj = object_with(vm, "bsta_mld", ucv_get(ucv_object_get(capability, "bsta_mld_configuration", NULL)));
	ucv_object_add(res, "bsta_mld", obj);

	ucv_put(capability);
	ucv_put(local);

	return res;
}
