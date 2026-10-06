'use strict';

import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { unlink, writefile } from 'fs';
import { log_info, log_warn } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';
import * as wifi_schemas from 'ubbf.schemas.WiFi';
import {
	ubus_topology_get, device_api_data_get, radio_band_priority
} from 'ubbf.utils.wifi-dataelements';

let topology_devices_get;

/**
 * Initializes the operations module with required dependencies.
 *
 * @param {function} fn - Function to get topology devices
 */
export function set_topology_devices_get(fn) {
	topology_devices_get = fn;
};

/**
 * Returns sorted radios for a device, matching DM instance order.
 *
 * @param {object} device - Device from topology
 * @returns {array} Sorted radio array from ap_operational_bss
 */
function device_radios_sorted(device) {
	let al_mac = device.al_address;
	let api_data = device_api_data_get(al_mac, true);
	let capability = api_data?.capability ?? {};
	return sort([...(device.map?.ap_operational_bss ?? [])],
		(a, b) => radio_band_priority(a, capability) - radio_band_priority(b, capability));
}

/**
 * Converts TR-181 band specification to OpenWrt band format.
 *
 * @param {string} tr181_bands - Comma-separated TR-181 band values
 * @returns {array} Array of OpenWrt band strings (2g, 5g, 6g)
 */
function band_convert(tr181_bands) {
	let bands = ubbf.csv_to_list(tr181_bands);
	if (length(bands) == 0)
		return ['2g', '5g'];

	let result = [];
	for (let band in bands) {
		switch (band) {
		case 'All':
			return ['2g', '5g', '6g'];
		case '2.4':
			push(result, '2g');
			break;
		case '5':
		case '5_UNII_1':
		case '5_UNII_2':
		case '5_UNII_3':
		case '5_UNII_4':
			if (index(result, '5g') < 0)
				push(result, '5g');
			break;
		case '6':
		case '6_UNII_5':
		case '6_UNII_6':
		case '6_UNII_7':
		case '6_UNII_8':
			if (index(result, '6g') < 0)
				push(result, '6g');
			break;
		}
	}
	return length(result) > 0 ? result : ['2g', '5g'];
}

/**
 * Converts TR-181 AKM specification to OpenWrt authentication format.
 *
 * @param {string} tr181_akms - Comma-separated TR-181 AKM values
 * @returns {array} Array of OpenWrt authentication strings
 */
function akm_convert(tr181_akms) {
	let akms = ubbf.csv_to_list(tr181_akms);
	if (length(akms) == 0)
		return ['open'];

	let result = [];
	for (let akm in akms) {
		switch (akm) {
		case 'psk':
			push(result, 'psk2');
			break;
		case 'sae':
			push(result, 'sae');
			break;
		case 'psk+sae':
			push(result, 'psk2');
			push(result, 'sae');
			break;
		case 'dpp':
		case 'dpp+sae':
		case 'dpp+psk+sae':
			push(result, 'sae');
			break;
		case 'owe':
			push(result, 'owe');
			break;
		default:
			log_warn('akm_convert: unrecognized AKM value: %s', akm);
			break;
		}
	}
	return length(result) > 0 ? result : ['open'];
}

/**
 * Parses TR-181 haul type specification.
 *
 * @param {string} tr181_haul - Comma-separated haul type values
 * @returns {object} Object with fronthaul and backhaul boolean flags
 */
function haul_type_parse(tr181_haul) {
	let hauls = ubbf.csv_to_list(tr181_haul);
	let fronthaul = false;
	let backhaul = false;

	for (let h in hauls) {
		if (h == 'Fronthaul')
			fronthaul = true;
		else if (h == 'Backhaul')
			backhaul = true;
	}

	if (!fronthaul && !backhaul)
		fronthaul = true;

	return { fronthaul, backhaul };
}

/**
 * Async operation handler for SetServicePrioritization.
 *
 * @param {object} input - Operation input with Enable, SPRule.{i}.*, DSCPMap
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_service_prioritization_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	if (input.Enable == null) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Enable parameter is mandatory', null);
		return;
	}

	let enabled = ubbf.to_bool(input.Enable);
	let rules = [];

	for (let key, value in input) {
		let m = match(key, /^SPRule\.(\d+)\.ID$/);
		if (!m)
			continue;

		let idx = m[1];
		let rule_id = int(value);
		let precedence = int(input[`SPRule.${idx}.Precedence`] ?? '0');
		let output_val = int(input[`SPRule.${idx}.Output`] ?? '0');
		let always_match = ubbf.to_bool(input[`SPRule.${idx}.AlwaysMatch`] ?? 'false');

		push(rules, {
			rule_id,
			precedence,
			output: output_val,
			always_match
		});
	}

	let dscp_mapping_table = input.DSCPMap ?? "";

	root.EasyMesh ??= {};
	root.EasyMesh.ServicePrioritization = {
		enabled,
		rules,
		dscp_mapping_table
	};

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetPreferredBackhauls (stub).
 *
 * @param {object} input - Operation input parameters
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 */
function set_preferred_backhauls_handler(input, instance, complete) {
	complete(instance, USP_ERR_COMMAND_FAILURE, 'Not implemented', null);
}

/**
 * Async operation handler for SetTrafficSeparation.
 *
 * @param {object} input - Operation input with Enable and SSIDtoVIDMapping
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_traffic_separation_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	if (input.Enable == null) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Enable parameter is mandatory', null);
		return;
	}

	let enabled = ubbf.to_bool(input.Enable);
	let mappings = {};

	for (let key, value in input) {
		let m = match(key, /^SSIDtoVIDMapping\.(\d+)\.SSID$/);
		if (!m)
			continue;

		let idx = m[1];
		let ssid = value;
		let vid = int(input[`SSIDtoVIDMapping.${idx}.VID`]);

		if (!ssid) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'SSID is required in mapping', null);
			return;
		}
		// EasyMesh secondary-haul VIDs must avoid the reserved low IDs and
		// stay below the 802.1Q ceiling (4095); see EasyMesh spec Traffic
		// Separation policy
		if (vid == null || vid < 3 || vid > 4094) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'VID must be 3-4094', null);
			return;
		}
		mappings[ssid] = vid;
	}

	let primary_vid = root.EasyMesh?.TrafficSeparation?.primary_vid;
	if (input['X_UBBF_PrimaryVLANID'] != null) {
		let vid = int(input['X_UBBF_PrimaryVLANID']);
		if (vid == 0) {
			primary_vid = null;
		} else if (vid >= 3 && vid <= 4094) {
			primary_vid = vid;
		} else {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'X_UBBF_PrimaryVLANID must be 0 or 3-4094', null);
			return;
		}
	}

	root.EasyMesh ??= {};
	root.EasyMesh.TrafficSeparation = {
		enabled: enabled,
		primary_vid: primary_vid,
		ssid_vid_mappings: mappings
	};

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Finds SSID entry index in array by name.
 *
 * @param {array} ssids - Array of SSID entries
 * @param {string} ssid_name - SSID name to search for
 * @returns {number} Index of matching entry or -1 if not found
 */
function ssid_entry_find(ssids, ssid_name) {
	for (let i = 0; i < length(ssids); i++)
		if (ssids[i].ssid == ssid_name)
			return i;
	return -1;
}

/**
 * Creates an SSID entry for EasyMesh configuration.
 *
 * EasyMesh and non-EasyMesh deployments hold SSIDs in different shapes:
 * EasyMesh keeps a flat array under root.EasyMesh.SSIDs (this helper),
 * while non-EasyMesh stores TR-181 Device.WiFi.SSID objects via
 * wifi_ssid_entry_create/update. Set handlers pick the correct pair based
 * on whether the EasyMesh Controller is enabled.
 *
 * @param {object} input - SetSSID input parameters
 * @returns {object} SSID entry object for EasyMesh.SSIDs array
 */
function ssid_entry_create(input) {
	let haul = haul_type_parse(input.HaulType);
	return {
		ssid: input.SSID,
		key: input.PassPhrase ?? null,
		authentication: akm_convert(input.AKMsAllowed),
		band: band_convert(input.Band),
		hidden: input.AdvertisementEnabled != null ? !ubbf.to_bool(input.AdvertisementEnabled) : null,
		fronthaul: haul.fronthaul,
		backhaul: haul.backhaul,
		enabled: input.Enable != null ? ubbf.to_bool(input.Enable) : true,
		type: input.Type ?? null,
		mfp_config: input.MFPConfig ?? null,
		suite_selector: input.SuiteSelector ?? null,
		mobility_domain: input.MobilityDomain ?? null
	};
}

/**
 * Updates an existing EasyMesh.SSIDs entry with new values.
 *
 * Counterpart of ssid_entry_create for the EasyMesh storage shape; see that
 * function for why the EasyMesh and non-EasyMesh paths are split.
 *
 * @param {object} existing - Existing SSID entry
 * @param {object} input - SetSSID input parameters with changes
 * @returns {object} Updated SSID entry object
 */
function ssid_entry_update(existing, input) {
	let updated = { ...existing };
	if (input.PassPhrase != null)
		updated.key = input.PassPhrase;
	if (input.AKMsAllowed != null)
		updated.authentication = akm_convert(input.AKMsAllowed);
	if (input.Band != null)
		updated.band = band_convert(input.Band);
	if (input.AdvertisementEnabled != null)
		updated.hidden = !ubbf.to_bool(input.AdvertisementEnabled);
	if (input.HaulType != null) {
		let haul = haul_type_parse(input.HaulType);
		updated.fronthaul = haul.fronthaul;
		updated.backhaul = haul.backhaul;
	}
	if (input.Enable != null)
		updated.enabled = ubbf.to_bool(input.Enable);
	if (input.Type != null)
		updated.type = input.Type;
	if (input.MFPConfig != null)
		updated.mfp_config = input.MFPConfig;
	if (input.SuiteSelector != null)
		updated.suite_selector = input.SuiteSelector;
	if (input.MobilityDomain != null)
		updated.mobility_domain = input.MobilityDomain;
	return updated;
}

/**
 * Converts TR-181 AKM values to TR-181 ModeEnabled value.
 *
 * @param {string} tr181_akms - Comma-separated TR-181 AKM values
 * @returns {string} TR-181 ModeEnabled value
 */
function akm_to_mode_enabled(tr181_akms) {
	let akms = ubbf.csv_to_list(tr181_akms);
	if (length(akms) == 0)
		return 'None';

	let has_psk = index(akms, 'psk') >= 0;
	let has_sae = index(akms, 'sae') >= 0;
	let has_psk_sae = index(akms, 'psk+sae') >= 0;

	if (has_psk_sae || (has_psk && has_sae))
		return 'WPA3-Personal-Transition';
	if (has_sae)
		return 'WPA3-Personal';
	if (has_psk)
		return 'WPA2-Personal';

	return 'None';
}

/**
 * Finds a radio path by frequency band.
 *
 * @param {object} root - Root configuration object
 * @param {string} band - Band identifier (e.g., "2.4", "5", "6")
 * @returns {string|null} TR-181 radio path or null if not found
 */
function radio_by_band_find(root, band) {
	let radios = root.Device?.WiFi?.Radio;
	if (!radios)
		return null;

	let target_band;
	switch (band) {
	case '2.4':
		target_band = '2.4GHz';
		break;
	case '5':
	case '5_UNII_1':
	case '5_UNII_2':
	case '5_UNII_3':
	case '5_UNII_4':
		target_band = '5GHz';
		break;
	case '6':
	case '6_UNII_5':
	case '6_UNII_6':
	case '6_UNII_7':
	case '6_UNII_8':
		target_band = '6GHz';
		break;
	default:
		target_band = '2.4GHz';
	}

	for (let inst, radio in radios) {
		if (radio.OperatingFrequencyBand == target_band)
			return `Device.WiFi.Radio.${inst}`;
	}
	return null;
}

/**
 * Finds an SSID entry by name in Device.WiFi.SSID.
 *
 * @param {object} root - Root configuration object
 * @param {string} ssid_name - SSID name to search for
 * @returns {object|null} Object with inst and data, or null if not found
 */
function ssid_by_name_find(root, ssid_name) {
	let ssids = root.Device?.WiFi?.SSID;
	if (!ssids)
		return null;

	for (let inst, ssid in ssids) {
		if (ssid.SSID == ssid_name)
			return { inst, data: ssid };
	}
	return null;
}

/**
 * Finds an AccessPoint entry by SSID reference.
 *
 * @param {object} root - Root configuration object
 * @param {string} ssid_inst - SSID instance number
 * @returns {object|null} Object with inst and data, or null if not found
 */
function ap_by_ssid_ref_find(root, ssid_inst) {
	let aps = root.Device?.WiFi?.AccessPoint;
	if (!aps)
		return null;

	let ssid_path = `Device.WiFi.SSID.${ssid_inst}`;
	for (let inst, ap in aps) {
		if (ap.SSIDReference == ssid_path)
			return { inst, data: ap };
	}
	return null;
}

/**
 * Creates a Device.WiFi.SSID entry from SetSSID input.
 *
 * @param {object} input - SetSSID input parameters
 * @param {string} radio_path - TR-181 radio path for LowerLayers
 * @returns {object} Device.WiFi.SSID entry object
 */
function wifi_ssid_entry_create(input, radio_path) {
	return {
		...wifi_schemas.SSID.defaults,
		Enable: input.Enable != null ? (ubbf.to_bool(input.Enable) ? 'true' : 'false') : 'true',
		Alias: ubbf.alias_from_name(input.SSID),
		LowerLayers: radio_path,
		SSID: input.SSID
	};
}

/**
 * Updates a Device.WiFi.SSID entry with new values.
 *
 * @param {object} existing - Existing SSID entry
 * @param {object} input - SetSSID input parameters with changes
 * @param {object} root - Root configuration object
 * @returns {object} Updated SSID entry object
 */
function wifi_ssid_entry_update(existing, input, root) {
	let updated = { ...wifi_schemas.SSID.defaults, ...existing };

	if (input.Enable != null)
		updated.Enable = ubbf.to_bool(input.Enable) ? 'true' : 'false';

	if (input.Band != null) {
		let bands = ubbf.csv_to_list(input.Band);
		if (length(bands) > 0) {
			let radio_path = radio_by_band_find(root, bands[0]);
			if (radio_path)
				updated.LowerLayers = radio_path;
		}
	}
	return updated;
}

/**
 * Creates a Device.WiFi.AccessPoint entry from SetSSID input.
 *
 * @param {object} input - SetSSID input parameters
 * @param {string} ssid_path - TR-181 SSID path for SSIDReference
 * @returns {object} Device.WiFi.AccessPoint entry object
 */
function wifi_ap_entry_create(input, ssid_path) {
	let security = {
		...wifi_schemas.AccessPoint_Security.defaults,
		ModeEnabled: akm_to_mode_enabled(input.AKMsAllowed),
		KeyPassphrase: input.PassPhrase ?? '',
		MFPConfig: input.MFPConfig ?? 'Disabled'
	};

	if (input.SuiteSelector != null)
		security.SuiteSelector = input.SuiteSelector;
	if (input.MobilityDomain != null)
		security.MobilityDomainID = input.MobilityDomain;

	return {
		...wifi_schemas.AccessPoint.defaults,
		Enable: input.Enable != null ? (ubbf.to_bool(input.Enable) ? 'true' : 'false') : 'true',
		Alias: ubbf.alias_from_name(input.SSID),
		SSIDReference: ssid_path,
		SSIDAdvertisementEnabled: input.AdvertisementEnabled != null ?
			(ubbf.to_bool(input.AdvertisementEnabled) ? 'true' : 'false') : 'true',
		Security: security
	};
}

/**
 * Updates a Device.WiFi.AccessPoint entry with new values.
 *
 * @param {object} existing - Existing AccessPoint entry
 * @param {object} input - SetSSID input parameters with changes
 * @returns {object} Updated AccessPoint entry object
 */
function wifi_ap_entry_update(existing, input) {
	let updated = { ...wifi_schemas.AccessPoint.defaults, ...existing };

	if (input.Enable != null)
		updated.Enable = ubbf.to_bool(input.Enable) ? 'true' : 'false';

	if (input.AdvertisementEnabled != null)
		updated.SSIDAdvertisementEnabled = ubbf.to_bool(input.AdvertisementEnabled) ? 'true' : 'false';

	if (input.AKMsAllowed != null || input.PassPhrase != null || input.MFPConfig != null ||
	    input.SuiteSelector != null || input.MobilityDomain != null) {
		updated.Security = {
			...wifi_schemas.AccessPoint_Security.defaults,
			...(updated.Security ?? {})
		};
		if (input.AKMsAllowed != null)
			updated.Security.ModeEnabled = akm_to_mode_enabled(input.AKMsAllowed);
		if (input.PassPhrase != null)
			updated.Security.KeyPassphrase = input.PassPhrase;
		if (input.MFPConfig != null)
			updated.Security.MFPConfig = input.MFPConfig;
		if (input.SuiteSelector != null)
			updated.Security.SuiteSelector = input.SuiteSelector;
		if (input.MobilityDomain != null)
			updated.Security.MobilityDomainID = input.MobilityDomain;
	}
	return updated;
}

/**
 * Handles SetSSID operation in non-EasyMesh mode.
 *
 * @param {object} input - SetSSID input parameters
 * @param {object} root - Root configuration object
 * @returns {object} Result object with success flag and optional error
 */
function set_ssid_non_easymesh(input, root) {
	root.Device ??= {};
	root.Device.WiFi ??= {};
	root.Device.WiFi.SSID ??= {};
	root.Device.WiFi.AccessPoint ??= {};

	let existing_ssid = ssid_by_name_find(root, input.SSID);

	switch (input.AddRemoveChange) {
	case 'Add':
		if (existing_ssid)
			return { success: false, error: 'SSID already exists' };

		let bands = ubbf.csv_to_list(input.Band);
		let radio_path = radio_by_band_find(root, length(bands) > 0 ? bands[0] : '2.4');
		if (!radio_path)
			return { success: false, error: 'No matching radio found for band' };

		let ssid_inst = ubbf.find_next_instance(root.Device.WiFi.SSID);
		let ssid_path = `Device.WiFi.SSID.${ssid_inst}`;
		root.Device.WiFi.SSID[ssid_inst] = wifi_ssid_entry_create(input, radio_path);

		let ap_inst = ubbf.find_next_instance(root.Device.WiFi.AccessPoint);
		root.Device.WiFi.AccessPoint[ap_inst] = wifi_ap_entry_create(input, ssid_path);
		break;

	case 'Remove':
		if (!existing_ssid)
			return { success: false, error: 'SSID not found' };

		let ap_to_remove = ap_by_ssid_ref_find(root, existing_ssid.inst);
		if (ap_to_remove)
			delete root.Device.WiFi.AccessPoint[ap_to_remove.inst];
		delete root.Device.WiFi.SSID[existing_ssid.inst];
		break;

	case 'Change':
		if (!existing_ssid)
			return { success: false, error: 'SSID not found' };

		root.Device.WiFi.SSID[existing_ssid.inst] =
			wifi_ssid_entry_update(existing_ssid.data, input, root);

		let ap_to_update = ap_by_ssid_ref_find(root, existing_ssid.inst);
		if (ap_to_update) {
			root.Device.WiFi.AccessPoint[ap_to_update.inst] =
				wifi_ap_entry_update(ap_to_update.data, input);
		}
		break;

	default:
		return { success: false, error: 'Invalid AddRemoveChange value' };
	}
	return { success: true };
}

/**
 * Async operation handler for SetSSID.
 *
 * @param {object} input - Operation input with SSID, AddRemoveChange, etc.
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_ssid_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!input.SSID || !input.AddRemoveChange) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Missing mandatory parameters', null);
		return;
	}

	if (length(input.SSID) < 1 || length(input.SSID) > 32) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'SSID must be 1-32 characters', null);
		return;
	}

	if (controller_enabled) {
		root.EasyMesh ??= {};
		root.EasyMesh.SSIDs ??= [];
		let existing_idx = ssid_entry_find(root.EasyMesh.SSIDs, input.SSID);

		switch (input.AddRemoveChange) {
		case 'Add':
			if (existing_idx >= 0) {
				complete(instance, USP_ERR_INVALID_ARGUMENTS, 'SSID already exists', null);
				return;
			}
			push(root.EasyMesh.SSIDs, ssid_entry_create(input));
			break;
		case 'Remove':
			if (existing_idx < 0) {
				complete(instance, USP_ERR_INVALID_ARGUMENTS, 'SSID not found', null);
				return;
			}
			splice(root.EasyMesh.SSIDs, existing_idx, 1);
			break;
		case 'Change':
			if (existing_idx < 0) {
				complete(instance, USP_ERR_INVALID_ARGUMENTS, 'SSID not found', null);
				return;
			}
			root.EasyMesh.SSIDs[existing_idx] = ssid_entry_update(
				root.EasyMesh.SSIDs[existing_idx], input);
			break;
		default:
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid AddRemoveChange value', null);
			return;
		}
	} else if (!agent_enabled) {
		let result = set_ssid_non_easymesh(input, root);
		if (!result.success) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, result.error, null);
			return;
		}
	} else {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'SetSSID not supported when only EasyMesh Agent is enabled', null);
		return;
	}

	log_info('SetSSID: %s SSID=%s', input.AddRemoveChange, input.SSID);
	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetMSCSDisallowed.
 *
 * @param {object} input - Operation input with MSCSDisallowedStaList
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_mscs_disallowed_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	let sta_list = ubbf.csv_to_list(input.MSCSDisallowedStaList ?? '');

	root.EasyMesh ??= {};
	root.EasyMesh.QoSManagement ??= {};
	root.EasyMesh.QoSManagement.mscs_disallowed_sta = sta_list;

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetSCSDisallowed.
 *
 * @param {object} input - Operation input with SCSDisallowedStaList
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_scs_disallowed_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	let sta_list = ubbf.csv_to_list(input.SCSDisallowedStaList ?? '');

	root.EasyMesh ??= {};
	root.EasyMesh.QoSManagement ??= {};
	root.EasyMesh.QoSManagement.scs_disallowed_sta = sta_list;

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for ChannelScanRequest.
 *
 * @param {object} input - Operation input with OpClass and ChannelList
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device_instance, radio_instance]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function channel_scan_request_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let al_mac = device.al_address;
	let ruid = radio.radio_unique_identifier;

	// The operation belongs to one radio, and the controller reads an empty
	// radio map as every radio of the device; an empty class list is every
	// class of the radio named.
	let scan_radios = { [ruid]: [] };
	if (input.OpClass != null) {
		let opclass_entry = { opclass: int(input.OpClass) };
		if (input.ChannelList)
			opclass_entry.channels = map(ubbf.csv_to_list(input.ChannelList), (c) => int(c));
		scan_radios[ruid] = [opclass_entry];
	}

	let umap_obj = controller_enabled ? 'umap' : 'umap-agent';
	let result = ubus.call(umap_obj, 'initiate_scan', {
		macaddress: al_mac,
		radios: scan_radios
	});

	if (!result) {
		let err = ubus.error();
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Scan initiation failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, {});
}

/**
 * Async operation handler for InitiateWPSPBC.
 *
 * @param {object} input - Operation input parameters (none expected)
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device_instance]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function initiate_wps_pbc_handler(input, instance, complete, instances, command_key, root) {
	let device_instance = instances[0];
	let network = root.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);

	if (controller_enabled) {
		let devices = topology_devices_get(root);
		let device = ubbf.get_by_instance(devices, device_instance);
		if (!device) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
			return;
		}

		let topology = ubus_topology_get();
		if (device.al_address != topology.colocated_agent_id) {
			complete(instance, USP_ERR_COMMAND_FAILURE,
				'Only supported on local agent device', null);
			return;
		}
	}

	let rc = system('ACTION=released SEEN=1 /etc/rc.button/wps');
	if (rc != 0) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'WPS PBC trigger failed',
			{ Status: 'Error_Other' });
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

const AGENT_STOP_POLL_MS = 250;
const AGENT_STOP_TIMEOUT_MS = 60000;
const AGENT_STATE_FILE = '/etc/umap-agent.json';
const AGENT_RESET_INVALID_MSG = 'Agent reset: invalid DPP bootstrap key input';
const BOOTSTRAP_HEX_FIELDS = ['privkey', 'pubkey_x', 'pubkey_y', 'hash'];

/**
 * Builds the umapd `dpp_bootstrap` key from the Reset() input.
 *
 * @param {object} input - Operation input parameters
 * @returns {?object} Key with hex fields, or null when no key field is given
 */
function agent_reset_bootstrap_get(input) {
	if (!input.curve && !length(filter(BOOTSTRAP_HEX_FIELDS, field => input[field])))
		return null;

	return {
		privkey: input.privkey,
		pubkey_x: input.pubkey_x,
		pubkey_y: input.pubkey_y,
		curve: input.curve ?? 'P-256',
		hash: input.hash,
	};
}

/**
 * Converts a bootstrap key to the lower case hex form that umapd stores.
 *
 * @param {object} bootstrap - Key from agent_reset_bootstrap_get()
 * @returns {?object} Stored form, or null when a field is missing or not hex
 */
function bootstrap_stored_get(bootstrap) {
	let stored = { curve: bootstrap.curve };

	for (let field in BOOTSTRAP_HEX_FIELDS) {
		let bin = type(bootstrap[field]) == 'string' ? hexdec(bootstrap[field]) : null;
		if (!length(bin))
			return null;

		stored[field] = hexenc(bin);
	}

	return stored;
}

/**
 * Writes the umapd DPP state to the provisioning partition.
 *
 * umapd reads this store at start after its state file and prefers the key
 * it holds, so a key in the state file alone does not take effect.
 *
 * @param {?object} stored - Key from bootstrap_stored_get(), or null
 * @param {boolean} disable_dpp - Whether DPP onboarding is disabled
 */
function agent_provision_save(stored, disable_dpp) {
	let provision;

	try {
		provision = import('provision');
	} catch (e) {
		return;
	}

	let ctx = provision.open();
	if (!ctx)
		return;

	ctx.init();
	ctx.set('umap_dpp.bootstrap_key', stored);
	ctx.set('umap_dpp.disabled', disable_dpp ? true : null);
	ctx.commit();
}

/**
 * Persists the Reset() result for an agent that is not running.
 *
 * @param {?object} stored - Key from bootstrap_stored_get(), or null
 * @param {boolean} disable_dpp - Whether DPP onboarding is disabled
 */
function agent_reset_persist(stored, disable_dpp) {
	agent_provision_save(stored, disable_dpp);

	if (disable_dpp)
		writefile(AGENT_STATE_FILE, '{"dpp_disabled":true}\n');
	else if (stored)
		writefile(AGENT_STATE_FILE, sprintf('%J\n', { dpp_state: { bootstrap_key: stored } }));
	else
		unlink(AGENT_STATE_FILE);
}

/**
 * Completes the operation once umapd has released its ubus object.
 *
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {number} waited - Milliseconds already spent waiting
 */
function agent_stop_wait(instance, complete, waited) {
	if (!ubus.list('umap-agent')) {
		complete(instance, 0, null, {});
		return;
	}

	if (waited >= AGENT_STOP_TIMEOUT_MS) {
		log_warn('Agent reset: umap-agent still present after %dms, completing anyway',
		         waited);
		complete(instance, 0, null, {});
		return;
	}

	uloop.timer(AGENT_STOP_POLL_MS, function() {
		agent_stop_wait(instance, complete, waited + AGENT_STOP_POLL_MS);
	});
}

/**
 * Async operation handler for Agent Reset.
 *
 * @param {object} input - Operation input parameters
 * @param {string} [input.privkey] - DPP bootstrap private key (hex)
 * @param {string} [input.pubkey_x] - DPP bootstrap public key X coordinate (hex)
 * @param {string} [input.pubkey_y] - DPP bootstrap public key Y coordinate (hex)
 * @param {string} [input.hash] - DPP bootstrap key hash (hex)
 * @param {string} [input.curve] - DPP bootstrap key curve (default: "P-256")
 * @param {string} [input.disable_dpp] - When true, disables DPP onboarding on the agent
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function agent_reset_handler(input, instance, complete, command_key, root) {
	let network = root.Device?.WiFi?.DataElements?.Network;

	let bootstrap = agent_reset_bootstrap_get(input);
	let disable_dpp = ubbf.to_bool(input.disable_dpp);

	ubus.call('bbf-device', 'event_data_clear');

	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable)) {
		let stored = bootstrap ? bootstrap_stored_get(bootstrap) : null;
		if (bootstrap && (!stored || disable_dpp)) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, AGENT_RESET_INVALID_MSG, null);
			return;
		}

		agent_reset_persist(stored, disable_dpp);
		// procd stops the service asynchronously and offers no completion
		// event, so a disabled agent can still be running here. Reporting
		// the reset as done while umapd is still tearing the network down
		// makes the caller race against that teardown.
		agent_stop_wait(instance, complete, 0);
		return;
	}

	let args = {};
	if (bootstrap)
		args.dpp_bootstrap = bootstrap;

	if (disable_dpp)
		args.disable_dpp = true;

	ubus.call('umap-agent', 'reset', args);
	let err_code = ubus.error(true);
	if (err_code == ubus.STATUS_INVALID_ARGUMENT) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, AGENT_RESET_INVALID_MSG, null);
		return;
	}

	if (err_code) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
		         sprintf('Agent reset failed (ubus status %d)', err_code), null);
		return;
	}

	complete(instance, 0, null, {});
}

/**
 * Async operation handler for SteerWiFiBackhaul.
 * Instructs a device to move its backhaul STA to a different BSS.
 *
 * @param {object} input - Operation input parameters
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function steer_wifi_backhaul_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);

	if (!controller_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'EasyMesh Controller must be enabled', null);
		return;
	}

	if (!input.TargetBSS) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let al_mac = device.al_address;
	let agent_data = ubus.call('umap', 'get_agent', { address: al_mac });
	let sta_mac = agent_data?.backhaul_info?.backhaul?.mac_address;
	if (!sta_mac) {
		complete(instance, 0, null, { Status: 'Error_Not_Ready' });
		return;
	}

	let args = {
		al_mac,
		sta_mac,
		target_bssid: input.TargetBSS
	};
	if (input.Channel != null)
		args.target_bss_channel = int(input.Channel);

	ubus.call('umap', 'request_backhaul_steering', args);
	let err = ubus.error();
	if (err) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'request_backhaul_steering failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetSTASteeringState.
 * Stores per-device steering disallowed flag for policy distribution.
 *
 * @param {object} input - Operation input parameters
 * @param {string} input.Disallowed - Whether steering is disallowed ("true"/"false")
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_sta_steering_state_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	if (input.Disallowed == null) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let al_mac = device.al_address;
	root.EasyMesh ??= {};
	root.EasyMesh.STASteeringDisallowed ??= {};
	root.EasyMesh.STASteeringDisallowed[al_mac] = ubbf.to_bool(input.Disallowed);

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for RefreshAPMetrics.
 * Queries AP metrics for all BSSes on a device.
 *
 * @param {object} input - Operation input parameters
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function refresh_ap_metrics_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let ap_macs = [];
	for (let radio in device.map?.ap_operational_bss ?? [])
		for (let bss in radio.bss ?? [])
			if (bss.mac_address)
				push(ap_macs, bss.mac_address);

	if (length(ap_macs) == 0) {
		complete(instance, 0, null, { Status: 'Success' });
		return;
	}

	let umap_obj = controller_enabled ? 'umap' : 'umap-agent';
	ubus.call(umap_obj, 'query', { ap_macs, ap_metrics: true });
	let err = ubus.error();
	if (err) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'query failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for ChannelSelectionRequest.
 * Triggers channel selection on a specific radio.
 *
 * @param {object} input - Operation input parameters (accepted but not forwarded)
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function channel_selection_request_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let al_mac = device.al_address;
	let ruid = radio.radio_unique_identifier;

	let umap_obj = controller_enabled ? 'umap' : 'umap-agent';
	ubus.call(umap_obj, 'query', {
		al_mac,
		ruid,
		channel_selection: true
	});
	let err = ubus.error();
	if (err) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'channel_selection query failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

const CLIENT_STEER_STATUS_MAP = {
	'success': 'Success',
	'timeout': 'Error_Timeout'
};

/**
 * Async operation handler for ClientSteer.
 * Steers a STA to a target BSS via the EasyMesh controller.
 *
 * @param {object} input - Operation input parameters
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio, bss, sta]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function client_steer_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);

	if (!controller_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'EasyMesh Controller must be enabled', null);
		return;
	}

	if (!input.TargetBSSID) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];
	let bss_instance = instances[2];
	let sta_instance = instances[3];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let bss_list = radio.bss ?? [];
	let bss = ubbf.get_by_instance(bss_list, bss_instance);
	if (!bss) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'BSS not found', null);
		return;
	}

	let source_bssid = bss.mac_address;
	if (!source_bssid) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'BSS has no MAC address', null);
		return;
	}

	let sta_list = bss.associated_clients ?? [];
	let sta = ubbf.get_by_instance(sta_list, sta_instance);
	if (!sta) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'STA not found', null);
		return;
	}

	let sta_mac = sta.mac_address ?? sta.mac;
	if (!sta_mac) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'STA has no MAC address', null);
		return;
	}

	let args = {
		sta_mac,
		source_bssid,
		target_bssid: input.TargetBSSID
	};

	if (input.RequestMode == 'Steering_Mandate')
		args.request_mode = 1;
	else if (input.RequestMode == 'Steering_Opportunity')
		args.request_mode = 0;

	if (input.BTMDisassociationImminent != null)
		args.btm_disassociation_imminent = ubbf.to_bool(input.BTMDisassociationImminent) ? 1 : 0;
	if (input.BTMAbridged != null)
		args.btm_abridged = ubbf.to_bool(input.BTMAbridged) ? 1 : 0;
	if (input.SteeringOpportunityWindow != null)
		args.steering_opportunity_window = int(input.SteeringOpportunityWindow);
	if (input.BTMDisassociationTimer != null)
		args.btm_disassociation_timer = int(input.BTMDisassociationTimer);
	if (input.TargetBSSOperatingClass != null)
		args.target_bss_opclass = int(input.TargetBSSOperatingClass);
	if (input.TargetBSSChannel != null)
		args.target_bss_channel = int(input.TargetBSSChannel);

	let result = ubus.call('umap', 'client_steer', args);
	if (!result) {
		let err = ubus.error();
		complete(instance, USP_ERR_COMMAND_FAILURE, 'client_steer failed: ' + err, null);
		return;
	}

	let status = CLIENT_STEER_STATUS_MAP[result.status] ?? 'Error_Other';
	complete(instance, 0, null, { Status: status });
}

/**
 * Async operation handler for SetSpatialReuse.
 * Configures spatial reuse parameters on a specific radio.
 *
 * @param {object} input - Operation input with BSSColor, SRG params, etc.
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_spatial_reuse_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let al_mac = device.al_address;
	let ruid = radio.radio_unique_identifier;

	let args = { al_mac, ruid };

	if (input.BSSColor != null)
		args.bss_color = int(input.BSSColor);
	if (input.HESIGASpatialReuseValue15Allowed != null)
		args.hesiga_spatial_reuse_value15_allowed = ubbf.to_bool(input.HESIGASpatialReuseValue15Allowed);
	if (input.SRGInformationValid != null)
		args.srg_information_valid = ubbf.to_bool(input.SRGInformationValid);
	if (input.NonSRGOffsetValid != null)
		args.non_srg_offset_valid = ubbf.to_bool(input.NonSRGOffsetValid);
	if (input.PSRDisallowed != null)
		args.psr_disallowed = ubbf.to_bool(input.PSRDisallowed);
	if (input.NonSRGOBSSPDMaxOffset != null)
		args.non_srg_obsspd_max_offset = int(input.NonSRGOBSSPDMaxOffset);
	if (input.SRGOBSSPDMinOffset != null)
		args.srg_obsspd_min_offset = int(input.SRGOBSSPDMinOffset);
	if (input.SRGOBSSPDMaxOffset != null)
		args.srg_obsspd_max_offset = int(input.SRGOBSSPDMaxOffset);
	if (input.SRGBSSColorBitmap != null)
		args.srg_bss_color_bitmap = input.SRGBSSColorBitmap;
	if (input.SRGPartialBSSIDBitmap != null)
		args.srg_partial_bssid_bitmap = input.SRGPartialBSSIDBitmap;

	let umap_obj = controller_enabled ? 'umap' : 'umap-agent';
	ubus.call(umap_obj, 'set_spatial_reuse', args);
	let err = ubus.error();
	if (err) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'set_spatial_reuse failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Configures transmit power limit on a specific radio via policy.
 *
 * @param {object} input - Operation input with TransmitPowerLimit and OperatingClass
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_tx_power_limit_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh Controller must be enabled', null);
		return;
	}

	if (input.TransmitPowerLimit == null || input.OperatingClass == null) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let al_mac = device.al_address;
	let ruid = radio.radio_unique_identifier;
	let txpower = int(input.TransmitPowerLimit);
	let opclass = int(input.OperatingClass);

	root.EasyMesh ??= {};
	root.EasyMesh.TxPowerLimit ??= {};
	root.EasyMesh.TxPowerLimit[al_mac] ??= [];

	let entries = root.EasyMesh.TxPowerLimit[al_mac];
	let found;
	for (let i = 0; i < length(entries); i++) {
		if (entries[i].ruid == ruid && entries[i].opclass == opclass) {
			found = i;
			break;
		}
	}

	let entry = { ruid, opclass, txpower };
	if (found != null)
		entries[found] = entry;
	else
		push(entries, entry);

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetAnticipatedChannelPreference.
 * Sends anticipated channel preference to a specific device via umapd.
 *
 * @param {object} input - Operation input with OpClass and ChannelList
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_anticipated_channel_preference_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'EasyMesh must be enabled', null);
		return;
	}

	if (input.OpClass == null) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	if (input.ChannelList == null) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let al_mac = device.al_address;
	let channels = map(ubbf.csv_to_list(input.ChannelList), (c) => int(c));

	let umap_obj = controller_enabled ? 'umap' : 'umap-agent';
	ubus.call(umap_obj, 'set_anticipated_channel_preference', {
		al_mac,
		opclasses: [{ opclass: int(input.OpClass), channels }]
	});
	let err = ubus.error();
	if (err) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'set_anticipated_channel_preference failed: ' + err, null);
		return;
	}

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Async operation handler for SetQMDescriptors.
 * Sends QoS Management descriptor elements to an agent via set_policy.
 *
 * @param {object} input - Operation input with QMDescriptor.{i}.* entries
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio, bss]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_qm_descriptors_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'EasyMesh Controller must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];
	let bss_instance = instances[2];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let al_mac = device.al_address;
	if (!al_mac) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device has no AL MAC', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let bss_list = radio.bss ?? [];
	let bss = ubbf.get_by_instance(bss_list, bss_instance);
	if (!bss) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'BSS not found', null);
		return;
	}

	let source_bssid = bss.mac_address;
	if (!source_bssid) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'BSS has no MAC address', null);
		return;
	}

	let descriptors = [];
	for (let key, value in input) {
		let m = match(key, /^QMDescriptor\.(\d+)\.ClientMAC$/);
		if (!m)
			continue;

		let idx = m[1];
		let client_mac = value;
		let descriptor_element = input[`QMDescriptor.${idx}.DescriptorElement`];
		if (!client_mac || !descriptor_element) {
			complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
			return;
		}

		let bssid = input[`QMDescriptor.${idx}.BSSID`] ?? source_bssid;
		push(descriptors, {
			qmid: length(descriptors) + 1,
			bssid,
			client_mac,
			descriptor_element
		});
	}

	if (length(descriptors) == 0) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	root.EasyMesh ??= {};
	root.EasyMesh.QMDescriptors ??= {};
	root.EasyMesh.QMDescriptors[al_mac] = descriptors;

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Configures EHT operations on a BSS via set_policy eht_operations.
 * Only disabled_subchannel_bitmap is forwarded; other TR-181 inputs
 * are accepted but have no effect until umapd extends TLV 0xE7 support.
 *
 * @param {object} input - Operation input with EHT operation parameters
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio, bss]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function set_eht_operations_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'EasyMesh Controller must be enabled', null);
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];
	let bss_instance = instances[2];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let al_mac = device.al_address;
	if (!al_mac) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device has no AL MAC', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let ruid = radio.radio_unique_identifier;

	let bss_list = radio.bss ?? [];
	let bss = ubbf.get_by_instance(bss_list, bss_instance);
	if (!bss) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'BSS not found', null);
		return;
	}

	let eht_params = {};

	if (input.DisabledSubchannelBitmap != null)
		eht_params.disabled_subchannel_bitmap = hex(input.DisabledSubchannelBitmap) ?? 0;

	root.EasyMesh ??= {};
	root.EasyMesh.EHTOperations ??= {};
	root.EasyMesh.EHTOperations[al_mac] ??= {};
	root.EasyMesh.EHTOperations[al_mac][ruid] = eht_params;

	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Enables or disables a radio on an agent via disabled_radios policy.
 *
 * @param {object} input - Operation input with Enable boolean
 * @param {string} instance - Operation instance path
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Multi-instance path [device, radio]
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function radio_enable_handler(input, instance, complete, instances, command_key, root) {
	let network = root?.Device?.WiFi?.DataElements?.Network;
	if (!ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable)) {
		complete(instance, USP_ERR_COMMAND_FAILURE,
			'EasyMesh Controller must be enabled', null);
		return;
	}

	if (input.Enable == null) {
		complete(instance, 0, null, { Status: 'Error_Invalid_Input' });
		return;
	}

	let device_instance = instances[0];
	let radio_instance = instances[1];

	let devices = topology_devices_get(root);
	let device = ubbf.get_by_instance(devices, device_instance);
	if (!device) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Device not found', null);
		return;
	}

	let radios = device_radios_sorted(device);
	let radio = ubbf.get_by_instance(radios, radio_instance);
	if (!radio) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Radio not found', null);
		return;
	}

	let al_mac = device.al_address;
	let ruid = radio.radio_unique_identifier;

	root.EasyMesh ??= {};
	root.EasyMesh.DisabledRadios ??= {};
	root.EasyMesh.DisabledRadios[al_mac] ??= {};

	if (ubbf.to_bool(input.Enable))
		delete root.EasyMesh.DisabledRadios[al_mac][ruid];
	else
		root.EasyMesh.DisabledRadios[al_mac][ruid] = true;

	complete(instance, 0, null, { Status: 'Success' });
}

export const operations = {
	'Device.WiFi.DataElements.Network.SetTrafficSeparation()': {
		type: 'async',
		commit: true,
		handler: set_traffic_separation_handler
	},

	'Device.WiFi.DataElements.Network.SetServicePrioritization()': {
		type: 'async',
		commit: true,
		handler: set_service_prioritization_handler
	},

	'Device.WiFi.DataElements.Network.SetPreferredBackhauls()': {
		type: 'async',
		handler: set_preferred_backhauls_handler
	},

	'Device.WiFi.DataElements.Network.SetSSID()': {
		type: 'async',
		commit: true,
		handler: set_ssid_handler
	},

	'Device.WiFi.DataElements.Network.SetMSCSDisallowed()': {
		type: 'async',
		commit: true,
		handler: set_mscs_disallowed_handler
	},

	'Device.WiFi.DataElements.Network.SetSCSDisallowed()': {
		type: 'async',
		commit: true,
		handler: set_scs_disallowed_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ChannelScanRequest()': {
		type: 'async',
		handler: channel_scan_request_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.InitiateWPSPBC()': {
		type: 'async',
		handler: initiate_wps_pbc_handler
	},

	'Device.WiFi.DataElements.Network.X_UBBF_EasyMesh.Agent.Reset()': {
		type: 'async',
		handler: agent_reset_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.ClientSteer()': {
		type: 'async',
		handler: client_steer_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.SteerWiFiBackhaul()': {
		type: 'async',
		handler: steer_wifi_backhaul_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.RefreshAPMetrics()': {
		type: 'async',
		handler: refresh_ap_metrics_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SetSTASteeringState()': {
		type: 'async',
		commit: true,
		handler: set_sta_steering_state_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SetAnticipatedChannelPreference()': {
		type: 'async',
		handler: set_anticipated_channel_preference_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ChannelSelectionRequest()': {
		type: 'async',
		handler: channel_selection_request_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.SetSpatialReuse()': {
		type: 'async',
		handler: set_spatial_reuse_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.SetTxPowerLimit()': {
		type: 'async',
		commit: true,
		handler: set_tx_power_limit_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.SetQMDescriptors()': {
		type: 'async',
		commit: true,
		handler: set_qm_descriptors_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.SetEHTOperations()': {
		type: 'async',
		commit: true,
		handler: set_eht_operations_handler
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.RadioEnable()': {
		type: 'async',
		commit: true,
		handler: radio_enable_handler
	}
};
