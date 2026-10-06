'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { transfer_complete } from 'ubbf.utils.helpers';
import { curl_upload } from 'ubbf.utils.curl';
import { log_info, log_debug, log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

const log_sources = [
	{ name: 'syslog', command: 'logread', persistent: false },
	{ name: 'kernlog', command: 'dmesg', persistent: false },
	{ name: 'udebug', file_command: 'udebug -o %s snapshot', extension: '.pcapng', persistent: false }
];

/**
 * Reads log output from a command that outputs to stdout.
 *
 * @param {string} command - Command to execute
 * @returns {string|null} Log output or null on failure
 */
function log_read(command) {
	let p = fs.popen(command, 'r');
	if (!p)
		return null;

	let output = p.read('all');
	p.close();

	return output;
}

/**
 * Generates log file from a source.
 *
 * @param {object} source - Log source definition
 * @returns {string|null} Temporary file path or null on failure
 */
function log_generate_file(source) {
	let ext = source.extension ?? '.txt';
	let tmpfile = sprintf('/tmp/logfile_%d%s', time(), ext);

	if (source.file_command) {
		let cmd = sprintf(source.file_command, tmpfile);
		let p = fs.popen(cmd, 'r');
		if (!p)
			return null;
		p.read('all');
		p.close();

		if (!fs.stat(tmpfile))
			return null;

		return tmpfile;
	}

	let output = log_read(source.command);
	if (!output)
		return null;

	let written = fs.writefile(tmpfile, output);
	if (!written) {
		fs.unlink(tmpfile);
		return null;
	}

	return tmpfile;
}

/**
 * Gets the size of log output from a source.
 *
 * @param {object} source - Log source definition
 * @returns {number} Size in bytes
 */
function log_get_size(source) {
	if (source.file_command) {
		let tmpfile = log_generate_file(source);
		if (!tmpfile)
			return 0;

		let st = fs.stat(tmpfile);
		let size = st?.size ?? 0;
		fs.unlink(tmpfile);
		return size;
	}

	let output = log_read(source.command);
	return output ? length(output) : 0;
}

/**
 * Returns the number of vendor log sources.
 *
 * @returns {number} Count of log sources
 */
export function source_count() {
	return length(log_sources);
};

/**
 * Retrieves a log source by TR-181 instance number.
 *
 * @param {number} instance - Instance number (1-based)
 * @returns {object|null} Log source or null if not found
 */
function source_by_instance(instance) {
	if (instance < 1 || instance > length(log_sources))
		return null;
	return log_sources[instance - 1];
}

/**
 * Converts a log source to TR-181 VendorLogFile format.
 *
 * @param {object} source - Log source with name and persistent flag
 * @returns {object} TR-181 formatted VendorLogFile object
 */
function source_to_object(source) {
	return {
		Alias: ubbf.alias_from_name(source.name),
		Name: source.name,
		MaximumSize: '0',
		Persistent: source.persistent ? 'true' : 'false'
	};
}

/**
 * Get handler for Device.DeviceInfo.VendorLogFile.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} VendorLogFile properties
 */
function get(ctx) {
	if (ctx.instance == null)
		return ubbf.enumerate_instances(log_sources, source_to_object);

	let source = ubbf.get_by_instance(log_sources, ctx.instance);
	if (!source)
		return null;

	return source_to_object(source);
}

/**
 * Async handler for VendorLogFile Upload operation.
 *
 * @param {object} input - Input parameters with URL, Username, Password
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers array
 * @param {string} command_key - USP command key
 */
function upload_handler(input, instance, complete, instances, command_key) {
	let log_instance = instances[0];
	let url = input.URL ?? '';
	let username = input.Username ?? '';
	let password = input.Password ?? '';

	if (url == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'URL is required', {});
		return;
	}

	if (!ubbf.transfer_url_validate(url)) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid URL scheme', {});
		return;
	}

	let source = source_by_instance(log_instance);
	if (!source) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid log instance', {});
		return;
	}

	log_info('vendorlogfile: upload instance=%d source=%s url=%s', log_instance, source.name, url);

	let ctx = {
		command: 'Upload',
		obj_path: sprintf('Device.DeviceInfo.VendorLogFile.%d.', log_instance),
		url,
		transfer_type: 'Upload',
		start_time: time(),
		command_key,
		instance,
		complete
	};

	let opts = { command_key };
	if (source.extension)
		opts.extension = source.extension;
	if (username != '')
		opts = { ...opts, username, password };
	/* Allow self-signed HTTPS targets when the testbed dev sentinel is
	 * present (same gate as Backup / Restore in VendorConfigFile.uc).
	 * Production images keep strict TLS validation. */
	if (fs.stat('/etc/ubbf/developer'))
		opts.insecure = true;

	let task = uloop.task(
		(pipe) => {
			let tmpfile = log_generate_file(source);
			if (!tmpfile) {
				log_err('vendorlogfile: failed to generate log file');
				pipe.send({ success: false, output: 'Failed to generate log file' });
				return;
			}

			log_debug('vendorlogfile: uploading %s', tmpfile);
			let result = curl_upload(url, tmpfile, opts);
			log_debug('vendorlogfile: upload result success=%s', result.success);

			fs.unlink(tmpfile);
			pipe.send(result);
		},
		(result) => {
			if (!result)
				return;

			let fault_string = null;
			if (!result.success)
				fault_string = sprintf('Upload failed: %s', result.output);

			log_info('vendorlogfile: upload complete success=%s', result.success);
			transfer_complete(ctx, fault_string);
		}
	);

	if (!task) {
		log_err('vendorlogfile: failed to create task');
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

export const model = {
	'Device.DeviceInfo.VendorLogFile': {
	},

	'Device.DeviceInfo.VendorLogFile.{i}': {
		schema: schemas.VendorLogFile,
		get: get
	}
};

export const operations = {
	'Device.DeviceInfo.VendorLogFile.{i}.Upload()': {
		type: 'async',
		handler: upload_handler
	}
};
