'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { md5 } from 'digest';
import { log_info } from 'ubbf.utils.logging';
import { dm_event_send } from 'ubbf.utils.events';
import { topology_devices_get } from 'ubbf.utils.wifi-dataelements';

const EVENT_BUFFER_MAX = 64;
const CHANNEL_HISTORY_BUFFER_MAX = 64;
// hostapd fires the CSA within a few seconds of a radar trigger; widen if
// observed CAC paths take longer on some drivers.
const RADAR_CORRELATION_WINDOW_SECONDS = 10;

let association_events = [];
let disassociation_events = [];
let failed_connection_events = [];

// Per-radio rolling buffer of channel-switch events. previous_channel_by_radio
// holds the last-seen channel number per radio, used to fill FromChannel on
// the next switch since hostapd's channel-switch ubus event only carries the
// new frequency.
let channel_history_by_radio = {};
let pending_radar_by_radio = {};
let previous_channel_by_radio = {};

let hostapd = {};

function event_buffer_push(buf, entry) {
	push(buf, entry);
	while (length(buf) > EVENT_BUFFER_MAX)
		shift(buf);
}

/**
 * Resolves a hostapd ubus path to the kernel radio name (radio0/radio1/...).
 *
 * hostapd's channel-switch ubus payload carries the wifi-iface ifname only,
 * not the radio it belongs to; the daemon maps ifname -> radio via the live
 * network.wireless status.
 *
 * @param {string} ifname - Wireless interface name (e.g. wlan0, phy0-ap0)
 * @returns {string|null} Radio name or null if no mapping
 */
function ifname_to_radio_name(ifname) {
	if (!ifname)
		return null;

	let status = ubus.call('network.wireless', 'status');
	if (!status)
		return null;

	for (let radio_name, radio in status) {
		if (!radio.interfaces)
			continue;
		for (let iface in radio.interfaces) {
			if (iface.ifname == ifname)
				return radio_name;
		}
	}
	return null;
}

/**
 * Extracts the wifi ifname from a hostapd ubus object path.
 *
 * @param {string} path - ubus object path like "hostapd.wlan0"
 * @returns {string|null} ifname suffix, or null
 */
function hostapd_path_to_ifname(path) {
	let m = match(path ?? '', /^hostapd\.(.+)$/);
	return m ? m[1] : null;
}

function channel_history_push(radio_name, entry) {
	let buf = channel_history_by_radio[radio_name];
	if (!buf) {
		buf = [];
		channel_history_by_radio[radio_name] = buf;
	}
	push(buf, entry);
	while (length(buf) > CHANNEL_HISTORY_BUFFER_MAX)
		shift(buf);
}

function hostapd_cache(path) {
	let obj = split(path, '.');
	if (obj[0] != 'hostapd' || !obj[1])
		return null;

	let ifname = obj[1];
	if (!hostapd[ifname]) {
		hostapd[ifname] = ubus.call(path, 'get_status');
		if (!hostapd[ifname])
			return null;
		hostapd[ifname].ifname = ifname;
		hostapd[ifname].path = path;
		log_info('hostapd %s ssid=%s', ifname, hostapd[ifname].ssid);
	}
	return hostapd[ifname];
}

let hapd_handlers = {
	'sta-authorized': function(notify, hapd) {
		if (!hapd)
			return;

		let msg = {
			device: notify.data.vlan ? `${notify.data.ifname}-v${notify.data.vlan}` : notify.data.ifname,
			address: notify.data.address
		};

		if (notify.data['rate-limit']) {
			msg.rate_ingress = `${notify.data['rate-limit'][0]}mbit`;
			msg.rate_egress = `${notify.data['rate-limit'][1]}mbit`;
		} else if (hapd.ssid) {
			msg.defaults = md5(hapd.ssid);
		}

		if (!msg.rate_ingress && !msg.defaults)
			return;

		ubus.call('ratelimit', 'client_set', msg);
	},

	disassoc: function(notify) {
		ubus.call('ratelimit', 'client_delete', {
			address: notify.data.address,
			device: notify.data.ifname
		});
	},

	vlan_remove: function(notify) {
		ubus.call('ratelimit', 'device_delete', { device: notify.data.ifname });
	},

	'channel-switch': function(notify) {
		let ifname = notify.data?.ifname ?? hostapd_path_to_ifname(notify.info?.object?.path);
		let freq = notify.data?.freq;
		if (!ifname || !freq)
			return;

		let radio_name = ifname_to_radio_name(ifname);
		if (!radio_name)
			return;

		let to_channel = ubbf.freq_to_channel(freq);
		let from_channel = previous_channel_by_radio[radio_name] ?? 0;
		let now = time();
		let ts_iso = ubbf.iso8601_format(now);

		let reason = 'ChannelSwitch';
		let radar = pending_radar_by_radio[radio_name];
		if (radar && (now - radar.epoch) <= RADAR_CORRELATION_WINDOW_SECONDS)
			reason = 'DFSRadar';
		delete pending_radar_by_radio[radio_name];

		channel_history_push(radio_name, {
			timestamp: ts_iso,
			epoch: now,
			from_channel: from_channel,
			to_channel: to_channel,
			frequency: freq,
			bssid: notify.data?.bssid ?? '',
			reason: reason
		});
		previous_channel_by_radio[radio_name] = to_channel;
		log_info('channel-switch radio=%s %d->%d freq=%d reason=%s', radio_name, from_channel, to_channel, freq, reason);
	},

	'radar-detected': function(notify) {
		let ifname = notify.data?.ifname ?? hostapd_path_to_ifname(notify.info?.object?.path);
		let radio_name = ifname_to_radio_name(ifname);
		if (!radio_name)
			return;

		pending_radar_by_radio[radio_name] = {
			epoch: time(),
			frequency: notify.data?.frequency ?? 0,
			width: notify.data?.width ?? 0
		};
		log_info('radar-detected radio=%s freq=%d width=%d', radio_name, notify.data?.frequency ?? 0, notify.data?.width ?? 0);
	}
};

function hapd_subscriber_notify_cb(req) {
	if (req.type == 'probe')
		return 0;

	let handler = hapd_handlers[req.type];
	if (!handler)
		return 0;

	// Some events (radar-detected) do not carry ifname in their payload;
	// derive it from the publishing object's ubus path. Mutating req.data
	// keeps handlers that read notify.data?.ifname working unchanged.
	let ifname = req.data?.ifname ?? hostapd_path_to_ifname(req.info?.object?.path);
	if (!ifname)
		return 0;

	if (!req.data)
		req.data = {};
	if (!req.data.ifname)
		req.data.ifname = ifname;

	let hapd = hostapd_cache('hostapd.' + ifname);
	handler(req, hapd);
	return 0;
}

function hapd_subscriber_remove_cb(id) {
	for (let ifname in hostapd) {
		log_info('hostapd %s removed', ifname);
		delete hostapd[ifname];
	}
}

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

function event_data_status_handler(req) {
	return {
		association: association_events,
		disassociation: disassociation_events,
		failed_connection: failed_connection_events
	};
}

function event_data_clear_handler(req) {
	association_events = [];
	disassociation_events = [];
	failed_connection_events = [];
	return {};
}

function channel_history_status_handler(req) {
	let out = {};
	for (let radio_name, entries in channel_history_by_radio)
		out[radio_name] = entries;
	return { radios: out };
}

function channel_history_clear_handler(req) {
	channel_history_by_radio = {};
	pending_radar_by_radio = {};
	return {};
}

/**
 * Registers hostapd and umap notification subscribers.
 */
export function subscribe() {
	ubus.subscriber(hapd_subscriber_notify_cb, hapd_subscriber_remove_cb, ['hostapd.*']);
	ubus.subscriber(umap_notify_cb, null, ['umap', 'umap-agent']);
};

/**
 * Returns the ubus method table for the WiFi event data buffer.
 *
 * @returns {object} Method definition for event_data_status
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
		},
		channel_history_status: {
			call: channel_history_status_handler,
			args: {}
		},
		channel_history_clear: {
			call: channel_history_clear_handler,
			args: {}
		}
	};
};
