'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import { cmd_build } from 'ubbf.utils.process';
import { log_info, log_warn, log_err } from 'ubbf.utils.logging';
import { config_path_check } from 'ubbf.utils.validate';

const CONFIG_PATH = '/etc/ubbf/config.json';

const BACKUP_PATH = '/tmp/ubbf-backup.tgz';

// factoryreset -k spares exactly this name at the root of the overlay while
// erasing everything else, fopivot() then moves it into upper/ on the next
// mount, and /lib/preinit/80_mount_root extracts it at /.
const RESET_KEEP_PATH = '/overlay/sysupgrade.tgz';

// `sysupgrade -f` substitutes this archive for the one sysupgrade would have
// built, so /etc/sysupgrade.conf and /lib/upgrade/keep.d are not consulted
// and this list is the whole of what survives an upgrade.
const BACKUP_FILES = [
	'/etc/usp/bbf.json',
	'/etc/ubbf/config.json',
	'/etc/ubbf/firmware.json',
	'/etc/ubbf/process-faults.json',
	'/etc/ubbf/reboots.json',
	'/etc/ubbf/kernel-faults.json',
	'/etc/ubbf/webui/credentials',
	'/etc/ubbf/certs',
	'/etc/config/obuspa',
	'/etc/usp/acs-ca.pem',
	// The CWMP counterparts of the two above: the ACS binding with its
	// Connection Request credentials, and the protocol state holding the
	// ParameterKey. Losing either across an upgrade orphans the device
	// until the ACS re-provisions it on a later Inform. cwmpd's cache holds
	// the pending Download, without which no TRANSFER COMPLETE follows the
	// upgrade.
	'/etc/config/cwmp',
	'/etc/ubbf/cwmp-state.json',
	'/etc/cwmp-cache.json'
];

// A factory reset keeps only what the device is managed through, so it comes
// back reachable from the ACS. Deliberately not the data model, the fault
// records or the local credentials: keeping those would not be a reset.
const RESET_KEEP_FILES = [
	'/etc/config/cwmp',
	'/etc/config/obuspa',
	'/etc/usp/acs-ca.pem'
];

let apply_timer;
let shutting_down;

function backup_create(dest, wanted) {
	let files = [];
	for (let path in wanted) {
		if (fs.stat(path))
			push(files, path);
	}

	if (!length(files)) {
		log_warn('no backup files found');
		return null;
	}

	let cmd = sprintf('tar czf %s -C / %s 2>/dev/null',
		dest, join(' ', map(files, f => substr(f, 1))));

	if (system(cmd) != 0) {
		log_err('failed to create backup archive');
		return null;
	}

	return dest;
}

function pstore_write(data) {
	let pmsg = fs.open('/dev/pmsg0', 'w');
	if (!pmsg) {
		log_err('failed to open /dev/pmsg0');
		return false;
	}
	pmsg.write(sprintf('%J\n', data));
	pmsg.close();
	return true;
}

function reboot_handler(req) {
	shutting_down = true;
	let command_key = req.args?.command_key ?? '';
	let local = req.args?.local ?? true;

	log_warn('reboot scheduled local=%s', local);

	uloop.timer(1000, function() {
		pstore_write({
			reason: 'reboot',
			command_key: command_key,
			local: local
		});
		let rc = system('reboot');
		if (rc != 0) {
			log_err('reboot failed (exit %d), resuming normal operation', rc);
			shutting_down = false;
		}
	});

	return { status: 'scheduled' };
}

function factory_reset_handler(req) {
	shutting_down = true;
	let command_key = req.args?.command_key ?? '';
	let local = req.args?.local ?? true;

	log_warn('factory_reset scheduled local=%s', local);

	let keep = backup_create(RESET_KEEP_PATH, RESET_KEEP_FILES);
	if (!keep)
		log_warn('factory reset: no archive kept, the ACS binding will be lost');

	uloop.timer(1000, function() {
		pstore_write({
			reason: 'factoryreset',
			command_key: command_key,
			local: local
		});
		let rc = system('factoryreset -y -r -k');
		if (rc != 0) {
			log_err('factory reset failed (exit %d), resuming normal operation', rc);
			fs.unlink(RESET_KEEP_PATH);
			shutting_down = false;
		}
	});

	return { status: 'scheduled' };
}

function sysupgrade_handler(req) {
	let command_key = req.args?.command_key ?? '';
	let local = req.args?.local ?? true;
	let url = req.args?.url ?? '';

	if (url == '')
		return { error: 'url required' };

	shutting_down = true;
	log_warn('sysupgrade scheduled url=%s', url);

	let backup = backup_create(BACKUP_PATH, BACKUP_FILES);

	uloop.timer(1000, function() {
		pstore_write({
			reason: 'sysupgrade',
			command_key: command_key,
			local: local
		});

		let parts = [{raw: 'sysupgrade'}];
		if (backup)
			push(parts, '-f', backup);
		push(parts, url);

		let rc = system(cmd_build(parts));
		if (rc != 0) {
			log_err('sysupgrade failed (exit %d), resuming normal operation', rc);
			shutting_down = false;
		}
	});

	return { status: 'scheduled' };
}

function apply_handler(req) {
	let do_apply = req.args?.apply ?? false;
	let file_path = req.args?.file ?? CONFIG_PATH;

	let reason = config_path_check(file_path);
	if (reason)
		return { success: false, error: reason, logs: [] };

	// The scheduled apply always applies the stored configuration, so a
	// check of another file would not describe what gets applied.
	if (do_apply && file_path != CONFIG_PATH)
		return { success: false, error: 'file is only valid for a dry run', logs: [] };

	let p = fs.popen(cmd_build([ '/usr/libexec/ubbf/apply', '--dry-run', file_path ]), 'r');
	let raw = p ? p.read('all') : '';
	let rc = p ? p.close() : -1;

	if (rc != 0)
		return { success: false, error: 'Dry-run failed', logs: [], output: raw };

	let dry_result;
	try {
		dry_result = json(raw);
	} catch (e) {
		dry_result = null;
	}
	if (!dry_result)
		return { success: false, error: 'Failed to parse dry-run output', logs: [], output: raw };

	if (do_apply) {
		if (apply_timer)
			apply_timer.cancel();

		log_info('apply scheduled in 1 second');
		apply_timer = uloop.timer(1000, function() {
			apply_timer = null;
			log_info('applying configuration');
			system('/usr/libexec/ubbf/apply /etc/ubbf/config.json');
		});
	}

	return {
		success: true,
		logs: dry_result.logs ?? [],
		output: dry_result.uci ?? '',
		scheduled: do_apply
	};
}

// The apply itself runs in system() and blocks this daemon, so a caller
// only gets this answer once a running apply has finished.
function apply_state_handler(req) {
	return { pending: apply_timer != null };
}

/**
 * Returns true when a shutdown / sysupgrade / factory-reset is in progress.
 * Consumed by process-faults to suppress fault recording during teardown.
 *
 * @returns {boolean} true if shutdown has been scheduled
 */
export function is_shutting_down() {
	return shutting_down == true;
};

/**
 * Returns the ubus method table for lifecycle operations.
 *
 * @returns {object} Method definitions for reboot, factory_reset, sysupgrade, apply,
 *                   apply_state
 */
export function ubus_methods() {
	return {
		reboot: {
			call: reboot_handler,
			args: { command_key: '', local: true }
		},
		factory_reset: {
			call: factory_reset_handler,
			args: { command_key: '', local: true }
		},
		sysupgrade: {
			call: sysupgrade_handler,
			args: { command_key: '', local: true, url: '' }
		},
		apply: {
			call: apply_handler,
			args: { apply: false, file: '' }
		},
		apply_state: {
			call: apply_state_handler,
			args: {}
		}
	};
};
