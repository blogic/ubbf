'use strict';

import * as ubbf from 'ubbf';

/**
 * Makes a string from another device fit a TR-181 string(:N) parameter:
 * removes control characters and cuts it to max_length bytes, without
 * splitting a UTF-8 sequence.
 *
 * @param {*} value - Value from the other device
 * @param {number} max_length - Maximum length in bytes
 * @returns {string} The clamped string; '' for a non-string
 */
export function text_clamp(value, max_length) {
	if (type(value) != 'string')
		return '';

	value = ubbf.uci_value_sanitise(value);
	if (length(value) <= max_length)
		return value;

	let n = max_length;
	while (n > 0 && (ord(value, n) & 0xc0) == 0x80)
		n--;

	return substr(value, 0, n);
};

/**
 * Formats a UNIX timestamp as an ISO 8601 string in UTC. Returns the
 * TR-181 "unknown time" sentinel `0001-01-01T00:00:00Z` when the input
 * is falsy so callers can safely pass missing/zero fields straight
 * through.
 *
 * @param {number} ts - UNIX timestamp, falsy for the unknown-time sentinel
 * @returns {string} ISO 8601 datetime or the unknown-time sentinel
 */
export function datetime_format(ts) {
	if (!ts)
		return '0001-01-01T00:00:00Z';

	return usp_unix_to_datetime(ts);
};

/**
 * Returns the path of the upstream Device.IP.Interface: the first enabled
 * upstream interface with NAT (an enabled Device.NAT.InterfaceSetting),
 * else the first enabled upstream interface, else null. upnpd serves the
 * external address of this interface, and the runtime rows of UPnP
 * (mappings and pinholes) reference it as their Interface.
 *
 * @param {object} root - Root config data
 * @returns {string|null} Device.IP.Interface.{i} path
 */
export function upstream_interface_ref(root) {
	let ifaces = root?.Device?.IP?.Interface;

	if (type(ifaces) != 'object')
		return null;

	for (let key, ifs in root?.Device?.NAT?.InterfaceSetting ?? {}) {
		if (type(ifs) != 'object' || ifs.Enable != 'true')
			continue;

		let m = match(ifs.Interface ?? '', /^Device\.IP\.Interface\.([0-9]+)$/);
		let iface = m ? ifaces[m[1]] : null;

		if (type(iface) == 'object' && iface.Upstream == 'true' && iface.Enable != 'false')
			return ifs.Interface;
	}

	for (let key, iface in ifaces) {
		if (type(iface) != 'object')
			continue;

		if (iface.Upstream == 'true' && iface.Enable != 'false')
			return `Device.IP.Interface.${key}`;
	}

	return null;
};

/**
 * Reports whether the lower layers of a bridge port are WiFi SSIDs only.
 * The wireless configuration adds such a port to the bridge, not netifd.
 *
 * @param {string} lower_layers - Comma-separated lower layer references
 * @returns {boolean} True when every reference is a WiFi SSID
 */
export function lower_layers_wifi(lower_layers) {
	if (!lower_layers)
		return false;

	for (let ref in ubbf.csv_to_list(lower_layers)) {
		if (!match(ref, /^Device\.WiFi\.SSID\.\d+$/))
			return false;
	}

	return true;
};

/**
 * Reports whether a bridge port keeps multicast snooping: IGMP and MLD both
 * true. A row stored before TR-181 2.21 has neither value and keeps the
 * snooping it had.
 *
 * @param {object} port - Device.Bridging.Bridge.{i}.Port.{i} row
 * @returns {boolean} True when the port is snooped
 */
export function port_snooped(port) {
	for (let name in [ 'IGMP', 'MLD' ])
		if (port?.[name] != null && !ubbf.to_bool(port[name]))
			return false;

	return true;
};

/**
 * Signals completion of a USP transfer operation.
 *
 * @param {object} ctx - Transfer context with command, command_key, url, etc.
 * @param {string} fault_string - Error message if failed, null if successful
 */
export function transfer_complete(ctx, fault_string) {
	let fault_code = fault_string ? 7000 : 0;
	let event_data = {
		Command: ctx.command,
		CommandKey: ctx.command_key ?? '',
		Requestor: '',
		TransferType: ctx.transfer_type,
		Affected: ctx.obj_path,
		TransferURL: ctx.url,
		StartTime: usp_unix_to_datetime(ctx.start_time),
		CompleteTime: usp_unix_to_datetime(time()),
		FaultCode: fault_code,
		FaultString: fault_string ?? ''
	};

	usp_datamodel_event('Device.LocalAgent.TransferComplete!', event_data);

	let output = {
		MaxRetries: '0',
		StartTime: usp_unix_to_datetime(ctx.start_time),
		CompleteTime: usp_unix_to_datetime(time())
	};

	if (fault_string)
		ctx.complete(ctx.instance, USP_ERR_COMMAND_FAILURE, fault_string, output);
	else
		ctx.complete(ctx.instance, 0, null, output);
};
