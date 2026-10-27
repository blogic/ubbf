'use strict';

// Blocks the SFPs that Device.SFPs.AllowedSFPs (TR-181 2.21) does not
// allow. netifd treats a deferred device as absent (network.device
// set_state, device_refresh_present()), so the interfaces on the cage
// netdev stay down until the SFP is allowed again. The laser of the module
// is not switched off: the kernel sfp driver owns TX_DISABLE.

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { log_info, log_err, sfp_type_resolve, sfp_allowed } from 'ubbf';
import { dm_visible } from 'ubbf.utils.dm-version';

const CONFIG_PATH = '/etc/ubbf/config.json';
const USFPD = 'usfpd';
const APPLY_DELAY_MS = 200;

const SUPPORTED = dm_visible('2.21', null);

let sfps;
let deferred = {};
let apply_timer;

function config_load() {
	sfps = null;

	let data = fs.readfile(CONFIG_PATH);
	if (!data)
		return;

	try {
		sfps = json(data)?.Device?.SFPs;
	} catch (e) {
		log_err('sfp-allow: invalid JSON in %s', CONFIG_PATH);
	}
}

/**
 * Tells whether the SFP in a cage is blocked: present and not allowed.
 *
 * @param {string} cage - Cage netdev name
 * @returns {boolean|null} True when the SFP must be blocked, null when
 *   usfpd did not answer
 */
function cage_blocked(cage) {
	let status = ubus.call(USFPD, 'cage_status', { name: cage });
	if (!status)
		return null;
	if (!status.SFPPresent)
		return false;

	let trx = ubus.call(USFPD, 'transceiver', { name: cage });
	if (!trx)
		return null;

	let ident = trx.vendor ?? {};
	let type = sfp_type_resolve(sfps, ident, status.SFPType ?? '');

	return !sfp_allowed(sfps, ident, type);
}

/**
 * Defers or releases the netdev of each cage. Only a cage that this
 * subsystem deferred is released, so other users of defer keep theirs. A
 * cage that usfpd does not answer for keeps its state.
 */
function apply() {
	apply_timer = null;

	for (let cage in ubus.call(USFPD, 'cages', {})?.cages ?? []) {
		let blocked = cage_blocked(cage);
		if (blocked == null || (deferred[cage] ?? false) == blocked)
			continue;

		// set_state answers without data, so ubus.call() returns null on
		// success too; ubus.error() tells the outcome
		ubus.call('network.device', 'set_state', { name: cage, defer: blocked });
		if (ubus.error()) {
			log_err('sfp-allow: set_state %s defer %s failed: %s', cage, blocked, ubus.error());
			continue;
		}

		deferred[cage] = blocked;
		log_info('sfp-allow: SFP in %s %s', cage, blocked ? 'blocked' : 'allowed');
	}
}

function apply_schedule() {
	if (apply_timer)
		apply_timer.set(APPLY_DELAY_MS);
	else
		apply_timer = uloop.timer(APPLY_DELAY_MS, apply);
}

function digest_event() {
	config_load();
	apply_schedule();
}

/**
 * A restarted netifd has forgotten the deferred devices; a started usfpd
 * makes the cages known, at boot after this subsystem.
 *
 * @param {string} type - Event type
 * @param {object} data - Event data with the object path
 */
function object_event(type, data) {
	if (data?.path == 'network.device')
		deferred = {};
	else if (data?.path != USFPD)
		return;

	apply_schedule();
}

/**
 * Loads the allow list and blocks the SFPs it does not allow; follows SFP
 * insertions (usfpd.cage), configuration changes and netifd restarts. Below
 * TR-181 2.21 there is no allow list and nothing is blocked.
 */
export function init() {
	if (!SUPPORTED)
		return;

	config_load();
	ubus.listener('usfpd.cage', apply_schedule);
	ubus.listener('bbf-dm.digest', digest_event);
	ubus.listener('ubus.object.add', object_event);
	apply_schedule();
};
