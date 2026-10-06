'use strict';

import * as ubbf from 'ubbf';
import {
	ht_caps_encode, vht_caps_encode, he_caps_encode,
	sta_he_caps_from_frame_body, ubus_topology_get,
	radio_band_priority, client_query_get
} from 'ubbf.utils.wifi-dataelements';


/**
 * Converts WiFi standard name to generation number.
 *
 * @param {string} std - Standard name (be, ax, ac, n, g, b, a)
 * @returns {number} WiFi generation number (1-7) or 0 if unknown
 */
function standard_to_wifi_generation(std) {
	let map = { 'be': 7, 'ax': 6, 'ac': 5, 'n': 4, 'g': 3, 'b': 2, 'a': 1 };
	return map[std] ?? 0;
}

const MEDIA_TYPE_CODE_MAP = {
	[0x0000]: "IEEE 802.3u",
	[0x0001]: "IEEE 802.3ab",
	[0x0100]: "IEEE 802.11b",
	[0x0101]: "IEEE 802.11g",
	[0x0102]: "IEEE 802.11a",
	[0x0103]: "IEEE 802.11n 2.4",
	[0x0104]: "IEEE 802.11n 5.0",
	[0x0105]: "IEEE 802.11ac",
	[0x0106]: "IEEE 802.11ad",
	[0x0107]: "IEEE 802.11af",
	[0x0108]: "IEEE 802.11ax",
	[0x0109]: "IEEE 802.11be",
	[0x0200]: "IEEE 1901 Wavelet",
	[0x0201]: "IEEE 1901 FFT",
	[0x0300]: "MoCAv1.1",
	[0xFFFF]: "Generic PHY",
};

/**
 * Converts IEEE 1905.1 media type code to TR-181 media type name.
 *
 * @param {number} code - IEEE 1905.1 media type code (Table 6-12)
 * @returns {string} TR-181 media type name or empty string if unknown
 */
function media_type_code_to_name(code) {
	return MEDIA_TYPE_CODE_MAP[code] ?? "";
}

const MEDIA_TYPE_LINK_TYPE_MAP = {
	[0x00]: "Ethernet",
	[0x01]: "Wi-Fi",
	[0x02]: "HomePlug",
	[0x03]: "MoCA",
};

const SCAN_STATUS_NAME_TO_CODE = {
	"Success": "0",
	"Scan not supported on this operating class and channel on this radio": "1",
	"Request too soon after last scan": "2",
	"Radio too busy to perform scan": "3",
	"Scan not completed": "4",
	"Scan aborted": "5",
	"Fresh scan not supported. Radio only supports on boot scans.": "6",
};

/**
 * Maps an IEEE 1905.1 media type code to the deprecated TR-181
 * `MultiAPDevice.Backhaul.LinkType` enum (Wi-Fi / Ethernet / MoCA / HomePlug
 * / G.hn / HPNA / UPA / None). Classification is by the top byte of the
 * 1905.1 code per Table 6-12. Unknown or missing codes map to "".
 *
 * @param {number} code - IEEE 1905.1 media type code (Table 6-12)
 * @returns {string} TR-181 LinkType enum value or empty string if unknown
 */
function media_type_code_to_link_type(code) {
	if (code == null)
		return "";
	return MEDIA_TYPE_LINK_TYPE_MAP[(code >> 8) & 0xFF] ?? "";
}


const STEERING_TRIGGER_EVENT_MAP = {
	'signal_quality': 'Wi-Fi Link Quality',
	'ap_load': 'Wi-Fi Channel Utilization',
	'backhaul_link': 'Backhaul Link Utilization'
};


/**
 * Filters QoS management descriptors for a BSSID.
 *
 * @param {array} qm_descriptors - Array of QoS management descriptor entries
 * @param {string} bssid - BSSID to filter for
 * @returns {array} Filtered array of QM descriptors for the BSSID
 */
function bss_qm_descriptors_filter(qm_descriptors, bssid) {
	return filter(qm_descriptors ?? [], (entry) => entry.bssid == bssid);
}

/**
 * Encodes ESP (Estimated Service Parameters) bytes to base64.
 *
 * @param {array} esp_bytes - ESP byte array
 * @returns {string} Base64-encoded ESP or empty string
 */
function esp_encode(esp_bytes) {
	if (!esp_bytes || length(esp_bytes) == 0)
		return "";
	return b64enc(esp_bytes);
}

/**
 * Encodes the AP Capability TLV value octet (EasyMesh v6.0 §17.2.6, TLV 0xA1)
 * as base64. Returns an empty string when the underlying flags are absent
 * so a missing input is distinguishable from all-flags-cleared.
 *
 * @param {object} ap_capability - ap_capability flags from umapd
 * @returns {string} Base64-encoded TLV value octet or empty string
 */
function multiap_capabilities_encode(ap_capability) {
	if (!ap_capability)
		return "";

	let byte = 0;
	if (ap_capability.onchannel_unassoc_sta_metrics)
		byte |= 0x80;
	if (ap_capability.offchannel_unassoc_sta_metrics)
		byte |= 0x40;
	if (ap_capability.agent_initiated_rcpi_steering)
		byte |= 0x20;
	if (ap_capability.m8_bsta_reconfiguration)
		byte |= 0x10;

	return b64enc(chr(byte));
}

/**
 * Converts operating class data to TR-181 object format.
 *
 * @param {object} opclass - Operating class data
 * @returns {object} TR-181 formatted operating class object
 */
function opclass_to_object(opclass) {
	let non_operable = opclass.statically_non_operable_channels ?? [];
	return {
		Class: sprintf('%d', opclass.opclass ?? 0),
		MaxTxPower: sprintf('%d', opclass.max_txpower_eirp ?? 0),
		NonOperable: join(',', non_operable),
		NumberOfNonOperChan: sprintf('%d', length(non_operable))
	};
}

/**
 * Converts CAC capabilities to TR-181 CACCapability object format.
 *
 * @param {array} cac_caps - CAC capabilities from get_agent radios[ruid].cac_capabilities
 * @returns {object} TR-181 formatted CACCapability object
 */
function cac_capability_to_object(cac_caps) {
	if (!cac_caps || length(cac_caps) == 0)
		return { CACMethodNumberOfEntries: "0" };

	return {
		CACMethodNumberOfEntries: sprintf('%d', length(cac_caps)),
		CACMethod: ubbf.enumerate_instances(cac_caps, (method) => {
			let opclasses = method.opclasses ?? [];
			return {
				Method: sprintf('%d', method.cac_method_supported ?? 0),
				NumberOfSeconds: sprintf('%d', method.duration ?? 0),
				OpClassChannelsNumberOfEntries: sprintf('%d', length(opclasses)),
				OpClassChannels: ubbf.enumerate_instances(opclasses, (oc) => ({
					OpClass: sprintf('%d', oc.opclass ?? 0),
					ChannelList: join(',', oc.channels ?? [])
				}))
			};
		})
	};
}


/**
 * Converts spatial reuse data to TR-181 SpatialReuse object format.
 *
 * @param {object} sr - Spatial reuse data from get_agent radios[ruid].spatial_reuse
 * @returns {object|null} TR-181 formatted SpatialReuse object or null
 */
function spatial_reuse_to_object(sr) {
	if (!sr)
		return null;

	return {
		BSSColor: sprintf('%d', sr.bss_color ?? 0),
		PartialBSSColor: sr.partial_bss_color ? "1" : "0",
		HESIGASpatialReuseValue15Allowed: sr.hesiga_spatial_reuse_value15_allowed ? "true" : "false",
		SRGInformationValid: sr.srg_information_valid ? "true" : "false",
		NonSRGOffsetValid: sr.non_srg_offset_valid ? "true" : "false",
		PSRDisallowed: sr.psr_disallowed ? "true" : "false",
		NonSRGOBSSPDMaxOffset: sprintf('%d', sr.non_srg_obsspd_max_offset ?? 0),
		SRGOBSSPDMinOffset: sprintf('%d', sr.srg_obsspd_min_offset ?? 0),
		SRGOBSSPDMaxOffset: sprintf('%d', sr.srg_obsspd_max_offset ?? 0),
		SRGBSSColorBitmap: ubbf.int_to_hexbin(sr.srg_bss_color_bitmap, 8),
		SRGPartialBSSIDBitmap: ubbf.int_to_hexbin(sr.srg_partial_bssid_bitmap, 8),
		NeighborBSSColorInUseBitmap: ubbf.int_to_hexbin(sr.used_neighbor_bss_colors, 8)
	};
}

/**
 * Filters unassociated STA metrics for a specific radio by opclass.
 *
 * @param {object} unassoc_metrics - Device-level unassociated STA metrics keyed by opclass
 * @param {object} raw_data - Raw radio capability data with opclass info
 * @returns {array} Flattened array of unassociated STA entries for this radio
 */
function unassoc_sta_entries_get(unassoc_metrics, raw_data) {
	if (!unassoc_metrics)
		return [];

	let radio_opclasses = {};
	for (let oc in raw_data?.basic_capabilities?.opclasses_supported ?? [])
		radio_opclasses[oc.opclass] = true;
	for (let oc in raw_data?.operating_classes ?? [])
		radio_opclasses[oc.class] = true;

	let entries = [];
	for (let opclass_str, data in unassoc_metrics) {
		let opclass = int(opclass_str);
		if (!radio_opclasses[opclass])
			continue;
		for (let sta in data.sta_entries ?? [])
			push(entries, { ...sta, _opclass: opclass });
	}
	return entries;
}

/**
 * Converts scan capability data to TR-181 object format.
 *
 * @param {object} scan_cap - Scan capability data from radio
 * @returns {object|null} TR-181 formatted ScanCapability object or null
 */
function scan_capability_to_object(scan_cap) {
	if (!scan_cap) {
		return {
			OnBootOnly: "false",
			Impact: "0",
			MinimumInterval: "0",
			OpClassChannelsNumberOfEntries: "0"
		};
	}

	let opclasses = scan_cap.opclasses ?? [];
	return {
		OnBootOnly: scan_cap.on_boot_only ? "true" : "false",
		Impact: sprintf('%d', scan_cap.scan_impact ?? 0),
		MinimumInterval: sprintf('%d', scan_cap.minimum_scan_interval ?? 0),
		OpClassChannelsNumberOfEntries: sprintf('%d', length(opclasses)),
		OpClassChannels: ubbf.enumerate_instances(opclasses, (oc) => ({
			OpClass: sprintf('%d', oc.opclass ?? 0),
			ChannelList: join(',', oc.channels ?? [])
		}))
	};
}

/**
 * Converts AKM suite data to TR-181 object format.
 * Handles umapd field naming with bh_/fh_ prefixes and hex string OUI.
 *
 * @param {string} prefix - Field name prefix ("bh" or "fh")
 * @param {object} akm_entry - AKM entry from umapd
 * @returns {object} TR-181 formatted AKM object with OUI and Type
 */
function akm_to_object(prefix, akm_entry) {
	let oui_hex = akm_entry[prefix + "_oui"] ?? "000000";
	return {
		OUI: b64enc(hexdec(oui_hex)),
		Type: sprintf('%d', akm_entry[prefix + "_akm_suite_type"] ?? 0)
	};
}

/**
 * Classifies an AKM suite selector into a TR-181 AKMsAllowed enum group.
 * Returns "psk"/"sae"/"dpp"/null for known IEEE/WFA selectors, else the
 * hex-encoded 4-octet selector as a SuiteSelector fallback.
 *
 * @param {string} oui_hex - 6-char hex OUI (lower-case, no delimiters)
 * @param {number} suite_type - AKM suite type number
 * @returns {object} { group: "psk"|"sae"|"dpp"|null, selector: string }
 */
function akm_classify(oui_hex, suite_type) {
	if (oui_hex == "000fac") {
		if (suite_type == 2 || suite_type == 6)
			return { group: "psk", selector: "" };
		if (suite_type == 8 || suite_type == 9)
			return { group: "sae", selector: "" };
	}
	if (oui_hex == "506f9a" && suite_type == 2)
		return { group: "dpp", selector: "" };
	return { group: null, selector: sprintf("%s%02x", oui_hex, suite_type & 0xff) };
}

/**
 * Combines psk/sae/dpp presence flags into the TR-181 AKMsAllowed token.
 *
 * @param {boolean} has_psk
 * @param {boolean} has_sae
 * @param {boolean} has_dpp
 * @returns {string} combined token, or "" when none set
 */
function akm_combined_token(has_psk, has_sae, has_dpp) {
	if (has_dpp && has_psk && has_sae) return "dpp+psk+sae";
	if (has_dpp && has_sae) return "dpp+sae";
	if (has_psk && has_sae) return "psk+sae";
	if (has_dpp) return "dpp";
	if (has_sae) return "sae";
	if (has_psk) return "psk";
	return "";
}

/**
 * Encodes a list of AKM suite selectors into the TR-181 AKMsAllowed list and
 * an optional SuiteSelector hex-4 companion value.
 *
 * @param {string} prefix - Field name prefix ("bh" or "fh")
 * @param {array} akm_list - Array of AKM entries from umapd
 * @returns {object} { akms: string, selector: string }
 */
function akm_list_encode(prefix, akm_list) {
	if (!akm_list || length(akm_list) == 0)
		return { akms: "", selector: "" };

	let has_psk, has_sae, has_dpp;
	let selector = "";
	for (let entry in akm_list) {
		let oui_hex = lc(entry[prefix + "_oui"] ?? "000000");
		let suite_type = entry[prefix + "_akm_suite_type"] ?? 0;
		let cls = akm_classify(oui_hex, suite_type);
		if (cls.group == "psk") has_psk = true;
		else if (cls.group == "sae") has_sae = true;
		else if (cls.group == "dpp") has_dpp = true;
		else if (selector == "") selector = cls.selector;
	}

	let combined = akm_combined_token(has_psk, has_sae, has_dpp);
	let tokens = [];
	if (combined != "")
		push(tokens, combined);
	if (selector != "")
		push(tokens, "SuiteSelector");

	return { akms: join(',', tokens), selector };
}

/**
 * Converts WiFi 6 role capabilities to TR-181 object format.
 *
 * @param {object} wifi6_caps - WiFi 6 capabilities with roles array
 * @param {number} target_role - Target role (0x00=AP, 0x80=bSTA)
 * @returns {object|null} TR-181 formatted WiFi6 role object or null
 */
function wifi6_role_to_object(wifi6_caps, target_role) {
	let roles = wifi6_caps?.roles ?? [];
	let role_data;
	for (let r in roles) {
		if (r.agent_role == target_role) {
			role_data = r;
			break;
		}
	}
	if (!role_data) {
		return {
			HE160: "false", HE8080: "false", MCSNSS: "",
			SUBeamformer: "false", SUBeamformee: "false", MUBeamformer: "false",
			Beamformee80orLess: "false", BeamformeeAbove80: "false",
			ULMUMIMO: "false", ULOFDMA: "false", DLOFDMA: "false",
			MaxDLMUMIMO: "0", MaxULMUMIMO: "0", MaxDLOFDMA: "0", MaxULOFDMA: "0",
			RTS: "false", MURTS: "false", MultiBSSID: "false", MUEDCA: "false",
			TWTRequestor: "false", TWTResponder: "false",
			SpatialReuse: "false", AnticipatedChannelUsage: "false"
		};
	}

	return {
		HE160: role_data.he_160 ? "true" : "false",
		HE8080: role_data.he_8080 ? "true" : "false",
		MCSNSS: role_data.mcs_nss ? b64enc(role_data.mcs_nss) : "",
		SUBeamformer: role_data.su_beamformer ? "true" : "false",
		SUBeamformee: role_data.su_beamformee ? "true" : "false",
		MUBeamformer: role_data.mu_beamformer_status ? "true" : "false",
		Beamformee80orLess: (role_data.beamformee_sts_less_80 ?? 0) > 0 ? "true" : "false",
		BeamformeeAbove80: (role_data.beamformee_sts_greater_80 ?? 0) > 0 ? "true" : "false",
		ULMUMIMO: role_data.ul_mu_mimo ? "true" : "false",
		ULOFDMA: role_data.ul_ofdma ? "true" : "false",
		DLOFDMA: role_data.dl_ofdma ? "true" : "false",
		MaxDLMUMIMO: sprintf('%d', role_data.max_dl_mu_mimo_tx ?? 0),
		MaxULMUMIMO: sprintf('%d', role_data.max_ul_mu_mimo_rx ?? 0),
		MaxDLOFDMA: sprintf('%d', role_data.max_dl_ofdma_tx ?? 0),
		MaxULOFDMA: sprintf('%d', role_data.max_ul_ofdma_rx ?? 0),
		RTS: role_data.rts ? "true" : "false",
		MURTS: role_data.mu_rts ? "true" : "false",
		MultiBSSID: role_data.multi_bssid ? "true" : "false",
		MUEDCA: role_data.mu_edca ? "true" : "false",
		TWTRequestor: role_data.twt_requester ? "true" : "false",
		TWTResponder: role_data.twt_responder ? "true" : "false",
		SpatialReuse: role_data.spatial_reuse ? "true" : "false",
		AnticipatedChannelUsage: role_data.anticipated_channel_usage ? "true" : "false"
	};
}

/**
 * Converts HE capabilities to TR-181 WiFi6Capabilities object format.
 *
 * @param {object} sta_caps - HE capabilities object
 * @returns {object} TR-181 WiFi6Capabilities object with defaults if input is null
 */
function sta_wifi6_caps_to_object(sta_caps) {
	sta_caps ??= {};

	return {
		HE160: sta_caps.he_160 ? "true" : "false",
		HE8080: sta_caps.he_8080 ? "true" : "false",
		MCSNSS: sta_caps.mcs_nss ? b64enc(sta_caps.mcs_nss) : "",
		SUBeamformer: sta_caps.su_beamformer ? "true" : "false",
		SUBeamformee: sta_caps.su_beamformee ? "true" : "false",
		MUBeamformer: sta_caps.mu_beamformer_status ? "true" : "false",
		Beamformee80orLess: (sta_caps.beamformee_sts_less_80 ?? 0) > 0 ? "true" : "false",
		BeamformeeAbove80: (sta_caps.beamformee_sts_greater_80 ?? 0) > 0 ? "true" : "false",
		ULMUMIMO: sta_caps.ul_mu_mimo ? "true" : "false",
		ULOFDMA: sta_caps.ul_ofdma ? "true" : "false",
		DLOFDMA: sta_caps.dl_ofdma ? "true" : "false",
		MaxDLMUMIMO: sprintf('%d', sta_caps.max_dl_mu_mimo_tx ?? 0),
		MaxULMUMIMO: sprintf('%d', sta_caps.max_ul_mu_mimo_rx ?? 0),
		MaxDLOFDMA: sprintf('%d', sta_caps.max_dl_ofdma_tx ?? 0),
		MaxULOFDMA: sprintf('%d', sta_caps.max_ul_ofdma_rx ?? 0),
		RTS: sta_caps.rts ? "true" : "false",
		MURTS: sta_caps.mu_rts ? "true" : "false",
		MultiBSSID: sta_caps.multi_bssid ? "true" : "false",
		MUEDCA: sta_caps.mu_edca ? "true" : "false",
		TWTRequestor: sta_caps.twt_requester ? "true" : "false",
		TWTResponder: sta_caps.twt_responder ? "true" : "false",
		SpatialReuse: sta_caps.spatial_reuse ? "true" : "false",
		AnticipatedChannelUsage: sta_caps.anticipated_channel_usage ? "true" : "false"
	};
}

/**
 * Builds a WiFi 7 frequency separation table for one MLO mode.
 *
 * @param {array} records - freq separation records from the Wi-Fi 7 Agent Capabilities TLV
 * @param {string} key - record field prefix, e.g. "ap_str"
 * @returns {object} TR-181 formatted FreqSeparation instances
 */
function wifi7_freq_separation_to_object(records, key) {
	return ubbf.enumerate_instances(records ?? [], (rec) => ({
		RUID: ubbf.mac_to_base64(rec[key + '_ruid']),
		FreqSeparation: sprintf('%d', rec[key + '_freq_separation'] ?? 0)
	}));
}

/**
 * Converts WiFi 7 role capabilities to TR-181 object format.
 *
 * @param {object} radio_caps - per-radio entry of the Wi-Fi 7 Agent Capabilities TLV
 * @param {number} tid_capability - device level TID-to-link mapping capability
 * @param {string} role - "ap" or "bsta", selecting which role's fields to read
 * @returns {object} TR-181 formatted WiFi7 role object
 */
function wifi7_role_to_object(radio_caps, tid_capability, role) {
	let str_records = radio_caps?.[role + '_str_records'] ?? [];
	let nstr_records = radio_caps?.[role + '_nstr_records'] ?? [];
	let emlsr_records = radio_caps?.[role + '_emlsr_records'] ?? [];
	let emlmr_records = radio_caps?.[role + '_emlmr_records'] ?? [];

	return {
		EMLMRSupport: radio_caps?.[role + '_emlmr_support'] ? "true" : "false",
		EMLSRSupport: radio_caps?.[role + '_emlsr_support'] ? "true" : "false",
		STRSupport: radio_caps?.[role + '_str_support'] ? "true" : "false",
		NSTRSupport: radio_caps?.[role + '_nstr_support'] ? "true" : "false",
		TIDLinkMapNegotiation: tid_capability ? "true" : "false",
		EMLMRFreqSeparationNumberOfEntries: sprintf('%d', length(emlmr_records)),
		EMLMRFreqSeparation: wifi7_freq_separation_to_object(emlmr_records, role + '_emlmr'),
		EMLSRFreqSeparationNumberOfEntries: sprintf('%d', length(emlsr_records)),
		EMLSRFreqSeparation: wifi7_freq_separation_to_object(emlsr_records, role + '_emlsr'),
		STRFreqSeparationNumberOfEntries: sprintf('%d', length(str_records)),
		STRFreqSeparation: wifi7_freq_separation_to_object(str_records, role + '_str'),
		NSTRFreqSeparationNumberOfEntries: sprintf('%d', length(nstr_records)),
		NSTRFreqSeparation: wifi7_freq_separation_to_object(nstr_records, role + '_nstr')
	};
}

/**
 * Finds the Wi-Fi 7 capability entry describing one radio.
 *
 * @param {object} wifi7_caps - device level Wi-Fi 7 capabilities
 * @param {string} ruid - radio unique identifier
 * @returns {object|null} the matching radio entry
 */
function wifi7_radio_caps_find(wifi7_caps, ruid) {
	for (let radio in wifi7_caps?.radios ?? [])
		if (radio.ruid == ruid)
			return radio;

	return null;
}

/**
 * Converts radio capabilities to TR-181 Capabilities object format.
 *
 * @param {object} radio_caps - Basic radio capabilities
 * @param {object} advanced_caps - Advanced radio capabilities
 * @param {object} akm_caps - AKM suite capabilities
 * @param {object} wifi6_caps - WiFi 6 capabilities
 * @param {object} raw_data - Raw capability data with band and HE interface data
 * @param {object} wifi7_radio - per-radio entry of the Wi-Fi 7 Agent Capabilities TLV
 * @param {number} tid_capability - device level TID-to-link mapping capability
 * @returns {object} TR-181 formatted Capabilities object
 */
function capabilities_to_object(radio_caps, advanced_caps, akm_caps, wifi6_caps, raw_data, wifi7_radio, tid_capability) {
	let opclasses = radio_caps?.opclasses_supported ?? [];
	let fronthaul_akms = akm_caps?.fronthaul_akm_suite_selectors ?? [];
	let backhaul_akms = akm_caps?.backhaul_akm_suite_selectors ?? [];

	return {
		HTCapabilities: ht_caps_encode(raw_data?.ht_capabilities, raw_data?._band),
		VHTCapabilities: vht_caps_encode(raw_data?.vht_capabilities, raw_data?._band),
		MSCSCapability: advanced_caps?.mscs ? "true" : "false",
		SCSCapability: advanced_caps?.scs ? "true" : "false",
		QoSMapCapability: advanced_caps?.qos_map ? "true" : "false",
		DSCPPolicyCapability: advanced_caps?.dscp_policy ? "true" : "false",
		SCSTrafficDescriptionCapability: advanced_caps?.scs_traffic_description ? "true" : "false",
		CapableOperatingClassProfileNumberOfEntries: sprintf('%d', length(opclasses)),
		CapableOperatingClassProfile: ubbf.enumerate_instances(opclasses, opclass_to_object),
		AKMFrontHaulNumberOfEntries: sprintf('%d', length(fronthaul_akms)),
		AKMFrontHaul: ubbf.enumerate_instances(fronthaul_akms, (e) => akm_to_object("fh", e)),
		AKMBackhaulNumberOfEntries: sprintf('%d', length(backhaul_akms)),
		AKMBackhaul: ubbf.enumerate_instances(backhaul_akms, (e) => akm_to_object("bh", e)),
		WiFi6APRole: wifi6_role_to_object(wifi6_caps, 0x00),
		WiFi6bSTARole: wifi6_role_to_object(wifi6_caps, 1),
		WiFi7APRole: wifi7_role_to_object(wifi7_radio, tid_capability, "ap"),
		WiFi7bSTARole: wifi7_role_to_object(wifi7_radio, tid_capability, "bsta")
	};
}

const AKM_OUI_MAP = {
	'psk': '000fac02',
	'sae': '000fac08',
	'owe': '000fac12',
	'dpp': '506f9a02',
	'802.1x': '000fac01',
	'ft-psk': '000fac04',
	'ft-sae': '000fac09',
	'ft-802.1x': '000fac03',
	'sae-ext-key': '000fac18'
};

const CIPHER_OUI_MAP = {
	'ccmp': '000fac04',
	'tkip': '000fac02',
	'gcmp-128': '000fac08',
	'gcmp-256': '000fac09',
	'ccmp-256': '000fac0a'
};

/**
 * Encodes STA security fields from capability data.
 *
 * @param {object} security - Security data from get_client/topology
 * @returns {object} Object with SecurityAssociation, PairwiseAKM, PairwiseCipher, RSNCapabilities
 */
function sta_security_encode(security) {
	if (!security)
		return {};

	let akm = security.akm_suites?.[0];
	let cipher = security.pairwise_ciphers?.[0];
	let mfp_cap = security.mfp_capable ? 0x0040 : 0;
	let mfp_req = security.mfp_required ? 0x0080 : 0;

	return {
		SecurityAssociation: "PTKSA",
		PairwiseAKM: AKM_OUI_MAP[akm] ?? "",
		PairwiseCipher: CIPHER_OUI_MAP[cipher] ?? "",
		RSNCapabilities: sprintf('%d', mfp_cap | mfp_req)
	};
}

/**
 * Encodes STA measurement report fields from beacon report data.
 * Elements are already base64-encoded by umapd.
 *
 * @param {object} beacon_report - Beacon report data from get_client/topology
 * @returns {object} Object with MeasurementReport and NumberOfMeasureReports
 */
function sta_measurement_report_encode(beacon_report) {
	let elements = beacon_report?.measurement_report_elements;
	if (!elements || length(elements) == 0)
		return {};

	return {
		MeasurementReport: join(',', elements),
		NumberOfMeasureReports: sprintf('%d', length(elements))
	};
}

/**
 * Converts STA HE capability format to the format expected by he_caps_encode.
 * STA data uses mcs_nss (raw binary) while the encoder expects supported_he_mcs (hex).
 * Derives spatial stream counts from the MCS/NSS map.
 *
 * @param {object} he_caps - STA HE capabilities (mcs_nss, he_160, he_8080, etc.)
 * @returns {object|null} Converted object for he_caps_encode, or null
 */
function sta_he_to_encode_format(he_caps) {
	if (!he_caps?.mcs_nss || length(he_caps.mcs_nss) == 0)
		return null;

	let mcs_nss = he_caps.mcs_nss;
	let tx_ss = 1, rx_ss = 1;
	if (length(mcs_nss) >= 4) {
		let rx_map = ord(mcs_nss, 0) | (ord(mcs_nss, 1) << 8);
		let tx_map = ord(mcs_nss, 2) | (ord(mcs_nss, 3) << 8);
		for (let i = 7; i >= 0; i--) {
			if (((rx_map >> (i * 2)) & 0x03) != 0x03) {
				rx_ss = i + 1;
				break;
			}
		}
		for (let i = 7; i >= 0; i--) {
			if (((tx_map >> (i * 2)) & 0x03) != 0x03) {
				tx_ss = i + 1;
				break;
			}
		}
	}

	return {
		supported_he_mcs: hexenc(mcs_nss),
		max_supported_tx_spatial_streams: tx_ss,
		max_supported_rx_spatial_streams: rx_ss,
		he_support_160mhz: he_caps.he_160,
		he_support_8080mhz: he_caps.he_8080,
		su_beamformer_capable: he_caps.su_beamformer,
		mu_beamformer_capable: he_caps.mu_beamformer_status,
		ul_mu_mimo_capable: he_caps.ul_mu_mimo,
		ul_ofdma_capable: he_caps.ul_ofdma,
		dl_ofdma_capable: he_caps.dl_ofdma
	};
}

const cellular_data_pref_names = {
	[1]: "Excluded",
	[2]: "Should not use",
	[3]: "Should use"
};

/**
 * Maps MBO cellular data preference subelement value to TR-181 enumeration.
 *
 * @param {number} val - MBO subelement 6 value (1=excluded, 2=not preferred, 3=preferred)
 * @returns {string} TR-181 CellularDataPreference enumeration value
 */
function cellular_data_pref_name(val) {
	return cellular_data_pref_names[val] ?? "";
}

/**
 * Formats a raw counter as a TR-181 string, defaulting a missing one to zero.
 *
 * @param {number|null} val - Counter value
 * @returns {string} Decimal string
 */
function counter_format(val) {
	return sprintf('%d', val ?? 0);
}

/**
 * Creates a factory function for converting STA data to TR-181 format.
 *
 * @param {object} api_data - API data for the device
 * @param {string} bssid - BSSID of the BSS
 * @returns {function} Factory function that converts STA data to TR-181 object
 */
function sta_to_object_factory(api_data, bssid) {
	return function(sta) {
		let sta_mac = sta.mac_address ?? sta.mac ?? "";

		let link = sta.link_metrics ?? {};
		let traffic = sta.traffic_stats ?? {};
		let ext = sta.extended_metrics ?? {};
		let sta_caps = api_data?.sta_capabilities?.[bssid]?.[sta_mac] ?? {};
		let sec = sta_security_encode(sta_caps.security);
		let meas = sta_measurement_report_encode(sta_caps.beacon_report);

		let now = time();
		let last_assoc_elapsed = sta.last_association ?? 0;

		let sta_steering = api_data.steering_stats?.sta?.[sta_mac] ?? {};
		let history_all = api_data.steering_history?.history;
		let sta_history = (type(history_all) == 'object')
			? (history_all?.[sta_mac] ?? [])
			: [];
		let last_steer = sta_steering.last_steer_time;
		let last_steer_delta = (last_steer && last_steer > 0) ? (now - last_steer) : 0;
		if (last_steer_delta < 0)
			last_steer_delta = 0;

		return {
			MACAddress: sta_mac,
			TimeStamp: ubbf.iso8601_format(),
			HTCapabilities: ht_caps_encode(sta_caps.ht_capabilities, null),
			VHTCapabilities: vht_caps_encode(sta_caps.vht_capabilities, null),
			HECapabilities: he_caps_encode(sta_he_to_encode_format(sta_caps.he_capabilities), null),
			ClientCapabilities: "",
			LastDataDownlinkRate: sprintf('%d', ext.last_data_downlink_rate ?? 0),
			LastDataUplinkRate: sprintf('%d', ext.last_data_uplink_rate ?? 0),
			UtilizationReceive: sprintf('%d', ext.utilization_receive ?? 0),
			UtilizationTransmit: sprintf('%d', ext.utilization_transmit ?? 0),
			EstMACDataRateDownlink: sprintf('%d', link.estimated_downlink_mac_data_rate ?? 0),
			EstMACDataRateUplink: sprintf('%d', link.estimated_uplink_mac_data_rate ?? 0),
			SignalStrength: sprintf('%d', link.uplink_rcpi ?? 0),
			LastConnectTime: sprintf('%d', last_assoc_elapsed),
			BytesSent: counter_format(traffic.bytes_sent),
			BytesReceived: counter_format(traffic.bytes_received),
			PacketsSent: counter_format(traffic.packets_sent),
			PacketsReceived: counter_format(traffic.packets_received),
			ErrorsSent: counter_format(traffic.tx_packets_errors),
			ErrorsReceived: counter_format(traffic.rx_packets_errors),
			RetransCount: counter_format(traffic.retransmission_count),
			MeasurementReport: meas.MeasurementReport ?? "",
			NumberOfMeasureReports: meas.NumberOfMeasureReports ?? "0",
			IPV4Address: "",
			IPV6Address: "",
			Hostname: "",
			CellularDataPreference: cellular_data_pref_name(sta_caps.mbo?.cellular_data_preference),
			ReAssociationDelay: "0",
			SleepMode: "",
			SecurityAssociation: sec.SecurityAssociation ?? "",
			PairwiseAKM: sec.PairwiseAKM ?? "",
			PairwiseCipher: sec.PairwiseCipher ?? "",
			RSNCapabilities: sec.RSNCapabilities ?? "0",
			TIDQueueSizesNumberOfEntries: "0",
			WiFi6Capabilities: sta_wifi6_caps_to_object(sta_caps.he_capabilities),
			MultiAPSTA: {
				AssociationTime: last_assoc_elapsed > 0 ? ubbf.iso8601_format(now - last_assoc_elapsed) : "",
				Noise: "0",
				SteeringHistoryNumberOfEntries: sprintf('%d', length(sta_history)),
				SteeringSummaryStats: {
					NoCandidateAPFailures: sprintf('%d', sta_steering.no_candidate_ap_failures ?? 0),
					BlacklistAttempts: sprintf('%d', sta_steering.blacklist_attempts ?? 0),
					BlacklistSuccesses: sprintf('%d', sta_steering.blacklist_successes ?? 0),
					BlacklistFailures: sprintf('%d', sta_steering.blacklist_failures ?? 0),
					BTMAttempts: sprintf('%d', sta_steering.btm_attempts ?? 0),
					BTMSuccesses: sprintf('%d', sta_steering.btm_successes ?? 0),
					BTMFailures: sprintf('%d', sta_steering.btm_failures ?? 0),
					BTMQueryResponses: sprintf('%d', sta_steering.btm_query_responses ?? 0),
					LastSteerTime: sprintf('%d', last_steer_delta)
				},
				SteeringHistory: ubbf.enumerate_instances(sta_history, (entry) => ({
					Time: entry.time ? ubbf.iso8601_format(entry.time) : "",
					APOrigin: entry.ap_origin ?? "",
					TriggerEvent: STEERING_TRIGGER_EVENT_MAP[entry.trigger_event] ?? "Unknown",
					SteeringApproach: entry.steering_approach ?? "",
					APDestination: entry.ap_destination ?? "",
					SteeringDuration: sprintf('%d', entry.steering_duration ?? 0)
				}))
			}
		};
	};
}

/**
 * Creates a factory function for converting BSS data to TR-181 format.
 *
 * @param {object} api_data - API data for the device
 * @returns {function} Factory function that converts BSS data to TR-181 object
 */
function bss_to_object_factory(api_data) {
	let akm_caps = api_data?.capability?.akm_suite_capabilities ?? {};

	let metrics_idx = ubbf.bss_index_by_bssid(api_data?.ap_metrics);
	let ext_metrics_idx = ubbf.bss_index_by_bssid(api_data?.ap_extended_metrics);
	let bss_config_idx = ubbf.bss_index_by_bssid(api_data?.bss_configuration_report, 'bss');
	let backhaul_idx = ubbf.bss_index_by_bssid(api_data?.backhaul_bss_configuration);
	let assoc_status_idx = ubbf.bss_index_by_bssid(api_data?.association_status);

	return function(bss) {
		let bssid = bss.mac_address ?? "";
		let ap_metrics = metrics_idx[bssid];
		let ext_metrics = ext_metrics_idx[bssid];
		let bss_config = bss_config_idx[bssid];
		let backhaul_config = backhaul_idx[bssid];
		let assoc_status = assoc_status_idx[bssid];
		let qm_descriptors = bss_qm_descriptors_filter(api_data?.qos_management_descriptors, bssid);
		let sta_list = api_data?.associated_clients?.[bssid] ?? [];
		let bss_steering = api_data.steering_stats?.bss?.[bssid] ?? {};

		// An agent encodes these counters in the units it declared in its
		// Profile-2 AP Capability, so report them as received and name that
		// unit. The AP Extended Metrics TLV carries no unit of its own, and
		// treating that as kibibytes, as this did, rounded every counter down
		// to a multiple of 1024 and contradicted the unit the agent declared.
		let byte_unit = sprintf('%d',
			api_data?.capability?.profile2_ap_capability?.byte_counter_unit ?? 0);
		let format_bytes = (val) => val != null ? sprintf('%d', val) : "";

		let fh_akms = bss_config?.fronthaul ? akm_list_encode("fh", akm_caps.fronthaul_akm_suite_selectors) : { akms: "", selector: "" };
		let bh_akms = bss_config?.backhaul ? akm_list_encode("bh", akm_caps.backhaul_akm_suite_selectors) : { akms: "", selector: "" };

		return {
			BSSID: bssid,
			SSID: bss.ssid ?? "",
			Enabled: "true",
			// TR-181 counts from the last change to Enabled, which is when
			// the BSS came up; `timestamp` moves with every report of it.
			LastChange: sprintf('%d', bss.enabled_since ? clock(true)[0] - int(bss.enabled_since / 1000) : 0),
			TimeStamp: bss.timestamp
				? ubbf.iso8601_format(time() - (clock(true)[0] - bss.timestamp / 1000))
				: "",
			UnicastBytesSent: format_bytes(ext_metrics?.unicast_bytes_sent),
			UnicastBytesReceived: format_bytes(ext_metrics?.unicast_bytes_received),
			MulticastBytesSent: format_bytes(ext_metrics?.multicast_bytes_sent),
			MulticastBytesReceived: format_bytes(ext_metrics?.multicast_bytes_received),
			BroadcastBytesSent: format_bytes(ext_metrics?.broadcast_bytes_sent),
			BroadcastBytesReceived: format_bytes(ext_metrics?.broadcast_bytes_received),
			ByteCounterUnits: byte_unit,
			Profile1bSTAsDisallowed: backhaul_config?.profile1_backhaul_sta_disallowed ? "true" : "false",
			Profile2bSTAsDisallowed: backhaul_config?.profile2_backhaul_sta_disallowed ? "true" : "false",
			AssociationAllowanceStatus: sprintf('%d', assoc_status?.association_allowance_status ?? 0),
			EstServiceParametersBE: esp_encode(ap_metrics?.esp_be),
			EstServiceParametersBK: esp_encode(ap_metrics?.esp_bk),
			EstServiceParametersVI: esp_encode(ap_metrics?.esp_vi),
			EstServiceParametersVO: esp_encode(ap_metrics?.esp_vo),
			BackhaulUse: bss_config?.backhaul ? "true" : "false",
			FronthaulUse: bss_config?.fronthaul ? "true" : "false",
			R1disallowed: bss_config?.r1_disallowed_status ? "true" : "false",
			R2disallowed: bss_config?.r2_disallowed_status ? "true" : "false",
			MultiBSSID: bss_config?.multiple_bssid ? "true" : "false",
			TransmittedBSSID: bss_config?.transmitted_bssid ? "true" : "false",
			FronthaulAKMsAllowed: fh_akms.akms,
			FronthaulSuiteSelector: fh_akms.selector,
			BackhaulAKMsAllowed: bh_akms.akms,
			BackhaulSuiteSelector: bh_akms.selector,
			BasicDataTransmitRates: "0",
			STANumberOfEntries: sprintf('%d', length(sta_list)),
			STA: ubbf.enumerate_instances(sta_list, sta_to_object_factory(api_data, bssid)),
			QMDescriptorNumberOfEntries: sprintf('%d', length(qm_descriptors)),
			QMDescriptor: ubbf.enumerate_instances(qm_descriptors, (qm) => ({
				BSSID: qm.bssid ?? "",
				ClientMAC: qm.client_mac ?? "",
				DescriptorElement: qm.descriptor_element ? b64enc(qm.descriptor_element) : ""
			})),
			MultiAPSteering: {
				BlacklistAttempts: sprintf('%d', bss_steering.blacklist_attempts ?? 0),
				BTMAttempts: sprintf('%d', bss_steering.btm_attempts ?? 0),
				BTMQueryResponses: sprintf('%d', bss_steering.btm_query_responses ?? 0)
			}
		};
	};
}

/**
 * Converts neighbor BSS data to TR-181 object format.
 *
 * @param {object} neighbor - Neighbor BSS data from scan results
 * @returns {object} TR-181 formatted NeighborBSS object
 */
function neighbor_bss_to_object(neighbor) {
	return {
		BSSID: neighbor.bssid ?? "",
		SSID: neighbor.ssid ?? "",
		SignalStrength: sprintf('%d', neighbor.signal_strength ?? 0),
		ChannelBandwidth: neighbor.channel_bandwidth ?? "",
		ChannelUtilization: sprintf('%d', neighbor.channel_utilization ?? 0),
		StationCount: sprintf('%d', neighbor.station_count ?? 0),
		MLDMACAddress: neighbor.mld_mac_address ?? "",
		ReportingBSSID: neighbor.reporting_bssid ?? "",
		MultiBSSID: neighbor.multi_bssid ? "true" : "false",
		BSSLoadElementPresent: neighbor.bss_load_element_present ? "true" : "false",
		BSSColor: sprintf('%d', neighbor.bss_color ?? 0)
	};
}

/**
 * Converts channel scan data to TR-181 object format.
 *
 * @param {object} channel - Channel scan data from scan results
 * @returns {object} TR-181 formatted ChannelScan object
 */
function channel_scan_to_object(channel) {
	let neighbors = channel.neighbors ?? [];
	return {
		Channel: sprintf('%d', channel.channel ?? 0),
		TimeStamp: channel.timestamp ?? "",
		Utilization: sprintf('%d', channel.utilization ?? 0),
		Noise: sprintf('%d', channel.noise ?? 0),
		ScanStatus: SCAN_STATUS_NAME_TO_CODE[channel.scan_status] ?? "",
		NeighborBSSNumberOfEntries: sprintf('%d', length(neighbors)),
		NeighborBSS: ubbf.enumerate_instances(neighbors, neighbor_bss_to_object)
	};
}

/**
 * Groups channel scan results by operating class.
 *
 * @param {array} channels - Array of channel scan results
 * @returns {object} Map of opclass to array of channel results
 */
function scan_results_group_by_opclass(channels) {
	let by_opclass = {};
	for (let ch in channels) {
		let opclass = ch.opclass ?? 0;
		by_opclass[opclass] ??= [];
		push(by_opclass[opclass], ch);
	}
	return by_opclass;
}

/**
 * Converts scan results to TR-181 ScanResult hierarchy.
 *
 * @param {array} scan_results - Array of channel scan results from get_scan_results
 * @returns {object} TR-181 formatted ScanResult enumeration
 */
function scan_results_to_object(scan_results) {
	if (length(scan_results) == 0)
		return {};

	let by_opclass = scan_results_group_by_opclass(scan_results);
	let opclass_keys = keys(by_opclass);

	let total_duration = 0;
	let first_timestamp = "";
	let is_active = false;
	for (let ch in scan_results) {
		total_duration += ch.aggregate_scan_duration ?? 0;
		if (!first_timestamp && ch.timestamp)
			first_timestamp = ch.timestamp;
		if (ch.active_scan)
			is_active = true;
	}

	let opclass_scans = {};
	let opclass_idx = 1;
	for (let opclass in opclass_keys) {
		let channels = by_opclass[opclass];
		opclass_scans[sprintf('%d', opclass_idx)] = {
			OperatingClass: sprintf('%d', opclass),
			ChannelScanNumberOfEntries: sprintf('%d', length(channels)),
			ChannelScan: ubbf.enumerate_instances(channels, channel_scan_to_object)
		};
		opclass_idx++;
	}

	return {
		"1": {
			TimeStamp: first_timestamp,
			AggregateScanDuration: sprintf('%d', total_duration),
			ScanType: is_active ? "true" : "false",
			OpClassScanNumberOfEntries: sprintf('%d', length(opclass_keys)),
			OpClassScan: opclass_scans
		}
	};
}

/**
 * Looks up transmit power limit from policy txpower_limit array (first match wins).
 * Omitted match fields in a policy entry act as wildcards.
 *
 * @param {array} txpower_entries - Array of {ruid, band, opclass, txpower}
 * @param {string} ruid - Radio unique identifier MAC
 * @param {number} opclass - Operating class to match
 * @returns {number|null} Matched txpower value or null
 */
function txpower_limit_get(txpower_entries, ruid, opclass) {
	for (let entry in txpower_entries) {
		if (entry.ruid != null && entry.ruid != ruid)
			continue;
		if (entry.band != null)
			continue;
		if (entry.opclass != null && entry.opclass != opclass)
			continue;
		return entry.txpower;
	}
	return null;
}

/**
 * Creates a factory function for converting radio data to TR-181 format.
 *
 * @param {object} api_data - API data for the device
 * @param {string} al_mac - Device AL MAC address for policy lookups
 * @param {object} easymesh - Root EasyMesh config for operator policy data
 * @returns {function} Factory function that converts radio data to TR-181 object
 */
function radio_to_object_factory(api_data, al_mac, easymesh, device_cfg) {
	let txpower_entries = easymesh?.TxPowerLimit?.[al_mac] ?? [];
	let radio_idx = 0;

	let merged_policy = api_data?.policy?.policy ?? {};
	let cfg_steer = merged_policy.steering;
	let cfg_mr = merged_policy.metric_reporting;

	let user_policy = easymesh?.ConfigPolicy?.[al_mac] ?? easymesh?.ConfigPolicy?.['*'] ?? {};
	let user_steer_by_ruid = {};
	for (let r in user_policy.steering?.radios ?? [])
		if (r.radio_unique_identifier)
			user_steer_by_ruid[r.radio_unique_identifier] = r;
	let user_mr_by_ruid = {};
	for (let r in user_policy.metric_reporting?.radios ?? [])
		if (r.radio_unique_identifier)
			user_mr_by_ruid[r.radio_unique_identifier] = r;

	return function(radio_bss) {
		radio_idx++;
		let ruid = radio_bss.radio_unique_identifier ?? "";
		let bss_list = radio_bss.bss ?? [];
		let radio_survey = api_data?.survey?.radios?.[ruid] ?? {};
		let raw_data = api_data?.capability?.radios?.[ruid] ?? {};
		let radio_caps = raw_data.basic_capabilities ?? {};
		let advanced_caps = raw_data.advanced_capabilities ?? {};
		let akm_caps = api_data?.capability?.akm_suite_capabilities ?? {};
		let wifi6_caps = raw_data.wifi6_capabilities ?? {};
		let multiap = raw_data?.multiap_policy;
		let user_steer_radio = user_steer_by_ruid[ruid];
		let user_mr_radio = user_mr_by_ruid[ruid];
		let combined_fb = advanced_caps.combined_front_back ? "true" : "false";
		let onboard_protocol = raw_data?.config_method ? uc(raw_data.config_method) : "";
		let scan_results = api_data?.scan_results?.radios?.[ruid] ?? [];
		let radio_prefs = raw_data?.channel_preferences ?? [];
		let operating_classes = raw_data?.operating_classes ?? [];
		let eirp = raw_data?.eirp ?? 0;
		let scan_capability = raw_data?.scan_capability;
		let unassoc_entries = unassoc_sta_entries_get(
			api_data?.capability?.unassoc_sta_metrics, raw_data);

		let radio_cfg = device_cfg?.Radio?.[sprintf('%d', radio_idx)];
		let disallowed = [];
		for (let inst, entry in radio_cfg?.DisAllowedOpClassChannels ?? {}) {
			if (!ubbf.to_bool(entry.Enable))
				continue;
			push(disallowed, {
				opclass: int(entry.OpClass),
				channels: ubbf.csv_to_list(entry.ChannelList)
			});
		}

		return {
			ID: ubbf.mac_to_base64(ruid),
			Enabled: "true",
			Noise: sprintf('%d', radio_survey?.noise ?? 0),
			Utilization: sprintf('%d', radio_survey?.utilization ?? 0),
			Transmit: sprintf('%d', radio_survey?.transmit ?? 0),
			ReceiveSelf: sprintf('%d', radio_survey?.receive_self ?? 0),
			ReceiveOther: sprintf('%d', radio_survey?.receive_other ?? 0),
			TrafficSeparationCombinedFronthaul: combined_fb,
			TrafficSeparationCombinedBackhaul: combined_fb,
			SteeringPolicy: sprintf('%d', user_steer_radio?.steering_policy ?? cfg_steer?.policy ?? multiap?.steering_policy ?? 0),
			ChannelUtilizationThreshold: sprintf('%d', user_steer_radio?.channel_utilization_threshold ?? cfg_steer?.channel_utilization_threshold ?? multiap?.channel_utilization_threshold ?? 0),
			RCPISteeringThreshold: sprintf('%d', user_steer_radio?.rcpi_steering_threshold ?? cfg_steer?.rcpi_threshold ?? multiap?.rcpi_steering_threshold ?? 0),
			STAReportingRCPIThreshold: sprintf('%d', user_mr_radio?.sta_metrics_reporting_rcpi_threshold ?? cfg_mr?.rcpi_threshold ?? multiap?.sta_metrics_reporting_rcpi_threshold ?? 0),
			STAReportingRCPIHysteresisMarginOverride: sprintf('%d', user_mr_radio?.sta_metrics_reporting_rcpi_hysteresis_margin_override ?? cfg_mr?.rcpi_hysteresis ?? multiap?.sta_metrics_reporting_rcpi_hysteresis_margin_override ?? 0),
			ChannelUtilizationReportingThreshold: sprintf('%d', user_mr_radio?.ap_metrics_channel_utilization_reporting_threshold ?? cfg_mr?.channel_utilization_threshold ?? multiap?.ap_metrics_channel_utilization_reporting_threshold ?? 0),
			AssociatedSTATrafficStatsInclusionPolicy: (user_mr_radio?.associated_sta_traffic_stats_inclusion_policy ?? cfg_mr?.include_traffic_stats ?? multiap?.associated_sta_traffic_stats_inclusion_policy) ? "true" : "false",
			AssociatedSTALinkMetricsInclusionPolicy: (user_mr_radio?.associated_sta_link_metrics_inclusion_policy ?? cfg_mr?.include_link_metrics ?? multiap?.associated_sta_link_metrics_inclusion_policy) ? "true" : "false",
			ChipsetVendor: api_data?.capability?.device_inventory?.radios?.[ruid]?.chipset_vendor ?? "",
			X_UBBF_OnboardProtocol: onboard_protocol,
			APMetricsWiFi6: (user_mr_radio?.associated_wifi6_sta_status_inclusion_policy ?? cfg_mr?.wifi6_metrics ?? multiap?.associated_wifi6_sta_status_inclusion_policy) ? "true" : "false",
			MaxBSS: sprintf('%d', radio_caps?.max_bss_supported ?? 0),
			Capabilities: capabilities_to_object(radio_caps, advanced_caps, akm_caps, wifi6_caps, raw_data,
				wifi7_radio_caps_find(api_data?.capability?.wifi7_capabilities, ruid),
				api_data?.capability?.wifi7_capabilities?.tid_to_link_mapping_capability),
			CurrentOperatingClassProfileNumberOfEntries: sprintf('%d', length(operating_classes)),
			CurrentOperatingClassProfile: ubbf.enumerate_instances(operating_classes, (oc) => ({
				Class: sprintf('%d', oc.class ?? 0),
				Channel: sprintf('%d', oc.channel ?? 0),
				TxPower: sprintf('%d', eirp),
				TransmitPowerLimit: sprintf('%d', txpower_limit_get(txpower_entries, ruid, oc.class) ?? 0),
				TimeStamp: ubbf.iso8601_format()
			})),
			UnassociatedSTANumberOfEntries: sprintf('%d', length(unassoc_entries)),
			UnassociatedSTA: ubbf.enumerate_instances(unassoc_entries, (sta) => ({
				MACAddress: sta.mac_address ?? "",
				SignalStrength: sprintf('%d', sta.rcpi_uplink ?? 0),
				OperatingClass: sprintf('%d', sta._opclass ?? 0),
				Channel: sprintf('%d', sta.channel ?? 0)
			})),
			BSSNumberOfEntries: sprintf('%d', length(bss_list)),
			BSS: ubbf.enumerate_instances(bss_list, bss_to_object_factory(api_data)),
			ScanResultNumberOfEntries: length(scan_results) > 0 ? "1" : "0",
			ScanResult: scan_results_to_object(scan_results),
			DisAllowedOpClassChannelsNumberOfEntries: sprintf('%d', length(disallowed)),
			DisAllowedOpClassChannels: ubbf.enumerate_instances(disallowed, (dc) => ({
				Enable: "true",
				OpClass: sprintf('%d', dc.opclass ?? 0),
				ChannelList: join(',', dc.channels ?? [])
			})),
			OpClassPreferenceNumberOfEntries: sprintf('%d', length(radio_prefs)),
			OpClassPreference: ubbf.enumerate_instances(radio_prefs, (pref) => ({
				OpClass: sprintf('%d', pref.opclass ?? 0),
				ChannelList: join(',', pref.channels ?? []),
				Preference: sprintf('%d', pref.preference ?? 0),
				ReasonCode: sprintf('%d', pref.reason_code ?? 0)
			})),
			BackhaulSta: {
				MACAddress: raw_data?.backhaul_sta?.mac_address ?? ""
			},
			ScanCapability: scan_capability_to_object(scan_capability),
			CACCapability: cac_capability_to_object(raw_data?.cac_capabilities),
			SpatialReuse: spatial_reuse_to_object(raw_data?.spatial_reuse),
			MultiAPRadio: {
				RadarDetections: "0"
			}
		};
	};
}

/**
 * Converts get_client HT/VHT spatial stream counts from 0-indexed to 1-indexed.
 * get_client returns 0-indexed values (0=1SS, 1=2SS) but the encoders expect
 * 1-indexed values (1=1SS, 2=2SS).
 *
 * @param {object} caps - HT or VHT capabilities object from get_client
 * @returns {object} Adjusted capabilities object, or null if input is null
 */
function spatial_streams_adjust(caps) {
	if (!caps)
		return null;

	return {
		...caps,
		max_supported_tx_spatial_streams: (caps.max_supported_tx_spatial_streams ?? 0) + 1,
		max_supported_rx_spatial_streams: (caps.max_supported_rx_spatial_streams ?? 0) + 1
	};
}

/**
 * Gets capabilities for associated clients from topology or ubus.
 *
 * @param {object} associated_clients - Map of BSSID to client arrays
 * @param {string} ubus_object - ubus object name ('umap' or 'umap-agent')
 * @returns {object} Map of BSSID to client MAC to capability data object
 */
function client_capabilities_get(associated_clients, ubus_object) {
	let sta_capabilities = {};

	for (let bssid, clients in associated_clients) {
		for (let client in clients) {
			let sta_mac = client.mac_address ?? client.mac;
			if (!sta_mac)
				continue;

			let caps = {
				he_capabilities: client.he_capabilities,
				ht_capabilities: spatial_streams_adjust(client.ht_capabilities),
				vht_capabilities: spatial_streams_adjust(client.vht_capabilities),
				security: client.security,
				beacon_report: client.beacon_report,
				power_management: client.power_management,
				mbo: client.mbo
			};

			if (ubus_object) {
				let result = client_query_get(ubus_object, sta_mac);
				let client_data = result?.[bssid];
				if (client_data) {
					caps.he_capabilities ??= client_data.he_capabilities ??
						sta_he_caps_from_frame_body(client_data.frame_body);
					caps.ht_capabilities ??= spatial_streams_adjust(client_data.ht_capabilities);
					caps.vht_capabilities ??= spatial_streams_adjust(client_data.vht_capabilities);
					caps.security ??= client_data.security;
					caps.beacon_report ??= client_data.beacon_report;
					caps.power_management ??= client_data.power_management;
					caps.mbo ??= client_data.mbo;
				}
			}

			sta_capabilities[bssid] ??= {};
			sta_capabilities[bssid][sta_mac] = caps;
		}
	}

	return sta_capabilities;
}

/**
 * Converts SSID to VID mapping entry to TR-181 object format.
 *
 * @param {string} ssid - SSID name
 * @param {number} vid - VLAN ID
 * @returns {object} TR-181 formatted SSIDtoVIDMapping object
 */
function ssid_vid_mapping_to_object(ssid, vid) {
	return {
		SSID: ssid,
		VID: sprintf('%d', vid)
	};
}

/**
 * Converts IEEE 1905 security association to TR-181 object format.
 *
 * @param {object} assoc - Association data
 * @returns {object} TR-181 formatted IEEE1905Security object
 */
function ieee1905_security_to_object(assoc) {
	return {
		OnboardingProtocol: "0",
		IntegrityAlgorithm: "0",
		EncryptionAlgorithm: "0"
	};
}

/**
 * Finds operating class data for the radio used as backhaul.
 *
 * @param {object} api_data - Device API data
 * @param {string} backhaul_mac - Backhaul interface MAC address
 * @returns {object} Object with operating_classes array and eirp value
 */
function backhaul_operating_class_get(api_data, backhaul_mac) {
	if (!backhaul_mac)
		return { operating_classes: [], eirp: 0 };

	let radios = api_data?.capability?.radios ?? {};

	// A backhaul STA MLD reports its MLD address at device level, while each
	// radio reports the address of the STA affiliated with that radio, so the
	// two never compare equal. The MLD configuration names the radio of every
	// affiliated STA, which resolves the operating radio without addresses.
	let bsta_mld = api_data?.bsta_mld?.bsta_mld;
	if (bsta_mld?.bsta_mld_mac_addr_valid && bsta_mld.bsta_mld_mac_addr == backhaul_mac) {
		for (let bsta in bsta_mld.affiliated_bstas ?? []) {
			let radio = radios[bsta.ruid];
			if (length(radio?.operating_classes))
				return { operating_classes: radio.operating_classes, eirp: radio.eirp ?? 0 };
		}
	}

	for (let ruid, radio in radios) {
		if (radio.backhaul_sta?.mac_address == backhaul_mac)
			return { operating_classes: radio.operating_classes ?? [], eirp: radio.eirp ?? 0 };
	}
	return { operating_classes: [], eirp: 0 };
}

/**
 * Maps an EasyMesh ChannelUsageReason numeric code to its TR-181 enum name.
 *
 * @param {number} code - Numeric reason code from anticipated_channel_usage
 * @returns {string} TR-181 enum string (Unknown for unrecognised codes)
 */
function channel_usage_reason_name(code) {
	switch (code) {
	case 0: return "TWTSchedule";
	case 1: return "TSPEC";
	case 2: return "SchedulerPolicy";
	case 3: return "External802.11";
	case 4: return "Non802.11";
	case 255: return "BSSNonUsage";
	default: return "Unknown";
	}
}

/**
 * Builds AnticipatedChannels list: groups reports by opclass, collects unique channels.
 *
 * @param {array} reports - Anticipated channel usage reports from umapd
 * @returns {array} Array of { opclass, channels } grouped by opclass
 */
function anticipated_channels_build(reports) {
	let by_opclass = {};
	for (let r in reports) {
		let oc = r.opclass ?? 0;
		by_opclass[oc] ??= {};
		let ch = r.channel ?? 0;
		by_opclass[oc][ch] = true;
	}

	let result = [];
	for (let oc, channels in by_opclass)
		push(result, { opclass: int(oc), channels: sort(keys(channels), (a, b) => int(a) - int(b)) });

	return sort(result, (a, b) => a.opclass - b.opclass);
}

const T2LM_DIRECTION = { [0]: "DL+UL", [1]: "DL", [2]: "UL" };

/**
 * @param {array} t2lm_list - tid_to_link_mapping array from get_agent
 * @param {string} mld_mac - MLD MAC to match
 * @param {boolean} is_bsta - true for bSTA MLD, false for AP MLD
 * @returns {object|null} matching T2LM entry
 */
function t2lm_find_for_mld(t2lm_list, mld_mac, is_bsta) {
	for (let entry in t2lm_list)
		if (entry.mld_mac_addr == mld_mac && entry.is_bsta_config == is_bsta)
			return entry;

	return null;
}

/**
 * Decodes one T2LM mapping entry into flat TR-181 TIDLinkMap tuples.
 *
 * @param {object} mapping - entry from t2lm_entry.mappings[]
 * @param {object} link_to_bssid - linkid-to-BSSID lookup
 * @returns {array} array of {Direction, TID, BSSID, LinkID} objects
 */
function t2lm_decode_mapping(mapping, link_to_bssid) {
	if (mapping.default_link_mapping)
		return [];

	let presence = mapping.link_mapping_presence_indicator ?? 0;
	if (!presence)
		return [];

	let dir_str = T2LM_DIRECTION[mapping.direction] ?? "DL+UL";
	let raw = hexdec(mapping.tid_to_link_mapping ?? "");
	// link_mapping_size flag selects 2-byte form (up to 16 links) versus the
	// default 1-byte form (up to 8 links) per 802.11be T2LM element layout
	let byte_size = mapping.link_mapping_size ? 2 : 1;
	let offset = 0;
	let result = [];

	for (let tid = 0; tid < 8; tid++) {
		if (!(presence & (1 << tid)))
			continue;

		let link_bitmask = 0;
		if (offset < length(raw)) {
			link_bitmask = ord(raw, offset);
			if (byte_size == 2 && offset + 1 < length(raw))
				link_bitmask |= (ord(raw, offset + 1) << 8);
		}
		offset += byte_size;

		for (let linkid = 0; linkid < (byte_size * 8); linkid++) {
			if (!(link_bitmask & (1 << linkid)))
				continue;

			push(result, {
				Direction: dir_str,
				TID: sprintf('%d', tid),
				BSSID: link_to_bssid[linkid] ?? "",
				LinkID: sprintf('%d', linkid)
			});
		}
	}

	return result;
}

/**
 * @param {array} affiliated_aps - from AP MLD
 * @returns {object} linkid -> BSSID lookup
 */
function link_bssid_build(affiliated_aps) {
	let result = {};
	for (let ap in affiliated_aps)
		result[ap.linkid] = ap.affiliated_ap_mac_addr ?? "";
	return result;
}

/**
 * @param {array} affiliated_aps - from AP MLD
 * @param {object} radios - capability.radios keyed by ruid
 * @returns {array} array of {LinkID, OpClass} objects
 */
function link_to_opclass_map_build(affiliated_aps, radios) {
	let result = [];
	for (let ap in affiliated_aps) {
		let radio = radios?.[ap.ruid];
		let opclass = radio?.operating_classes?.[0]?.class ?? 0;
		push(result, {
			LinkID: sprintf('%d', ap.linkid ?? 0),
			OpClass: sprintf('%d', opclass)
		});
	}
	return result;
}

/**
 * Factory for converting AP MLD affiliated STA data to TR-181
 * STAMLD.AffiliatedSTA objects.
 *
 * @param {object} client_index - Associated clients keyed by BSSID then MAC
 * @returns {function} converter function (s) => TR-181 AffiliatedSTA object
 */
function stamld_affiliated_sta_to_object_factory(client_index) {
	return function(s) {
		let mac = s.affiliated_sta_mac_addr ?? "";
		let client = client_index?.[s.bssid]?.[mac] ?? {};
		let aff = client.affiliated_metrics ?? {};
		let link = client.link_metrics ?? {};
		let ext = client.extended_metrics ?? {};

		return {
			MACAddress: mac,
			BSSID: s.bssid ?? "",
			BytesSent: counter_format(aff.bytes_sent),
			BytesReceived: counter_format(aff.bytes_received),
			PacketsSent: counter_format(aff.packets_sent),
			PacketsReceived: counter_format(aff.packets_received),
			ErrorsSent: counter_format(aff.packets_sent_errors),
			SignalStrength: counter_format(link.uplink_rcpi),
			EstMACDataRateDownlink: counter_format(link.estimated_downlink_mac_data_rate),
			EstMACDataRateUplink: counter_format(link.estimated_uplink_mac_data_rate),
			LastDataDownlinkRate: counter_format(ext.last_data_downlink_rate),
			LastDataUplinkRate: counter_format(ext.last_data_uplink_rate),
			UtilizationReceive: counter_format(ext.utilization_receive),
			UtilizationTransmit: counter_format(ext.utilization_transmit)
		};
	};
}

/**
 * Factory for converting STA MLD association data to TR-181 STAMLD objects.
 *
 * @param {object|null} t2lm_entry - T2LM entry for this AP MLD
 * @param {object} link_to_bssid - linkid-to-BSSID lookup
 * @param {object} client_index - Associated clients keyed by BSSID then MAC
 * @returns {function} converter function (sta) => TR-181 STAMLD object
 */
function stamld_to_object_factory(t2lm_entry, link_to_bssid, client_index) {
	let t2lm_neg = t2lm_entry?.tid_to_link_mapping_negotiation ? "true" : "false";

	return function(sta) {
		let affiliated = sta.affiliated_stas ?? [];
		let sta_mac = sta.sta_mld_mac_addr ?? "";

		let sta_tid_link_map = [];
		for (let m in t2lm_entry?.mappings ?? [])
			if (m.sta_mld_mac_addr == sta_mac)
				for (let e in t2lm_decode_mapping(m, link_to_bssid))
					push(sta_tid_link_map, e);

		return {
			MLDMACAddress: sta_mac,
			IsbSTA: "false",
			WiFi7Capabilities: {
				EMLMRSupport: sta.emlmr ? "true" : "false",
				EMLSRSupport: sta.emlsr ? "true" : "false",
				STRSupport: sta.str ? "true" : "false",
				NSTRSupport: sta.nstr ? "true" : "false",
				TIDLinkMapNegotiation: t2lm_neg
			},
			STAMLDConfig: {
				EMLMREnabled: sta.emlmr ? "true" : "false",
				EMLSREnabled: sta.emlsr ? "true" : "false",
				STREnabled: sta.str ? "true" : "false",
				NSTREnabled: sta.nstr ? "true" : "false",
				TIDLinkMapNegotiation: t2lm_neg
			},
			STATIDLinkMapNumberOfEntries: sprintf('%d', length(sta_tid_link_map)),
			STATIDLinkMap: ubbf.enumerate_instances(sta_tid_link_map, (e) => e),
			AffiliatedSTANumberOfEntries: sprintf('%d', length(affiliated)),
			AffiliatedSTA: ubbf.enumerate_instances(affiliated,
				stamld_affiliated_sta_to_object_factory(client_index))
		};
	};
}

/**
 * Factory for converting AP MLD data to TR-181 APMLD objects.
 *
 * @param {object} api_data - device API data (for capability.tid_to_link_mapping and radios)
 * @returns {function} converter function (mld) => TR-181 APMLD object
 */
function apmld_to_object_factory(api_data) {
	let t2lm_list = api_data.capability?.tid_to_link_mapping;
	let radios = api_data.capability?.radios ?? {};
	let aff_ap_metrics = api_data.affiliated_ap_metrics ?? {};
	let client_index = api_data.client_index ?? {};

	return function(mld) {
		let affiliated_aps = mld.affiliated_aps ?? [];
		let sta_mlds = mld.sta_mld_associations ?? [];
		let mld_mac = mld.ap_mld_mac_addr ?? "";

		let t2lm_entry = t2lm_find_for_mld(t2lm_list, mld_mac, false);
		let t2lm_neg = t2lm_entry?.tid_to_link_mapping_negotiation ? "true" : "false";

		let link_to_bssid = link_bssid_build(affiliated_aps);

		let tid_link_map = [];
		for (let m in t2lm_entry?.mappings ?? [])
			if (m.sta_mld_mac_addr == "ff:ff:ff:ff:ff:ff")
				for (let e in t2lm_decode_mapping(m, link_to_bssid))
					push(tid_link_map, e);

		let link_opclass = link_to_opclass_map_build(affiliated_aps, radios);

		return {
			MLDMACAddress: mld_mac,
			TIDLinkMapNumberOfEntries: sprintf('%d', length(tid_link_map)),
			TIDLinkMap: ubbf.enumerate_instances(tid_link_map, (e) => e),
			AffiliatedAPNumberOfEntries: sprintf('%d', length(affiliated_aps)),
			AffiliatedAP: ubbf.enumerate_instances(affiliated_aps, (ap) => {
				let m = aff_ap_metrics[ap.affiliated_ap_mac_addr] ?? {};
				return {
					BSSID: ap.affiliated_ap_mac_addr ?? "",
					LinkID: sprintf('%d', ap.linkid ?? 0),
					RUID: ubbf.mac_to_base64(ap.ruid),
					DisabledSubChannels: sprintf('%d', ap.eht_operations?.disabled_subchannel_bitmap ?? 0),
					PacketsSent: counter_format(m.packets_sent),
					PacketsReceived: counter_format(m.packets_received),
					ErrorsSent: counter_format(m.packet_sent_errors),
					UnicastBytesSent: counter_format(m.unicast_bytes_sent),
					UnicastBytesReceived: counter_format(m.unicast_bytes_received),
					MulticastBytesSent: counter_format(m.multicast_bytes_sent),
					MulticastBytesReceived: counter_format(m.multicast_bytes_received),
					BroadcastBytesSent: counter_format(m.broadcast_bytes_sent),
					BroadcastBytesReceived: counter_format(m.broadcast_bytes_received),
					// The Affiliated AP Metrics TLV carries no ESP fields, and
					// the only ESP value umapd produces is a BE figure
					// synthesised from channel utilisation, so there is nothing
					// truthful to report per link. Emitted empty rather than
					// omitted: this object is built from live data, so the
					// schema default fallback in dm.c never reaches it and a
					// missing key fails the Get of the whole object.
					EstServiceParametersBE: "",
					EstServiceParametersBK: "",
					EstServiceParametersVI: "",
					EstServiceParametersVO: ""
				};
			}),
			APMLDConfig: {
				EMLMREnabled: mld.emlmr ? "true" : "false",
				EMLSREnabled: mld.emlsr ? "true" : "false",
				STREnabled: mld.str ? "true" : "false",
				NSTREnabled: mld.nstr ? "true" : "false",
				TIDLinkMapNegotiation: t2lm_neg,
				TIDToOpClassPolicyNumberOfEntries: "0"
			},
			STAMLDNumberOfEntries: sprintf('%d', length(sta_mlds)),
			STAMLD: ubbf.enumerate_instances(sta_mlds,
				stamld_to_object_factory(t2lm_entry, link_to_bssid, client_index)),
			LinkToOpClassMapNumberOfEntries: sprintf('%d', length(link_opclass)),
			LinkToOpClassMap: ubbf.enumerate_instances(link_opclass, (e) => e)
		};
	};
}

/**
 * Converts bSTA MLD data to TR-181 bSTAMLD object.
 *
 * @param {object} data - bSTA MLD data from umapd get_agent bsta_mld_configuration
 * @returns {object} TR-181 formatted bSTAMLD object
 */
function bstamld_to_object(data) {
	if (!data)
		return {
			MLDMACAddress: "",
			BSSID: "",
			AffiliatedbSTAList: "",
			bSTAMLDConfig: {}
		};

	return {
		MLDMACAddress: data.bsta_mld_mac_addr ?? "",
		BSSID: data.ap_mld_mac_addr ?? "",
		AffiliatedbSTAList: join(',', map(data.affiliated_bstas ?? [],
			(b) => b.affiliated_bsta_mac_addr ?? "")),
		bSTAMLDConfig: {
			EMLMREnabled: data.emlmr ? "true" : "false",
			EMLSREnabled: data.emlsr ? "true" : "false",
			STREnabled: data.str ? "true" : "false",
			NSTREnabled: data.nstr ? "true" : "false",
			TIDLinkMapNegotiation: "false"
		}
	};
}

/**
 * Resolves stored controller policy config for a device.
 * Looks up per-device policy first, then falls back to broadcast (*).
 *
 * @param {object} easymesh - Root EasyMesh config (with ConfigPolicy populated)
 * @param {string} al_mac - Device AL MAC address
 * @returns {object|null} Parsed policy Data JSON or null
 */
function config_policy_resolve(easymesh, al_mac) {
	return easymesh?.ConfigPolicy?.[al_mac] ?? easymesh?.ConfigPolicy?.['*'];
}

/**
 * Converts device data to TR-181 Device object format.
 *
 * @param {object} device - Device data from topology
 * @param {object} api_data - API data for the device
 * @param {boolean} is_controller - Whether this device is the colocated controller
 * @param {object} easymesh - Root EasyMesh config for operator policy data
 * @param {object} device_cfg - Per-device configuration entries
 * @param {object} ieee1905_idx - Map of AL MAC to 1-based IEEE1905Device index
 * @returns {object} TR-181 formatted Device object
 */
export function device_to_object(device, api_data, is_controller, easymesh, device_cfg, ieee1905_idx) {
	api_data ??= {};
	api_data.ap_metrics = device.map?.ap_metrics ?? [];
	api_data.ap_extended_metrics = device.map?.ap_extended_metrics ?? [];
	let associated_clients = {};
	let affiliated_ap_metrics = {};
	let client_index = {};
	for (let radio in device.map?.ap_operational_bss ?? []) {
		for (let bss in radio.bss ?? []) {
			if (bss.affiliated_ap_metrics)
				affiliated_ap_metrics[bss.mac_address] = bss.affiliated_ap_metrics;

			if (!bss.associated_clients || !length(bss.associated_clients))
				continue;

			associated_clients[bss.mac_address] = bss.associated_clients;
			let by_mac = (client_index[bss.mac_address] = {});
			for (let client in bss.associated_clients) {
				let sta_mac = client.mac_address ?? client.mac;
				if (sta_mac)
					by_mac[sta_mac] = client;
			}
		}
	}
	api_data.associated_clients = associated_clients;
	api_data.affiliated_ap_metrics = affiliated_ap_metrics;
	api_data.client_index = client_index;
	api_data.sta_capabilities = client_capabilities_get(api_data.associated_clients, api_data._ubus_object);
	api_data.bss_configuration_report = device.map?.bss_configuration_report ?? [];
	api_data.backhaul_bss_configuration = device.map?.backhaul_bss_configuration ?? [];
	api_data.association_status = device.map?.association_status ?? [];
	api_data.qos_management_descriptors = device.map?.qos_management_descriptors ?? [];
	let ident = device.identification ?? {};
	let caps = device.map?.capabilities ?? {};
	let capability = api_data.capability ?? {};
	let radios = sort([...(device.map?.ap_operational_bss ?? [])],
		(a, b) => radio_band_priority(a, capability) - radio_band_priority(b, capability));
	let policy = api_data.policy?.policy ?? {};
	let config_policy = config_policy_resolve(easymesh, device.al_address);
	if (config_policy) {
		for (let key in [ 'metric_reporting', 'steering', 'channel_scan_reporting', 'agent_steering' ]) {
			if (!config_policy[key])
				continue;
			if (!policy[key]) {
				policy[key] = config_policy[key];
				continue;
			}
			for (let field, val in config_policy[key])
				policy[key][field] ??= val;
		}
	}
	let backhaul = api_data.backhaul?.backhaul ?? {};
	let bh_stats = backhaul?.traffic_stats;
	let traffic_sep = api_data.traffic_sep ?? {};
	let downstream = api_data.backhaul?.downstream ?? [];

	let service_prio = api_data.service_prio ?? {};
	let security_1905 = api_data.security_1905 ?? {};
	let cac_status = capability.cac_status ?? {};

	let cac_available = cac_status.available_channels ?? [];
	let cac_non_occupancy = cac_status.radar_detected_channels ?? [];
	let cac_active = cac_status.active_cac_channels ?? [];
	let has_cac_data = length(cac_available) > 0 || length(cac_non_occupancy) > 0 || length(cac_active) > 0;
	let backhaul_radio = backhaul_operating_class_get(api_data, backhaul?.mac_address);

	let acu_reports = api_data.anticipated_channel_usage?.reports ?? [];
	let anticipated_channels = anticipated_channels_build(acu_reports);
	let anticipated_usage = acu_reports;
	let ap_mld_list = values(api_data.ap_mld?.ap_mlds ?? {});

	return {
		ID: device.al_address ?? "",
		MultiAPCapabilities: multiap_capabilities_encode(capability.ap_capability),
		CollectionInterval: sprintf('%d', policy?.metric_reporting?.collection_interval ?? 0),
		ReportUnsuccessfulAssociations: policy?.metric_reporting?.report_unsuccessful_associations ? "true" : "false",
		MaxReportingRate: sprintf('%d', policy?.metric_reporting?.max_reporting_rate ?? 0),
		APMetricsReportingInterval: sprintf('%d', policy?.metric_reporting?.ap_metrics_interval ?? 0),
		AssociatedSTAReportingInterval: sprintf('%d', policy?.metric_reporting?.sta_metrics_interval ?? 0),
		Manufacturer: ident.manufacturer_name ?? "",
		SerialNumber: ident.serial_number ?? "",
		ManufacturerModel: ident.manufacturer_model ?? "",
		SoftwareVersion: ident.software_version ?? "",
		ExecutionEnv: ident.execution_env ?? "",
		DSCPMap: ubbf.dscp_map_to_hex(service_prio.dscp_mapping_table),
		MaxPrioritizationRules: sprintf('%d', caps.max_prioritization_rules ?? 0),
		PrioritizationSupport: caps.supports_prioritization ? "true" : "false",
		MaxVIDs: sprintf('%d', caps.max_unique_vids ?? 0),
		CountryCode: device.country_code ?? "",
		LocalSteeringDisallowedSTAList: join(',', policy?.steering?.local_steering_disallowed ?? []),
		BTMSteeringDisallowedSTAList: join(',', policy?.steering?.btm_steering_disallowed ?? []),
		DFSEnable: "false",
		ReportIndependentScans: policy?.channel_scan_reporting?.report_independent_scans ? "true" : "false",
		MaxUnsuccessfulAssociationReportingRate: sprintf('%d', policy?.unsuccessful_association?.max_reporting_rate ?? 0),
		STASteeringState: policy?.agent_steering?.disallowed ? "true" : "false",
		CoordinatedCACAllowed: policy?.steering?.coordinated_cac_allowed ? "true" : "false",
		TrafficSeparationAllowed: caps.supports_traffic_separation ? "true" : "false",
		ServicePrioritizationAllowed: caps.supports_prioritization ? "true" : "false",
		ControllerOperationMode: is_controller ? "Running" : "NotSupported",
		BackhaulMACAddress: backhaul?.upstream_mac ?? "",
		BackhaulALID: backhaul?.upstream_al_id ?? "",
		BackhaulDownMACAddress: downstream[0]?.mac_address ?? "",
		BackhaulMediaType: media_type_code_to_name(backhaul?.media_type_code),
		BackhaulPHYRate: sprintf('%d', backhaul?.phy_rate ?? 0),
		TrafficSeparationCapability: caps.supports_traffic_separation ? "true" : "false",
		EasyConnectCapability: caps.supports_dpp_onboarding ? "true" : "false",
		TestCapabilities: sprintf('%d', capability?.test_capabilities ?? 0),
		RadioNumberOfEntries: sprintf('%d', length(radios)),
		Radio: ubbf.enumerate_instances(radios, radio_to_object_factory(api_data, device.al_address, easymesh, device_cfg)),
		Default8021QNumberOfEntries: traffic_sep.primary_vlan_id ? "1" : "0",
		SSIDtoVIDMappingNumberOfEntries: sprintf('%d', length(keys(traffic_sep.ssid_vlan_mappings ?? {}))),
		SSIDtoVIDMapping: ubbf.enumerate_instances(
			keys(traffic_sep.ssid_vlan_mappings ?? {}),
			(ssid) => ssid_vid_mapping_to_object(ssid, traffic_sep.ssid_vlan_mappings[ssid])
		),
		Default8021Q: traffic_sep.primary_vlan_id ? {
			"1": {
				Enable: traffic_sep.enabled ? "true" : "false",
				PrimaryVID: sprintf('%d', traffic_sep.primary_vlan_id),
				DefaultPCP: sprintf('%d', traffic_sep.default_pcp ?? 0)
			}
		} : {},
		CACStatusNumberOfEntries: has_cac_data ? "1" : "0",
		CACStatus: has_cac_data ? {
			"1": {
				TimeStamp: ubbf.iso8601_format(),
				CACAvailableChannelNumberOfEntries: sprintf('%d', length(cac_available)),
				CACAvailableChannel: ubbf.enumerate_instances(cac_available, (ch) => ({
					OpClass: sprintf('%d', ch.opclass ?? 0),
					Channel: sprintf('%d', ch.channel ?? 0),
					Minutes: sprintf('%d', ch.minutes ?? 0)
				})),
				CACNonOccupancyChannelNumberOfEntries: sprintf('%d', length(cac_non_occupancy)),
				CACNonOccupancyChannel: ubbf.enumerate_instances(cac_non_occupancy, (ch) => ({
					OpClass: sprintf('%d', ch.opclass ?? 0),
					Channel: sprintf('%d', ch.channel ?? 0),
					Seconds: sprintf('%d', ch.seconds ?? 0)
				})),
				CACActiveChannelNumberOfEntries: sprintf('%d', length(cac_active)),
				CACActiveChannel: ubbf.enumerate_instances(cac_active, (ch) => ({
					OpClass: sprintf('%d', ch.opclass ?? 0),
					Channel: sprintf('%d', ch.channel ?? 0),
					Countdown: sprintf('%d', ch.countdown ?? 0)
				}))
			}
		} : {},
		IEEE1905SecurityNumberOfEntries: sprintf('%d', length(security_1905.associations ?? [])),
		IEEE1905Security: ubbf.enumerate_instances(
			security_1905.associations ?? [],
			ieee1905_security_to_object
		),
		SPRuleNumberOfEntries: sprintf('%d', length(service_prio.rules ?? [])),
		SPRule: ubbf.enumerate_instances(service_prio.rules ?? [], (rule) => ({
			ID: sprintf('%d', rule.rule_id ?? 0),
			Precedence: sprintf('%d', rule.precedence ?? 0),
			Output: sprintf('%d', rule.output ?? 0),
			AlwaysMatch: rule.always_match ? "true" : "false"
		})),
		AnticipatedChannelsNumberOfEntries: sprintf('%d', length(anticipated_channels)),
		AnticipatedChannels: ubbf.enumerate_instances(anticipated_channels, (ac) => ({
			OpClass: sprintf('%d', ac.opclass),
			ChannelList: join(',', ac.channels)
		})),
		AnticipatedChannelUsageNumberOfEntries: sprintf('%d', length(anticipated_usage)),
		AnticipatedChannelUsage: ubbf.enumerate_instances(anticipated_usage, (au) => ({
			OpClass: sprintf('%d', au.opclass ?? 0),
			Channel: sprintf('%d', au.channel ?? 0),
			ReferenceBSSID: au.reference_bssid ?? "",
			EntryNumberOfEntries: sprintf('%d', length(au.usage_entries ?? [])),
			Entry: ubbf.enumerate_instances(au.usage_entries ?? [], (e) => ({
				BurstStartTime: e.burst_start_time ?? "",
				BurstLength: sprintf('%d', e.burst_length ?? 0),
				Repetitions: sprintf('%d', e.repetitions ?? 0),
				BurstInterval: sprintf('%d', e.burst_interval ?? 0),
				RUBitmask: e.ru_bitmask ?? "",
				TransmitterIdentifier: e.transmitter_identifier ?? "",
				PowerLevel: sprintf('%d', e.power_level ?? 0),
				ChannelUsageReason: channel_usage_reason_name(e.channel_usage_reason)
			}))
		})),
		MaxNumMLDs: sprintf('%d', capability?.wifi7_capabilities?.max_num_mlds ?? 0),
		APMLDMaxLinks: sprintf('%d', capability?.wifi7_capabilities?.ap_max_links ?? 0),
		bSTAMLDMaxLinks: sprintf('%d', capability?.wifi7_capabilities?.bsta_max_links ?? 0),
		TIDLinkMapCapability: sprintf('%d', capability?.wifi7_capabilities?.tid_to_link_mapping_capability ?? 0),
		APMLDNumberOfEntries: sprintf('%d', length(ap_mld_list)),
		APMLD: ubbf.enumerate_instances(ap_mld_list, apmld_to_object_factory(api_data)),
		bSTAMLD: bstamld_to_object(api_data.bsta_mld?.bsta_mld),
		BackhaulDownNumberOfEntries: sprintf('%d', length(downstream)),
		BackhaulDown: ubbf.enumerate_instances(downstream, (entry) => ({
			BackhaulDownALID: entry.al_id ?? "",
			BackhaulDownMACAddress: entry.mac_address ?? ""
		})),
		MultiAPDevice: {
			LastContactTime: capability.last_contact_time
				? ubbf.iso8601_format(time() - (clock(true)[0] - capability.last_contact_time / 1000))
				: "",
			AssocIEEE1905DeviceRef: ieee1905_idx?.[device.al_address]
				? `Device.IEEE1905.AL.NetworkTopology.IEEE1905Device.${ieee1905_idx[device.al_address]}.`
				: "",
			EasyMeshControllerOperationMode: is_controller ? "Running" : "NotSupported",
			EasyMeshAgentOperationMode: "Running",
			Backhaul: {
				LinkType: (is_controller && backhaul?.media_type_code == null)
					? "None"
					: media_type_code_to_link_type(backhaul?.media_type_code),
				BackhaulMACAddress: backhaul?.upstream_mac ?? "",
				BackhaulDeviceID: backhaul?.upstream_al_id ?? "",
				MACAddress: backhaul?.mac_address ?? "",
				CurrentOperatingClassProfileNumberOfEntries: sprintf('%d', length(backhaul_radio.operating_classes)),
				CurrentOperatingClassProfile: ubbf.enumerate_instances(backhaul_radio.operating_classes, (oc) => ({
					Class: sprintf('%d', oc.class ?? 0),
					Channel: sprintf('%d', oc.channel ?? 0),
					TxPower: sprintf('%d', backhaul_radio.eirp),
					TimeStamp: ubbf.iso8601_format()
				})),
				Stats: {
					BytesSent: bh_stats ? sprintf('%d', bh_stats.bytes_sent) : "0",
					BytesReceived: bh_stats ? sprintf('%d', bh_stats.bytes_received) : "0",
					PacketsSent: bh_stats ? sprintf('%d', bh_stats.packets_sent) : "0",
					PacketsReceived: bh_stats ? sprintf('%d', bh_stats.packets_received) : "0",
					ErrorsSent: bh_stats ? sprintf('%d', bh_stats.errors_sent) : "0",
					ErrorsReceived: bh_stats ? sprintf('%d', bh_stats.errors_received) : "0",
					LinkUtilization: sprintf('%d', backhaul?.link_utilization ?? 0),
					SignalStrength: sprintf('%d', backhaul?.rssi ?? 0),
					LastDataDownlinkRate: sprintf('%d', backhaul?.phy_rate ?? 0),
					LastDataUplinkRate: sprintf('%d', backhaul?.uplink_rate ?? 0),
					TimeStamp: bh_stats ? ubbf.iso8601_format() : ""
				}
			}
		}
	};
};

export { client_capabilities_get };
