'use strict';

import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.WiFiDataElements';
import * as X_UBBF from 'ubbf.schemas.X_UBBF';
import { vendor_schema } from 'ubbf.utils.schema';
import {
	ubus_topology_get, local_device_get, local_api_data_get, device_api_data_get,
	steering_stats_get, steering_history_get, topology_devices_get,
	radio_band_priority
} from 'ubbf.utils.wifi-dataelements';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf.utils.logging';
import { device_to_object } from 'ubbf.tr181.WiFiDataElements.ObjectData';
import { al_index_map } from 'ubbf.tr181.IEEE1905';
import * as Operations from 'ubbf.tr181.WiFiDataElements.Operations';
import * as EasyMesh from 'ubbf.tr181.WiFiDataElements.EasyMesh';

/**
 * Gets list of devices from EasyMesh topology or local device.
 *
 * @param {object} root - Root configuration object
 * @returns {array} Array of device objects from topology
 */
function devices_get(root) {
	let network = root.Device?.WiFi?.DataElements?.Network;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	if (!controller_enabled && !agent_enabled)
		return [local_device_get()];

	return topology_devices_get();
}

Operations.set_topology_devices_get(devices_get);

/**
 * Fetches event data buffers from bbf-device.
 *
 * @returns {object} Object with association, disassociation, failed_connection arrays
 */
function event_data_get() {
	return ubus.call('bbf-device', 'event_data_status') ?? {};
}

/**
 * Builds the WiFi6Capabilities sub-object from translated umapd fields.
 *
 * @param {object} w - Translated WiFi6 capabilities (ubbf-internal naming)
 * @returns {object} TR-181 WiFi6Capabilities sub-object
 */
function wifi6_caps_to_schema(w) {
	w ??= {};
	return {
		HE160: w.he160 ? "true" : "false",
		HE8080: w.he8080 ? "true" : "false",
		MCSNSS: w.mcsnss ? b64enc(w.mcsnss) : "",
		SUBeamformer: w.su_beamformer ? "true" : "false",
		SUBeamformee: w.su_beamformee ? "true" : "false",
		MUBeamformer: w.mu_beamformer ? "true" : "false",
		Beamformee80orLess: (w.beamformee_80_or_less ?? 0) > 0 ? "true" : "false",
		BeamformeeAbove80: (w.beamformee_above_80 ?? 0) > 0 ? "true" : "false",
		ULMUMIMO: w.ul_mumimo ? "true" : "false",
		ULOFDMA: w.ul_ofdma ? "true" : "false",
		DLOFDMA: w.dl_ofdma ? "true" : "false",
		MaxDLMUMIMO: sprintf('%d', w.max_dl_mumimo ?? 0),
		MaxULMUMIMO: sprintf('%d', w.max_ul_mumimo ?? 0),
		MaxDLOFDMA: sprintf('%d', w.max_dl_ofdma ?? 0),
		MaxULOFDMA: sprintf('%d', w.max_ul_ofdma ?? 0),
		RTS: w.rts ? "true" : "false",
		MURTS: w.murts ? "true" : "false",
		MultiBSSID: w.multibssid ? "true" : "false",
		MUEDCA: w.muedca ? "true" : "false",
		TWTRequestor: w.twt_requestor ? "true" : "false",
		TWTResponder: w.twt_responder ? "true" : "false",
		SpatialReuse: w.spatial_reuse ? "true" : "false",
		AnticipatedChannelUsage: w.anticipated_channel_usage ? "true" : "false"
	};
}

/**
 * Get handler for Device.WiFi.DataElements.AssociationEvent.
 *
 * @param {object} ctx - Context
 * @returns {object} AssociationEvent with event data entries
 */
function association_event_get(ctx) {
	let events = event_data_get().association ?? [];
	return {
		...ubbf.ctx_config(ctx),
		AssociationEventDataNumberOfEntries: sprintf('%d', length(events)),
		AssociationEventData: ubbf.enumerate_instances(events, (e) => ({
			TimeStamp: e.timestamp ?? "",
			BSSID: e.bssid ?? "",
			MACAddress: e.sta_mac ?? "",
			StatusCode: sprintf('%d', e.status_code ?? 0),
			HTCapabilities: e.ht_capabilities ?? "",
			VHTCapabilities: e.vht_capabilities ?? "",
			HECapabilities: e.he_capabilities ?? "",
			ClientCapabilities: e.client_capabilities ?? "",
			OpClass: sprintf('%d', e.op_class ?? 0),
			Channel: sprintf('%d', e.channel ?? 0),
			WiFi6Capabilities: wifi6_caps_to_schema(e.wifi6_caps)
		}))
	};
}

/**
 * Get handler for Device.WiFi.DataElements.DisassociationEvent.
 *
 * @param {object} ctx - Context
 * @returns {object} DisassociationEvent with event data entries
 */
function disassociation_event_get(ctx) {
	let events = event_data_get().disassociation ?? [];
	return {
		...ubbf.ctx_config(ctx),
		DisassociationEventDataNumberOfEntries: sprintf('%d', length(events)),
		DisassociationEventData: ubbf.enumerate_instances(events, (e) => ({
			BSSID: e.bssid ?? "",
			MACAddress: e.sta_mac ?? "",
			ReasonCode: sprintf('%d', e.reason_code ?? 0),
			BytesSent: sprintf('%d', e.bytes_sent ?? 0),
			BytesReceived: sprintf('%d', e.bytes_received ?? 0),
			PacketsSent: sprintf('%d', e.packets_sent ?? 0),
			PacketsReceived: sprintf('%d', e.packets_received ?? 0),
			ErrorsSent: sprintf('%d', e.errors_sent ?? 0),
			ErrorsReceived: sprintf('%d', e.errors_received ?? 0),
			RetransCount: sprintf('%d', e.retrans_count ?? 0),
			TimeStamp: e.timestamp ?? "",
			LastDataDownlinkRate: sprintf('%d', e.last_data_downlink_rate ?? 0),
			LastDataUplinkRate: sprintf('%d', e.last_data_uplink_rate ?? 0),
			UtilizationReceive: sprintf('%d', e.utilization_receive ?? 0),
			UtilizationTransmit: sprintf('%d', e.utilization_transmit ?? 0),
			EstMACDataRateDownlink: sprintf('%d', e.est_mac_data_rate_downlink ?? 0),
			EstMACDataRateUplink: sprintf('%d', e.est_mac_data_rate_uplink ?? 0),
			SignalStrength: sprintf('%d', e.signal_strength ?? 0),
			LastConnectTime: sprintf('%d', e.last_connect_time ?? 0),
			Noise: sprintf('%d', e.noise ?? 0),
			InitiatedBy: e.initiated_by ?? "",
			OpClass: sprintf('%d', e.op_class ?? 0),
			Channel: sprintf('%d', e.channel ?? 0)
		}))
	};
}

/**
 * Get handler for Device.WiFi.DataElements.FailedConnectionEvent.
 *
 * @param {object} ctx - Context
 * @returns {object} FailedConnectionEvent with event data entries
 */
function failed_connection_event_get(ctx) {
	let events = event_data_get().failed_connection ?? [];
	return {
		...ubbf.ctx_config(ctx),
		FailedConnectionEventDataNumberOfEntries: sprintf('%d', length(events)),
		FailedConnectionEventData: ubbf.enumerate_instances(events, (e) => ({
			BSSID: e.bssid ?? "",
			MACAddress: e.sta_mac ?? "",
			StatusCode: sprintf('%d', e.status_code ?? 0),
			ReasonCode: sprintf('%d', e.reason_code ?? 0),
			TimeStamp: e.timestamp ?? ""
		}))
	};
}

/**
 * Get handler for Device.WiFi.DataElements.Network.Device.{i}.
 *
 * @param {object} ctx - Context with root config and optional instance
 * @returns {object|null} Device data or all devices if no instance specified
 */
function device_get(ctx) {
	let network = ctx.root.Device?.WiFi?.DataElements?.Network ?? {};
	let controller_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Agent?.Enable);
	let is_easymesh = controller_enabled || agent_enabled;
	let easymesh = ctx.root.EasyMesh ?? {};
	ctx.root.EasyMesh = easymesh;
	easymesh.ConfigPolicy = {};
	for (let inst, entry in network.X_UBBF_EasyMesh?.Controller?.Policy ?? {}) {
		if (!entry.ALMAC || !entry.Data)
			continue;
		// a malformed Policy Data string must not throw and take the whole
		// Network.Device subtree down with it
		try {
			let parsed = json(entry.Data);
			if (type(parsed) == 'object')
				easymesh.ConfigPolicy[entry.ALMAC] = parsed;
		} catch (e) {
			log_err('WiFiDataElements: invalid Policy Data for %s: %s', entry.ALMAC, e);
		}
	}
	let devices_cfg = ctx.root.Device?.WiFi?.DataElements?.Network?.Device;

	let topology = is_easymesh ? ubus_topology_get() : null;
	let colocated_agent_id = topology?.colocated_agent_id;

	let devices = devices_get(ctx.root);

	let steer_stats = controller_enabled ? steering_stats_get() : {};
	let steer_history = controller_enabled ? steering_history_get() : {};
	let ieee1905_idx = al_index_map();

	if (ctx.instance == null) {
		let result = {};
		for (let i = 0; i < length(devices); i++) {
			let device = devices[i];
			let api_data = is_easymesh
				? device_api_data_get(device.al_address, controller_enabled)
				: local_api_data_get();
			api_data.steering_stats = steer_stats;
			api_data.steering_history = steer_history;
			let is_controller = controller_enabled && device.al_address == colocated_agent_id;
			let dev_inst = sprintf('%d', i + 1);
			result[dev_inst] = device_to_object(device, api_data, is_controller, easymesh, devices_cfg?.[dev_inst], ieee1905_idx);
		}
		return result;
	}

	let device = ubbf.get_by_instance(devices, ctx.instance);
	if (!device)
		return null;

	let api_data = is_easymesh
		? device_api_data_get(device.al_address, controller_enabled)
		: local_api_data_get();
	api_data.steering_stats = steer_stats;
	api_data.steering_history = steer_history;
	let is_controller = controller_enabled && device.al_address == colocated_agent_id;
	return device_to_object(device, api_data, is_controller, easymesh, devices_cfg?.[sprintf('%d', ctx.instance)], ieee1905_idx);
}

/**
 * Reverse of band_convert: maps the stored band set back to the TR-181
 * Band enumeration value. Emits "All" for the full {2g, 5g, 6g} set.
 *
 * @param {array} stored - Stored band array using 2g/5g/6g identifiers
 * @returns {string} TR-181 Band value, comma-separated
 */
function band_reverse(stored) {
	stored ??= [];
	let has_2g = index(stored, '2g') >= 0;
	let has_5g = index(stored, '5g') >= 0;
	let has_6g = index(stored, '6g') >= 0;

	if (has_2g && has_5g && has_6g)
		return 'All';

	let parts = [];
	if (has_2g)
		push(parts, '2.4');
	if (has_5g)
		push(parts, '5');
	if (has_6g)
		push(parts, '6');

	return join(',', parts);
}

/**
 * Reverse of akm_convert: collapses the stored authentication list back to
 * a TR-181 AKMsAllowed value. Combines psk2 + sae into psk+sae.
 *
 * @param {array} stored - Stored authentication array (psk2/sae/owe)
 * @returns {string} TR-181 AKMsAllowed value, comma-separated
 */
function akm_reverse(stored) {
	stored ??= [];
	let has_psk = false, has_sae = false, has_owe = false;
	for (let a in stored) {
		if (a == 'psk2')
			has_psk = true;
		else if (a == 'sae')
			has_sae = true;
		else if (a == 'owe')
			has_owe = true;
	}

	let parts = [];
	if (has_psk && has_sae)
		push(parts, 'psk+sae');
	else if (has_psk)
		push(parts, 'psk');
	else if (has_sae)
		push(parts, 'sae');
	if (has_owe)
		push(parts, 'owe');

	return join(',', parts);
}

/**
 * Reverse of akm_to_mode_enabled: maps AccessPoint_Security.ModeEnabled
 * back to a TR-181 AKMsAllowed value.
 *
 * @param {string} mode - TR-181 ModeEnabled value
 * @returns {string} TR-181 AKMsAllowed value
 */
function mode_enabled_to_akm(mode) {
	switch (mode) {
	case 'WPA2-Personal': return 'psk';
	case 'WPA3-Personal': return 'sae';
	case 'WPA3-Personal-Transition': return 'psk+sae';
	}
	return '';
}

/**
 * Builds the HaulType enumeration value from EasyMesh storage flags.
 *
 * @param {boolean} fronthaul - Fronthaul flag from ssid_entry_create
 * @param {boolean} backhaul - Backhaul flag from ssid_entry_create
 * @returns {string} Comma-separated HaulType value or empty string
 */
function haul_type_reverse(fronthaul, backhaul) {
	let parts = [];
	if (fronthaul)
		push(parts, 'Fronthaul');
	if (backhaul)
		push(parts, 'Backhaul');
	return join(',', parts);
}

/**
 * Reconstructs a TR-181 Network.SSID.{i} object from an EasyMesh-stored
 * entry in root.EasyMesh.SSIDs.
 *
 * @param {object} entry - Stored SSID entry (ssid_entry_create shape)
 * @returns {object} TR-181 formatted Network.SSID object
 */
function easymesh_ssid_to_object(entry) {
	let adv;
	if (entry.hidden == null)
		adv = 'true';
	else
		adv = entry.hidden ? 'false' : 'true';

	return {
		Alias: ubbf.alias_from_name(entry.ssid ?? ''),
		SSID: entry.ssid ?? '',
		Band: band_reverse(entry.band),
		Enable: entry.enabled ? 'true' : 'false',
		AKMsAllowed: akm_reverse(entry.authentication),
		SuiteSelector: entry.suite_selector ?? '',
		AdvertisementEnabled: adv,
		MFPConfig: entry.mfp_config ?? '',
		MobilityDomain: entry.mobility_domain ?? '',
		HaulType: haul_type_reverse(entry.fronthaul, entry.backhaul),
		Type: entry.type ?? ''
	};
}

/**
 * Looks up the OperatingFrequencyBand of the radio referenced by
 * wifi_ssid.LowerLayers and maps it back to a TR-181 Band value.
 *
 * @param {object} root - Root configuration object
 * @param {string} lower_layers - Device.WiFi.Radio.{i} reference path
 * @returns {string} TR-181 Band value or empty string
 */
function radio_band_reverse(root, lower_layers) {
	if (!lower_layers)
		return '';

	let m = match(lower_layers, /Device\.WiFi\.Radio\.(\d+)/);
	if (!m)
		return '';

	let radio = root.Device?.WiFi?.Radio?.[m[1]];
	switch (radio?.OperatingFrequencyBand) {
	case '2.4GHz': return '2.4';
	case '5GHz': return '5';
	case '6GHz': return '6';
	}
	return '';
}

/**
 * Finds a Device.WiFi.AccessPoint entry by its SSIDReference.
 * Mirrors Operations.uc:ap_by_ssid_ref_find without creating an Operations
 * import loop.
 *
 * @param {object} root - Root configuration object
 * @param {string} ssid_inst - 1-based SSID instance number
 * @returns {object|null} AccessPoint entry or null
 */
function access_point_for_ssid(root, ssid_inst) {
	let aps = root.Device?.WiFi?.AccessPoint;
	if (!aps)
		return null;

	let ref = `Device.WiFi.SSID.${ssid_inst}`;
	for (let inst, ap in aps)
		if (ap.SSIDReference == ref)
			return ap;

	return null;
}

/**
 * Reconstructs a TR-181 Network.SSID.{i} object from non-EasyMesh storage
 * at Device.WiFi.SSID.{i} / Device.WiFi.AccessPoint.{i}.
 *
 * @param {object} root - Root configuration object
 * @param {string} ssid_inst - SSID instance number
 * @param {object} wifi_ssid - Device.WiFi.SSID entry
 * @returns {object} TR-181 formatted Network.SSID object
 */
function wifi_ssid_to_object(root, ssid_inst, wifi_ssid) {
	let ap = access_point_for_ssid(root, ssid_inst);
	let sec = ap?.Security ?? {};

	return {
		Alias: wifi_ssid.Alias ?? ubbf.alias_from_name(wifi_ssid.SSID ?? ''),
		SSID: wifi_ssid.SSID ?? '',
		Band: radio_band_reverse(root, wifi_ssid.LowerLayers),
		Enable: wifi_ssid.Enable ?? 'false',
		AKMsAllowed: mode_enabled_to_akm(sec.ModeEnabled ?? ''),
		SuiteSelector: sec.SuiteSelector ?? '',
		AdvertisementEnabled: ap?.SSIDAdvertisementEnabled ?? 'true',
		MFPConfig: sec.MFPConfig ?? '',
		MobilityDomain: sec.MobilityDomainID ?? '',
		HaulType: 'Fronthaul',
		Type: ''
	};
}

/**
 * Returns the authoritative SSID count used for Network.SSIDNumberOfEntries.
 * Matches the source the Network.SSID.{i} get handler reads from.
 *
 * @param {object} root - Root configuration object
 * @returns {number} Count of SSIDs in the active storage
 */
function ssid_count_get(root) {
	let network = root.Device?.WiFi?.DataElements?.Network ?? {};
	let controller_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Agent?.Enable);

	if (controller_enabled)
		return length(root.EasyMesh?.SSIDs ?? []);
	if (agent_enabled)
		return 0;
	return length(keys(root.Device?.WiFi?.SSID ?? {}));
}

/**
 * Builds the ordered list of Network.SSID.{i} objects from the active
 * storage, selecting EasyMesh or non-EasyMesh source by enablement.
 *
 * @param {object} root - Root configuration object
 * @returns {array} Array of TR-181 formatted Network.SSID objects
 */
function ssid_list_build(root) {
	let network = root.Device?.WiFi?.DataElements?.Network ?? {};
	let controller_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Agent?.Enable);

	if (controller_enabled) {
		let ssids = root.EasyMesh?.SSIDs ?? [];
		let result = [];
		for (let entry in ssids)
			push(result, easymesh_ssid_to_object(entry));
		return result;
	}

	if (agent_enabled)
		return [];

	let result = [];
	let wifi_ssids = root.Device?.WiFi?.SSID ?? {};
	for (let inst, wifi_ssid in wifi_ssids)
		push(result, wifi_ssid_to_object(root, inst, wifi_ssid));
	return result;
}

/**
 * Get handler for Device.WiFi.DataElements.Network.SSID.{i}.
 *
 * @param {object} ctx - Context with root config and optional instance
 * @returns {object|null} SSID entry or enumerated instances
 */
function network_ssid_get(ctx) {
	let ssid_list = ssid_list_build(ctx.root);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(ssid_list, (e) => e);

	return ubbf.get_by_instance(ssid_list, ctx.instance);
}

/**
 * Get handler for Device.WiFi.DataElements.Network.STABlock.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} STABlock data with ScheduleNumberOfEntries
 */
function stablock_get(ctx) {
	if (!ctx.config)
		return null;

	let schedule_count = length(keys(ctx.config.Schedule ?? {}));
	return {
		...ctx.config,
		ScheduleNumberOfEntries: sprintf('%d', schedule_count)
	};
}

/**
 * Get handler for Device.WiFi.DataElements.Network.
 *
 * @param {object} ctx - Context with root config
 * @returns {object} Network data with topology and controller information
 */
function network_get(ctx) {
	let easymesh = ctx.root.EasyMesh ?? {};
	let network = ctx.root.Device?.WiFi?.DataElements?.Network ?? {};
	let controller_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network.X_UBBF_EasyMesh?.Agent?.Enable);

	let steering_stats = controller_enabled ? (steering_stats_get()?.network ?? {}) : {};

	let result = {
		...ubbf.ctx_config(ctx),
		ID: easymesh.Controller?.ID ?? "",
		TimeStamp: ubbf.iso8601_format(),
		ControllerID: "",
		ColocatedAgentID: "",
		DeviceNumberOfEntries: sprintf('%d', length(devices_get(ctx.root))),
		SSIDNumberOfEntries: sprintf('%d', ssid_count_get(ctx.root)),
		STABlockNumberOfEntries: sprintf('%d', length(keys(network.STABlock ?? {}))),
		ProvisionedDPPNumberOfEntries: sprintf('%d', length(keys(network.ProvisionedDPP ?? {}))),
		PreferredBackhaulsNumberOfEntries: "0",
		SteeringMandates: sprintf('%d', steering_stats.steering_mandates ?? 0),
		SteeringOpportunities: sprintf('%d', steering_stats.steering_opportunities ?? 0),
		MSCSDisallowedStaList: join(',', easymesh.QoSManagement?.mscs_disallowed_sta ?? []),
		SCSDisallowedStaList: join(',', easymesh.QoSManagement?.scs_disallowed_sta ?? []),
		MultiAPSteeringSummaryStats: {
			NoCandidateAPFailures: sprintf('%d', steering_stats.no_candidate_ap_failures ?? 0),
			BlacklistAttempts: sprintf('%d', steering_stats.blacklist_attempts ?? 0),
			BlacklistSuccesses: sprintf('%d', steering_stats.blacklist_successes ?? 0),
			BlacklistFailures: sprintf('%d', steering_stats.blacklist_failures ?? 0),
			BTMAttempts: sprintf('%d', steering_stats.btm_attempts ?? 0),
			BTMSuccesses: sprintf('%d', steering_stats.btm_successes ?? 0),
			BTMFailures: sprintf('%d', steering_stats.btm_failures ?? 0),
			BTMQueryResponses: sprintf('%d', steering_stats.btm_query_responses ?? 0)
		}
	};

	if (controller_enabled || agent_enabled) {
		let topology = ubus_topology_get();
		if (topology) {
			result.ControllerID = topology.controller_id;
			result.ColocatedAgentID = topology.colocated_agent_id;
		}
	}

	return result;
}

/**
 * Set handler for DisAllowedOpClassChannels.{i}.
 * Rebuilds disallowed channel policy from all sibling instances and stores in EasyMesh config.
 *
 * @param {object} ctx - Context with param, value, config and root
 */
function disallowed_opclass_channels_set(ctx) {
	let network = ctx.root.Device?.WiFi?.DataElements?.Network;
	let devices_cfg = network?.Device;
	if (!devices_cfg)
		return;

	let device_inst, radio_inst, radio_cfg;
	for (let dinst, dev in devices_cfg) {
		for (let rinst, radio in dev.Radio ?? {}) {
			let dac = radio.DisAllowedOpClassChannels;
			if (!dac)
				continue;

			for (let inst, entry in dac) {
				if (entry !== ctx.config)
					continue;

				device_inst = int(dinst);
				radio_inst = int(rinst);
				radio_cfg = radio;
				break;
			}
			if (device_inst)
				break;
		}
		if (device_inst)
			break;
	}

	if (!device_inst || !radio_cfg)
		return;

	let topo_devices = devices_get(ctx.root);
	let device = ubbf.get_by_instance(topo_devices, device_inst);
	if (!device)
		return;

	let al_mac = device.al_address;
	let controller_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Controller?.Enable);
	let agent_enabled = ubbf.to_bool(network?.X_UBBF_EasyMesh?.Agent?.Enable);

	// resolve the capability map and sort exactly like device_to_object()
	// does when it numbers the Radio.{i} instances, otherwise radio_inst
	// points at a different radio than the one the ACS addressed
	let api_data = (controller_enabled || agent_enabled)
		? device_api_data_get(al_mac, controller_enabled)
		: local_api_data_get();
	let capability = api_data?.capability ?? {};
	let radios = sort([...(device.map?.ap_operational_bss ?? [])],
		(a, b) => radio_band_priority(a, capability) - radio_band_priority(b, capability));

	let radio = ubbf.get_by_instance(radios, radio_inst);
	if (!radio)
		return;

	let ruid = radio.radio_unique_identifier;

	let rebuilt = [];
	for (let inst, entry in radio_cfg.DisAllowedOpClassChannels ?? {}) {
		if (!ubbf.to_bool(entry.Enable))
			continue;

		let opclass = int(entry.OpClass);
		let channels = map(ubbf.csv_to_list(entry.ChannelList), (c) => int(c));
		push(rebuilt, { opclass, channels });
	}

	ctx.root.EasyMesh ??= {};
	ctx.root.EasyMesh.DisAllowedChannels ??= {};
	ctx.root.EasyMesh.DisAllowedChannels[al_mac] ??= {};
	ctx.root.EasyMesh.DisAllowedChannels[al_mac][ruid] = {
		device_inst, radio_inst,
		entries: rebuilt
	};
}

export const model = {
	'Device.WiFi.DataElements': {
		schema: schemas.DataElements
	},

	'Device.WiFi.DataElements.Network': {
		schema: schemas.DataElements_Network,
		get: network_get
	},

	'Device.WiFi.DataElements.Network.MultiAPSteeringSummaryStats': {
		schema: schemas.Network_MultiAPSteeringSummaryStats
	},

	...EasyMesh.model,

	'Device.WiFi.DataElements.Network.Device': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}': {
		schema: schemas.Network_Device,
		get: device_get
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SSIDtoVIDMapping': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SSIDtoVIDMapping.{i}': {
		schema: schemas.Device_SSIDtoVIDMapping
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Default8021Q': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Default8021Q.{i}': {
		schema: schemas.Device_Default8021Q
	},

	'Device.WiFi.DataElements.Network.Device.{i}.IEEE1905Security': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.IEEE1905Security.{i}': {
		schema: schemas.Device_IEEE1905Security
	},

	'Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.BackhaulDown.{i}': {
		schema: schemas.Device_BackhaulDown
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}': {
		schema: schemas.Device_APMLD
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.TIDLinkMap': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.TIDLinkMap.{i}': {
		schema: schemas.APMLD_TIDLinkMap
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.AffiliatedAP': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.AffiliatedAP.{i}': {
		schema: schemas.APMLD_AffiliatedAP
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig': {
		schema: schemas.APMLD_APMLDConfig
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.TIDToOpClassPolicy': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.APMLDConfig.TIDToOpClassPolicy.{i}': {
		schema: schemas.APMLDConfig_TIDToOpClassPolicy
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}': {
		schema: schemas.APMLD_STAMLD
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STATIDLinkMap': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STATIDLinkMap.{i}': {
		schema: schemas.STAMLD_STATIDLinkMap
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.STAMLDConfig': {
		schema: schemas.STAMLD_STAMLDConfig
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.WiFi7Capabilities': {
		schema: schemas.STAMLD_WiFi7Capabilities
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.AffiliatedSTA': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.STAMLD.{i}.AffiliatedSTA.{i}': {
		schema: schemas.STAMLD_AffiliatedSTA
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.LinkToOpClassMap': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.APMLD.{i}.LinkToOpClassMap.{i}': {
		schema: schemas.APMLD_LinkToOpClassMap
	},

	'Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD': {
		schema: schemas.Device_bSTAMLD
	},

	'Device.WiFi.DataElements.Network.Device.{i}.bSTAMLD.bSTAMLDConfig': {
		schema: schemas.bSTAMLD_bSTAMLDConfig
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannels.{i}': {
		schema: schemas.Device_AnticipatedChannels
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}': {
		schema: schemas.Device_AnticipatedChannelUsage
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.Entry': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.AnticipatedChannelUsage.{i}.Entry.{i}': {
		schema: schemas.AnticipatedChannelUsage_Entry
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}': {
		schema: schemas.Device_CACStatus
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACAvailableChannel': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACAvailableChannel.{i}': {
		schema: schemas.CACStatus_CACAvailableChannel
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACNonOccupancyChannel': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACNonOccupancyChannel.{i}': {
		schema: schemas.CACStatus_CACNonOccupancyChannel
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACActiveChannel': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.CACStatus.{i}.CACActiveChannel.{i}': {
		schema: schemas.CACStatus_CACActiveChannel
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SPRule': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.SPRule.{i}': {
		schema: schemas.Device_SPRule
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice': {
		schema: schemas.Device_MultiAPDevice
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul': {
		schema: schemas.MultiAPDevice_Backhaul
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.Stats': {
		schema: schemas.Backhaul_Stats
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.CurrentOperatingClassProfile': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.MultiAPDevice.Backhaul.CurrentOperatingClassProfile.{i}': {
		schema: schemas.Backhaul_CurrentOperatingClassProfile
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}': {
		schema: vendor_schema(schemas.Device_Radio, X_UBBF.Device_Radio_X_UBBF)
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities': {
		schema: schemas.Radio_Capabilities
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.CapableOperatingClassProfile': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.CapableOperatingClassProfile.{i}': {
		schema: schemas.Capabilities_CapableOperatingClassProfile
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMFrontHaul': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMFrontHaul.{i}': {
		schema: schemas.Capabilities_AKMFrontHaul
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMBackhaul': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.AKMBackhaul.{i}': {
		schema: schemas.Capabilities_AKMBackhaul
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6APRole': {
		schema: schemas.Capabilities_WiFi6APRole
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi6bSTARole': {
		schema: schemas.Capabilities_WiFi6bSTARole
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole': {
		schema: schemas.Capabilities_WiFi7APRole
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLMRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLMRFreqSeparation.{i}': {
		schema: schemas.WiFi7APRole_EMLMRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLSRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.EMLSRFreqSeparation.{i}': {
		schema: schemas.WiFi7APRole_EMLSRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.STRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.STRFreqSeparation.{i}': {
		schema: schemas.WiFi7APRole_STRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.NSTRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7APRole.NSTRFreqSeparation.{i}': {
		schema: schemas.WiFi7APRole_NSTRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole': {
		schema: schemas.Capabilities_WiFi7bSTARole
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLMRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLMRFreqSeparation.{i}': {
		schema: schemas.WiFi7bSTARole_EMLMRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLSRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.EMLSRFreqSeparation.{i}': {
		schema: schemas.WiFi7bSTARole_EMLSRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.STRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.STRFreqSeparation.{i}': {
		schema: schemas.WiFi7bSTARole_STRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.NSTRFreqSeparation': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.Capabilities.WiFi7bSTARole.NSTRFreqSeparation.{i}': {
		schema: schemas.WiFi7bSTARole_NSTRFreqSeparation
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.OpClassPreference': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.OpClassPreference.{i}': {
		schema: schemas.Radio_OpClassPreference
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.DisAllowedOpClassChannels': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.DisAllowedOpClassChannels.{i}': {
		schema: schemas.Radio_DisAllowedOpClassChannels,
		set: disallowed_opclass_channels_set
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability': {
		schema: schemas.Radio_CACCapability
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}': {
		schema: schemas.CACCapability_CACMethod
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CACCapability.CACMethod.{i}.OpClassChannels.{i}': {
		schema: schemas.CACMethod_OpClassChannels
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.SpatialReuse': {
		schema: schemas.Radio_SpatialReuse
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.MultiAPRadio': {
		schema: schemas.Radio_MultiAPRadio
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.UnassociatedSTA': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.UnassociatedSTA.{i}': {
		schema: schemas.Radio_UnassociatedSTA
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BackhaulSta': {
		schema: schemas.Radio_BackhaulSta
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability': {
		schema: schemas.Radio_ScanCapability
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanCapability.OpClassChannels.{i}': {
		schema: schemas.ScanCapability_OpClassChannels
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CurrentOperatingClassProfile': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.CurrentOperatingClassProfile.{i}': {
		schema: schemas.Radio_CurrentOperatingClassProfile
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}': {
		schema: schemas.Radio_ScanResult
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}': {
		schema: schemas.ScanResult_OpClassScan
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}': {
		schema: schemas.OpClassScan_ChannelScan
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.ScanResult.{i}.OpClassScan.{i}.ChannelScan.{i}.NeighborBSS.{i}': {
		schema: schemas.ChannelScan_NeighborBSS
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}': {
		schema: schemas.Radio_BSS
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}': {
		schema: schemas.BSS_STA
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.WiFi6Capabilities': {
		schema: schemas.STA_WiFi6Capabilities
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA': {
		schema: schemas.STA_MultiAPSTA
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringSummaryStats': {
		schema: schemas.MultiAPSTA_SteeringSummaryStats
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringHistory': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.STA.{i}.MultiAPSTA.SteeringHistory.{i}': {
		schema: schemas.MultiAPSTA_SteeringHistory
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.QMDescriptor': {
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.QMDescriptor.{i}': {
		schema: schemas.BSS_QMDescriptor
	},

	'Device.WiFi.DataElements.Network.Device.{i}.Radio.{i}.BSS.{i}.MultiAPSteering': {
		schema: schemas.BSS_MultiAPSteering
	},

	'Device.WiFi.DataElements.Network.SSID': {
	},

	'Device.WiFi.DataElements.Network.SSID.{i}': {
		schema: schemas.Network_SSID,
		get: network_ssid_get
	},

	'Device.WiFi.DataElements.Network.STABlock': {
	},

	'Device.WiFi.DataElements.Network.STABlock.{i}': {
		schema: schemas.Network_STABlock,
		get: stablock_get
	},

	'Device.WiFi.DataElements.Network.STABlock.{i}.Schedule': {
	},

	'Device.WiFi.DataElements.Network.STABlock.{i}.Schedule.{i}': {
		schema: schemas.STABlock_Schedule
	},

	'Device.WiFi.DataElements.Network.ProvisionedDPP': {
	},

	'Device.WiFi.DataElements.Network.ProvisionedDPP.{i}': {
		schema: schemas.Network_ProvisionedDPP
	},

	'Device.WiFi.DataElements.AssociationEvent': {
		schema: schemas.DataElements_AssociationEvent,
		get: association_event_get
	},

	'Device.WiFi.DataElements.AssociationEvent.AssociationEventData': {
	},

	'Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}': {
		schema: schemas.AssociationEvent_AssociationEventData
	},

	'Device.WiFi.DataElements.AssociationEvent.AssociationEventData.{i}.WiFi6Capabilities': {
		schema: schemas.AssociationEventData_WiFi6Capabilities
	},

	'Device.WiFi.DataElements.DisassociationEvent': {
		schema: schemas.DataElements_DisassociationEvent,
		get: disassociation_event_get
	},

	'Device.WiFi.DataElements.DisassociationEvent.DisassociationEventData': {
	},

	'Device.WiFi.DataElements.DisassociationEvent.DisassociationEventData.{i}': {
		schema: schemas.DisassociationEvent_DisassociationEventData
	},

	'Device.WiFi.DataElements.FailedConnectionEvent': {
		schema: schemas.DataElements_FailedConnectionEvent,
		get: failed_connection_event_get
	},

	'Device.WiFi.DataElements.FailedConnectionEvent.FailedConnectionEventData': {
	},

	'Device.WiFi.DataElements.FailedConnectionEvent.FailedConnectionEventData.{i}': {
		schema: schemas.FailedConnectionEvent_FailedConnectionEventData
	}
};

export const operations = {
	...Operations.operations
};
