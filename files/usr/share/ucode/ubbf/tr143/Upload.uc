'use strict';

import { popen_async } from 'ubbf.utils.process';
import { curl_exit_to_status } from 'ubbf.utils.curl';
import { interface_resolve } from 'ubbf.utils.path';
import * as ubbf from 'ubbf';
import { log_info, log_debug } from 'ubbf.utils.logging';

/**
 * Async handler for Device.IP.Diagnostics.UploadDiagnostics operation.
 *
 * @param {object} input - Input parameters with UploadURL, TestFileLength, ProtocolVersion, Interface
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {string} command_key - Caller-supplied correlation key recorded with the result
 * @param {object} root - Full datamodel root, used for resolving Interface references
 */
export function handler(input, instance, complete, command_key, root) {
	let url = input.UploadURL ?? '';
	let file_length = int(input.TestFileLength) ?? 0;
	let proto = input.ProtocolVersion ?? 'Any';

	if (url == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'UploadURL is required', {});
		return;
	}

	if (file_length <= 0) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'TestFileLength must be > 0', {});
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

	log_info('upload: url=%s size=%d', url, file_length);

	let ip_flag = (proto == 'IPv4') ? '--ipv4'
	            : (proto == 'IPv6') ? '--ipv6'
	            : null;

	let curl_format = 'time_appconnect:%{time_appconnect}\\n' +
		'time_connect:%{time_connect}\\n' +
		'time_pretransfer:%{time_pretransfer}\\n' +
		'time_starttransfer:%{time_starttransfer}\\n' +
		'time_total:%{time_total}\\n' +
		'size_upload:%{size_upload}\\n' +
		'remote_ip:%{remote_ip}\\n';

	// feed exactly TestFileLength bytes: full blocks plus one
	// remainder-sized block, instead of rounding up to a 4096 multiple
	let bs = 4096;
	let feed = sprintf('dd if=/dev/zero bs=%d count=%d 2>/dev/null', bs, file_length / bs);
	if (file_length % bs)
		feed += sprintf('; dd if=/dev/zero bs=%d count=1 2>/dev/null', file_length % bs);

	popen_async([
		{raw: sprintf('{ %s; } |', feed)},
		{raw: 'curl'},
		ip_flag,
		iface_name ? '--interface' : null, iface_name,
		'--fail', '--silent',
		// 1800s ceiling matches Download.uc; bounds runaway uploads on very slow links
		'--max-time', 1800,
		'-T', '-',
		'-w', curl_format,
		url,
		{raw: '2>&1'},
	], (result) => {
		log_debug('upload: output:\n%s', result.data ?? '');

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
		let size_upload = int(metrics.size_upload ?? 0);

		let period_usec = int((time_starttransfer - time_pretransfer) * 1000000);

		// TR-143 upload semantics run in the transmission direction: the
		// payload starts flowing right after the request goes out and is
		// fully sent by the time the first response byte arrives. The
		// received-direction wording in the TR-181 XML is a copy-paste from
		// Download (it even says "GET command" for an upload).
		//   ROMTime  <- time_pretransfer   (request-out moment)
		//   BOMTime  <- time_pretransfer   (first payload byte sent)
		//   EOMTime  <- time_starttransfer (payload sent, first response byte)
		// TotalBytesReceived stays '0' because TR-143 UploadDiagnostics measures
		// only bytes sent; the matching *Received fields are required by the
		// schema but semantically unused for an upload test.
		let output = {
			Status: curl_exit_to_status(result.exitcode),
			IPAddressUsed: metrics.remote_ip ?? '',
			ROMTime: ubbf.iso8601_format_usec(base_time + time_pretransfer, (time_pretransfer % 1) * 1000000),
			BOMTime: ubbf.iso8601_format_usec(base_time + time_pretransfer, (time_pretransfer % 1) * 1000000),
			EOMTime: ubbf.iso8601_format_usec(base_time + time_starttransfer, (time_starttransfer % 1) * 1000000),
			TestBytesSent: sprintf('%d', size_upload),
			TotalBytesReceived: '0',
			TotalBytesSent: sprintf('%d', size_upload),
			TestBytesSentUnderFullLoading: sprintf('%d', size_upload),
			TotalBytesReceivedUnderFullLoading: '0',
			TotalBytesSentUnderFullLoading: sprintf('%d', size_upload),
			PeriodOfFullLoading: sprintf('%d', period_usec),
			TCPOpenRequestTime: ubbf.iso8601_format_usec(base_time, 0),
			TCPOpenResponseTime: ubbf.iso8601_format_usec(base_time + time_connect, (time_connect % 1) * 1000000)
		};

		log_info('upload: complete status=%s bytes=%d', output.Status, size_upload);
		complete(instance, 0, null, output);
	}, { capture_time: true });
};
