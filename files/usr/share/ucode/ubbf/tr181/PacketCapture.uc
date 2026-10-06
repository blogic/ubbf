'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.PacketCapture';
import { curl_upload } from 'ubbf.utils.curl';
import { interface_resolve } from 'ubbf.utils.path';
import { log_warn, log_exception } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

/**
 * Async operation handler for Device.PacketCaptureDiagnostics().
 *
 * @param {object} input - Operation input with Interface, Duration, FileTarget, etc.
 * @param {number} instance - Operation instance identifier
 * @param {function} complete - Callback to signal operation completion
 * @param {string} command_key - USP command key
 * @param {object} root - Root configuration object
 */
function packetcapture_handler(input, instance, complete, command_key, root) {
	let iface = input.Interface ?? '';
	let format = input.Format ?? 'libpcap';
	let duration = int(input.Duration) || 60;
	let packet_count = int(input.PacketCount) ?? 0;
	let byte_count = int(input.ByteCount) ?? 0;
	let file_target = input.FileTarget ?? '';
	let filter_expr = input.FilterExpression ?? '';
	let username = input.Username ?? '';
	let password = input.Password ?? '';

	if (format != '' && format != 'libpcap') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS,
			'Only libpcap format is supported', {});
		return;
	}

	if (file_target == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS,
			'FileTarget is required', {});
		return;
	}

	if (!ubbf.transfer_url_validate(file_target)) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS,
			'FileTarget must be an HTTP or FTP URL', {});
		return;
	}

	if (duration < 1)
		duration = 1;

	let iface_name = null;
	if (iface != '') {
		iface_name = interface_resolve(root, iface);
		if (!iface_name) {
			complete(instance, USP_ERR_INVALID_ARGUMENTS,
				'Cannot resolve interface', {});
			return;
		}
	}

	let tmpfile = ubbf.tmpfile_name('packetcapture', '.pcap');
	if (!tmpfile) {
		complete(instance, USP_ERR_INTERNAL_ERROR, 'Failed to create temp file', {});
		return;
	}

	// tcpdump -C rotates output files instead of stopping at a size, so a
	// byte limit streams through head -c: the pipe closing stops tcpdump
	// at the limit and everything lands in the single upload file.
	let errfile = tmpfile + '.err';
	let cmd = (byte_count > 0)
		? sprintf('timeout %d tcpdump -w -', duration)
		: sprintf('timeout %d tcpdump -w %s', duration, tmpfile);

	if (iface_name)
		cmd += ' -i ' + ubbf.shell_escape(iface_name);
	else
		// libpcap's default interface can be a DSA conduit (mtk tag on
		// eth0) whose link-layer type rejects BPF filter compilation
		cmd += ' -i any';

	if (packet_count > 0)
		cmd += sprintf(' -c %d', packet_count);

	if (filter_expr != '')
		cmd += ' ' + ubbf.shell_escape(filter_expr);

	if (byte_count > 0)
		cmd += sprintf(' 2>%s | head -c %d > %s', errfile, byte_count, tmpfile);
	else
		cmd += ' 2>&1';

	let task = uloop.task(
		(pipe) => {
			let start_time = ubbf.iso8601_format();

			let p = fs.popen(cmd, 'r');
			if (!p) {
				pipe.send({ error: 'Failed to start tcpdump' });
				return;
			}

			let tcpdump_output = p.read('all');
			let rc = p.close();

			if (byte_count > 0) {
				tcpdump_output = fs.readfile(errfile) ?? '';
				fs.unlink(errfile);
			}

			let end_time = ubbf.iso8601_format();

			let count = 0;
			let count_match = match(tcpdump_output, /(\d+) packets captured/);
			if (count_match)
				count = int(count_match[1]);

			// tcpdump prints the summary on every graceful exit,
			// including the SIGTERM from timeout (rc 124), so a
			// missing summary means the capture never ran. Not
			// checked for ByteCount: there rc belongs to head and
			// an EPIPE-killed tcpdump omits the summary even when
			// the byte limit worked.
			if (!count_match && byte_count == 0) {
				fs.unlink(tmpfile);
				pipe.send({
					error: sprintf('tcpdump failed (%d): %s',
						rc, trim(tcpdump_output)),
					start_time, end_time
				});
				return;
			}

			let opts = { timeout: 1800, command_key };
			if (username != '' && password != '')
				opts = { ...opts, username, password };

			let result;
			try {
				result = curl_upload(file_target, tmpfile, opts);
			} catch (e) {
				log_exception('Device.PacketCaptureDiagnostics', e);
				result = { success: false };
			}

			if (!fs.unlink(tmpfile))
				log_warn('Failed to remove temp file: %s', tmpfile);

			if (!result.success) {
				pipe.send({
					error: 'Failed to upload capture file',
					start_time, end_time, count
				});
				return;
			}

			pipe.send({
				status: 'Complete',
				file_location: file_target,
				start_time,
				end_time,
				count
			});
		},
		(result) => {
			if (!result)
				return;

			if (!result.error) {
				let output = {
					Status: result.status,
					'PacketCaptureResult.1.FileLocation': result.file_location,
					'PacketCaptureResult.1.StartTime': result.start_time,
					'PacketCaptureResult.1.EndTime': result.end_time,
					'PacketCaptureResult.1.Count': sprintf('%d', result.count)
				};
				complete(instance, 0, null, output);
				return;
			}

			let output = {
				Status: 'Error_Internal'
			};
			if (result.start_time) {
				output['PacketCaptureResult.1.FileLocation'] = '';
				output['PacketCaptureResult.1.StartTime'] = result.start_time;
				output['PacketCaptureResult.1.EndTime'] = result.end_time ?? '';
				output['PacketCaptureResult.1.Count'] = sprintf('%d', result.count ?? 0);
			}
			complete(instance, USP_ERR_COMMAND_FAILURE, result.error, output);
		}
	);

	if (!task) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

export const model = {
	'Device.PacketCaptureResult': {
		schema: schemas.PacketCaptureResult
	}
};

export const operations = {
	'Device.PacketCaptureDiagnostics()': {
		type: 'async',
		handler: packetcapture_handler
	}
};
