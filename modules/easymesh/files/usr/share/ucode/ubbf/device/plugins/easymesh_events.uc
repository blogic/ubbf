'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { dm_event_send } from 'ubbf.utils.events';
import { topology_devices_get } from 'ubbf.utils.wifi-dataelements';

const EVENT_BUFFER_MAX = 64;

let association_events = [];
let disassociation_events = [];
let failed_connection_events = [];

/**
 * Appends an entry to a rolling event buffer and drops the oldest entries
 * above EVENT_BUFFER_MAX.
 *
 * @param {array} buf - Event buffer, changed in place
 * @param {object} entry - Event entry to append
 */
function event_buffer_push(buf, entry) {
	push(buf, entry);
	while (length(buf) > EVENT_BUFFER_MAX)
		shift(buf);
}

/**
 * Returns the DataElements name of a BTM status code.
 *
 * @param {number} code - BTM status code from umapd
 * @returns {string} BTMStatusCode enumeration value
 */
function btm_status_code_name(code) {
	switch (code) {
	case 0: return "Accept";
	case 1: return "Reject_Unspecified";
	case 2: return "Reject_Insufficient_Response";
	case 3: return "Reject_Insufficient_Capacity";
	case 4: return "Reject_Undesired";
	case 5: return "Reject_Delay";
	case 6: return "Reject_STA_List";
	case 7: return "Reject_No_BSS";
	case 8: return "Reject_Leaving_ESS";
	default: return "Reject_Unspecified";
	}
}

/**
 * Returns the DataElements name of a backhaul steering result code.
 *
 * @param {number} code - Result code from umapd
 * @returns {string} ResultCode enumeration value
 */
function backhaul_result_code_name(code) {
	return code == 0 ? "Success" : "Failure";
}

/**
 * Resolves an AL MAC to a DataElements Device instance number.
 *
 * @param {string} al_mac - AL MAC address to resolve
 * @returns {number|null} 1-based instance number, or null if not found
 */
function device_instance_resolve(al_mac) {
	if (!al_mac)
		return null;

	let devices = topology_devices_get();
	for (let i = 0; i < length(devices); i++)
		if (devices[i].al_address == al_mac)
			return i + 1;

	return null;
}

/**
 * Translates umapd WiFi6 capability key names to ubbf internal names.
 *
 * @param {object} caps - WiFi6 capabilities object from umapd event payload
 * @returns {object} Object with ubbf-consistent key names
 */
function umap_wifi6_to_ubbf(caps) {
	if (!caps)
		return {};

	return {
		he160: caps.he_160,
		he8080: caps.he_8080,
		mcsnss: caps.mcs_nss,
		su_beamformer: caps.su_beamformer,
		su_beamformee: caps.su_beamformee,
		mu_beamformer: caps.mu_beamformer_status,
		beamformee_80_or_less: caps.beamformee_sts_less_80,
		beamformee_above_80: caps.beamformee_sts_greater_80,
		ul_mumimo: caps.ul_mu_mimo,
		ul_ofdma: caps.ul_ofdma,
		dl_ofdma: caps.dl_ofdma,
		max_dl_mumimo: caps.max_dl_mu_mimo_tx,
		max_ul_mumimo: caps.max_ul_mu_mimo_rx,
		max_dl_ofdma: caps.max_dl_ofdma_tx,
		max_ul_ofdma: caps.max_ul_ofdma_rx,
		rts: caps.rts,
		murts: caps.mu_rts,
		multibssid: caps.multi_bssid,
		muedca: caps.mu_edca,
		twt_requestor: caps.twt_requester,
		twt_responder: caps.twt_responder,
		spatial_reuse: caps.spatial_reuse,
		anticipated_channel_usage: caps.anticipated_channel_usage
	};
}

/**
 * Forwards a umapd notification as a DataElements event and keeps the
 * association events for event_data_status.
 *
 * @param {object} req - ubus notification with type and data
 */
function umap_notify_cb(req) {
	let type = req.type;
	let d = req.data;

	switch (type) {
	case 'steer_result':
		dm_event_send('Device.WiFi.DataElements.Network.ControllerBTMSteer!', {
			BSSID: d.source_bssid ?? "",
			STAMAC: d.sta_mac ?? "",
			BTMStatusCode: btm_status_code_name(d.btm_status_code ?? 1)
		});
		break;

	case 'agent_onboarded':
		dm_event_send('Device.WiFi.DataElements.Network.AgentOnboard!', {
			DeviceID: d.al_address ?? "",
			BackhaulSta: d.backhaul_sta ?? "",
			BackhaulMACAddress: d.backhaul_mac ?? "",
			BackhaulALID: d.backhaul_al_id ?? ""
		});
		break;

	case 'backhaul_steering_response': {
		let inst = device_instance_resolve(d.al_address);
		if (inst)
			dm_event_send(`Device.WiFi.DataElements.Network.Device.${inst}.BackhaulChange!`, {
				MACAddress: d.sta_mac ?? "",
				TargetBSSID: d.target_bssid ?? "",
				ResultCode: backhaul_result_code_name(d.result_code),
				ReasonCode: sprintf('%d', d.reason_code ?? 0)
			});
		break;
	}

	case 'backhaul_change': {
		let inst = device_instance_resolve(d.al_address);
		if (inst)
			dm_event_send(`Device.WiFi.DataElements.Network.Device.${inst}.BackhaulChange!`, {
				MACAddress: d.mac_address ?? "",
				TargetBSSID: d.upstream_mac ?? "",
				ResultCode: d.upstream_al_id ? "Success" : "Failure",
				ReasonCode: "0"
			});
		break;
	}

	case 'client_association': {
		if (!d.associated)
			break;
		let ts = ubbf.iso8601_format();
		dm_event_send('Device.WiFi.DataElements.AssociationEvent.Associated!', {
			TimeStamp: ts,
			BSSID: d.bssid ?? "",
			MACAddress: d.sta_mac ?? "",
			StatusCode: "0"
		});
		event_buffer_push(association_events, {
			timestamp: ts,
			bssid: d.bssid ?? "",
			sta_mac: d.sta_mac ?? "",
			status_code: 0,
			op_class: d.op_class ?? 0,
			channel: d.channel ?? 0,
			ht_capabilities: d.ht_capabilities ?? "",
			vht_capabilities: d.vht_capabilities ?? "",
			he_capabilities: d.he_capabilities ?? "",
			client_capabilities: d.client_capabilities ?? "",
			wifi6_caps: umap_wifi6_to_ubbf(d.wifi6_capabilities)
		});
		break;
	}

	case 'disassociation': {
		let traf = d.traffic_stats ?? {};
		let ts = ubbf.iso8601_format();
		dm_event_send('Device.WiFi.DataElements.DisassociationEvent.Disassociated!', {
			BSSID: d.bssid ?? "",
			MACAddress: d.sta_mac ?? "",
			ReasonCode: sprintf('%d', d.reason_code ?? 0),
			BytesSent: sprintf('%d', traf.bytes_sent ?? 0),
			BytesReceived: sprintf('%d', traf.bytes_received ?? 0),
			PacketsSent: sprintf('%d', traf.packets_sent ?? 0),
			PacketsReceived: sprintf('%d', traf.packets_received ?? 0),
			ErrorsSent: sprintf('%d', traf.errors_sent ?? 0),
			ErrorsReceived: sprintf('%d', traf.errors_received ?? 0),
			RetransCount: sprintf('%d', traf.retrans_count ?? 0),
			TimeStamp: ts
		});
		event_buffer_push(disassociation_events, {
			timestamp: ts,
			bssid: d.bssid ?? "",
			sta_mac: d.sta_mac ?? "",
			reason_code: d.reason_code ?? 0,
			bytes_sent: traf.bytes_sent ?? 0,
			bytes_received: traf.bytes_received ?? 0,
			packets_sent: traf.packets_sent ?? 0,
			packets_received: traf.packets_received ?? 0,
			errors_sent: traf.errors_sent ?? 0,
			errors_received: traf.errors_received ?? 0,
			retrans_count: traf.retrans_count ?? 0,
			op_class: d.op_class ?? 0,
			channel: d.channel ?? 0,
			signal_strength: d.signal_strength ?? 0,
			est_mac_data_rate_downlink: d.est_mac_data_rate_downlink ?? 0,
			est_mac_data_rate_uplink: d.est_mac_data_rate_uplink ?? 0,
			last_data_downlink_rate: d.last_data_downlink_rate ?? 0,
			last_data_uplink_rate: d.last_data_uplink_rate ?? 0,
			utilization_receive: d.utilization_receive ?? 0,
			utilization_transmit: d.utilization_transmit ?? 0,
			noise: d.noise ?? 0,
			last_connect_time: d.last_connect_time ?? 0,
			initiated_by: d.initiated_by ?? ""
		});
		break;
	}

	case 'failed_connection': {
		let ts = ubbf.iso8601_format();
		dm_event_send('Device.WiFi.DataElements.FailedConnectionEvent.FailedConnection!', {
			BSSID: d.bssid ?? "",
			MACAddress: d.sta_mac ?? "",
			StatusCode: sprintf('%d', d.status_code ?? 0),
			ReasonCode: sprintf('%d', d.reason_code ?? 0),
			TimeStamp: ts
		});
		event_buffer_push(failed_connection_events, {
			timestamp: ts,
			bssid: d.bssid ?? "",
			sta_mac: d.sta_mac ?? "",
			status_code: d.status_code ?? 0,
			reason_code: d.reason_code ?? 0
		});
		break;
	}
	}
}

/**
 * ubus method event_data_status: returns the kept association events.
 *
 * @param {object} req - ubus request
 * @returns {object} Association, disassociation and failed connection events
 */
function event_data_status_handler(req) {
	return {
		association: association_events,
		disassociation: disassociation_events,
		failed_connection: failed_connection_events
	};
}

/**
 * ubus method event_data_clear: drops the kept association events.
 *
 * @param {object} req - ubus request
 * @returns {object} Empty reply
 */
function event_data_clear_handler(req) {
	association_events = [];
	disassociation_events = [];
	failed_connection_events = [];
	return {};
}

/**
 * Registers the umap notification subscriber.
 */
export function subscribe() {
	ubus.subscriber(umap_notify_cb, null, ['umap', 'umap-agent']);
};

/**
 * Returns the ubus methods for the DataElements event buffers.
 *
 * @returns {object} Method definitions of event_data_status and event_data_clear
 */
export function ubus_methods() {
	return {
		event_data_status: {
			call: event_data_status_handler,
			args: {}
		},
		event_data_clear: {
			call: event_data_clear_handler,
			args: {}
		}
	};
};
