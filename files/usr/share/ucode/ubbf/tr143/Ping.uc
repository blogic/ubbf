'use strict';

import { popen_async } from 'ubbf.utils.process';
import { interface_resolve } from 'ubbf.utils.path';
import { log_info, log_debug } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

/**
 * Async handler for Device.IP.Diagnostics.IPPing operation.
 *
 * @param {object} input - Input parameters with Host, NumberOfRepetitions, Timeout, DataBlockSize, Interface, ProtocolVersion
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let host = input.Host ?? '';
	let count = int(input.NumberOfRepetitions) || 3;
	let timeout = int(input.Timeout) || 1000;
	let size = int(input.DataBlockSize) || 64;
	let protocol = input.ProtocolVersion ?? 'Any';

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

	let family_flag;
	if (protocol == 'IPv4')
		family_flag = '-4';
	else if (protocol == 'IPv6')
		family_flag = '-6';

	log_info('ping: host=%s count=%d proto=%s', host, count, protocol);

	let timeout_sec = (timeout + 999) / 1000;

	popen_async([
		{raw: 'ping'},
		family_flag,
		iface_name ? '-I' : null, iface_name,
		'-c', count,
		'-W', timeout_sec,
		'-s', size,
		host,
		{raw: '2>&1'},
	], (result) => {
		log_debug('ping: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = ubbf.ping_output_parse(result.data, count);
		if (result.exitcode != 0 && output.Status != 'Complete')
			output.Status = 'Error_Other';

		log_info('ping: complete status=%s', output.Status);
		complete(instance, 0, null, output);
	});
};
