'use strict';

import * as ubus from 'ubus';
import {
	dm, trans_start, trans_commit, trans_abort,
	apply_config, get_webui_data, webui_acl_get,
	start_operation, list_operations, operation_defer,
	operations_apply, config_write, paths_expand, names_list,
	param_schema
} from 'ubbf.datamodel';
import { acl_can_write, acl_can_add, acl_can_diagnose } from 'ubbf';
// Its top level does no I/O, so loading it under USP is inert.
import { methods as cwmp_methods, init as cwmp_init } from 'ubbf.cwmp-dm';
import { log_exception, cwmp_mode, config_path_check, config_restore } from 'ubbf';
import { write_reply } from 'ubbf.utils.write-gate';

const CONFIG_PATH = '/etc/ubbf/config.json';

// The shared apply loop reports protocol-neutral reasons; the web UI keeps the
// vocabulary its client already knows.
const WEBUI_ERROR = {
	value_required: 'VALUE_REQUIRED',
	unknown: 'INVALID_OPERATION',
	invalid_path: 'INVALID_OPERATION',
	readonly: 'ACL_DENIED',
	rejected: 'INVALID_OPERATION',
	invalid_value: 'INVALID_VALUE',
	max_instances: 'ADD_FAILED',
	not_found: 'INVALID_OPERATION',
	unknown_op: 'UNKNOWN_OPERATION',
	apply_failed: 'APPLY_FAILED'
};

// The only operations the web UI may run, keyed by the name it sends. The
// CWMP path is the object whose DiagnosticsState an ACS sets to Requested.
const WEBUI_DIAGNOSTICS = {
	IPPing: {
		usp: 'Device.IP.Diagnostics.IPPing()',
		cwmp: 'Device.IP.Diagnostics.IPPing'
	},
	TraceRoute: {
		usp: 'Device.IP.Diagnostics.TraceRoute()',
		cwmp: 'Device.IP.Diagnostics.TraceRoute'
	},
	NSLookup: {
		usp: 'Device.DNS.Diagnostics.NSLookupDiagnostics()',
		cwmp: 'Device.DNS.Diagnostics.NSLookupDiagnostics'
	}
};

const WEBUI_DIAGNOSTICS_EVENT = 'Device.LocalAgent.X_UBBF_DiagnosticsComplete!';
const WEBUI_DIAGNOSTICS_UBUS_EVENT = 'ubbf.diagnostics';

let webui_diagnostics_running = {};

let conn = ubus.connect();

ubus.guard(function(e) {
	log_exception('ubus', e);
});

/**
 * Handles ubus 'show' requests to retrieve a data model subtree with state.
 *
 * @param {object} req - The ubus request object
 * @returns {object} The data model subtree
 */
function show_handler(req) {
	let path = req.args?.path ?? '';
	return dm.get_subtree_with_state(path);
}

/**
 * Recursively flattens a nested object into dotted-path keys.
 *
 * Walks `obj` and writes leaf (non-object) values into `result` using keys of
 * the form `prefix + key1.key2…`. Used to expand a partial trailing-dot path
 * request into individual leaf entries for `get_handler`.
 *
 * @param {object} obj - The nested object to flatten
 * @param {string} prefix - Path prefix prepended to every emitted key
 * @param {object} result - Destination object that receives flattened entries
 */
function tree_flatten(obj, prefix, result) {
	for (let key, val in obj) {
		let full = prefix + key;
		if (type(val) == 'object')
			tree_flatten(val, full + '.', result);
		else
			result[full] = val;
	}
}

/**
 * Handles ubus 'get' requests to retrieve parameter values.
 * Supports both leaf paths and partial (trailing-dot) paths.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Object with paths as keys and values
 */
function get_handler(req) {
	if (!req.args?.paths)
		return {};

	if (!req.args?.typed) {
		let paths = {};
		let have_leaf = false;

		for (let wild in req.args.paths) {
			for (let p in dm.wildcard_expand(wild)) {
				if (substr(p, -1) == '.') {
					tree_flatten(dm.get_subtree_with_state(p), p, paths);
				} else {
					paths[p] = null;
					have_leaf = true;
				}
			}
		}

		if (have_leaf)
			dm.params_get(paths);

		return paths;
	}

	// The typed form reports the schema type per leaf and distinguishes a path
	// that resolves to nothing from one that is simply empty, which the plain
	// shape cannot express. Additive: the default reply is unchanged.
	let expanded = paths_expand(req.args.paths);
	if (length(expanded.unknown))
		return { error: 'unknown path', paths: expanded.unknown };

	// mask_secured reads a secured value as an empty string, as a USP Get
	// without a secured role does (params_get() in usp.uc): a caller that
	// exports the values, such as the bulk data daemon, must not leak them.
	let mask = !!req.args?.mask_secured;
	let params = [];
	for (let path, value in expanded.leaves) {
		let info = param_schema(path);
		push(params, {
			path,
			value: (value == null || (mask && info?.secured)) ? '' : sprintf('%s', value),
			type: info?.type ?? 'DM_STRING'
		});
	}

	return { params };
}

/**
 * Handles ubus 'names' requests, listing the objects and parameters below a
 * path with their writability, which is what a management protocol needs to
 * enumerate a subtree it has not seen.
 *
 * @param {object} req - The ubus request object with path and next_level
 * @returns {object} `{ params: [{ path, writable }] }`, or an error
 */
function names_handler(req) {
	let path = req.args?.path ?? 'Device.';
	if (substr(path, -1) != '.')
		return { error: 'path must name an object' };

	let params = names_list(path, !!req.args?.next_level);
	if (params == null)
		return { error: 'unknown path' };

	return { params };
}

/**
 * Turns the outcome of a single set or del into its reply.
 *
 * @param {object} outcome - Result of `operations_apply()`
 * @returns {object} `{ success: true }` or `{ error }`
 */
function single_op_reply(outcome) {
	if (!outcome.success)
		return { error: outcome.results?.[0]?.reason ?? outcome.error };

	return { success: true };
}

/**
 * Handles ubus 'set' requests to set a single parameter value.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with success status or error
 */
function set_handler(req) {
	if (!req.args?.path || req.args?.value == null)
		return { error: 'path and value required' };

	let ops = [ { op: 'set', path: req.args.path, value: req.args.value } ];
	return write_reply(req, (done) => operations_apply(ops, done), single_op_reply);
}

/**
 * Handles ubus 'add' requests to add a new object instance.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with new instance number or error
 */
function add_handler(req) {
	if (!req.args?.path)
		return { error: 'path required' };

	let ops = [ { op: 'add', path: req.args.path } ];
	return write_reply(req, (done) => operations_apply(ops, done), (outcome) => {
		if (!outcome.success)
			return { error: outcome.results?.[0]?.reason ?? outcome.error };

		return { instance: outcome.results[0].instance };
	});
}

/**
 * Handles ubus 'del' requests to delete an object instance.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with success status or error
 */
function del_handler(req) {
	if (!req.args?.path)
		return { error: 'path required' };

	let ops = [ { op: 'del', path: req.args.path } ];
	return write_reply(req, (done) => operations_apply(ops, done), single_op_reply);
}

/**
 * Handles ubus 'apply' requests to apply configuration from a file.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with success status or error
 */
function apply_handler(req) {
	let file_path = req.args?.file ?? CONFIG_PATH;

	let reason = config_path_check(file_path);
	if (reason)
		return { success: false, error: reason };

	return write_reply(req, (done) => apply_config(file_path, done), (result) => result);
}

/**
 * Handles ubus 'restore' requests: replaces the live config with a file
 * through the data model, and applies the previous config again when the
 * new one fails. The USP VendorConfigFile Restore() does the same.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with success status or error
 */
function restore_handler(req) {
	let file_path = req.args?.file;

	let reason = config_path_check(file_path);
	if (reason)
		return { success: false, error: reason };

	return write_reply(req, (done) => config_restore(file_path, done), (result) => result);
}

/**
 * Handles ubus 'webui-show' requests to retrieve data filtered by the ACL of
 * the session role.
 *
 * @param {object} req - The ubus request object with path and role
 * @returns {object} Data with digest, or error
 */
function webui_show_handler(req) {
	let path = req.args?.path ?? 'Device';

	let data = get_webui_data(path, req.args?.role);
	if (data == null)
		return { error: 'ACL_NOT_FOUND' };

	return {
		digest: dm.get_digest(),
		data
	};
}

/**
 * Checks and applies a web UI transaction against the config as it is when
 * the transaction runs.
 *
 * @param {string} client_digest - Digest of the config the web UI showed
 * @param {array} operations - The operations of the transaction
 * @param {string} role - RoleName of the session
 * @returns {object} The reply
 */
function webui_transaction_run(client_digest, operations, role) {
	if (client_digest != dm.get_digest())
		return { success: false, error: 'CONFIG_CHANGED', digest: dm.get_digest() };

	let acl = webui_acl_get(role);
	if (!acl)
		return { success: false, error: 'ACL_NOT_FOUND' };

	let tree = { Device: dm.get_subtree('Device') };

	for (let op in operations) {
		if (!op.path)
			return { success: false, error: 'INVALID_OPERATION', op };

		if (op.op == 'set' || op.op == 'del') {
			if (!acl_can_write(acl, op.path, tree))
				return { success: false, error: 'ACL_DENIED', path: op.path };
		} else if (op.op == 'add') {
			if (!acl_can_add(acl, op.path))
				return { success: false, error: 'ACL_DENIED', path: op.path };
		}
	}

	let outcome = operations_apply(operations);
	if (!outcome.success) {
		let first = filter(outcome.results, (r) => !r.success)[0];
		return {
			success: false,
			error: WEBUI_ERROR[first?.reason] ?? 'APPLY_FAILED',
			op: first ? { op: first.op, path: first.path } : null,
			digest: outcome.digest
		};
	}

	return {
		success: true,
		digest: outcome.digest,
		results: outcome.results
	};
}

/**
 * Handles ubus 'webui-transaction' requests for batched ACL-checked operations.
 *
 * @param {object} req - The ubus request object with digest, operations array
 *   and role
 * @returns {object} Result object with success status, new digest, and results
 */
function webui_transaction_handler(req) {
	let client_digest = req.args?.digest;
	let operations = req.args?.operations;
	let role = req.args?.role;

	if (!client_digest)
		return { success: false, error: 'DIGEST_REQUIRED' };

	if (!operations || type(operations) != 'array')
		return { success: false, error: 'OPERATIONS_REQUIRED' };

	return write_reply(req,
		(done) => config_write(() => webui_transaction_run(client_digest, operations, role), done),
		(result) => result);
}

/**
 * Reports the end of a web UI diagnostic: to the controllers as the vendor
 * event (USP), and to the web UI as a ubus event carrying the caller's id.
 *
 * @param {string} id - Caller-supplied correlation id
 * @param {string} name - Key into WEBUI_DIAGNOSTICS
 * @param {number} err - Error code, 0 on success
 * @param {string|null} msg - Error message
 * @param {object|null} output - Operation output
 */
function webui_diagnostics_done(id, name, err, msg, output) {
	delete webui_diagnostics_running[name];

	let status = output?.Status ?? (err == 0 ? 'Complete' : 'Error_Internal');

	usp_datamodel_event(WEBUI_DIAGNOSTICS_EVENT, {
		Command: WEBUI_DIAGNOSTICS[name].usp,
		Requestor: 'webui',
		Status: status,
		FaultCode: sprintf('%d', err),
		FaultString: msg ?? ''
	});

	conn.event(WEBUI_DIAGNOSTICS_UBUS_EVENT, {
		id,
		status,
		error: err,
		message: msg ?? '',
		output: output ?? {}
	});
}

/**
 * Starts a diagnostic through the ubbf-device runner, the path an ACS
 * trigger takes, so the result lands in the overlay and the ACS gets
 * 8 DIAGNOSTICS COMPLETE. The runner reports the end with the same ubus
 * event as webui_diagnostics_done().
 *
 * @param {object} req - The ubus request object
 * @param {string} id - Caller-supplied correlation id
 * @param {object} diag - WEBUI_DIAGNOSTICS entry
 * @param {object} input - Operation input
 * @returns {object} The deferred request
 */
function webui_diagnostics_cwmp_start(req, id, diag, input) {
	req.defer();
	conn.defer({
		object: 'bbf-device',
		method: 'op_request',
		data: { path: diag.cwmp, input, id },
		cb: function(status, result) {
			if (status != 0)
				return req.reply({ error: 'START_FAILED', message: ubus.error() ?? '' });
			if (result?.error)
				return req.reply({ error: result.busy ? 'BUSY' : 'START_FAILED', message: result.error });
			req.reply({ id });
		}
	});
	return req;
}

/**
 * Handles ubus 'webui-diagnostics' requests. The caller names a diagnostic
 * from WEBUI_DIAGNOSTICS, never an operation path, so the web UI can only
 * run these. The reply comes at once; the result follows as the ubus event
 * WEBUI_DIAGNOSTICS_UBUS_EVENT with the caller's id, because a run can take
 * longer than the web UI waits for a reply.
 *
 * @param {object} req - The ubus request object with id, name and input
 * @returns {object} `{ id }` once started, or `{ error, message? }`
 */
function webui_diagnostics_handler(req) {
	let id = req.args?.id;
	let name = req.args?.name;
	let input = req.args?.input ?? {};

	if (type(id) != 'string' || id == '')
		return { error: 'ID_REQUIRED' };

	let diag = (type(name) == 'string') ? WEBUI_DIAGNOSTICS[name] : null;
	if (!diag)
		return { error: 'UNKNOWN_DIAGNOSTIC' };

	let acl = webui_acl_get(req.args?.role);
	if (!acl)
		return { error: 'ACL_NOT_FOUND' };
	if (!acl_can_diagnose(acl, name))
		return { error: 'ACL_DENIED' };

	if (type(input) != 'object')
		return { error: 'INVALID_INPUT' };
	for (let key, value in input)
		if (type(value) != 'string')
			return { error: 'INVALID_INPUT', message: key };

	if (cwmp_mode())
		return webui_diagnostics_cwmp_start(req, id, diag, input);

	if (webui_diagnostics_running[name])
		return { error: 'BUSY' };

	webui_diagnostics_running[name] = true;
	let result = start_operation(diag.usp, input, {
		usp_cb: (inst, err, msg, output) => webui_diagnostics_done(id, name, err, msg, output)
	});
	if (result.error) {
		delete webui_diagnostics_running[name];
		return { error: 'START_FAILED', message: result.error };
	}

	return { id };
}

/**
 * Handles ubus 'operate' requests to run data model operations.
 *
 * @param {object} req - The ubus request object with path and input
 * @returns {object} When no path supplied: `{ operations: [...] }`.
 *                   On error: `{ error: <string>, ... }`.
 *                   On sync success: `{ success: true, output }`.
 *                   For async: returns the deferred `req` object; the caller
 *                   must not reply, the deferred reply is delivered later by
 *                   `operation_defer()`/`operation_complete()`.
 */
function operate_handler(req) {
	let path = req.args?.path;
	let input = req.args?.input ?? {};

	if (!path)
		return { operations: list_operations() };

	let result = start_operation(path, input);

	if (result.error)
		return result;
	if (result.sync)
		return { success: true, output: result.output };

	req.defer();
	operation_defer(result.op_id, req);
	return req;
}

/**
 * Handles ubus 'event' requests to trigger USP events.
 *
 * @param {object} req - The ubus request object with path and args
 * @returns {object} Result object with success status or error
 */
function event_handler(req) {
	if (!req.args?.path || !req.args?.args)
		return { error: 'path and args required' };

	let ret = usp_datamodel_event(req.args.path, req.args.args);
	return { result: ret };
}

/**
 * Handles ubus 'batch' requests for batched operations without ACL checks.
 *
 * @param {object} req - The ubus request object with operations array
 * @returns {object} Result object with success status and results
 */
function batch_handler(req) {
	let operations = req.args?.operations;
	if (!operations || type(operations) != 'array')
		return { error: 'operations array required' };

	return write_reply(req, (done) => operations_apply(operations, done), (outcome) => {
		if (!outcome.success) {
			// Every operation carries its own outcome, because a caller
			// reporting to a protocol that names each failure needs them all.
			let first = filter(outcome.results ?? [], (r) => !r.success)[0];
			return {
				error: first?.reason ?? 'apply failed',
				op: first ? { op: first.op, path: first.path } : null,
				results: outcome.results ?? []
			};
		}

		return { success: true, digest: outcome.digest, results: outcome.results };
	});
}

let bbf_dm_methods = {
	show: { call: show_handler, args: { path: '' } },
	get: { call: get_handler, args: { paths: [], typed: true, mask_secured: true } },
	names: { call: names_handler, args: { path: '', next_level: true } },
	set: { call: set_handler, args: { path: '', value: '' } },
	add: { call: add_handler, args: { path: '' } },
	del: { call: del_handler, args: { path: '' } },
	apply: { call: apply_handler, args: { file: '' } },
	restore: { call: restore_handler, args: { file: '' } },
	operate: { call: operate_handler, args: { path: '', input: {} } },
	event: { call: event_handler, args: { path: '', args: {} } },
	batch: { call: batch_handler, args: { operations: [] } },
	'webui-show': { call: webui_show_handler, args: { path: '', role: '' } },
	'webui-transaction': { call: webui_transaction_handler, args: { digest: '', operations: [], role: '' } },
	'webui-diagnostics': { call: webui_diagnostics_handler, args: { id: '', name: '', input: {}, role: '' } }
};

// The CWMP methods exist only where CWMP does. In USP mode obuspa owns the
// protocol state and these would be a second, idle claim on it.
if (cwmp_mode())
	for (let name, method in cwmp_methods)
		bbf_dm_methods[name] = method;

let bbf_dm = conn.publish('bbf-dm', bbf_dm_methods);

if (cwmp_mode())
	cwmp_init(bbf_dm);
