'use strict';

import * as ubus from 'ubus';
import * as iwinfo from 'iwinfo';
import * as schemas from 'ubbf.schemas.WiFi';
import {
	channel_width_to_bandwidth,
	wireless_status_get,
	ssid_ifname_get,
	assoclist_get,
	iwinfo_update,
	phy_for_band,
	band_to_uci,
	phy_supported_bands,
	phy_supported_standards,
	phy_possible_channels,
	phy_supported_bandwidths,
	phy_max_ssids,
	phy_max_bitrate
} from 'ubbf.utils.wifi';
import { log_info, log_debug, log_err } from 'ubbf.utils.logging';
import { popen_async } from 'ubbf.utils.process';
import { last_change_get } from 'ubbf.utils.netdev_change';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';
import * as ubbf from 'ubbf';

/**
 * Gets the first interface name for a radio.
 *
 * @param {string} radio_name - Radio name (e.g., radio0)
 * @returns {string|null} Interface name or null if not found
 */
function radio_ifname_get(radio_name) {
	let status = wireless_status_get();
	if (!status || !status[radio_name])
		return null;

	let radio = status[radio_name];
	if (!radio.interfaces || length(radio.interfaces) == 0)
		return null;

	return radio.interfaces[0].ifname;
}

/**
 * Determines the WiFi operating standard from station flags.
 *
 * @param {object} sta - Station data with tx/rx flags
 * @returns {string} WiFi standard (be, ax, ac, n) or empty string
 */
function operating_standard_get(sta) {
	return ubbf.wifi_operating_standard(sta.tx?.flags ?? sta.rx?.flags ?? []);
}

/**
 * Converts a station entry to TR-181 AssociatedDevice format.
 *
 * @param {string} mac - Station MAC address
 * @param {object} sta - Station data from iwinfo.assoclist
 * @returns {object} TR-181 formatted AssociatedDevice object
 */
function station_to_object(mac, sta) {
	let assoc_time = '';
	let connected = sta.connected_time;
	if (connected != null)
		assoc_time = ubbf.iso8601_format(time() - connected);

	// iwinfo reports bitrate_raw in units of 100 kbit/s; TR-181 wants kbit/s
	return {
		...schemas.AccessPoint_AssociatedDevice.defaults,
		MACAddress: mac,
		SignalStrength: sprintf('%d', sta.signal ?? 0),
		Noise: sprintf('%d', sta.noise ?? 0),
		LastDataDownlinkRate: sprintf('%d', (sta.tx?.bitrate_raw ?? 0) * 100),
		LastDataUplinkRate: sprintf('%d', (sta.rx?.bitrate_raw ?? 0) * 100),
		Active: 'true',
		AuthenticationState: 'true',
		OperatingStandard: operating_standard_get(sta),
		Retransmissions: '0',
		AssociationTime: assoc_time
	};
}

/**
 * Gets the interface name for an access point from its SSIDReference.
 *
 * @param {object} ctx - Context with config or parent containing SSIDReference
 * @returns {string|null} Interface name or null if not found
 */
function accesspoint_ifname_get(ctx) {
	let ap_config = ctx.parent ?? ctx.config;
	if (!ap_config)
		return null;

	let ssid_ref = ap_config.SSIDReference;
	if (!ssid_ref)
		return null;

	let ssid_match = match(ssid_ref, /Device\.WiFi\.SSID\.(\d+)/);
	if (!ssid_match)
		return null;

	return ssid_ifname_get(int(ssid_match[1]));
}

/**
 * Fetches the per-radio channel-switch history maintained by the ubbf-device
 * daemon. The daemon subscribes to hostapd's channel-switch and radar-detected
 * ubus notifications and keeps a rolling buffer per radio; this helper just
 * shapes the data into TR-181 form.
 */
function channel_history_entries_get(radio_name) {
	if (!radio_name)
		return [];

	let resp = ubus.call('bbf-device', 'channel_history_status', {});
	if (!resp)
		return [];

	let radios = resp.radios ?? {};
	let raw = radios[radio_name];
	return type(raw) == 'array' ? raw : [];
}

function channel_history_to_object(entry) {
	return {
		Timestamp: entry.timestamp ?? '',
		FromChannel: sprintf('%d', entry.from_channel ?? 0),
		ToChannel: sprintf('%d', entry.to_channel ?? 0),
		Frequency: sprintf('%d', entry.frequency ?? 0),
		BSSID: entry.bssid ?? '',
		Reason: entry.reason ?? ''
	};
}

function channel_history_get(ctx) {
	let radio_cfg = ctx.parent ?? ctx.config;
	let radio_name = radio_cfg?.Name;
	if (!radio_name)
		return ctx.instance == null ? {} : null;

	let entries = channel_history_entries_get(radio_name);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(entries, channel_history_to_object);

	let entry = ubbf.get_by_instance(entries, ctx.instance);
	if (!entry)
		return null;

	return channel_history_to_object(entry);
}

/**
 * Get handler for Device.WiFi.Radio.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Radio properties with runtime status
 */
function radio_get(ctx) {
	if (!ctx.config)
		return null;

	let radio_name = ctx.config.Name;
	if (!radio_name)
		return null;

	iwinfo_update();

	let ifname = radio_ifname_get(radio_name);
	let status = 'Down';
	let channel = ctx.config.Channel ?? '0';
	let current_bandwidth = '';

	let iface = ifname ? iwinfo.ifaces?.[ifname] : null;
	if (iface) {
		status = 'Up';
		if (iface.wiphy_freq)
			channel = sprintf('%d', ubbf.freq_to_channel(iface.wiphy_freq));
		if (iface.channel_width != null)
			current_bandwidth = channel_width_to_bandwidth(iface.channel_width);
	}

	// UCI accepts both literal 'auto' and channel '0' as auto-channel selection;
	// either form implies AutoChannelEnable for TR-181 reporting
	let auto_channel = ubbf.to_bool(ctx.config.AutoChannelEnable) ||
		ctx.config.Channel == '0' ||
		ctx.config.Channel == 'auto';

	let history_entries = channel_history_entries_get(radio_name);
	let history_dict = {};
	for (let i = 0; i < length(history_entries); i++)
		history_dict[sprintf('%d', i + 1)] = channel_history_to_object(history_entries[i]);

	let result = {
		...ubbf.ctx_config(ctx),
		Status: status,
		// TR-181 Channel is the channel actually in use; when the radio is
		// up report the live channel (the auto-selected one under auto),
		// falling back to the stored value only when it is down
		Channel: iface ? channel : (ctx.config.Channel ?? '0'),
		ChannelsInUse: channel,
		CurrentOperatingChannelBandwidth: current_bandwidth,
		AutoChannelEnable: auto_channel ? 'true' : 'false',
		X_UBBF_ChannelHistoryNumberOfEntries: sprintf('%d', length(history_entries)),
		X_UBBF_ChannelHistory: history_dict
	};

	if (length(history_entries) > 0) {
		let latest = history_entries[length(history_entries) - 1];
		// TR-181 ChannelLastChange is seconds elapsed since the change, not the epoch
		let epoch = latest.epoch ?? 0;
		result.ChannelLastChange = sprintf('%d', epoch > 0 ? time() - epoch : 0);
		result.ChannelLastSelectionReason = latest.reason ?? '';
	}

	let band = band_to_uci(ctx.config.OperatingFrequencyBand);
	let phy_info = phy_for_band(band);
	if (phy_info) {
		let phy = phy_info.phy;
		let band_idx = phy_info.band_idx;

		result.SupportedFrequencyBands = phy_supported_bands(phy);
		result.SupportedStandards = phy_supported_standards(phy, band_idx);
		result.PossibleChannels = phy_possible_channels(phy, band_idx);
		result.SupportedOperatingChannelBandwidths = phy_supported_bandwidths(phy, band_idx);
		// TR-181 TransmitPowerSupported is a list of supported power levels
		// as a percentage of full power, not a dBm value; mac80211 allows
		// continuous control plus auto, so report the spec's percentage
		// ladder with -1 (auto)
		result.TransmitPowerSupported = '-1,0,25,50,75,100';
		result.MaxSupportedSSIDs = sprintf('%d', phy_max_ssids(phy));
		result.MaxBitRate = sprintf('%d', phy_max_bitrate(phy, band_idx));
	}

	if (iface?.wiphy_country)
		result.RegulatoryDomain = iface.wiphy_country;

	return result;
}

/**
 * Get handler for Device.WiFi.Radio.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} Radio statistics with noise level
 */
function radio_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	if (!parent?.Name)
		return null;

	let ifname = radio_ifname_get(parent.Name);
	if (!ifname)
		return null;

	let stats = ifstats_get(ifname);

	let noise = '0';
	iwinfo_update();
	let iface = iwinfo.ifaces?.[ifname];
	if (iface?.noise)
		noise = sprintf('%d', iface.noise);

	return {
		...stats,
		Noise: noise
	};
}

/**
 * Get handler for Device.WiFi.SSID.{i}.
 *
 * @param {object} ctx - Context with config and instance
 * @returns {object|null} SSID properties with runtime status
 */
function ssid_get(ctx) {
	if (!ctx.config)
		return null;

	let ifname = ssid_ifname_get(ctx.instance);

	iwinfo_update();

	let status = 'Down';
	let mac = '';

	let iface = ifname ? iwinfo.ifaces?.[ifname] : null;
	if (iface) {
		status = 'Up';
		if (iface.mac)
			mac = uc(iface.mac);
	}

	return {
		...ctx.config,
		Name: ifname ?? ctx.config.Name,
		Status: status,
		BSSID: mac,
		MACAddress: mac,
		LastChange: last_change_get(ifname)
	};
}

/**
 * Get handler for Device.WiFi.SSID.{i}.Stats.
 *
 * @param {object} ctx - Context with parent config
 * @returns {object|null} SSID interface statistics
 */
function ssid_stats_get(ctx) {
	let parent = ctx.parent ?? ctx.config;
	let ssid_instance = parent?.['.instance'] ?? ctx.instance;
	let ifname = ssid_ifname_get(ssid_instance);
	if (!ifname)
		return null;

	return ifstats_get(ifname);
}

/**
 * Maps an IEEE 802.11 channel number plus band label to a centre frequency
 * in MHz, for the bands UBBF radios actually run on. Returns 0 when the
 * channel is out of the band's valid range.
 */
function channel_to_freq(band, channel) {
	if (band == '2.4GHz') {
		if (channel == 14)
			return 2484;
		if (channel >= 1 && channel <= 13)
			return 2407 + channel * 5;
	} else if (band == '5GHz') {
		if (channel >= 36 && channel <= 177)
			return 5000 + channel * 5;
	} else if (band == '6GHz') {
		if (channel >= 1 && channel <= 233)
			return 5950 + channel * 5;
	}
	return 0;
}

/**
 * Sync operation handler for Device.WiFi.Radio.{i}.X_UBBF_ChannelSwitch().
 *
 * Drives a runtime CSA on the radio's first AP iface so the hostapd
 * channel-switch ubus notification lands in the ubbf-device channel-history
 * buffer. UCI writes to Radio.{i}.Channel trigger a full hostapd restart and
 * do not generate a CSA event, hence this dedicated entry point.
 *
 * @param {object} input - Operation input with Channel parameter
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @param {object} root - Runtime data root
 * @returns {object|null} Empty object on success, null on failure
 */
function channel_switch_op(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		die('channel_switch: missing radio instance');

	let radio = root?.Device?.WiFi?.Radio?.['' + idx];
	if (!radio?.Name)
		die(sprintf('channel_switch: radio %s not found in data model', idx));

	let channel = int(input?.Channel);
	if (!channel)
		die('channel_switch: Channel input missing or zero');

	let band = radio.OperatingFrequencyBand;
	let freq = channel_to_freq(band, channel);
	if (!freq)
		die(sprintf('channel_switch: channel %d invalid for band %s', channel, band));

	let ifname = radio_ifname_get(radio.Name);
	if (!ifname)
		die(sprintf('channel_switch: no AP iface on radio %s (network.wireless not up?)', radio.Name));

	let object = 'hostapd.' + ifname;
	// Default to a 20 MHz HT CSA so hostapd does not need a center_freq1 /
	// secondary_channel_offset hint. Callers wanting a wider CSA can use
	// switch_chan directly via ubus.
	//
	// bcn_count must be > 1: without it hostapd passes count 0 and
	// mac80211 skips the countdown beacon entirely ("switch
	// immediately"), a path that never finalises on multi-radio wiphys
	// (mt7996) and leaves csa_active armed forever. A real countdown is
	// also what announces the switch to associated clients.
	let data = {
		freq: freq,
		bandwidth: 20,
		ht: true,
		bcn_count: 5
	};
	log_info('channel_switch: %s freq=%d (ch=%d, band=%s)', object, freq, channel, band);

	let result = ubus.call({ object: object, method: 'switch_chan', data: data });
	let err_code = ubus.error(true);
	if (err_code && err_code != ubus.STATUS_NO_DATA)
		die(sprintf('channel_switch: %s switch_chan failed (ubus status %d, freq=%d)', object, err_code, freq));

	return result ?? {};
}

/**
 * Sync operation handler for Device.WiFi.X_UBBF_ChannelHistoryReset().
 *
 * Clears the per-radio channel-switch history kept by ubbf-device. Used by
 * tests to baseline the buffer before driving a known CSA.
 *
 * @returns {object} Empty object on success
 */
function channel_history_reset_op() {
	let res = ubus.call('bbf-device', 'channel_history_clear', {});
	if (!res) {
		log_err('channel_history_reset: bbf-device.channel_history_clear failed');
		return null;
	}
	return {};
}

/**
 * Sync operation handler for Device.WiFi.Reset().
 *
 * @returns {object} Empty object on success
 */
function wifi_reset() {
	log_info('wifi_reset: restarting WiFi sub-system');
	system('wifi');
	return {};
}

/**
 * Sync operation handler for Device.WiFi.X_UBBF_SetEnabled().
 *
 * @param {object} input - Operation input with Enabled parameter
 * @returns {object} Empty object on success
 */
function wifi_set_enabled(input) {
	let enabled = ubbf.to_bool(input.Enabled);
	let method = enabled ? 'up' : 'down';
	log_info('wifi_set_enabled: calling network.wireless %s', method);
	ubus.call('network.wireless', method);
	return {};
}

/**
 * Sync operation handler for WiFi.Radio.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function radio_stats_reset(input, command_key, instances, root) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let radio = root?.Device?.WiFi?.Radio?.['' + idx];
	if (!radio?.Name)
		return null;

	let ifname = radio_ifname_get(radio.Name);
	if (!ifname)
		return null;

	if (!ifstats_reset(ifname))
		return null;
	return {};
}

/**
 * Sync operation handler for WiFi.SSID.{i}.Stats.Reset().
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers from path match
 * @returns {object|null} Empty object on success, null on failure
 */
function ssid_stats_reset(input, command_key, instances) {
	let idx = instances[0];
	if (idx == null)
		return null;

	let ifname = ssid_ifname_get(idx);
	if (!ifname)
		return null;

	if (!ifstats_reset(ifname))
		return null;
	return {};
}

/**
 * Builds the access point result object.
 *
 * Centralises the result shape used by access_point_get's three early-return
 * paths (disabled, missing ifname, missing iwinfo entry) so every exit returns
 * the same TR-181 fields.
 *
 * @param {object} config - Access point configuration
 * @param {string} status - Status string (Enabled/Disabled)
 * @param {object} assoc_devices - Associated devices map
 * @param {number} assoc_count - Number of associated devices
 * @returns {object} Access point result object
 */
function access_point_result_build(config, status, assoc_devices, assoc_count) {
	return {
		...config,
		Status: status,
		AssociatedDeviceNumberOfEntries: sprintf('%d', assoc_count),
		AssociatedDevice: assoc_devices,
		X_UBBF_VendorIENumberOfEntries: sprintf('%d', ubbf.instance_count(config?.X_UBBF_VendorIE))
	};
}

/**
 * Get handler for Device.WiFi.AccessPoint.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Access point properties with associated devices
 */
function access_point_get(ctx) {
	if (!ctx.config)
		return null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = enabled ? 'Enabled' : 'Disabled';

	if (!enabled)
		return access_point_result_build(ctx.config, status, {}, 0);

	let ifname = accesspoint_ifname_get(ctx);
	if (!ifname)
		return access_point_result_build(ctx.config, status, {}, 0);

	iwinfo_update();
	if (!iwinfo.ifaces?.[ifname])
		return access_point_result_build(ctx.config, status, {}, 0);

	let stations = assoclist_get(ifname);
	let assoc_devices = {};
	let instance = 1;

	for (let mac, sta in stations) {
		assoc_devices[sprintf('%d', instance)] = station_to_object(mac, sta);
		instance++;
	}

	return access_point_result_build(ctx.config, status, assoc_devices, length(keys(stations)));
}

/**
 * Builds array of station entries from assoclist.
 *
 * Adapter for ubbf.enumerate_instances(), which expects an array of entries
 * rather than the MAC-keyed dict that iwinfo.assoclist returns.
 *
 * @param {object} stations - Stations object keyed by MAC
 * @returns {array} Array of {mac, sta} objects
 */
function stations_to_array(stations) {
	let entries = [];
	for (let mac, sta in stations)
		push(entries, { mac, sta });
	return entries;
}

/**
 * Converts a station entry to TR-181 object format.
 *
 * Thunk that unpacks the {mac, sta} shape produced by stations_to_array
 * back into the (mac, sta) signature that station_to_object expects, so the
 * pair can be passed as an enumerate_instances() callback.
 *
 * @param {object} entry - Entry with mac and sta properties
 * @returns {object} TR-181 AssociatedDevice object
 */
function station_entry_to_object(entry) {
	return station_to_object(entry.mac, entry.sta);
}

/**
 * Gets all associated devices for an access point as enumerated instances.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Enumerated instance object of associated devices
 */
function associated_device_container_get(ctx) {
	let ifname = accesspoint_ifname_get(ctx);
	if (!ifname)
		return {};

	iwinfo_update();
	if (!iwinfo.ifaces?.[ifname])
		return {};

	let stations = assoclist_get(ifname);
	let entries = stations_to_array(stations);

	return ubbf.enumerate_instances(entries, station_entry_to_object);
}

/**
 * Get handler for Device.WiFi.AccessPoint.{i}.AssociatedDevice.{i}.
 *
 * @param {object} ctx - Context with config and instance
 * @returns {object|null} Associated device properties or enumerated list
 */
function associated_device_get(ctx) {
	let ifname = accesspoint_ifname_get(ctx);
	if (!ifname)
		return ctx.instance == null ? {} : null;

	iwinfo_update();
	if (!iwinfo.ifaces?.[ifname])
		return ctx.instance == null ? {} : null;

	let stations = assoclist_get(ifname);
	let entries = stations_to_array(stations);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(entries, station_entry_to_object);

	let entry = ubbf.get_by_instance(entries, ctx.instance);
	if (!entry)
		return null;

	return station_entry_to_object(entry);
}

/**
 * Parses wifi-scan JSON output into TR-181 operation output format.
 *
 * @param {string} data - Raw JSON output from wifi-scan
 * @returns {object|null} TR-181 formatted output object, or null on parse failure
 */
function scan_output_parse(data) {
	if (!data)
		return null;

	let parsed;
	try {
		parsed = json(data);
	} catch (e) {
		return null;
	}

	if (!parsed || !parsed.results)
		return null;

	for (let skip in parsed.skipped ?? [])
		log_info('neighboring_wifi: skipped %s: %s', skip.Interface, skip.Reason);

	let output = {
		Status: 'Complete',
		ResultNumberOfEntries: sprintf('%d', length(parsed.results))
	};

	for (let i = 0; i < length(parsed.results); i++) {
		let r = parsed.results[i];
		let idx = i + 1;
		output[sprintf('Result.%d.Radio', idx)] = r.Radio;
		output[sprintf('Result.%d.SSID', idx)] = r.SSID;
		output[sprintf('Result.%d.BSSID', idx)] = r.BSSID;
		output[sprintf('Result.%d.Mode', idx)] = r.Mode;
		output[sprintf('Result.%d.Channel', idx)] = r.Channel;
		output[sprintf('Result.%d.SignalStrength', idx)] = r.SignalStrength;
		output[sprintf('Result.%d.SecurityModeEnabled', idx)] = r.SecurityModeEnabled;
		output[sprintf('Result.%d.EncryptionMode', idx)] = r.EncryptionMode;
		output[sprintf('Result.%d.OperatingFrequencyBand', idx)] = r.OperatingFrequencyBand;
		output[sprintf('Result.%d.OperatingStandards', idx)] = r.OperatingStandards;
		output[sprintf('Result.%d.OperatingChannelBandwidth', idx)] = r.OperatingChannelBandwidth;
		output[sprintf('Result.%d.Noise', idx)] = r.Noise;
	}

	return output;
}

/**
 * Async operation handler for Device.WiFi.NeighboringWiFiDiagnostic().
 *
 * @param {object} input - Operation input parameters (unused)
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - Command key (unused)
 */
function neighboring_wifi_handler(input, instance, complete, command_key) {
	log_info('neighboring_wifi: starting diagnostic');

	popen_async('/usr/libexec/ubbf/wifi-scan', (result) => {
		log_debug('neighboring_wifi: output:\n%s', result.data ?? '');

		if (result.error) {
			log_err('neighboring_wifi: %s', result.error);
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = scan_output_parse(result.data);
		if (!output) {
			let err_msg = 'scan failed';
			let parsed;
			try { parsed = json(result.data); } catch (e) {}
			if (parsed?.error)
				err_msg = parsed.error;
			log_err('neighboring_wifi: %s', err_msg);
			complete(instance, USP_ERR_COMMAND_FAILURE, err_msg, {});
			return;
		}

		log_info('neighboring_wifi: complete, found %s networks', output.ResultNumberOfEntries);
		complete(instance, 0, null, output);
	});
}

/**
 * Get handler for Device.WiFi.AccessPoint.{i}.WPS.
 *
 * @param {object} ctx - Context with config and parent
 * @returns {object} WPS properties with runtime status from hostapd
 */
function wps_get(ctx) {
	let result = ubbf.ctx_config(ctx);

	if (!ubbf.to_bool(result.Enable)) {
		result.Status = 'Disabled';
		return result;
	}

	let ifname = accesspoint_ifname_get(ctx);
	if (!ifname)
		return result;

	let wps = ubus.call('hostapd.' + ifname, 'wps_status', {});
	if (!wps) {
		result.Status = 'Error';
		return result;
	}

	// hostapd 'Overlap' indicates simultaneous PBC sessions (a TR-181 WPS error
	// condition); any other state with WPS enabled is treated as Configured
	if (wps.pbc_status == 'Overlap')
		result.Status = 'Error';
	else
		result.Status = 'Configured';

	return result;
}

/**
 * Async operation handler for Device.WiFi.AccessPoint.{i}.WPS.InitiateWPSPBC().
 *
 * @param {object} input - Operation input (unused)
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {array} instances - Instance numbers from path match
 */
function wps_pbc_handler(input, instance, complete, instances, command_key, root) {
	let ap_idx = instances[0];
	if (ap_idx == null) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'missing AP instance', { Status: 'Error_Other' });
		return;
	}

	let ap = root?.Device?.WiFi?.AccessPoint?.['' + ap_idx];
	if (!ap?.SSIDReference) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'AP not found', { Status: 'Error_Other' });
		return;
	}

	let ssid_match = match(ap.SSIDReference, /Device\.WiFi\.SSID\.(\d+)/);
	if (!ssid_match) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'invalid SSIDReference', { Status: 'Error_Other' });
		return;
	}

	let ifname = ssid_ifname_get(int(ssid_match[1]));
	if (!ifname) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'interface not found', { Status: 'Error_Other' });
		return;
	}

	log_info('wps_pbc: starting PBC on %s', ifname);
	ubus.call({ object: 'hostapd.' + ifname, method: 'wps_start', data: {} });

	let err_code = ubus.error(true);
	if (err_code && err_code != ubus.STATUS_NO_DATA) {
		let err = sprintf('wps_start failed (code %d)', err_code);
		log_err('wps_pbc: %s: %s', ifname, err);
		complete(instance, USP_ERR_COMMAND_FAILURE, err, { Status: 'Error_Other' });
		return;
	}

	log_info('wps_pbc: PBC initiated on %s', ifname);
	complete(instance, 0, null, { Status: 'Success' });
}

/**
 * Get handler for Device.WiFi.
 *
 * @param {object} ctx - Context with config
 * @returns {object} WiFi properties with instance counts
 */
function wifi_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		RadioNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Radio)),
		SSIDNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.SSID)),
		AccessPointNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AccessPoint)),
		EndPointNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.EndPoint)),
		X_UBBF_QoSMapNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.X_UBBF_QoSMap)),
		X_UBBF_QoSMap: ctx.config?.X_UBBF_QoSMap ?? {}
	};
}

export const model = {
	'Device.WiFi': {
		schema: schemas.WiFi,
		get: wifi_get
	},

	'Device.WiFi.X_UBBF_QoSMap': {
	},

	'Device.WiFi.X_UBBF_QoSMap.{i}': {
		schema: schemas.WiFi_X_UBBF_QoSMap
	},

	'Device.WiFi.Radio': {
	},

	'Device.WiFi.Radio.{i}': {
		schema: schemas.Radio,
		get: radio_get
	},

	'Device.WiFi.Radio.{i}.Stats': {
		schema: schemas.Radio_Stats,
		get: radio_stats_get
	},

	'Device.WiFi.Radio.{i}.X_UBBF_ChannelHistory': {
	},

	'Device.WiFi.Radio.{i}.X_UBBF_ChannelHistory.{i}': {
		schema: schemas.Radio_X_UBBF_ChannelHistory,
		get: channel_history_get
	},

	'Device.WiFi.SSID': {
	},

	'Device.WiFi.SSID.{i}': {
		schema: schemas.SSID,
		get: ssid_get
	},

	'Device.WiFi.SSID.{i}.Stats': {
		schema: schemas.SSID_Stats,
		get: ssid_stats_get
	},

	'Device.WiFi.AccessPoint': {
	},

	'Device.WiFi.AccessPoint.{i}': {
		schema: schemas.AccessPoint,
		get: access_point_get
	},

	'Device.WiFi.AccessPoint.{i}.Security': {
		schema: schemas.AccessPoint_Security
	},

	'Device.WiFi.AccessPoint.{i}.WPS': {
		schema: schemas.AccessPoint_WPS,
		get: wps_get
	},

	'Device.WiFi.AccessPoint.{i}.Accounting': {
		schema: schemas.AccessPoint_Accounting
	},

	'Device.WiFi.AccessPoint.{i}.AssociatedDevice': {
	},

	'Device.WiFi.AccessPoint.{i}.AssociatedDevice.{i}': {
		schema: schemas.AccessPoint_AssociatedDevice,
		get: associated_device_get
	},

	'Device.WiFi.AccessPoint.{i}.AC': {
	},

	'Device.WiFi.AccessPoint.{i}.AC.{i}': {
		schema: schemas.AccessPoint_AC
	},

	'Device.WiFi.AccessPoint.{i}.X_UBBF_VendorIE': {
	},

	'Device.WiFi.AccessPoint.{i}.X_UBBF_VendorIE.{i}': {
		schema: schemas.AccessPoint_X_UBBF_VendorIE
	},

	'Device.WiFi.Templates': {
	},

	'Device.WiFi.Templates.APMLDTemplate': {
	},

	'Device.WiFi.Templates.APMLDTemplate.{i}': {
		schema: schemas.APMLDTemplate
	},

	'Device.WiFi.EndPoint': {
	},

	'Device.WiFi.EndPoint.{i}': {
		schema: schemas.EndPoint
	},

	'Device.WiFi.NeighboringWiFiDiagnostic': {
		schema: schemas.NeighboringWiFiDiagnostic,
		get: (ctx) => ubbf.ctx_config(ctx)
	},

	'Device.WiFi.NeighboringWiFiDiagnostic.Result': {
	},

	'Device.WiFi.NeighboringWiFiDiagnostic.Result.{i}': {
		schema: schemas.NeighboringWiFiDiagnostic_Result
	}
};

export const operations = {
	'Device.WiFi.Reset()': {
		type: 'sync',
		handler: wifi_reset
	},

	'Device.WiFi.X_UBBF_SetEnabled()': {
		type: 'sync',
		handler: wifi_set_enabled
	},

	'Device.WiFi.X_UBBF_ChannelHistoryReset()': {
		type: 'sync',
		handler: channel_history_reset_op
	},

	'Device.WiFi.NeighboringWiFiDiagnostic()': {
		type: 'async',
		handler: neighboring_wifi_handler,
		store_results: 'Device.WiFi.NeighboringWiFiDiagnostic',
		output_key_map: { Status: 'DiagnosticsState' }
	},

	'Device.WiFi.Radio.{i}.Stats.Reset()': {
		type: 'sync',
		handler: radio_stats_reset
	},

	'Device.WiFi.Radio.{i}.X_UBBF_ChannelSwitch()': {
		type: 'sync',
		handler: channel_switch_op
	},

	'Device.WiFi.SSID.{i}.Stats.Reset()': {
		type: 'sync',
		handler: ssid_stats_reset
	},

	'Device.WiFi.AccessPoint.{i}.WPS.InitiateWPSPBC()': {
		type: 'async',
		handler: wps_pbc_handler
	}
};
