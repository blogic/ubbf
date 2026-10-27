'use strict';

import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { md5 } from 'digest';
import { log_info } from 'ubbf.utils.logging';

const CHANNEL_HISTORY_BUFFER_MAX = 64;
// hostapd fires the CSA within a few seconds of a radar trigger; widen if
// observed CAC paths take longer on some drivers.
const RADAR_CORRELATION_WINDOW_SECONDS = 10;

// Per-radio rolling buffer of channel-switch events. previous_channel_by_radio
// holds the last-seen channel number per radio, used to fill FromChannel on
// the next switch since hostapd's channel-switch ubus event only carries the
// new frequency.
let channel_history_by_radio = {};
let pending_radar_by_radio = {};
let previous_channel_by_radio = {};

let hostapd = {};

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
	let ifname = hostapd_path_to_ifname(path);
	if (!ifname)
		return null;

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
 * Registers the hostapd notification subscriber.
 */
export function subscribe() {
	ubus.subscriber(hapd_subscriber_notify_cb, hapd_subscriber_remove_cb, ['hostapd.*']);
};

/**
 * Returns the ubus methods for the channel history.
 *
 * @returns {object} Method definitions of channel_history_status and channel_history_clear
 */
export function ubus_methods() {
	return {
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
