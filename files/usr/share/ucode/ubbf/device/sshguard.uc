'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { log_info, log_err } from 'ubbf';
import { dm_visible } from 'ubbf.utils.dm-version';

const STATE_PATH = '/tmp/ubbf/ip-block-list.json';
const CONFIG_PATH = '/etc/ubbf/config.json';
const NFT_FILE = '/usr/share/nftables.d/ruleset-post/ubbf-sshguard.nft';
const TABLE_NAME = 'inet ubbf-sshguard';

const DEFAULT_THRESHOLD = 3;
const DEFAULT_BAN_TIME = 900;

// Device.SSH.Server.{i}.BanTime exists from TR-181 2.20; before, a ban lasts
// until Reset() or a reboot.
const BAN_TIME_SUPPORTED = dm_visible('2.20', null);

let entries = [];
let threshold = DEFAULT_THRESHOLD;
let ban_time = null;

function state_load() {
	let data = fs.readfile(STATE_PATH);
	if (!data) {
		entries = [];
		return;
	}

	try {
		let parsed = json(data);
		let loaded = parsed?.entries;
		entries = (type(loaded) == 'array') ? loaded : [];
	} catch (e) {
		log_err('sshguard: invalid JSON in %s, starting fresh', STATE_PATH);
		entries = [];
	}
}

function state_persist() {
	if (!ubbf.write_file_atomic(STATE_PATH, sprintf('%.J\n', { entries })))
		log_err('sshguard: failed to write %s', STATE_PATH);
}

/**
 * Returns the ban time in seconds: the largest BanTime of the SSH servers,
 * since a failed login does not say which server it was for.
 *
 * @param {object|null} ssh - Device.SSH of the configuration
 * @returns {number|null} Seconds, 0 for no ban, null for a ban until Reset()
 */
function ban_time_get(ssh) {
	if (!BAN_TIME_SUPPORTED)
		return null;

	let longest = null;
	for (let inst, server in ssh?.Server ?? {}) {
		let value = ubbf.to_int(server?.BanTime) ?? DEFAULT_BAN_TIME;
		if (longest == null || value > longest)
			longest = value;
	}

	return longest ?? DEFAULT_BAN_TIME;
}

function config_load() {
	threshold = DEFAULT_THRESHOLD;
	ban_time = ban_time_get(null);

	let data = fs.readfile(CONFIG_PATH);
	if (!data)
		return;

	try {
		let cfg = json(data);
		let bl = cfg?.Device?.SSH?.X_UBBF_BlockList;
		if (bl?.Threshold)
			threshold = +bl.Threshold || DEFAULT_THRESHOLD;
		ban_time = ban_time_get(cfg?.Device?.SSH);
	} catch (e) {
		log_err('sshguard: invalid JSON in %s, using defaults', CONFIG_PATH);
	}
}

function ip_family(ip) {
	let bytes = iptoarr(ip);
	if (type(bytes) != 'array')
		return null;
	if (length(bytes) == 4)
		return 'v4';
	if (length(bytes) == 16)
		return 'v6';
	return null;
}

function ip_canonical(ip) {
	let bytes = iptoarr(ip);
	if (type(bytes) != 'array')
		return null;
	return arrtoip(bytes);
}

function nft_block(ip, family, seconds) {
	let set = (family == 'v4') ? 'blocklist_v4' : 'blocklist_v6';
	let timeout = seconds ? sprintf(' timeout %ds', seconds) : '';
	let rc = system(sprintf(
		'nft add element %s %s { %s%s } >/dev/null 2>&1',
		TABLE_NAME, set, ip, timeout));
	if (rc != 0)
		log_err('sshguard: nft add element %s failed (rc=%d)', ip, rc);
}

function nft_flush_sets() {
	system(sprintf('nft flush set %s blocklist_v4 >/dev/null 2>&1', TABLE_NAME));
	system(sprintf('nft flush set %s blocklist_v6 >/dev/null 2>&1', TABLE_NAME));
}

/**
 * Adds the bans that have not ended to the nft sets.
 */
function bans_replay() {
	let now = time();

	for (let entry in entries) {
		if (!entry.blocked)
			continue;
		if (entry.blocked_until && now >= entry.blocked_until)
			continue;

		let family = ip_family(entry.ip);
		if (family)
			nft_block(entry.ip, family, entry.blocked_until ? entry.blocked_until - now : null);
	}
}

/**
 * Loads the nft table when it is missing, with the bans that have not
 * ended. A stop of the firewall deletes every nft table, and the
 * firewall stays stopped while Device.Firewall.Enable is false.
 */
function nft_table_install() {
	let rc = system(sprintf('nft list table %s >/dev/null 2>&1', TABLE_NAME));
	if (rc == 0)
		return;

	rc = system(sprintf('nft -f %s', NFT_FILE));
	if (rc != 0) {
		log_err('sshguard: failed to install %s (nft rc=%d)', NFT_FILE, rc);
		return;
	}

	bans_replay();
}

function entry_find(ip) {
	for (let i = 0; i < length(entries); i++) {
		if (entries[i].ip == ip)
			return entries[i];
	}
	return null;
}

function auth_event_handler(req) {
	let raw_ip = req.args?.ip ?? '';
	let reason = req.args?.reason ?? '';
	let user = req.args?.user ?? '';

	if (raw_ip == '')
		return { error: 'missing ip' };

	let family = ip_family(raw_ip);
	if (!family)
		return { error: 'invalid ip' };

	let ip = ip_canonical(raw_ip);

	let now = time();
	let entry = entry_find(ip);
	if (!entry) {
		entry = { ip: ip };
		push(entries, entry);
	}

	// nft drops the address when its ban ends; the count starts again then.
	if (!entry.fail_count || (entry.blocked_until && now >= entry.blocked_until)) {
		entry.fail_count = 0;
		entry.blocked = false;
		entry.blocked_at = null;
		entry.blocked_until = null;
	}

	entry.fail_count++;

	log_info('sshguard: %s (reason=%s user=%s) fail_count=%d',
		ip, reason, user, entry.fail_count);

	if (!entry.blocked && ban_time !== 0 && entry.fail_count >= threshold) {
		nft_table_install();
		entry.blocked = true;
		entry.blocked_at = now;
		entry.blocked_until = ban_time ? now + ban_time : null;
		nft_block(ip, family, ban_time);
		if (ban_time)
			log_info('sshguard: blocking %s for %d s', ip, ban_time);
		else
			log_info('sshguard: blocking %s (until Reset() or reboot)', ip);
	}

	state_persist();
	return {};
}

function sshguard_reset_handler(req) {
	entries = [];
	state_persist();
	nft_flush_sets();
	log_info('sshguard: reset (cleared counters and bans)');
	return {};
}

function digest_listener(type, data) {
	config_load();
}

/**
 * Adds the stored bans to the nft sets. fw4 runs it after each start and
 * reload, when a stop before the start emptied the sets.
 */
export function bans_restore() {
	state_load();
	bans_replay();
};

/**
 * Loads persisted state, installs the nft scaffold, and subscribes to
 * bbf-dm.digest so that config changes from obuspa take effect without
 * a restart.
 */
export function init() {
	config_load();
	state_load();
	nft_table_install();
	ubus.listener('bbf-dm.digest', digest_listener);
};

/**
 * Returns the ubus method table for the SSH brute-force guard.
 *
 * @returns {object} Method definitions for sshguard_auth_event and sshguard_reset
 */
export function ubus_methods() {
	return {
		sshguard_auth_event: {
			call: auth_event_handler,
			args: {
				reason: '',
				ip: '',
				user: ''
			}
		},
		sshguard_reset: {
			call: sshguard_reset_handler,
			args: {}
		}
	};
};
