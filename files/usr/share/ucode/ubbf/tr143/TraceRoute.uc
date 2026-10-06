'use strict';

import { popen_async } from 'ubbf.utils.process';
import { interface_resolve } from 'ubbf.utils.path';
import { log_info, log_debug } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

/**
 * Async handler for Device.IP.Diagnostics.TraceRoute operation.
 *
 * @param {object} input - Input parameters with Host, MaxHopCount, Timeout, NumberOfTries, DataBlockSize, DSCP, Interface, ProtocolVersion
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let host = input.Host ?? '';
	let max_hops = int(input.MaxHopCount) || 30;
	let timeout = int(input.Timeout) || 1000;
	let tries = int(input.NumberOfTries) || 1;
	let size = int(input.DataBlockSize) || 128;
	let dscp = int(input.DSCP) || 0;
	let protocol = input.ProtocolVersion ?? 'Any';

	if (host == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Host parameter is required', {});
		return;
	}

	if (dscp < 0 || dscp > 63) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'DSCP must be 0-63', {});
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

	log_info('traceroute: host=%s max_hops=%d proto=%s', host, max_hops, protocol);

	let timeout_sec = (timeout + 999) / 1000;
	// DSCP occupies the upper 6 bits of the IPv4 TOS byte (RFC 2474); shift left by 2 to position it correctly, leaving the ECN bits zeroed.
	let dscp_tos = (dscp > 0) ? (dscp << 2) : null;

	popen_async([
		{raw: 'traceroute'},
		family_flag,
		// '-I' selects ICMP-Echo probes; UDP probes (the busybox default) are often filtered by intermediate hops.
		'-I',
		iface_name ? '-i' : null, iface_name,
		dscp_tos ? '-t' : null, dscp_tos,
		'-m', max_hops,
		'-w', timeout_sec,
		'-q', tries,
		host,
		size,
		{raw: '2>&1'},
	], (result) => {
		log_debug('traceroute: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let output = ubbf.traceroute_output_parse(result.data);

		if (result.exitcode != 0 && output.Status != 'Complete')
			output.Status = 'Error_Other';

		log_info('traceroute: complete status=%s', output.Status);
		complete(instance, 0, null, output);
	});
};
