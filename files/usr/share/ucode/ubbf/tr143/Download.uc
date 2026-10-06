'use strict';

import { popen_async } from 'ubbf.utils.process';
import { curl_exit_to_status } from 'ubbf.utils.curl';
import { interface_resolve } from 'ubbf.utils.path';
import * as ubbf from 'ubbf';
import { log_info, log_debug } from 'ubbf.utils.logging';

/**
 * Async handler for Device.IP.Diagnostics.DownloadDiagnostics operation.
 *
 * @param {object} input - Input parameters with DownloadURL, ProtocolVersion, Interface
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let url = input.DownloadURL ?? '';
	let proto = input.ProtocolVersion ?? 'Any';

	if (url == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'DownloadURL is required', {});
		return;
	}

	if (!ubbf.transfer_url_validate(url)) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid URL scheme', {});
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

	log_info('download: url=%s', url);

	let ip_flag = (proto == 'IPv4') ? '--ipv4'
	            : (proto == 'IPv6') ? '--ipv6'
	            : null;

	// curl(1) -w write-out variables; emitted as key:value lines so the parser below can split on the first ':'
	let curl_format = 'time_appconnect:%{time_appconnect}\\n' +
		'time_connect:%{time_connect}\\n' +
		'time_pretransfer:%{time_pretransfer}\\n' +
		'time_starttransfer:%{time_starttransfer}\\n' +
		'time_total:%{time_total}\\n' +
		'size_download:%{size_download}\\n' +
		'remote_ip:%{remote_ip}\\n';

	// '-w' emits the metrics block on stdout; '--output /dev/null' discards the response body so only the metrics remain
	popen_async([
		{raw: 'curl'},
		ip_flag,
		iface_name ? '--interface' : null, iface_name,
		'--fail', '--silent',
		'--max-time', 1800,
		'-w', curl_format,
		url,
		'--output', '/dev/null',
		{raw: '2>&1'},
	], (result) => {
		log_debug('download: output:\n%s', result.data ?? '');

		if (result.error) {
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, {});
			return;
		}

		let metrics = {};
		let lines = split(result.data ?? '', '\n');
		for (let line in lines) {
			let m = match(line, /^([^:]+):(.+)$/);
			if (m)
				metrics[m[1]] = m[2];
		}

		let base_time = result.start_time;
		let time_connect = +(metrics.time_connect ?? 0);
		let time_pretransfer = +(metrics.time_pretransfer ?? 0);
		let time_starttransfer = +(metrics.time_starttransfer ?? 0);
		let time_total = +(metrics.time_total ?? 0);
		let size_download = int(metrics.size_download ?? 0);

		let period_usec = int((time_total - time_starttransfer) * 1000000);

		let output = {
			Status: curl_exit_to_status(result.exitcode),
			IPAddressUsed: metrics.remote_ip ?? '',
			ROMTime: ubbf.iso8601_format_usec(base_time + time_pretransfer, (time_pretransfer % 1) * 1000000),
			BOMTime: ubbf.iso8601_format_usec(base_time + time_starttransfer, (time_starttransfer % 1) * 1000000),
			EOMTime: ubbf.iso8601_format_usec(base_time + time_total, (time_total % 1) * 1000000),
			TestBytesReceived: sprintf('%d', size_download),
			TotalBytesReceived: sprintf('%d', size_download),
			TotalBytesSent: '0',
			TestBytesReceivedUnderFullLoading: sprintf('%d', size_download),
			TotalBytesReceivedUnderFullLoading: sprintf('%d', size_download),
			TotalBytesSentUnderFullLoading: '0',
			PeriodOfFullLoading: sprintf('%d', period_usec),
			TCPOpenRequestTime: ubbf.iso8601_format_usec(base_time, 0),
			TCPOpenResponseTime: ubbf.iso8601_format_usec(base_time + time_connect, (time_connect % 1) * 1000000)
		};

		log_info('download: complete status=%s bytes=%d', output.Status, size_download);
		complete(instance, 0, null, output);
	}, { capture_time: true });
};
