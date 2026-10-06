'use strict';

import { popen_async } from 'ubbf.utils.process';
import { interface_resolve } from 'ubbf.utils.path';
import { log_info, log_debug } from 'ubbf.utils.logging';

/**
 * Parses UDP echo client JSON output into TR-143 format.
 *
 * @param {string} data - Raw JSON output from udpecho-client
 * @returns {object} TR-143 result with fields Status, IPAddressUsed,
 *   SuccessCount, FailureCount, MinimumResponseTime, AverageResponseTime,
 *   MaximumResponseTime; defaults to an Error_Other shell when input
 *   is missing, unparseable, or carries an explicit error field.
 */
function output_parse(data) {
	let output = {
		Status: 'Error_Other',
		IPAddressUsed: '',
		SuccessCount: '0',
		FailureCount: '0',
		AverageResponseTime: '0',
		MinimumResponseTime: '0',
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

	if (result.error) {
		output.Status = 'Error_Other';
		return output;
	}

	return {
		Status: result.Status ?? 'Error_Other',
		IPAddressUsed: result.IPAddressUsed ?? '',
		SuccessCount: result.SuccessCount ?? '0',
		FailureCount: result.FailureCount ?? '0',
		AverageResponseTime: result.AverageResponseTime ?? '0',
		MinimumResponseTime: result.MinimumResponseTime ?? '0',
		MaximumResponseTime: result.MaximumResponseTime ?? '0'
	};
}

/**
 * Async handler for Device.IP.Diagnostics.UDPEchoDiagnostics operation.
 *
 * @param {object} input - Input parameters with Host, Port, NumberOfRepetitions, Timeout, DataBlockSize, DSCP, InterTransmissionTime, Interface, ProtocolVersion
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let host = input.Host ?? '';

	if (host == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Host parameter is required', {});
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

	// 7 is the IANA-assigned UDP Echo Protocol port (RFC 862)
	let port = int(input.Port) || 7;
	let count = int(input.NumberOfRepetitions) || 1;
	let timeout = int(input.Timeout) || 1000;
	let size = int(input.DataBlockSize) || 24;
	let dscp = int(input.DSCP) || 0;
	let interval = int(input.InterTransmissionTime) || 1000;
	let proto = input.ProtocolVersion ?? 'Any';

	log_info('udpecho: host=%s port=%d count=%d', host, port, count);

	let ip_flag = (proto == 'IPv4') ? '-4'
	            : (proto == 'IPv6') ? '-6'
	            : null;

	popen_async([
		{raw: '/usr/libexec/ubbf/udpecho-client'},
		'-h', host,
		'-p', port,
		'-c', count,
		'-t', timeout,
		'-s', size,
		'-d', dscp,
		'-i', interval,
		iface_name ? '-I' : null, iface_name,
		ip_flag,
	], (result) => {
		log_debug('udpecho: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = output_parse(result.data);
		log_info('udpecho: complete status=%s', output.Status);
		complete(instance, 0, null, output);
	});
};
