'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { transfer_complete } from 'ubbf.utils.helpers';
import { curl_upload, curl_download } from 'ubbf.utils.curl';
import { config_apply_safe, config_validate } from 'ubbf.utils.config';
import { log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

const CONFIG_JSON_PATH = '/etc/ubbf/config.json';

/* Developer / test images carry /etc/ubbf/developer (the same sentinel
 * default_config keys SSH / UserInterface defaults off). On those images
 * the testbed expects to drive Backup / Restore / Upload against a
 * snake-oil HTTPS endpoint, so curl needs to skip certificate
 * verification. Production images leave the file absent and the
 * transfer operates fall back to the strict default. */
function curl_insecure_p() {
	return fs.stat('/etc/ubbf/developer') ? true : false;
}

const extra_files = [
	{ path: CONFIG_JSON_PATH, description: 'UBBF datamodel configuration', restore_path: '/tmp/restore.json' }
];

/**
 * Formats file modification time as ISO8601 string.
 *
 * @param {object} file_stat - File stat object
 * @returns {string} ISO8601 formatted time or empty string
 */
function format_mtime(file_stat) {
	if (!file_stat?.mtime)
		return '';
	return ubbf.iso8601_format(file_stat.mtime);
}

/**
 * Enumerates all vendor configuration files.
 *
 * @returns {array} Array of file objects with path, name, description, and stat
 */
export function files_enumerate() {
	let files = [];

	for (let extra in extra_files) {
		let file_stat = fs.stat(extra.path);
		if (!file_stat)
			continue;

		let name = split(extra.path, '/')[-1];
		push(files, {
			path: extra.path,
			name: name,
			description: extra.description,
			restore_path: extra.restore_path,
			stat: file_stat
		});
	}

	let entries = fs.lsdir('/var/run/uci');
	if (entries) {
		for (let entry in entries) {
			if (substr(entry, 0, 1) == '.')
				continue;

			let path = sprintf('/var/run/uci/%s', entry);
			let file_stat = fs.stat(path);
			if (!file_stat || file_stat.type != 'file')
				continue;

			push(files, {
				path: path,
				name: entry,
				description: sprintf('UCI configuration file: %s', entry),
				restore_path: null,
				stat: file_stat
			});
		}
	}

	return files;
};

/**
 * Retrieves a file by TR-181 instance number.
 *
 * @param {number} instance - Instance number (1-based)
 * @returns {object|null} File object or null if not found
 */
function file_by_instance(instance) {
	let files = files_enumerate();
	if (instance < 1 || instance > length(files))
		return null;
	return files[instance - 1];
}

/**
 * Converts a file object to TR-181 VendorConfigFile format.
 *
 * @param {object} file - File object with name, stat, description
 * @param {number} instance - Instance number (1-based)
 * @returns {object} TR-181 formatted VendorConfigFile object
 */
function file_to_object(file, instance) {
	return {
		Alias: sprintf('cpe-config%d', instance),
		Name: file.name,
		Date: format_mtime(file.stat),
		Description: file.description,
		UseForBackupRestore: file.restore_path ? 'true' : 'false'
	};
}

/**
 * Get handler for Device.DeviceInfo.VendorConfigFile.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} VendorConfigFile properties
 */
function get(ctx) {
	let files = files_enumerate();
	let to_object = (file, idx) => file_to_object(file, idx + 1);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(files, to_object);

	let file = ubbf.get_by_instance(files, ctx.instance);
	if (!file)
		return null;

	return file_to_object(file, ctx.instance);
}

/**
 * Async handler for VendorConfigFile Backup operation.
 *
 * @param {object} input - Input parameters with URL, Username, Password
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers array
 * @param {string} command_key - USP command key
 */
function backup_handler(input, instance, complete, instances, command_key) {
	let file_instance = instances[0];
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

	let file = file_by_instance(file_instance);
	if (!file) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid file instance', {});
		return;
	}

	let ctx = {
		command: 'Backup',
		obj_path: sprintf('Device.DeviceInfo.VendorConfigFile.%d.', file_instance),
		url,
		transfer_type: 'Upload',
		start_time: time(),
		command_key,
		instance,
		complete
	};

	let opts = { command_key };
	if (username != '')
		opts = { ...opts, username, password };
	if (curl_insecure_p())
		opts.insecure = true;

	let task = uloop.task(
		(pipe) => {
			let result = curl_upload(url, file.path, opts);
			pipe.send(result);
		},
		(result) => {
			if (!result)
				return;

			let fault_string = null;
			if (!result.success)
				fault_string = sprintf('Upload failed: %s', result.output);

			transfer_complete(ctx, fault_string);
		}
	);

	if (!task) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

/**
 * Async handler for VendorConfigFile Restore operation.
 *
 * @param {object} input - Input parameters with URL, Username, Password
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers array
 * @param {string} command_key - USP command key
 */
function restore_handler(input, instance, complete, instances, command_key) {
	let file_instance = instances[0];
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

	let file = file_by_instance(file_instance);
	if (!file) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid file instance', {});
		return;
	}

	if (!file.restore_path) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Restore not supported for this file', {});
		return;
	}

	let ctx = {
		command: 'Restore',
		obj_path: sprintf('Device.DeviceInfo.VendorConfigFile.%d.', file_instance),
		url,
		transfer_type: 'Download',
		start_time: time(),
		command_key,
		instance,
		complete
	};

	let opts = {};
	if (username != '')
		opts = { username, password };
	if (curl_insecure_p())
		opts.insecure = true;

	let download_task = uloop.task(
		(pipe) => {
			/* Download + dry-run validate only. Doing config_apply
			 * here too would have the apply (which can bounce
			 * services that mediate the operate response) run
			 * before the operate completes, and the response
			 * would be lost: bbf-cli sees rc=0 with empty stdout
			 * because the ubus reply path has been torn down by
			 * the apply. Defer the apply until after the operate
			 * response has been delivered. */
			let result = curl_download(url, file.restore_path, opts);
			if (!result.success) {
				pipe.send({ success: false, error: sprintf('Download failed: %s', result.output) });
				return;
			}

			if (file.path != CONFIG_JSON_PATH) {
				pipe.send({ success: true });
				return;
			}

			let validation = config_validate(file.restore_path);
			if (!validation.success) {
				fs.unlink(file.restore_path);
				pipe.send({ success: false, error: sprintf('Validation failed: %s', validation.output) });
				return;
			}

			pipe.send({ success: true });
		},
		(result) => {
			if (!result)
				return;

			let fault_string = result.success ? null : result.error;
			transfer_complete(ctx, fault_string);

			/* If the download/validate stage failed, or this file
			 * doesn't apply via the global config path, we are
			 * done. Otherwise schedule the actual apply on a
			 * short timer so the operate response that
			 * transfer_complete just emitted has flushed before
			 * the apply touches the daemons that carry it. */
			if (!result.success || file.path != CONFIG_JSON_PATH)
				return;

			uloop.timer(100, function() {
				uloop.task(
					(pipe) => {
						let apply_result = config_apply_safe(file.restore_path, file.path);
						fs.unlink(file.restore_path);
						pipe.send(apply_result);
					},
					(apply_result) => {
						/* The operate has already returned success
						 * to the caller; this is a fire-and-forget
						 * apply. Failures roll back inside
						 * config_apply_safe; surface them in the
						 * log so an operator can correlate. */
						if (!apply_result?.success)
							log_err('Restore: deferred apply failed: %s',
								apply_result?.error ?? 'unknown');
					}
				);
			});
		}
	);

	if (!download_task) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

export const model = {
	'Device.DeviceInfo.VendorConfigFile': {
	},

	'Device.DeviceInfo.VendorConfigFile.{i}': {
		schema: schemas.VendorConfigFile,
		get: get
	}
};

export const operations = {
	'Device.DeviceInfo.VendorConfigFile.{i}.Backup()': {
		type: 'async',
		handler: backup_handler
	},

	'Device.DeviceInfo.VendorConfigFile.{i}.Restore()': {
		type: 'async',
		handler: restore_handler
	}
};
