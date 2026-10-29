'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import { cmd_build } from 'ubbf';
import { log_info, log_warn, log_err, config_path_check } from 'ubbf';
import { popen_async, status_describe } from 'ubbf.utils.process';

const CONFIG_PATH = '/etc/ubbf/config.json';
const APPLY_PATH = '/usr/libexec/ubbf/apply';
const SHUTDOWN_PATH = '/etc/ubbf/shutdown.json';

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
	// The device certificate and the CA that signed it, which
	// uci-defaults/ubbf-certs makes only when cert.pem is missing.
	'/etc/ubbf/ca.pem',
	'/etc/ubbf/ca.key',
	'/etc/ubbf/cert.pem',
	'/etc/ubbf/cert.key',
	'/etc/ubbf/firmware.json',
	'/etc/ubbf/process-faults.json',
	'/etc/ubbf/reboots.json',
	'/etc/ubbf/kernel-faults.json',
	// The accounts of Device.Users: config.json holds the rows, the system
	// files the password hashes, and the record which entries ubbf owns.
	'/etc/passwd',
	'/etc/shadow',
	'/etc/group',
	'/etc/ubbf/users-managed.json',
	// What AddCertificateBundle() and AddCABundle() installed, with the
	// Alias that refers to it. config.json pins the instance numbers.
	'/etc/ubbf/certs',
	'/etc/ubbf/cabundles',
	'/etc/ubbf/security-aliases.json',
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

// A factory reset keeps what the device is managed through, so it comes back
// reachable from the ACS, and the fault records, so the last crash can still
// be read after a reset. Deliberately not the data model, the
// reboot history or the local credentials: keeping those would not be a reset.
const RESET_KEEP_FILES = [
	'/etc/config/cwmp',
	'/etc/config/obuspa',
	'/etc/usp/acs-ca.pem',
	'/etc/ubbf/process-faults.json',
	'/etc/ubbf/kernel-faults.json'
];

let apply_timer;
let apply_proc;
let apply_pending;
let apply_waiters = [];
let shutting_down;

function apply_busy() {
	return apply_timer != null || apply_proc != null;
}

/**
 * Runs `fn` now, or once no real apply is scheduled, running or pending.
 *
 * @param {function} fn - Work that must not cut a real apply short
 */
function apply_idle_run(fn) {
	if (apply_busy()) {
		push(apply_waiters, fn);
		return;
	}

	fn();
}

let apply_start;

function apply_next() {
	if (apply_pending) {
		apply_start();
		return;
	}

	if (apply_busy())
		return;

	let waiters = apply_waiters;
	apply_waiters = [];
	for (let fn in waiters)
		fn();
}

// One real apply at a time: apply replaces /var/run/uci as a whole.
apply_start = function() {
	apply_pending = false;
	log_info('applying configuration');

	apply_proc = uloop.process(APPLY_PATH, [ CONFIG_PATH ], null, (status) => {
		apply_proc = null;
		if (status != 0)
			log_err('apply failed (%s)', status_describe(status));
		apply_next();
	});

	if (!apply_proc) {
		log_err('apply could not start: %s', uloop.error());
		apply_next();
	}
};

function apply_schedule() {
	if (apply_timer)
		apply_timer.cancel();

	log_info('apply scheduled in 1 second');
	apply_timer = uloop.timer(1000, function() {
		apply_timer = null;
		if (apply_proc) {
			apply_pending = true;
			log_info('apply queued behind the running apply');
			return;
		}
		apply_start();
	});
}

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

	uloop.timer(1000, () => apply_idle_run(function() {
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
	}));

	return { status: 'scheduled' };
}

// A power cycle follows a shutdown and clears the pstore RAM that reboot
// uses, so the cause goes to flash; boot-cause reads and removes it.
function shutdown_handler(req) {
	shutting_down = true;
	let record = {
		cause: req.args?.cause ?? 'RemoteShutdown',
		reason: req.args?.reason ?? 'Unknown',
		command_key: req.args?.command_key ?? ''
	};

	log_warn('shutdown scheduled cause=%s', record.cause);

	uloop.timer(1000, function() {
		fs.writefile(SHUTDOWN_PATH, sprintf('%J\n', record));
		let rc = system('poweroff');
		if (rc != 0) {
			log_err('poweroff failed (exit %d), resuming normal operation', rc);
			fs.unlink(SHUTDOWN_PATH);
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

	uloop.timer(1000, () => apply_idle_run(function() {
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
	}));

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

	uloop.timer(1000, () => apply_idle_run(function() {
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
	}));

	return { status: 'scheduled' };
}

/**
 * Makes the reply of the apply method from the end of its dry-run, and
 * schedules the real apply after a dry-run that succeeded.
 *
 * @param {object} result - Result of popen_async()
 * @param {boolean} do_apply - Whether the caller asked for the real apply
 * @returns {object} Reply of the apply method
 */
function dry_run_reply(result, do_apply) {
	let raw = result.data ?? '';

	if (result.exitcode != 0)
		return { success: false, error: 'Dry-run failed', logs: [], output: raw };

	let dry_result;
	try {
		dry_result = json(raw);
	} catch (e) {
		dry_result = null;
	}
	if (!dry_result)
		return { success: false, error: 'Failed to parse dry-run output', logs: [], output: raw };

	if (do_apply)
		apply_schedule();

	return {
		success: true,
		logs: dry_result.logs ?? [],
		output: dry_result.uci ?? '',
		scheduled: do_apply
	};
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

	req.defer();
	popen_async([ { raw: APPLY_PATH }, '--dry-run', file_path ],
		(result) => req.reply(dry_run_reply(result, do_apply)));
}

// The apply runs beside the event loop, so a running apply is still pending.
function apply_state_handler(req) {
	return { pending: apply_busy() };
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
 * @returns {object} Method definitions for reboot, shutdown, factory_reset,
 *                   sysupgrade, apply, apply_state
 */
export function ubus_methods() {
	return {
		reboot: {
			call: reboot_handler,
			args: { command_key: '', local: true }
		},
		shutdown: {
			call: shutdown_handler,
			args: { command_key: '', cause: '', reason: '' }
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
