'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import { CWMP_MODE } from 'ubbf.utils.protocol';
import * as ubbf from 'ubbf';

// Shared DM-side glue for invoking data-model operations over CWMP.
// CWMP has no operate RPC, so an operation Foo() is exposed as a
// companion object with its inputs plus a writable trigger parameter;
// writing the trigger to 'Requested' forwards the staged parameters to
// the persistent ubbf-device runner (device/cwmp-ops.uc), which hosts
// the run the short-lived cwmp-session cannot. Results come back as a
// per-object overlay the get handler merges over stored config. The
// runner and these hooks share OP_DIR and the overlay path formula
// through this module so there is a single source of truth.

export const OP_DIR = '/tmp/ubbf/op';

// Diagnostic runs waiting for the transaction that asked for them to
// commit. datamodel.uc registers the flush and drop below.
let staged = [];

/**
 * Overlay file path for an operation object.
 *
 * @param {string} path - TR-181 object path
 * @returns {string} Overlay file path under OP_DIR
 */
export function overlay_path(path) {
	return sprintf('%s/%s.json', OP_DIR, replace(path, '.', '_', true));
};

/**
 * Reads an operation's result overlay. Empty when absent or invalid.
 *
 * @param {string} path - TR-181 object path
 * @returns {object} Overlay parameters
 */
export function overlay_read(path) {
	let data = fs.readfile(overlay_path(path));
	if (!data)
		return {};
	try {
		return json(data) ?? {};
	} catch (e) {
		return {};
	}
};

/**
 * Writes an operation's result overlay.
 *
 * @param {string} path - TR-181 object path
 * @param {object} data - Result parameters keyed by TR-181 names
 * @returns {boolean} True on success
 */
export function overlay_write(path, data) {
	return fs.writefile(overlay_path(path), sprintf('%.J\n', data)) != null;
};

/**
 * Builds a get handler returning stored config merged with the
 * operation's result overlay. Under USP there is no overlay (the runner
 * is inert) so the stored config passes through unchanged.
 *
 * @param {string} path - TR-181 object path
 * @returns {function} Get handler for the model entry
 */
export function op_overlay_get(path) {
	return (ctx) => {
		if (!CWMP_MODE)
			return ubbf.ctx_config(ctx);
		return { ...ubbf.ctx_config(ctx), ...overlay_read(path) };
	};
};

/**
 * Builds a set hook forwarding a `<trigger>='Requested'` write to the
 * ubbf-device operation runner. TR-069 triggers on the write itself
 * (even when the stored value is already 'Requested'), so the trigger
 * cannot be derived from a config change. The staged sibling
 * parameters of the same SetParameterValues ride along in ctx.config
 * because commit has not persisted them yet when the hook fires.
 *
 * @param {string} path - TR-181 object path
 * @param {string} trigger - Trigger parameter name (e.g. DiagnosticsState)
 * @returns {function} Set handler for the model entry
 */
export function op_trigger_set(path, trigger) {
	return (ctx) => {
		if (!CWMP_MODE || ctx.param != trigger || ctx.value != 'Requested')
			return;

		let input = { ...(ctx.config ?? {}) };
		delete input[trigger];

		push(staged, { path, input });
	};
};

/**
 * Dispatches the staged diagnostic runs once the transaction has committed
 * and the renderer has applied it.
 *
 * The request is fire-and-forget, so it cannot be recalled: starting it
 * from inside params_set meant an aborted SetParameterValues still ran the
 * diagnostic, against inputs that were then rolled back, and before the
 * apply that configures the interface it runs over.
 */
export function op_trigger_flush() {
	let pending = staged;
	staged = [];

	for (let req in pending) {
		ubus.call({
			object: 'bbf-device',
			method: 'op_request',
			data: { path: req.path, input: req.input },
			return: 'ignore'
		});
	}
};

/**
 * Discards diagnostics staged by an abandoned transaction.
 */
export function op_trigger_drop() {
	staged = [];
};
