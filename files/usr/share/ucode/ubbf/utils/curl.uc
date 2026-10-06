'use strict';

import { popen } from 'fs';
import { log_exception, log_info } from 'ubbf.utils.logging';
import { deviceinfo_get } from 'ubbf.utils.deviceinfo';
import * as ubbf from 'ubbf';

/**
 * Builds an upload URL with a device-qualified filename when the URL
 * ends with '/'. The trailing slash is the contract used by callers to
 * opt in to server-side per-device naming: when present, the basename
 * is prefixed with timestamp, ManufacturerOUI and SerialNumber so a
 * shared upload endpoint can demultiplex files per device. When the
 * URL has no trailing slash the caller has supplied a fully-qualified
 * target and it is returned unchanged.
 *
 * @param {string} url - Target URL
 * @param {string} path - Local file path (basename used for filename)
 * @returns {string} Final upload URL
 */
function upload_url_build(url, path) {
	if (!match(url, /\/$/))
		return url;

	let info = deviceinfo_get();
	let oui = info.ManufacturerOUI ?? 'unknown';
	let serial = info.SerialNumber ?? 'unknown';
	let base = split(path, '/')[-1];

	return url + sprintf('%d-%s-%s-%s', time(), oui, serial, base);
}

// Curl exit codes mapped to the DiagnosticsState fault names defined in
// TR-143 for Download/Upload diagnostics. Unmapped codes fall back to
// Error_Other in curl_exit_to_status().
const EXIT_STATUS_MAP = {
	'0': 'Complete',
	'6': 'Error_CannotResolveHostName',
	'7': 'Error_InitConnectionFailed',
	'18': 'Error_IncorrectSize',
	'22': 'Error_NoResponse',
	'28': 'Error_Timeout'
};

/**
 * Converts a curl exit code to a TR-143 diagnostic status string.
 *
 * @param {number} exitcode - The curl process exit code
 * @returns {string} TR-143 diagnostic status string
 */
export function curl_exit_to_status(exitcode) {
	return EXIT_STATUS_MAP[exitcode] ?? 'Error_Other';
};


/**
 * Builds a curl command string with the specified options.
 *
 * @param {string} operation - 'download' or 'upload'
 * @param {string} url - Target URL
 * @param {string} path - Local file path
 * @param {object} opts - Options (username, password, timeout, etc.)
 * @returns {string} Complete curl command string
 */
function command_build(operation, url, path, opts) {
	opts ??= {};

	let parts = [ 'curl', '--fail', '--silent' ];

	if (opts.insecure)
		push(parts, '-k');

	if (opts.username)
		push(parts, '-u ' + ubbf.shell_escape(opts.username + ':' + (opts.password ?? '')));

	if (opts.timeout)
		push(parts, sprintf('--max-time %d', opts.timeout));

	if (opts.ipv4_only)
		push(parts, '--ipv4');
	else if (opts.ipv6_only)
		push(parts, '--ipv6');

	if (opts.headers)
		for (let name, value in opts.headers)
			push(parts, '-H ' + ubbf.shell_escape(sprintf('%s: %s', name, value)));

	if (opts.format_string)
		push(parts, '-w ' + ubbf.shell_escape(opts.format_string));

	if (operation == 'download')
		push(parts, '-o ' + ubbf.shell_escape(path) + ' ' + ubbf.shell_escape(url));
	else if (operation == 'upload')
		push(parts, '-T ' + ubbf.shell_escape(path) + ' ' + ubbf.shell_escape(url));

	push(parts, '2>&1');

	return join(' ', parts);
}

/**
 * Executes a curl command and returns the result.
 *
 * exitcode is the value returned by popen close(): 0 on clean curl exit,
 * a positive curl exit code on failure, or null when popen/close itself
 * reports a pipe error. Callers that need a numeric value should coalesce
 * null to -1 (the convention used on the popen-failed path).
 *
 * @param {string} cmd - The curl command to execute
 * @param {object} opts - Options (format_string triggers metrics parsing)
 * @returns {object} Result with success, exitcode, output, and metrics
 */
function execute(cmd, opts) {
	log_info('curl: %s', cmd);

	let p = popen(cmd, 'r');
	if (!p)
		return { success: false, exitcode: -1, output: 'Failed to execute curl', metrics: null };

	let output;
	let exitcode;
	try {
		output = p.read('all');
		exitcode = p.close();
	} catch (e) {
		log_exception('curl.execute', e);
		try { p.close(); } catch (e2) {}
		return { success: false, exitcode: -1, output: 'Exception during curl execution', metrics: null };
	}

	let metrics = null;
	if (opts?.format_string)
		metrics = ubbf.curl_w_metrics_parse(output);

	return {
		success: (exitcode == 0),
		exitcode: exitcode,
		output: output,
		metrics: metrics
	};
}

/**
 * Downloads a file from a URL using curl.
 *
 * @param {string} url - Source URL
 * @param {string} output_path - Local path to save file
 * @param {object} opts - Download options
 * @returns {object} Result with success, exitcode, output, and metrics
 */
export function curl_download(url, output_path, opts) {
	let cmd = command_build('download', url, output_path, opts);
	return execute(cmd, opts);
};

/**
 * Uploads a file to a URL using curl.
 *
 * @param {string} url - Target URL
 * @param {string} input_path - Local file path to upload
 * @param {object} opts - Upload options
 * @returns {object} Result with success, exitcode, output, and metrics
 */
export function curl_upload(url, input_path, opts) {
	try {
		opts ??= {};

		let info = deviceinfo_get();
		let headers = {};

		if (info.ManufacturerOUI)
			headers['X-ubbf-oui'] = info.ManufacturerOUI;
		if (info.SerialNumber)
			headers['X-ubbf-serial'] = info.SerialNumber;
		if (opts.command_key)
			headers['X-ubbf-key'] = opts.command_key;
		if (opts.extension) {
			let ext = opts.extension;
			if (substr(ext, 0, 1) == '.')
				ext = substr(ext, 1);
			if (ext != '')
				headers['X-ubbf-extension'] = ext;
		}

		opts.headers = headers;

		let final_url = upload_url_build(url, input_path);
		let cmd = command_build('upload', final_url, input_path, opts);
		return execute(cmd, opts);
	} catch (e) {
		log_exception('curl_upload', e);
		return { success: false, exitcode: -1, output: `Exception: ${e}`, metrics: null };
	}
};
