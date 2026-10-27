'use strict';

// Keeps a copy of resolv.conf.auto without the learned DNS servers a
// controller disabled (Device.DNS.Client.Server.{i}.Enable on a learned
// row). render/templates/dns.uc points dnsmasq at the copy while such a
// row exists; dnsmasq reads the file again when it changes.

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { log_err } from 'ubbf.utils.logging';
import { dns_learned_row, DNS_RESOLV_AUTO, DNS_RESOLV_FILTERED } from 'ubbf.utils.dns';

const CONFIG_PATH = '/etc/ubbf/config.json';

// netifd sends the network.interface event before it writes
// resolv.conf.auto (interface_proto_event_cb() in interface.c).
const SETTLE_MS = 1000;

let disabled = {};
let settle_timer;

/**
 * Reads the addresses of the disabled learned servers from the stored
 * configuration.
 *
 * @returns {object} Map with each disabled address as a truthy key
 */
function disabled_servers_read() {
	let config;
	try {
		config = json(fs.readfile(CONFIG_PATH) ?? '{}');
	} catch (e) {
		log_err('dns-filter: invalid JSON in %s', CONFIG_PATH);
		return {};
	}

	let result = {};
	for (let inst, row in config?.Device?.DNS?.Client?.Server ?? {}) {
		if (!dns_learned_row(row) || !row?.DNSServer)
			continue;
		if (!ubbf.to_bool(row.Enable ?? 'true'))
			result[row.DNSServer] = true;
	}
	return result;
}

/**
 * Tells whether a resolv.conf line names a disabled server.
 *
 * @param {string} line - One line of resolv.conf.auto
 * @returns {boolean} True when the line has to go
 */
function line_disabled(line) {
	let m = match(line, /^nameserver[ \t]+([^ \t]+)/);
	return !!(m && disabled[m[1]]);
}

/**
 * Writes the filtered copy of resolv.conf.auto when its content changed.
 */
function filtered_write() {
	let auto = fs.readfile(DNS_RESOLV_AUTO);
	if (auto == null)
		return;

	let lines = filter(split(auto, '\n'), (line) => !line_disabled(line));
	let content = join('\n', lines);

	if (fs.readfile(DNS_RESOLV_FILTERED) == content)
		return;

	if (!ubbf.write_file_atomic(DNS_RESOLV_FILTERED, content))
		log_err('dns-filter: failed to write %s', DNS_RESOLV_FILTERED);
}

/**
 * Handles bbf-dm.digest: a controller may have disabled or enabled a
 * learned server.
 *
 * @param {string} type - Event type
 * @param {object} data - Event payload
 */
function digest_listener(type, data) {
	disabled = disabled_servers_read();
	filtered_write();
}

/**
 * Handles network.interface: netifd may write a new resolv.conf.auto.
 *
 * @param {string} type - Event type
 * @param {object} data - Event payload
 */
function interface_listener(type, data) {
	if (settle_timer)
		settle_timer.cancel();
	settle_timer = uloop.timer(SETTLE_MS, () => {
		settle_timer = null;
		filtered_write();
	});
}

/**
 * Writes the filtered copy and follows config changes from obuspa and
 * interface changes from netifd.
 */
export function init() {
	disabled = disabled_servers_read();
	filtered_write();
	ubus.listener('bbf-dm.digest', digest_listener);
	ubus.listener('network.interface', interface_listener);
};
