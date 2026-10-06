'use strict';

import { popen_async } from 'ubbf.utils.process';
import { interface_resolve } from 'ubbf.utils.path';
import { log_info, log_debug } from 'ubbf.utils.logging';

/**
 * Parses server selection JSON output into TR-143 format.
 *
 * @param {string} data - Raw JSON output from serverselection
 * @returns {object} TR-143 result with fields Status, FastestHost,
 *   IPAddressUsed, MinimumResponseTime, AverageResponseTime,
 *   MaximumResponseTime; defaults to an Error_Other shell when input
 *   is missing or unparseable.
 */
function output_parse(data) {
	let output = {
		Status: 'Error_Other',
		FastestHost: '',
		IPAddressUsed: '',
		MinimumResponseTime: '0',
		AverageResponseTime: '0',
		MaximumResponseTime: '0'
	};

	if (!data)
		return output;

	let result;
	try {
		result = json(data);
	} catch (e) {
		return output;
	}

	if (!result)
		return output;

	return {
		Status: result.Status ?? 'Error_Other',
		FastestHost: result.FastestHost ?? '',
		IPAddressUsed: result.IPAddressUsed ?? '',
		MinimumResponseTime: result.MinimumResponseTime ?? '0',
		AverageResponseTime: result.AverageResponseTime ?? '0',
		MaximumResponseTime: result.MaximumResponseTime ?? '0'
	};
}

/**
 * Async handler for Device.IP.Diagnostics.ServerSelectionDiagnostics operation.
 *
 * @param {object} input - Input parameters with HostList, Protocol, NumberOfRepetitions, Timeout, Interface, ProtocolVersion
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let host_list = input.HostList ?? '';

	if (host_list == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'HostList parameter is required', {});
		return;
	}

	let iface = input.Interface ?? '';
	let iface_name;
	if (iface != '') {
		iface_name = interface_resolve(root, iface);
		if (!iface_name) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Cannot resolve interface', {});
			return;
		}
	}

	let protocol = input.Protocol ?? 'ICMP';
	let proto_version = input.ProtocolVersion ?? 'Any';
	let count = int(input.NumberOfRepetitions) || 3;
	let timeout = int(input.Timeout) || 1000;

	log_info('serverselection: hosts=%s protocol=%s count=%d', host_list, protocol, count);

	let ip_flag = (proto_version == 'IPv4') ? '-4'
	            : (proto_version == 'IPv6') ? '-6'
	            : null;

	popen_async([
		{raw: '/usr/libexec/ubbf/serverselection'},
		'-H', host_list,
		'-p', protocol,
		'-n', count,
		'-t', timeout,
		iface_name ? '-i' : null, iface_name,
		ip_flag,
	], (result) => {
		log_debug('serverselection: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = output_parse(result.data);
		log_info('serverselection: complete status=%s fastest=%s', output.Status, output.FastestHost);
		complete(instance, 0, null, output);
	});
};
