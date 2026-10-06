'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as digest from 'digest';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { transfer_complete } from 'ubbf.utils.helpers';
import { curl_download, curl_exit_to_status } from 'ubbf.utils.curl';
import { log_err } from 'ubbf.utils.logging';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';

const FIRMWARE_PATH = '/tmp/firmware.bin';
const UPGRADE_DELAY_MS = 15000;
const BOOT_BANK_BIN = '/usr/libexec/boot-bank';

const CHECKSUM_ALGOS = {
	'SHA-1': 'sha1_file',
	'SHA-256': 'sha256_file',
	'SHA-384': 'sha384_file',
	'SHA-512': 'sha512_file',
};

/**
 * Detects dual-bank capability by checking boot-bank board config.
 *
 * @returns {object|null} Board config if dual-bank, null otherwise
 */
function dual_bank_get() {
	let data = fs.readfile('/etc/boot-bank/boards.json');
	if (!data)
		return null;

	let boards;
	try {
		boards = json(data);
	} catch (e) {
		log_err('dual_bank_get: malformed boards.json: %s', e);
		return null;
	}

	let board = ubbf.readfile_trim('/tmp/sysinfo/board_name', '');
	return boards?.[board] ?? null;
}

/**
 * Runs boot-bank status and parses JSON output.
 *
 * @returns {object|null} Bank status with active/inactive info, or null
 */
function boot_bank_status() {
	let p = fs.popen(sprintf('%s status 2>/dev/null', BOOT_BANK_BIN), 'r');
	if (!p)
		return null;
	let output = p.read('all');
	let rc = p.close();

	if (rc != 0 || !output || trim(output) == '') {
		log_err('boot_bank_status: %s failed (rc=%d)', BOOT_BANK_BIN, rc);
		return null;
	}

	try {
		return json(output);
	} catch (e) {
		log_err('boot_bank_status: malformed JSON: %s', e);
		return null;
	}
}

/**
 * Reads a U-Boot environment variable.
 *
 * @param {string} name - Variable name
 * @returns {string|null} Variable value, or null if unset
 */
function fw_printenv(name) {
	let p = fs.popen(sprintf("fw_printenv -n '%s' 2>/dev/null", name), 'r');
	if (!p)
		return null;
	let val = trim(p.read('all') ?? '');
	p.close();
	return (val != '') ? val : null;
}

/**
 * Returns the flash partition name of a bank (UBI or eMMC GPT).
 *
 * @param {object} bank - Bank entry from boards.json
 * @returns {string} Partition name
 */
function bank_part_get(bank) {
	return bank.ubipart ?? bank.partname;
}

/**
 * Gets available firmware banks.
 *
 * @returns {array} Array of firmware bank objects
 */
export function banks_get() {
	let config = dual_bank_get();
	if (!config) {
		let board = ubus.call('system', 'board');
		let revision = board?.release?.revision;
		return [{
			instance: 1,
			env_value: null,
			name: 'firmware',
			version: revision ?? 'unknown',
			active: !!revision,
			bootable: !!revision
		}];
	}

	let status = boot_bank_status();
	if (!status)
		return [];

	let active_env = status.active.env_value;
	let sorted = sort(config.banks, (a, b) => {
		let an = bank_part_get(a);
		let bn = bank_part_get(b);
		return an < bn ? -1 : an > bn ? 1 : 0;
	});

	let result = [];
	for (let i = 0; i < length(sorted); i++) {
		let bank = sorted[i];
		let is_active = (bank.env_value == active_env);
		let revision = fw_printenv(sprintf('ubbf-bank-%s', bank.env_value));
		result[i] = {
			instance: i + 1,
			env_value: bank.env_value,
			name: bank_part_get(bank),
			version: revision ?? 'unknown',
			active: is_active,
			bootable: is_active || !!revision
		};
	}
	return result;
};

/**
 * Converts a firmware bank to TR-181 FirmwareImage format.
 *
 * @param {object} bank - Firmware bank with name, version, status flags
 * @returns {object} TR-181 formatted FirmwareImage object
 */
function bank_to_object(bank) {
	let status;
	if (bank.active)
		status = 'Active';
	else if (bank.bootable)
		status = 'Available';
	else
		status = 'NoImage';

	return {
		Alias: sprintf('cpe-firmware%d', bank.instance),
		Name: bank.name,
		Version: bank.version,
		Available: bank.bootable ? 'true' : 'false',
		Status: status,
		BootFailureLog: ''
	};
}

/**
 * Get handler for Device.DeviceInfo.FirmwareImage.{i}.
 *
 * @param {object} ctx - Context with instance
 * @returns {object|null} FirmwareImage properties
 */
function get(ctx) {
	let banks = banks_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(banks, bank_to_object);

	let bank = ubbf.get_by_instance(banks, ctx.instance);
	if (!bank)
		return null;

	return bank_to_object(bank);
}

/**
 * Validates a firmware image file.
 *
 * @param {string} path - Path to firmware image
 * @returns {object} Validation result with valid, forceable, allow_backup
 */
function firmware_validate(path) {
	let result = ubus.call('system', 'validate_firmware_image', { path });
	if (!result)
		return { valid: false };

	return {
		valid: result.valid ?? false,
		forceable: result.forceable ?? false,
		allow_backup: result.allow_backup ?? true
	};
}

/**
 * Schedules firmware activation (dual-bank: switch + reboot, single-bank: sysupgrade).
 *
 * @param {string} firmware_path - Path to firmware image (unused for dual-bank)
 * @param {string} command_key - USP command key
 * @returns {boolean} True if activation was initiated
 */
function firmware_install(firmware_path, command_key) {
	if (dual_bank_get()) {
		let rc = system(sprintf('%s switch', BOOT_BANK_BIN));
		if (rc != 0)
			return false;
		ubus.call('bbf-device', 'reboot', {
			command_key: command_key ?? '',
			local: false
		});
		return true;
	}

	let result = ubus.call('bbf-device', 'sysupgrade', {
		url: firmware_path,
		command_key: command_key ?? '',
		local: false
	});
	return result?.status == 'scheduled';
}

/**
 * Async handler for FirmwareImage Download operation.
 *
 * @param {object} input - Input parameters with URL, AutoActivate, credentials
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers array
 * @param {string} command_key - USP command key
 */
function download_handler(input, instance, complete, instances, command_key) {
	let fw_instance = instances[0];
	let url = input.URL ?? '';
	let auto_activate = input.AutoActivate ?? 'false';
	let username = input.Username ?? '';
	let password = input.Password ?? '';
	let file_size = input.FileSize ?? '';
	let checksum_algo = input.CheckSumAlgorithm ?? '';
	let checksum = input.CheckSum ?? '';

	if (url == '') {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'URL is required', {});
		return;
	}

	if (!ubbf.transfer_url_validate(url)) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'Invalid URL scheme', {});
		return;
	}

	let banks = banks_get();
	let target = ubbf.get_by_instance(banks, fw_instance);
	if (!target) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, sprintf('unknown FirmwareImage instance: %d', fw_instance), {});
		return;
	}

	if (length(banks) > 1 && target.active) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, 'cannot download to active bank', {});
		return;
	}

	let ctx = {
		command: 'Download',
		obj_path: sprintf('Device.DeviceInfo.FirmwareImage.%d.', fw_instance),
		url,
		transfer_type: 'Download',
		start_time: time(),
		command_key,
		instance,
		complete,
		auto_activate: ubbf.to_bool(auto_activate),
		fw_instance
	};

	fs.unlink(FIRMWARE_PATH);

	let opts = { timeout: 300 };
	if (username != '')
		opts = { ...opts, username, password };

	let task = uloop.task(
		(pipe) => {
			let result = curl_download(url, FIRMWARE_PATH, opts);
			result.download_path = FIRMWARE_PATH;
			pipe.send(result);
		},
		(result) => {
			if (!result)
				return;

			if (!result.success) {
				let status = curl_exit_to_status(result.exitcode);
				transfer_complete(ctx, sprintf('Download failed: %s (curl exit %d)', status, result.exitcode));
				return;
			}

			if (file_size != '') {
				let st = fs.stat(result.download_path);
				if (!st || st.size != +file_size) {
					transfer_complete(ctx, sprintf('File size mismatch: expected %s, got %d', file_size, st?.size ?? 0));
					return;
				}
			}

			if (checksum_algo != '' && checksum != '') {
				let hash_fn = CHECKSUM_ALGOS[checksum_algo];
				if (!hash_fn) {
					transfer_complete(ctx, sprintf('Unsupported checksum algorithm: %s', checksum_algo));
					return;
				}

				let actual = digest[hash_fn](result.download_path);
				if (!actual || lc(actual) != lc(checksum)) {
					transfer_complete(ctx, sprintf('Checksum mismatch (%s): expected %s, got %s', checksum_algo, checksum, actual ?? 'null'));
					return;
				}
			}

			let validation = firmware_validate(result.download_path);
			if (!validation.valid) {
				transfer_complete(ctx, 'Firmware validation failed');
				return;
			}

			if (dual_bank_get()) {
				let rc = system(sprintf("%s flash '%s'", BOOT_BANK_BIN, result.download_path));
				if (rc != 0) {
					transfer_complete(ctx, 'boot-bank flash failed');
					return;
				}
			}

			if (ctx.auto_activate) {
				transfer_complete(ctx, null);
				uloop.timer(UPGRADE_DELAY_MS, () => {
					firmware_install(result.download_path, ctx.command_key);
				});
				return;
			}

			transfer_complete(ctx, null);
		}
	);

	if (!task) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'Failed to create task', {});
		return;
	}
}

/**
 * Parses a time window specification string.
 *
 * @param {string} time_window - Comma-separated start,end,mode string
 * @returns {object|null} Parsed time window or null
 */
function time_window_parse(time_window) {
	if (!time_window || time_window == '')
		return null;

	let parts = split(time_window, ',');
	if (length(parts) < 3)
		return null;

	return {
		start: int(parts[0]),
		end: int(parts[1]),
		mode: parts[2]
	};
}

/**
 * Validates and activates downloaded firmware.
 *
 * @param {string} command_key - USP command key
 * @returns {boolean} True if activation was initiated
 */
function do_activate(command_key) {
	if (dual_bank_get())
		return firmware_install(null, command_key);

	let validation = firmware_validate(FIRMWARE_PATH);
	if (!validation.valid)
		return false;

	firmware_install(FIRMWARE_PATH, command_key);
	return true;
}

/**
 * Async handler for FirmwareImage Activate operation.
 *
 * @param {object} input - Input parameters with TimeWindow
 * @param {number} instance - Operation instance
 * @param {function} complete - Completion callback
 * @param {array} instances - Path instance numbers array
 * @param {string} command_key - USP command key
 */
function activate_handler(input, instance, complete, instances, command_key) {
	let fw_instance = instances[0];
	let banks = banks_get();
	let target = ubbf.get_by_instance(banks, fw_instance);
	if (!target) {
		complete(instance, USP_ERR_INVALID_ARGUMENTS, sprintf('unknown FirmwareImage instance: %d', fw_instance), { UserMessage: 'Unknown FirmwareImage instance' });
		return;
	}

	let is_dual_bank = length(banks) > 1;

	if (is_dual_bank) {
		if (target.active) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'FirmwareImage is already active', { UserMessage: 'FirmwareImage is already active' });
			return;
		}
		if (!target.bootable) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'FirmwareImage is not available', { UserMessage: 'FirmwareImage is not available' });
			return;
		}
	}
	else if (!fs.stat(FIRMWARE_PATH)) {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'No firmware image available', { UserMessage: 'No firmware image available' });
		return;
	}

	let tw = time_window_parse(input.TimeWindow ?? '');

	if (tw && tw.mode == 'ConfirmedActivation') {
		complete(instance, USP_ERR_COMMAND_FAILURE, 'ConfirmedActivation not supported', { UserMessage: 'ConfirmedActivation not supported' });
		return;
	}

	if (tw && tw.start > 0) {
		uloop.timer(tw.start * 1000, () => {
			do_activate(command_key);
		});
		complete(instance, 0, null, { UserMessage: 'Activation scheduled' });
		return;
	}

	if (!is_dual_bank) {
		let validation = firmware_validate(FIRMWARE_PATH);
		if (!validation.valid) {
			complete(instance, USP_ERR_COMMAND_FAILURE, 'Firmware validation failed', { UserMessage: 'Firmware validation failed' });
			return;
		}
	}

	complete(instance, 0, null, { UserMessage: 'Activating firmware' });
	uloop.timer(UPGRADE_DELAY_MS, () => {
		firmware_install(FIRMWARE_PATH, command_key);
	});
}

/**
 * Returns the TR-181 path of the currently active FirmwareImage instance.
 *
 * @returns {string} Path reference, or empty string if no bank is active
 */
export function active_path_get() {
	for (let bank in banks_get())
		if (bank.active)
			return sprintf('Device.DeviceInfo.FirmwareImage.%d', bank.instance);
	return '';
};

/**
 * Returns the TR-181 path of the FirmwareImage instance that will boot next.
 *
 * Currently identical to active_path_get(): boot-bank switch auto-reboots
 * 3s after flipping the env, so a user-visible Active/Boot divergence
 * window does not exist in practice.
 *
 * @returns {string} Path reference, or empty string if no bank is active
 */
export function boot_path_get() {
	return active_path_get();
};

export const model = {
	'Device.DeviceInfo.FirmwareImage': {
	},

	'Device.DeviceInfo.FirmwareImage.{i}': {
		schema: schemas.FirmwareImage,
		get: get
	}
};

export const operations = {
	'Device.DeviceInfo.FirmwareImage.{i}.Download()': {
		type: 'async',
		handler: download_handler
	},

	'Device.DeviceInfo.FirmwareImage.{i}.Activate()': {
		type: 'async',
		handler: activate_handler
	}
};
