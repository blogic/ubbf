'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.SSH';
import * as ubbf from 'ubbf';

const BLOCKLIST_STATE_PATH = '/tmp/ubbf/ip-block-list.json';

/**
 * Reads the SSH blocklist state file maintained by ubbf-device.
 *
 * The file is the contract between obuspa (which exposes the TR-181 surface)
 * and ubbf-device (which owns the runtime state). Missing file or invalid
 * JSON is treated as "no entries"; the file is allowed to lag behind reality
 * during ubbf-device startup.
 *
 * @returns {array} Array of { ip, fail_count, blocked, blocked_at } entries
 */
function blocklist_state_load() {
	let data = fs.readfile(BLOCKLIST_STATE_PATH);
	if (!data)
		return [];

	try {
		let parsed = json(data);
		let entries = parsed?.entries;
		return type(entries) == 'array' ? entries : [];
	} catch (e) {
		return [];
	}
}

/**
 * Converts a blocklist state entry into a TR-181 Entry object.
 *
 * @param {object} entry - State entry from /tmp/ubbf/ip-block-list.json
 * @returns {object} TR-181 X_UBBF_BlockList.Entry.{i} object
 */
function entry_to_object(entry) {
	return {
		Alias: sprintf('cpe-BlockList-%s', entry.ip ?? ''),
		IPAddress: entry.ip ?? '',
		FailCount: sprintf('%d', entry.fail_count ?? 0),
		Blocked: entry.blocked ? 'true' : 'false'
	};
}

/**
 * Get handler for Device.SSH.
 *
 * @param {object} ctx - Context with config
 * @returns {object} SSH properties with instance counts
 */
function ssh_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Server)),
		AuthorizedKeyNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.AuthorizedKey))
	};
}

/**
 * Firewall hook for Device.SSH.Server.{i}.
 *
 * @param {object} inst - Server instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptors for SSH port
 */
function ssh_server_firewall(inst, root, path) {
	if (!ubbf.to_bool(inst.Enable))
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	let port = inst.Port ?? '22';

	return [{
		type: 'Service',
		alias: sprintf('cpe-ssh-%s', port),
		Interface: inst.Interface,
		Protocol: 'tcp',
		DestPort: sprintf('%s', port),
		Action: 'Accept'
	}];
}

/**
 * Get handler for Device.SSH.X_UBBF_BlockList.
 *
 * Threshold comes from the persisted config; the EntryNumberOfEntries is
 * dynamic, computed from the state file.
 *
 * @param {object} ctx - Context with config
 * @returns {object} BlockList container properties
 */
function blocklist_get(ctx) {
	let entries = blocklist_state_load();
	return {
		...ubbf.ctx_config(ctx),
		EntryNumberOfEntries: sprintf('%d', length(entries))
	};
}

/**
 * Get handler for Device.SSH.X_UBBF_BlockList.Entry.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|array|null} Single entry or enumerated entries
 */
function entry_get(ctx) {
	let entries = blocklist_state_load();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(entries, entry_to_object);

	let entry = ubbf.get_by_instance(entries, ctx.instance);
	if (!entry)
		return null;

	return entry_to_object(entry);
}

/**
 * Operate handler for Device.SSH.X_UBBF_BlockList.Reset().
 *
 * Clears counters and active bans by delegating to ubbf-device via ubus.
 * Cross-process synchronous call is safe (bbf-dm runs in obuspa, bbf-device
 * in the ubbf-device daemon).
 *
 * @param {object} input - Operation input (unused)
 * @param {string} command_key - Command tracking key (unused)
 * @param {object} root - Root config (unused)
 * @returns {object|null} Empty object on success, null on failure
 */
function blocklist_reset_handler(input, command_key, root) {
	let result = ubus.call({
		object: 'bbf-device',
		method: 'sshguard_reset',
		data: {}
	});

	if (result == null)
		return null;

	return {};
}

export const model = {
	'Device.SSH': {
		schema: schemas.SSH,
		get: ssh_get
	},

	'Device.SSH.AuthorizedKey': {
	},

	'Device.SSH.AuthorizedKey.{i}': {
		schema: schemas.AuthorizedKey
	},

	'Device.SSH.Server': {
	},

	'Device.SSH.Server.{i}': {
		schema: schemas.Server,
		firewall: ssh_server_firewall
	},

	'Device.SSH.X_UBBF_BlockList': {
		schema: schemas.X_UBBF_BlockList,
		get: blocklist_get
	},

	'Device.SSH.X_UBBF_BlockList.Entry': {
	},

	'Device.SSH.X_UBBF_BlockList.Entry.{i}': {
		schema: schemas.X_UBBF_BlockList_Entry,
		get: entry_get
	}
};

export const operations = {
	'Device.SSH.X_UBBF_BlockList.Reset()': {
		type: 'sync',
		handler: blocklist_reset_handler
	}
};
