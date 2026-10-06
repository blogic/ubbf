'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as ubbf from 'ubbf';
import { log_info, log_err } from 'ubbf.utils.logging';

const STATE_PATH = '/tmp/ubbf/ip-block-list.json';
const CONFIG_PATH = '/etc/ubbf/config.json';
const NFT_FILE = '/usr/share/ubbf/sshguard.nft';
const TABLE_NAME = 'inet ubbf-sshguard';

const DEFAULT_THRESHOLD = 3;

let entries = [];
let threshold = DEFAULT_THRESHOLD;

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

function config_load() {
	threshold = DEFAULT_THRESHOLD;

	let data = fs.readfile(CONFIG_PATH);
	if (!data)
		return;

	try {
		let cfg = json(data);
		let bl = cfg?.Device?.SSH?.X_UBBF_BlockList;
		if (bl?.Threshold)
			threshold = +bl.Threshold || DEFAULT_THRESHOLD;
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

function nft_table_install() {
	let rc = system(sprintf('nft list table %s >/dev/null 2>&1', TABLE_NAME));
	if (rc == 0)
		return;

	rc = system(sprintf('nft -f %s', NFT_FILE));
	if (rc != 0)
		log_err('sshguard: failed to install %s (nft rc=%d)', NFT_FILE, rc);
}

function nft_block(ip, family) {
	let set = (family == 'v4') ? 'blocklist_v4' : 'blocklist_v6';
	let rc = system(sprintf(
		'nft add element %s %s { %s } >/dev/null 2>&1',
		TABLE_NAME, set, ip));
	if (rc != 0)
		log_err('sshguard: nft add element %s failed (rc=%d)', ip, rc);
}

function nft_flush_sets() {
	system(sprintf('nft flush set %s blocklist_v4 >/dev/null 2>&1', TABLE_NAME));
	system(sprintf('nft flush set %s blocklist_v6 >/dev/null 2>&1', TABLE_NAME));
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

	let entry = entry_find(ip);
	if (!entry) {
		entry = {
			ip: ip,
			fail_count: 0,
			blocked: false,
			blocked_at: null
		};
		push(entries, entry);
	}

	entry.fail_count++;

	log_info('sshguard: %s (reason=%s user=%s) fail_count=%d',
		ip, reason, user, entry.fail_count);

	if (!entry.blocked && entry.fail_count >= threshold) {
		entry.blocked = true;
		entry.blocked_at = time();
		nft_block(ip, family);
		log_info('sshguard: blocking %s (permanent until Reset() or reboot)', ip);
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
