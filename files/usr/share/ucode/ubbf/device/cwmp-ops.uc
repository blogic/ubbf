'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import { log_info, log_err } from 'ubbf.utils.logging';

// The operation handlers reference obuspa-injected globals; under
// ubbf-device nothing injects them, so provide the ones the handlers
// use (USP error codes per TR-369 annex) before any handler runs.
global.USP_ERR_INVALID_ARGUMENTS ??= 7004;
global.USP_ERR_COMMAND_FAILURE ??= 7022;

import { handler as ping_handler } from 'ubbf.tr143.Ping';
import { handler as traceroute_handler } from 'ubbf.tr143.TraceRoute';
import { handler as udpecho_handler } from 'ubbf.tr143.UDPEcho';
import { handler as serverselection_handler } from 'ubbf.tr143.ServerSelection';
import { OP_DIR, overlay_path, overlay_read, overlay_write } from 'ubbf.utils.cwmp-op-trigger';
import { CWMP_MODE } from 'ubbf.utils.protocol';

const CONFIG_PATH = '/etc/ubbf/config.json';
const CWMP_EVENT = '8 DIAGNOSTICS COMPLETE';

// CWMP has no operate RPC, so DM operations are invoked by writing a
// trigger state parameter; ubbf-device (persistent) hosts the run that
// the short-lived cwmp-session cannot. Each entry maps a TR-181 object
// path to its handler, the state parameter the handler's Status maps
// onto, and whether completion is signalled to the ACS by the
// "8 DIAGNOSTICS COMPLETE" event (diagnostics) or observed by the ACS
// polling the state parameter (everything else).
const op_table = {
	'Device.IP.Diagnostics.IPPing':
		{ handler: ping_handler, state_key: 'DiagnosticsState', event: true },
	'Device.IP.Diagnostics.TraceRoute':
		{ handler: traceroute_handler, state_key: 'DiagnosticsState', event: true },
	'Device.IP.Diagnostics.UDPEchoDiagnostics':
		{ handler: udpecho_handler, state_key: 'DiagnosticsState', event: true },
	'Device.IP.Diagnostics.ServerSelectionDiagnostics':
		{ handler: serverselection_handler, state_key: 'DiagnosticsState', event: true }
};

let running = {};

/**
 * Queues the TR-069 diagnostics-complete event with cwmpd; the flagged
 * event schedules a session and rides the next Inform to the ACS.
 */
function cwmp_event_flag() {
	let rv = ubus.call({
		object: 'cwmp',
		method: 'event_add',
		data: { event: CWMP_EVENT }
	});
	if (rv == null && ubus.error())
		log_err('cwmp-ops: cwmp event_add failed: %s', ubus.error());
}

/**
 * Completion callback shared by every operation: maps the handler
 * output onto TR-181 result parameters (its Status onto the entry's
 * state parameter), persists the overlay, and for event-signalled
 * operations flags the ACS event.
 *
 * @param {string} path - TR-181 object path of the operation
 * @param {object} entry - op_table entry (state_key, event)
 * @param {number} err - USP error code, 0 on success
 * @param {string|null} msg - Error message when err != 0
 * @param {object} output - Handler output keyed by result names
 */
function op_complete(path, entry, err, msg, output) {
	delete running[path];

	let result = {};
	for (let k, v in (output ?? {}))
		result[k == 'Status' ? entry.state_key : k] = v;

	if (err != 0) {
		result[entry.state_key] ??= 'Error_Internal';
		log_err('cwmp-ops: %s failed: %d %s', path, err, msg ?? '');
	} else {
		log_info('cwmp-ops: %s complete: %s', path,
			result[entry.state_key] ?? 'Complete');
	}

	overlay_write(path, result);
	if (entry.event)
		cwmp_event_flag();
}

/**
 * ubus handler for bbf-device op_request. Invoked by a DM trigger set
 * hook (cwmp-session is too short-lived to host the run itself); input
 * carries the staged SetParameterValues parameters minus the trigger.
 *
 * @param {object} req - ubus request with args.path and args.input
 * @returns {object} Status object or error
 */
function op_request_handler(req) {
	if (!CWMP_MODE)
		return { error: 'cwmp-ops runner only serves CWMP mode' };

	let path = req.args?.path ?? '';
	let input = req.args?.input ?? {};

	let entry = op_table[path];
	if (!entry)
		return { error: sprintf('unknown operation: %s', path) };
	if (running[path])
		return { error: 'already running' };

	let root = {};
	try {
		root = json(fs.readfile(CONFIG_PATH) ?? '{}') ?? {};
	} catch (e) {
		log_err('cwmp-ops: config parse failed: %s', e);
	}

	running[path] = true;
	// Publish Running before the handler forks so the ACS's first poll
	// of the state parameter observes progress rather than the stale
	// Requested/None it wrote or last saw.
	let pending = {};
	pending[entry.state_key] = 'Running';
	overlay_write(path, pending);
	log_info('cwmp-ops: %s requested', path);

	try {
		entry.handler(input, 0,
			(inst, err, msg, output) => op_complete(path, entry, err, msg, output),
			'', root);
	} catch (e) {
		op_complete(path, entry, USP_ERR_COMMAND_FAILURE, sprintf('%s', e), {});
	}

	return { status: 'started' };
}

/**
 * Prepares the overlay directory and masks any trigger state persisted
 * before a reboot (the stored config may still say 'Requested', but an
 * operation does not survive a reboot).
 */
export function init() {
	if (!CWMP_MODE)
		return;

	if (!fs.stat(OP_DIR))
		fs.mkdir(OP_DIR, 0o755);

	for (let path, entry in op_table) {
		if (fs.stat(overlay_path(path))) {
			// a Running op cannot have survived the daemon restart;
			// completed results stay readable for the ACS
			let existing = overlay_read(path);
			if (existing[entry.state_key] == 'Running') {
				existing[entry.state_key] = 'Error_Internal';
				overlay_write(path, existing);
			}
			continue;
		}
		let none = {};
		none[entry.state_key] = 'None';
		overlay_write(path, none);
	}
};

/**
 * Returns the ubus method table for the operation runner.
 *
 * @returns {object} Method definitions for op_request
 */
export function ubus_methods() {
	return {
		op_request: {
			call: op_request_handler,
			args: {
				path: '',
				input: {}
			}
		}
	};
};
