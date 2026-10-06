'use strict';

import * as ubbf from 'ubbf';
import * as ubus from 'ubus';
import { deviceinfo_get } from 'ubbf.utils.deviceinfo';
import * as iwinfo from 'iwinfo';
import * as nl80211 from 'nl80211';
import { find_phy } from 'wifi.utils';
import { call as cache_call } from 'ubbf.utils.cache';
import {
	phy_max_standard,
	phy_max_bandwidth,
	phy_max_txpower,
	iwinfo_update,
	band_to_index,
	radio_address_derive
} from 'ubbf.utils.wifi';

/**
 * Encodes HT (802.11n) capabilities to base64.
 *
 * @param {object} ht_data - HT capability data from EasyMesh API
 * @param {object} band - Band capability data from iwinfo
 * @returns {string} Base64-encoded HT capabilities or empty string
 */
export function ht_caps_encode(ht_data, band) {
	if (band?.ht_capa != null) {
		let ht_capa = band.ht_capa;
		let ht40 = (ht_capa & 0x02) ? 1 : 0;
		let sgi20 = (ht_capa & 0x20) ? 1 : 0;
		let sgi40 = (ht_capa & 0x40) ? 1 : 0;

		let tx_ss = 1, rx_ss = 1;
		let mcs = band.ht_mcs_set;
		if (mcs) {
			// HT MCS 0-31 map to 1-4 streams; 32+ are duplicate or
			// unequal-modulation rates without stream information
			for (let idx in mcs.rx_mcs_indexes ?? []) {
				if (idx > 31)
					continue;
				let ss = int(idx / 8) + 1;
				if (ss > rx_ss)
					rx_ss = ss;
			}
			tx_ss = (mcs.tx_mcs_set_defined && !mcs.tx_rx_mcs_set_equal)
				? (mcs.tx_max_spatial_streams ?? rx_ss) : rx_ss;
		}

		let caps_byte = ((tx_ss - 1) << 6) | ((rx_ss - 1) << 4) |
		                (sgi20 << 3) | (sgi40 << 2) | (ht40 << 1);
		return b64enc(chr(caps_byte));
	}

	if (ht_data) {
		let tx_ss = (ht_data.max_supported_tx_spatial_streams ?? 1) - 1;
		let rx_ss = (ht_data.max_supported_rx_spatial_streams ?? 1) - 1;
		let sgi20 = ht_data.short_gi_support_20mhz ? 1 : 0;
		let sgi40 = ht_data.short_gi_support_40mhz ? 1 : 0;
		let ht40 = ht_data.ht_support_40mhz ? 1 : 0;

		let caps_byte = (tx_ss << 6) | (rx_ss << 4) |
		                (sgi20 << 3) | (sgi40 << 2) | (ht40 << 1);
		return b64enc(chr(caps_byte));
	}
	return "";
};

/**
 * Rebuilds the 16-bit VHT MCS map from the nl80211 module's structured
 * rx_mcs_set / tx_mcs_set representation. Streams without an entry are
 * not supported (code 3, the 0xffff seed).
 *
 * @param {array} mcs_set - Array of { streams, mcs_indexes } entries
 * @returns {number} 16-bit VHT MCS map
 */
function vht_mcs_map_build(mcs_set) {
	let map = 0xffff;
	for (let entry in mcs_set ?? []) {
		let ss = entry.streams ?? 0;
		if (ss < 1 || ss > 8)
			continue;
		let max_idx = length(entry.mcs_indexes ?? []) - 1;
		let code = (max_idx >= 9) ? 2 : (max_idx == 8) ? 1 : 0;
		map = (map & ~(3 << ((ss - 1) * 2))) | (code << ((ss - 1) * 2));
	}
	return map;
}

/**
 * Encodes VHT (802.11ac) capabilities to base64.
 *
 * @param {object} vht_data - VHT capability data from EasyMesh API
 * @param {object} band - Band capability data from iwinfo
 * @returns {string} Base64-encoded VHT capabilities or empty string
 */
export function vht_caps_encode(vht_data, band) {
	if (band?.vht_mcs_set && band?.vht_capa != null) {
		let vht_mcs = band.vht_mcs_set;
		let vht_capa = band.vht_capa;

		let rx_mcs_map = vht_mcs_map_build(vht_mcs.rx_mcs_set);
		let tx_mcs_map = vht_mcs_map_build(vht_mcs.tx_mcs_set);
		let rx_mcs_lo = rx_mcs_map & 0xff;
		let rx_mcs_hi = (rx_mcs_map >> 8) & 0xff;
		let tx_mcs_lo = tx_mcs_map & 0xff;
		let tx_mcs_hi = (tx_mcs_map >> 8) & 0xff;

		let sgi80 = (vht_capa & (1 << 5)) ? 1 : 0;
		let sgi160 = (vht_capa & (1 << 6)) ? 1 : 0;
		let chan_width = (vht_capa >> 2) & 0x03;
		let vht160 = (chan_width >= 1) ? 1 : 0;
		let vht8080 = (chan_width >= 2) ? 1 : 0;
		let su_bf = (vht_capa & (1 << 11)) ? 1 : 0;
		let mu_bf = (vht_capa & (1 << 19)) ? 1 : 0;

		let tx_ss = 1, rx_ss = 1;
		for (let i = 7; i >= 0; i--) {
			if (((rx_mcs_map >> (i * 2)) & 0x03) != 0x03) {
				rx_ss = i + 1;
				break;
			}
		}
		for (let i = 7; i >= 0; i--) {
			if (((tx_mcs_map >> (i * 2)) & 0x03) != 0x03) {
				tx_ss = i + 1;
				break;
			}
		}

		let caps1 = ((tx_ss - 1) << 5) | ((rx_ss - 1) << 2) | (sgi80 << 1) | sgi160;
		let caps2 = (vht8080 << 7) | (vht160 << 6) | (su_bf << 5) | (mu_bf << 4);

		return b64enc(chr(tx_mcs_hi, tx_mcs_lo, rx_mcs_hi, rx_mcs_lo, caps1, caps2));
	}

	if (vht_data) {
		let tx_mcs = vht_data.supported_vht_tx_mcs ?? 0;
		let rx_mcs = vht_data.supported_vht_rx_mcs ?? 0;
		let tx_ss = (vht_data.max_supported_tx_spatial_streams ?? 1) - 1;
		let rx_ss = (vht_data.max_supported_rx_spatial_streams ?? 1) - 1;
		let sgi80 = vht_data.short_gi_support_80mhz ? 1 : 0;
		let sgi160 = vht_data.short_gi_support_160mhz_8080mhz ? 1 : 0;
		let vht160 = vht_data.vht_support_160mhz ? 1 : 0;
		let vht8080 = vht_data.vht_support_8080mhz ? 1 : 0;
		let su_bf = vht_data.su_beamformer_capable ? 1 : 0;
		let mu_bf = vht_data.mu_beamformer_capable ? 1 : 0;

		let caps1 = (tx_ss << 5) | (rx_ss << 2) | (sgi80 << 1) | sgi160;
		let caps2 = (vht8080 << 7) | (vht160 << 6) | (su_bf << 5) | (mu_bf << 4);

		return b64enc(chr((tx_mcs >> 8) & 0xff, tx_mcs & 0xff,
		                  (rx_mcs >> 8) & 0xff, rx_mcs & 0xff, caps1, caps2));
	}
	return "";
};

/**
 * Encodes HE (802.11ax) capabilities to base64.
 *
 * @param {object} he_data - HE capability data from EasyMesh API
 * @param {object} he_ifd - HE interface data from iwinfo
 * @returns {string} Base64-encoded HE capabilities or empty string
 */
export function he_caps_encode(he_data, he_ifd) {
	if (he_ifd?.he_mcs_nss_supp) {
		let he_mcs = he_ifd.he_mcs_nss_supp;
		let mcs_len = length(he_mcs);
		if (mcs_len == 0)
			return "";

		let he_phy = he_ifd.he_cap_phy ?? [];
		let he_160 = (he_phy[0] & 0x08) ? 1 : 0;
		let he_8080 = (he_phy[0] & 0x10) ? 1 : 0;
		let su_bf = (he_phy[3] & 0x80) ? 1 : 0;
		let mu_bf = (he_phy[4] & 0x02) ? 1 : 0;
		let ul_mu_mimo = (he_phy[2] & 0x40) ? 1 : 0;
		let ul_ofdma = (he_phy[2] & 0x20) ? 1 : 0;
		let dl_ofdma = (he_phy[3] & 0x08) ? 1 : 0;

		let tx_ss = 1, rx_ss = 1;
		if (mcs_len >= 4) {
			let rx_mcs_map = he_mcs[0] | (he_mcs[1] << 8);
			let tx_mcs_map = he_mcs[2] | (he_mcs[3] << 8);
			for (let i = 7; i >= 0; i--) {
				if (((rx_mcs_map >> (i * 2)) & 0x03) != 0x03) {
					rx_ss = i + 1;
					break;
				}
			}
			for (let i = 7; i >= 0; i--) {
				if (((tx_mcs_map >> (i * 2)) & 0x03) != 0x03) {
					tx_ss = i + 1;
					break;
				}
			}
		}

		let caps1 = ((tx_ss - 1) << 5) | ((rx_ss - 1) << 2) | (he_8080 << 1) | he_160;
		let caps2 = (su_bf << 7) | (mu_bf << 6) | (ul_mu_mimo << 5) |
		            (ul_ofdma << 2) | (dl_ofdma << 1);

		return b64enc(chr(mcs_len, ...he_mcs, caps1, caps2));
	}

	if (he_data?.supported_he_mcs) {
		let mcs_hex = he_data.supported_he_mcs;
		let mcs_bytes = hexdec(mcs_hex);
		let mcs_len = length(mcs_bytes);
		if (mcs_len == 0)
			return "";

		let tx_ss = (he_data.max_supported_tx_spatial_streams ?? 1) - 1;
		let rx_ss = (he_data.max_supported_rx_spatial_streams ?? 1) - 1;
		let he_160 = he_data.he_support_160mhz ? 1 : 0;
		let he_8080 = he_data.he_support_8080mhz ? 1 : 0;
		let su_bf = he_data.su_beamformer_capable ? 1 : 0;
		let mu_bf = he_data.mu_beamformer_capable ? 1 : 0;
		let ul_mu_mimo = he_data.ul_mu_mimo_capable ? 1 : 0;
		let ul_ofdma = he_data.ul_ofdma_capable ? 1 : 0;
		let dl_ofdma = he_data.dl_ofdma_capable ? 1 : 0;

		let caps1 = (tx_ss << 5) | (rx_ss << 2) | (he_8080 << 1) | he_160;
		let caps2 = (su_bf << 7) | (mu_bf << 6) | (ul_mu_mimo << 5) |
		            (ul_ofdma << 2) | (dl_ofdma << 1);

		return b64enc(chr(mcs_len) + mcs_bytes + chr(caps1, caps2));
	}
	return "";
};

/**
 * Builds HE capabilities object from parsed capability bytes.
 *
 * @param {array} mac_caps - MAC capability bytes
 * @param {array} phy_caps - PHY capability bytes
 * @param {string} mcs_nss - MCS/NSS data
 * @returns {object} HE capabilities object
 */
export function sta_he_caps_build(mac_caps, phy_caps, mcs_nss) {
	return {
		he_160: !!(phy_caps[0] & 0x08),
		he_8080: !!(phy_caps[0] & 0x10),
		mcs_nss: mcs_nss ?? "",
		su_beamformer: !!(phy_caps[3] & 0x80),
		su_beamformee: !!(phy_caps[4] & 0x01),
		mu_beamformer_status: !!(phy_caps[4] & 0x02),
		beamformee_sts_less_80: (phy_caps[4] >> 4) & 0x07,
		beamformee_sts_greater_80: (phy_caps[5] >> 0) & 0x07,
		ul_mu_mimo: !!(phy_caps[2] & 0x40),
		ul_ofdma: !!(phy_caps[2] & 0x20),
		dl_ofdma: false,
		max_dl_mu_mimo_tx: 0,
		max_ul_mu_mimo_rx: 0,
		max_dl_ofdma_tx: 0,
		max_ul_ofdma_rx: 0,
		rts: false,
		mu_rts: false,
		multi_bssid: false,
		mu_edca: !!(mac_caps[0] & 0x08),
		twt_requester: !!(mac_caps[0] & 0x02),
		twt_responder: !!(mac_caps[0] & 0x04),
		spatial_reuse: false,
		anticipated_channel_usage: false
	};
};

/**
 * Extracts HE capabilities from nl80211 station info.
 *
 * @param {object} sta_info - nl80211 station info object
 * @returns {object|null} HE capabilities object or null if unavailable
 */
export function sta_he_caps_from_nl80211(sta_info) {
	if (!sta_info)
		return null;

	let he_cap = sta_info.he_cap;
	if (!he_cap)
		return null;

	return sta_he_caps_build(he_cap.mac_cap ?? [], he_cap.phy_cap ?? [], he_cap.mcs_nss);
};

/**
 * Creates minimal HE capabilities object from TX/RX flags.
 *
 * @param {array} tx_flags - TX rate flags
 * @param {array} rx_flags - RX rate flags
 * @returns {object|null} HE capabilities object or null if no HE support
 */
export function sta_he_caps_from_flags(tx_flags, rx_flags) {
	let flags = tx_flags ?? rx_flags ?? [];
	let has_he = false;
	for (let flag in flags) {
		if (index(flag, 'HE-') == 0) {
			has_he = true;
			break;
		}
	}

	if (!has_he)
		return null;

	return {
		he_160: false,
		he_8080: false,
		mcs_nss: "",
		su_beamformer: false,
		su_beamformee: false,
		mu_beamformer_status: false,
		beamformee_sts_less_80: 0,
		beamformee_sts_greater_80: 0,
		ul_mu_mimo: false,
		ul_ofdma: false,
		dl_ofdma: false,
		max_dl_mu_mimo_tx: 0,
		max_ul_mu_mimo_rx: 0,
		max_dl_ofdma_tx: 0,
		max_ul_ofdma_rx: 0,
		rts: false,
		mu_rts: false,
		multi_bssid: false,
		mu_edca: false,
		twt_requester: false,
		twt_responder: false,
		spatial_reuse: false,
		anticipated_channel_usage: false
	};
};

/**
 * Parses HE capabilities from base64-encoded association frame body.
 *
 * @param {string} frame_body_b64 - Base64-encoded association request/response frame
 * @returns {object|null} HE capabilities object or null if not found
 */
export function sta_he_caps_from_frame_body(frame_body_b64) {
	if (!frame_body_b64)
		return null;

	let frame_body = b64dec(frame_body_b64);
	if (!frame_body || length(frame_body) < 4)
		return null;

	let pos = 4;
	let len = length(frame_body);

	while (pos + 2 <= len) {
		let elem_id = ord(frame_body, pos);
		let elem_len = ord(frame_body, pos + 1);

		if (pos + 2 + elem_len > len)
			break;

		if (elem_id != 255 || elem_len < 18) {
			pos += 2 + elem_len;
			continue;
		}

		let ext_id = ord(frame_body, pos + 2);
		if (ext_id != 35) {
			pos += 2 + elem_len;
			continue;
		}

		let mac_caps = [];
		let phy_caps = [];
		for (let i = 0; i < 6; i++)
			push(mac_caps, ord(frame_body, pos + 3 + i));
		for (let i = 0; i < 11; i++)
			push(phy_caps, ord(frame_body, pos + 9 + i));

		let mcs_nss_len = elem_len - 18;
		let mcs_nss = (mcs_nss_len > 0 && mcs_nss_len <= 12) ?
			substr(frame_body, pos + 20, mcs_nss_len) : "";

		return sta_he_caps_build(mac_caps, phy_caps, mcs_nss);
	}

	return null;
};

/**
 * Fetches wireless status from network.wireless ubus (uncached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
function wireless_status_fetch() {
	return ubus?.call('network.wireless', 'status');
}

/**
 * Gets wireless status from network.wireless ubus (cached).
 *
 * @returns {object|null} Wireless status keyed by radio name
 */
export function wireless_status_get() {
	return cache_call(wireless_status_fetch);
};

/**
 * Gets the first interface name for a radio.
 *
 * @param {string} radio_name - Radio name (e.g., radio0)
 * @returns {string|null} Interface name or null if not found
 */
export function radio_ifname_get(radio_name) {
	let status = wireless_status_get();
	let radio = status?.[radio_name];
	if (!radio?.interfaces || length(radio.interfaces) == 0)
		return null;
	return radio.interfaces[0].ifname;
};

/**
 * Gets the chipset vendor name from sysfs.
 *
 * @param {string} phy_name - PHY name (e.g., phy0)
 * @returns {string} Vendor name or empty string if unknown
 */
export function chipset_vendor_get(phy_name) {
	let vendor_id = ubbf.readfile_trim(`/sys/class/ieee80211/${phy_name}/device/vendor`, '');
	let vendors = {
		'0x14c3': 'MediaTek',
		'0x168c': 'Qualcomm Atheros',
		'0x8086': 'Intel',
		'0x14e4': 'Broadcom'
	};
	return vendors[vendor_id] ?? '';
};

/**
 * Fetches local radio survey data from iwinfo (uncached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Survey data with noise, utilization, transmit and receive stats
 */
function local_radio_survey_fetch(ifname) {
	if (!ifname)
		return {};

	let iface = iwinfo.ifaces?.[ifname];
	if (!iface)
		return {};

	let survey = iface.survey;
	// EasyMesh airtime fields are a fraction of the measurement window on a
	// 0-255 scale, not cumulative time; scale tx/rx against total like busy
	let total = survey?.time ?? 0;
	let scale = (v) => (total > 0) ? int((v * 255) / total) : 0;

	return {
		noise: survey?.noise ?? iface.noise ?? 0,
		utilization: scale(survey?.busy ?? 0),
		transmit: scale(survey?.time_tx ?? 0),
		receive_self: scale(survey?.time_rx ?? 0),
		receive_other: 0
	};
}

/**
 * Gets local radio survey data from iwinfo (cached).
 *
 * @param {string} ifname - Interface name
 * @returns {object} Survey data with noise, utilization, transmit and receive stats
 */
export function local_radio_survey_get(ifname) {
	return cache_call(local_radio_survey_fetch, ifname);
};

/**
 * Fetches local radio capability data from iwinfo (uncached).
 *
 * @param {string} phy_name - PHY name (e.g., phy0)
 * @param {number} band_idx - Band index (0=2.4GHz, 1=5GHz, 3=6GHz)
 * @returns {object} Radio capabilities including operating classes and HE capabilities
 */
function local_radio_capability_fetch(phy_name, band_idx) {
	let phy = null;
	for (let p in iwinfo.phys ?? []) {
		if (p?.wiphy_name == phy_name) {
			phy = p;
			break;
		}
	}

	let max_bss = 8;
	let max_std = phy_max_standard(phy, band_idx);
	let max_bw = phy_max_bandwidth(phy, band_idx);
	let max_txpower = phy_max_txpower(phy, band_idx) ?? 20;

	let opclasses = [];
	let band = phy?.wiphy_bands?.[band_idx];
	if (band) {
		let opclass_map = {};
		for (let freq in band.freqs ?? []) {
			if (freq.disabled)
				continue;
			let channel = ubbf.freq_to_channel(freq.freq);
			let txpower = int((freq.max_tx_power ?? 2000) / 100);

			// global 20MHz operating classes: 5GHz splits into
			// 115 (36-48), 118 (52-64), 121 (100-144), 125 (149+)
			let oc;
			if (freq.freq >= 5935)
				oc = 131;
			else if (freq.freq >= 5180) {
				if (channel >= 149)
					oc = 125;
				else if (channel >= 100)
					oc = 121;
				else if (channel >= 52)
					oc = 118;
				else
					oc = 115;
			} else
				oc = 81;

			opclass_map[oc] ??= { opclass: oc, max_txpower_eirp: 0, channels: [] };
			if (txpower > opclass_map[oc].max_txpower_eirp)
				opclass_map[oc].max_txpower_eirp = txpower;
			push(opclass_map[oc].channels, channel);
		}
		for (let oc in opclass_map)
			push(opclasses, opclass_map[oc]);
	}

	let wifi6_roles = [];
	let he_caps = null;
	for (let ifd in band?.iftype_data ?? []) {
		if (!ifd.iftypes?.ap)
			continue;
		if (ifd.he_cap_phy) {
			he_caps = ifd;
			push(wifi6_roles, {
				agent_role: 0x00,
				he_160: !!(ifd.he_cap_phy?.[0] & 0x08),
				he_8080: !!(ifd.he_cap_phy?.[0] & 0x10),
				su_beamformer: !!(ifd.he_cap_phy?.[3] & 0x80),
				su_beamformee: !!(ifd.he_cap_phy?.[4] & 0x01),
				mu_beamformer_status: !!(ifd.he_cap_phy?.[4] & 0x02),
				ul_mu_mimo: !!(ifd.he_cap_phy?.[2] & 0x40),
				dl_ofdma: !!(ifd.he_cap_phy?.[3] & 0x08),
				ul_ofdma: !!(ifd.he_cap_phy?.[2] & 0x20),
				twt_requester: !!(ifd.he_cap_mac?.[0] & 0x02),
				twt_responder: !!(ifd.he_cap_mac?.[0] & 0x04),
				max_dl_mu_mimo_tx: 0,
				max_ul_mu_mimo_rx: 0,
				max_dl_ofdma_tx: 0,
				max_ul_ofdma_rx: 0
			});
		}
	}

	return {
		basic_capabilities: {
			max_bss_supported: max_bss,
			opclasses_supported: opclasses
		},
		advanced_capabilities: {
			mscs: false,
			scs: false,
			qos_map: false,
			dscp_policy: false,
			scs_traffic_description: false
		},
		akm_suite_capabilities: {
			fronthaul_akm_suite_selectors: [],
			backhaul_akm_suite_selectors: []
		},
		wifi6_capabilities: {
			roles: wifi6_roles
		},
		_band: band,
		_he_ifd: he_caps
	};
}

/**
 * Gets local radio capability data from iwinfo (cached).
 *
 * @param {string} phy_name - PHY name (e.g., phy0)
 * @param {number} band_idx - Band index (0=2.4GHz, 1=5GHz, 3=6GHz)
 * @returns {object} Radio capabilities including operating classes and HE capabilities
 */
export function local_radio_capability_get(phy_name, band_idx) {
	return cache_call(local_radio_capability_fetch, phy_name, band_idx);
};

/**
 * Gets associated client data for a BSS in the umap topology shape.
 * HE capabilities are embedded per client so client_capabilities_get()
 * in device_to_object() picks them up like EasyMesh topology entries.
 *
 * @param {string} ifname - Interface name
 * @returns {array} Array of associated client objects
 */
export function local_sta_data_get(ifname) {
	let associated_clients = [];

	let assoclist = iwinfo.assoclist(ifname);
	if (!assoclist)
		return associated_clients;

	let nl_stations = null;
	try {
		nl_stations = nl80211.request(
			nl80211.const.NL80211_CMD_GET_STATION,
			nl80211.const.NLM_F_DUMP,
			{ dev: ifname }
		);
	} catch (e) {
		nl_stations = null;
	}

	// nl80211 reports MACs lower-case, iwinfo assoclist keys them
	// upper-case; key the map on the separator-stripped upper form so the
	// per-station lookup below actually matches
	let nl_sta_map = {};
	for (let sta in nl_stations ?? []) {
		if (sta.mac)
			nl_sta_map[ubbf.mac_normalise(sta.mac, ':-')] = sta.sta_info;
	}

	for (let mac, sta in assoclist) {
		let he_caps = sta_he_caps_from_nl80211(nl_sta_map[ubbf.mac_normalise(mac, ':-')]);
		if (!he_caps)
			he_caps = sta_he_caps_from_flags(sta.tx?.flags, sta.rx?.flags);

		// 802.11 RCPI encoding: 2 * (dBm + 110), clamped to 0-220,
		// matching the umap link metrics the consumer expects
		let rcpi = 2 * ((sta.signal ?? -110) + 110);
		if (rcpi < 0)
			rcpi = 0;
		else if (rcpi > 220)
			rcpi = 220;

		push(associated_clients, {
			mac_address: mac,
			he_capabilities: he_caps,
			link_metrics: {
				uplink_rcpi: rcpi
			},
			traffic_stats: {},
			extended_metrics: {
				last_data_downlink_rate: (sta.tx?.bitrate_raw ?? 0) * 100,
				last_data_uplink_rate: (sta.rx?.bitrate_raw ?? 0) * 100
			},
			last_association: 0
		});
	}

	return associated_clients;
};

/**
 * Fetches list of local radios with their BSS information (uncached).
 * Each AP BSS node carries its associated_clients inline, mirroring the
 * shape of umap topology devices.
 *
 * @returns {array} Array of radio objects with radio_unique_identifier and bss list
 */
function local_radios_fetch() {
	let status = wireless_status_get();
	if (!status)
		return [];

	iwinfo_update();

	let result = [];
	for (let radio_name, radio_status in status) {
		if (type(radio_status) != 'object')
			continue;

		let config = radio_status.config ?? {};
		let phy_name = find_phy(config, false);
		let phy = filter(iwinfo.phys ?? [], (p) => p?.wiphy_name == phy_name)[0];
		let ruid = radio_address_derive(phy?.mac, config.band);
		if (!ruid)
			continue;

		let bss_list = [];
		for (let iface in radio_status.interfaces ?? []) {
			if (iface.config?.mode != 'ap')
				continue;
			// the runtime BSSID is the netdev MAC; the UCI config rarely
			// pins macaddr, so fall back to sysfs rather than the ifname
			let bss_mac = iface.config?.macaddr;
			if (!bss_mac && iface.ifname)
				bss_mac = ubbf.readfile_trim(`/sys/class/net/${iface.ifname}/address`);
			push(bss_list, {
				mac_address: bss_mac ?? "",
				ssid: iface.config?.ssid ?? "",
				associated_clients: local_sta_data_get(iface.ifname),
				_ifname: iface.ifname
			});
		}

		push(result, {
			radio_unique_identifier: ruid,
			bss: bss_list,
			_radio_name: radio_name,
			_phy_name: phy_name,
			_band_idx: band_to_index(config.band)
		});
	}
	return result;
}

/**
 * Gets list of local radios with their BSS information (cached).
 *
 * @returns {array} Array of radio objects with radio_unique_identifier and bss list
 */
export function local_radios_get() {
	return cache_call(local_radios_fetch);
};

/**
 * Fetches local device information for non-EasyMesh mode (uncached).
 *
 * @returns {object} Device object with identification and AP operational BSS
 */
function local_device_fetch() {
	let deviceinfo = deviceinfo_get();
	let radios = local_radios_get();

	return {
		al_address: deviceinfo.ManufacturerOUI ?? "",
		identification: {
			manufacturer_name: deviceinfo.Manufacturer ?? "",
			serial_number: deviceinfo.SerialNumber ?? "",
			manufacturer_model: deviceinfo.ModelName ?? "",
			software_version: deviceinfo.SoftwareVersion ?? ""
		},
		map: {
			ap_operational_bss: radios
		}
	};
}

/**
 * Gets local device information for non-EasyMesh mode (cached).
 *
 * @returns {object} Device object with identification and AP operational BSS
 */
export function local_device_get() {
	return cache_call(local_device_fetch);
};

/**
 * Fetches local API data (capabilities, survey) for non-EasyMesh mode (uncached).
 *
 * @returns {object} API data structure with capability and survey information
 */
function local_api_data_fetch() {
	let radios = local_radios_get();
	if (length(radios) == 0)
		return {};

	let survey_radios = {};
	let capability_radios = {};
	let inventory_radios = {};

	for (let radio in radios) {
		let ruid = radio.radio_unique_identifier;
		if (!ruid)
			continue;

		survey_radios[ruid] = local_radio_survey_get(radio_ifname_get(radio._radio_name));
		capability_radios[ruid] = local_radio_capability_get(radio._phy_name, radio._band_idx);
		inventory_radios[ruid] = { chipset_vendor: chipset_vendor_get(radio._phy_name) };
	}

	return {
		policy: {},
		backhaul: {},
		capability: {
			radios: capability_radios,
			device_inventory: { radios: inventory_radios }
		},
		survey: { radios: survey_radios },
		traffic_sep: {},
		channel_pref: {},
		scan_results: {},
		cac_status: {},
		service_prio: {},
		security_1905: {},
		ap_mld: {},
		bsta_mld: {}
	};
}

/**
 * Gets local API data (capabilities, survey) for non-EasyMesh mode (cached).
 *
 * @returns {object} API data structure with capability and survey information
 */
export function local_api_data_get() {
	return cache_call(local_api_data_fetch);
};

/**
 * Fetches the raw topology blob from a umap ubus object (uncached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @returns {object|null} Raw get_topology result
 */
function raw_topology_fetch(obj) {
	return ubus.call(obj, 'get_topology', {});
}

/**
 * Gets the raw topology blob from a umap ubus object (cached).
 *
 * Both topology consumers (ubus_topology_get and topology_devices_get) share
 * this single cached fetch, so one Get resolves the whole DataElements subtree
 * from one topology snapshot per umap object instead of one get_topology call
 * (and one ~14 KB blob parse) per resolved parameter.
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @returns {object|null} Raw get_topology result
 */
function raw_topology_get(obj) {
	return cache_call(raw_topology_fetch, obj);
}

/**
 * Fetches per-client capability data from a umap ubus object (uncached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @param {string} sta_mac - Client MAC address
 * @returns {object|null} get_client result keyed by BSSID
 */
function client_query_fetch(obj, sta_mac) {
	return ubus.call(obj, 'get_client', { address: sta_mac });
}

/**
 * Gets per-client capability data from a umap ubus object (cached).
 *
 * @param {string} obj - ubus object name ('umap' or 'umap-agent')
 * @param {string} sta_mac - Client MAC address
 * @returns {object|null} get_client result keyed by BSSID
 */
export function client_query_get(obj, sta_mac) {
	return cache_call(client_query_fetch, obj, sta_mac);
};

/**
 * Fetches topology information from umap controller and agent (uncached).
 *
 * @returns {object} Object with controller_id and colocated_agent_id
 */
function ubus_topology_fetch() {
	let controller_id = "";
	let colocated_agent_id = "";

	let ctrl_result = raw_topology_get('umap');
	if (ctrl_result?.devices?.[0]?.al_address)
		controller_id = ctrl_result.devices[0].al_address;

	let agent_result = raw_topology_get('umap-agent');
	if (agent_result?.devices?.[0]?.al_address)
		colocated_agent_id = agent_result.devices[0].al_address;

	return { controller_id, colocated_agent_id };
}

/**
 * Gets topology information from umap controller and agent (cached).
 *
 * @returns {object} Object with controller_id and colocated_agent_id
 */
export function ubus_topology_get() {
	return cache_call(ubus_topology_fetch);
};

/**
 * Fetches device API data from umap for a specific device (uncached).
 *
 * @param {string} al_mac - AL MAC address of the device
 * @param {boolean} controller_enabled - Whether the EasyMesh controller is enabled
 * @returns {object} API data structure with policy, backhaul, capability, etc.
 */
function device_api_data_fetch(al_mac, controller_enabled) {
	let obj = controller_enabled ? 'umap' : 'umap-agent';
	let capability;

	if (controller_enabled) {
		capability = ubus.call('umap', 'get_agent', { address: al_mac }) ?? {};

		let local_cap = ubus.call('umap-agent', 'get_agent', {}) ?? {};
		if (local_cap.al_mac && al_mac == local_cap.al_mac) {
			if (local_cap.radios) {
				capability.radios ??= {};
				for (let ruid, local_radio in local_cap.radios) {
					let ctrl_radio = capability.radios[ruid];
					if (ctrl_radio)
						for (let key, val in local_radio)
							ctrl_radio[key] = val;
					else
						capability.radios[ruid] = local_radio;
				}
			}
			if (local_cap.security_associations)
				capability.security_associations = local_cap.security_associations;
			if (local_cap.agent_state)
				capability.agent_state = local_cap.agent_state;
		}
	}
	else {
		let local_cap = ubus.call('umap-agent', 'get_agent', {}) ?? {};
		capability = (local_cap.al_mac && al_mac == local_cap.al_mac) ? local_cap : {};
	}

	let policy = controller_enabled ? (ubus.call('umap', 'get_policy_config', { al_mac }) ?? {}) : {};

	return {
		_ubus_object: obj,
		policy,
		backhaul: capability.backhaul_info ?? {},
		capability,
		survey: capability.radio_survey ?? {},
		traffic_sep: policy.policy?.traffic_separation ?? {},
		scan_results: ubus.call(obj, 'get_scan_results', { al_mac }) ?? {},
		service_prio: capability.service_prioritization ?? {},
		security_1905: { associations: capability.security_associations ?? [] },
		anticipated_channel_usage: capability.anticipated_channel_usage ?? {},
		ap_mld: capability.ap_mld ?? {},
		bsta_mld: { bsta_mld: capability.bsta_mld_configuration }
	};
}

/**
 * Gets device API data from umap for a specific device (cached).
 *
 * @param {string} al_mac - AL MAC address of the device
 * @param {boolean} controller_enabled - Whether the EasyMesh controller is enabled
 * @returns {object} API data structure with policy, backhaul, capability, etc.
 */
export function device_api_data_get(al_mac, controller_enabled) {
	return cache_call(device_api_data_fetch, al_mac, controller_enabled);
};

/**
 * Returns sort priority for a radio based on its band.
 * Order: 2.4 GHz (0), 5 GHz (1), 6 GHz (2), unknown (3).
 *
 * @param {object} radio_bss - Radio entry from ap_operational_bss
 * @param {object} capability - Capability data keyed by RUID
 * @returns {number} Band priority (lower = first)
 */
export function radio_band_priority(radio_bss, capability) {
	let ruid = radio_bss.radio_unique_identifier ?? "";
	let raw = capability?.radios?.[ruid] ?? {};
	let opclasses = raw.operating_classes
		?? raw.basic_capabilities?.opclasses_supported
		?? [];

	for (let oc in opclasses) {
		let cl = oc.class ?? oc.opclass ?? 0;
		if (cl >= 81 && cl <= 84)
			return 0;
		if (cl >= 115 && cl <= 130)
			return 1;
		if (cl >= 131 && cl <= 137)
			return 2;
	}
	return 3;
};

/**
 * Fetches network-wide steering statistics from umap controller (uncached).
 *
 * @returns {object} Steering stats with network, bss, and sta sub-objects
 */
function steering_stats_fetch() {
	return ubus.call('umap', 'get_steering_stats', {}) ?? {};
}

/**
 * Gets network-wide steering statistics from umap controller (cached).
 *
 * @returns {object} Steering stats with network, bss, and sta sub-objects
 */
export function steering_stats_get() {
	return cache_call(steering_stats_fetch);
};

/**
 * Fetches steering history for all STAs from umap controller (uncached).
 *
 * @returns {object} Steering history keyed by STA MAC
 */
function steering_history_fetch() {
	return ubus.call('umap', 'get_steering_history', {}) ?? {};
}

/**
 * Gets steering history for all STAs from umap controller (cached).
 *
 * @returns {object} Steering history keyed by STA MAC
 */
export function steering_history_get() {
	return cache_call(steering_history_fetch);
};

/**
 * Enumerates EasyMesh agent devices from topology, deduplicating by AL MAC.
 * Queries umap controller first, then umap-agent, keeping only agent devices.
 *
 * @returns {array} Array of device objects with agent role
 */
function topology_devices_fetch() {
	let devices = [];
	let seen = {};

	/**
	 * Tests whether a topology device advertises the EasyMesh agent service
	 * (supported_service == 1).
	 *
	 * @param {object} dev - Topology device entry
	 * @returns {boolean} true if the device is an EasyMesh agent
	 */
	function is_agent(dev) {
		for (let svc in dev.map?.supported_services)
			if (svc.supported_service == 1)
				return true;
		return false;
	}

	/**
	 * Adds a device to the result list if it is an agent and has not been
	 * seen yet. Deduplicates by AL MAC address.
	 *
	 * @param {object} dev - Topology device entry
	 */
	function device_add(dev) {
		if (!dev.al_address || seen[dev.al_address])
			return;
		if (!is_agent(dev))
			return;
		seen[dev.al_address] = true;
		push(devices, dev);
	}

	let ctrl_result = raw_topology_get('umap');
	for (let dev in ctrl_result?.devices)
		device_add(dev);

	let agent_result = raw_topology_get('umap-agent');
	for (let dev in agent_result?.devices)
		device_add(dev);

	return devices;
}

/**
 * Gets EasyMesh agent devices from topology (cached).
 *
 * @returns {array} Array of device objects with agent role
 */
export function topology_devices_get() {
	return cache_call(topology_devices_fetch);
};
