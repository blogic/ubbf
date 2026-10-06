'use strict';

import { popen, stat, unlink, writefile } from 'fs';
import { log_exception, log_info } from 'ubbf.utils.logging';
import { deviceinfo_get } from 'ubbf.utils.deviceinfo';
import * as ubbf from 'ubbf';

const DEVELOPER_SENTINEL = '/etc/ubbf/developer';

export const CURL_TRANSFER_TIMEOUT_S = 1800;

/**
 * Tells whether a transfer may skip the TLS certificate check.
 *
 * Developer and test images carry /etc/ubbf/developer, and the testbed
 * drives their transfers against a lab HTTPS endpoint whose CA the image
 * does not have. Production images lack the file and keep the check.
 *
 * @returns {boolean} True on a developer image
 */
export function curl_insecure_allowed() {
	return stat(DEVELOPER_SENTINEL) != null;
};

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
 * Quotes a value for a curl config file.
 *
 * @param {string} value - Raw value
 * @returns {string} Double-quoted value with curl's escapes
 */
function config_quote(value) {
	value = replace(value, /\\/g, '\\\\');
	value = replace(value, /"/g, '\\"');
	value = replace(value, /\t/g, '\\t');
	value = replace(value, /\n/g, '\\n');
	value = replace(value, /\r/g, '\\r');
	value = replace(value, /\v/g, '\\v');
	return '"' + value + '"';
}

/**
 * Writes the credentials to a curl config file of mode 0600.
 *
 * The credentials go to curl through `-K` because a `-u` argument is
 * visible in the process list and in the logged command.
 *
 * @param {string} username - User name
 * @param {string} password - Password, may be empty
 * @returns {string|null} Path of the file, or null on failure
 */
function credentials_file_write(username, password) {
	let path = ubbf.tmpfile_name('curl', '.conf');
	if (!path)
		return null;

	if (writefile(path, 'user = ' + config_quote(username + ':' + password) + '\n') == null) {
		unlink(path);
		return null;
	}

	return path;
}

/**
 * Builds a curl command string with the specified options.
 *
 * @param {string} operation - 'download' or 'upload'
 * @param {string} url - Target URL
 * @param {string} path - Local file path
 * @param {object} opts - Options (timeout, headers, etc.)
 * @param {string} config_path - curl config file with the credentials, or null
 * @returns {string} Complete curl command string
 */
function command_build(operation, url, path, opts, config_path) {
	opts ??= {};

	let parts = [ 'curl', '--fail', '--silent' ];

	if (opts.insecure)
		push(parts, '-k');

	if (config_path)
		push(parts, '-K ' + ubbf.shell_escape(config_path));

	if (opts.timeout)
		push(parts, sprintf('--max-time %d', opts.timeout));

	if (opts.connect_timeout)
		push(parts, sprintf('--connect-timeout %d', opts.connect_timeout));

	if (opts.ipv4_only)
		push(parts, '--ipv4');
	else if (opts.ipv6_only)
		push(parts, '--ipv6');

	if (opts.headers)
		for (let name, value in opts.headers)
			push(parts, '-H ' + ubbf.shell_escape(sprintf('%s: %s', name, value)));

	if (opts.format_string)
		push(parts, '-w ' + ubbf.shell_escape(opts.format_string));

	// The URL goes after --url: as a bare argument, a value that starts
	// with '-' would be read as a curl option.
	if (operation == 'download')
		push(parts, '-o ' + ubbf.shell_escape(path));
	else if (operation == 'upload')
		push(parts, '-T ' + ubbf.shell_escape(path));
	else if (operation == 'POST' || operation == 'PUT')
		push(parts, '--show-error -X ' + operation + ' --data-binary ' + ubbf.shell_escape('@' + path));

	push(parts, '--url ' + ubbf.shell_escape(url));
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
	log_info('curl: %s', replace(cmd, /:\/\/[^\/@' ]*@/g, '://***@'));

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
 * Runs one curl transfer, with the credentials in a temporary config file.
 *
 * @param {string} operation - 'download' or 'upload'
 * @param {string} url - Target URL
 * @param {string} path - Local file path
 * @param {object} opts - Options (username, password, timeout, etc.)
 * @returns {object} Result with success, exitcode, output, and metrics
 */
function transfer(operation, url, path, opts) {
	let config_path = null;

	if (opts?.username) {
		config_path = credentials_file_write(opts.username, opts.password ?? '');
		if (!config_path)
			return { success: false, exitcode: -1, output: 'Failed to write curl credentials', metrics: null };
	}

	let result = execute(command_build(operation, url, path, opts, config_path), opts);

	if (config_path)
		unlink(config_path);

	return result;
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
	return transfer('download', url, output_path, opts);
};

/**
 * Sends a file as the body of an HTTP POST or PUT, as is, with the
 * headers in opts.headers.
 *
 * @param {string} method - 'POST' or 'PUT'
 * @param {string} url - Target URL
 * @param {string} body_path - Local file with the request body
 * @param {object} opts - Options (username, password, headers, timeout,
 *                        connect_timeout, insecure)
 * @returns {object} Result with success, exitcode, output, and metrics
 */
export function curl_send(method, url, body_path, opts) {
	if (method != 'POST' && method != 'PUT')
		return { success: false, exitcode: -1, output: `unsupported method ${method}`, metrics: null };

	return transfer(method, url, body_path, opts);
};

/**
 * Uploads a file to a URL using curl.
 *
 * @param {string} url - Target URL
 * @param {string} input_path - Local file path to upload
 * @param {object} opts - Upload options
 * @returns {object} Result with success, exitcode, output, metrics, and
 *                   url, the URL the file went to (see upload_url_build())
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
		return { ...transfer('upload', final_url, input_path, opts), url: final_url };
	} catch (e) {
		log_exception('curl_upload', e);
		return { success: false, exitcode: -1, output: `Exception: ${e}`, metrics: null };
	}
};
