'use strict';

import * as ubus from 'ubus';
import {
	dm, trans_start, trans_commit, trans_abort,
	apply_config, get_webui_data,
	start_operation, list_operations, operation_defer,
	operations_apply, paths_expand, names_list, param_schema
} from 'ubbf.datamodel';
import { ACTIVE_PROTOCOL } from 'ubbf.utils.protocol';
import { acl_load, acl_can_write, acl_can_add } from 'ubbf.acl';
// Imported statically because a require() plus member access does not survive
// the minifier. Its top level does no I/O, so loading it under USP is inert.
import { methods as cwmp_methods, init as cwmp_init } from 'ubbf.cwmp-dm';
import { log_exception } from 'ubbf.utils.logging';
import { config_path_check } from 'ubbf.utils.validate';

const ACL_PATH = '/etc/ubbf/webui-acl.json';
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
	busy: 'APPLY_FAILED',
	not_found: 'INVALID_OPERATION',
	unknown_op: 'UNKNOWN_OPERATION',
	apply_failed: 'APPLY_FAILED'
};

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

		for (let p in req.args.paths) {
			if (substr(p, -1) == '.') {
				tree_flatten(dm.get_subtree_with_state(p), p, paths);
			} else {
				paths[p] = null;
				have_leaf = true;
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

	let params = [];
	for (let path, value in expanded.leaves) {
		push(params, {
			path,
			value: (value == null) ? '' : sprintf('%s', value),
			type: param_schema(path)?.type ?? 'DM_STRING'
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
 * Handles ubus 'set' requests to set a single parameter value.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Result object with success status or error
 */
function set_handler(req) {
	if (!req.args?.path || req.args?.value == null)
		return { error: 'path and value required' };

	let outcome = operations_apply([
		{ op: 'set', path: req.args.path, value: req.args.value }
	]);
	if (!outcome.success)
		return { error: outcome.results[0].reason };

	return { success: true };
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

	let outcome = operations_apply([{ op: 'add', path: req.args.path }]);
	if (!outcome.success)
		return { error: outcome.results[0].reason };

	return { instance: outcome.results[0].instance };
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

	let outcome = operations_apply([{ op: 'del', path: req.args.path }]);
	if (!outcome.success)
		return { error: outcome.results[0].reason };

	return { success: true };
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

	return apply_config(file_path);
}

/**
 * Handles ubus 'webui-show' requests to retrieve ACL-filtered data.
 *
 * @param {object} req - The ubus request object
 * @returns {object} Data with digest, or error
 */
function webui_show_handler(req) {
	let path = req.args?.path ?? 'Device';

	let data = get_webui_data(path);
	if (data == null)
		return { error: 'ACL_NOT_FOUND' };

	return {
		digest: dm.get_digest(),
		data
	};
}

/**
 * Handles ubus 'webui-transaction' requests for batched ACL-checked operations.
 *
 * @param {object} req - The ubus request object with digest and operations array
 * @returns {object} Result object with success status, new digest, and results
 */
function webui_transaction_handler(req) {
	let client_digest = req.args?.digest;
	let operations = req.args?.operations;

	if (!client_digest)
		return { success: false, error: 'DIGEST_REQUIRED' };

	if (!operations || type(operations) != 'array')
		return { success: false, error: 'OPERATIONS_REQUIRED' };

	if (client_digest != dm.get_digest())
		return { success: false, error: 'CONFIG_CHANGED', digest: dm.get_digest() };

	let acl = acl_load(ACL_PATH);
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

	let outcome = operations_apply(operations);
	if (!outcome.success) {
		// Every operation carries its own outcome, because a caller
		// reporting to a protocol that names each failure needs them all.
		let first = filter(outcome.results, (r) => !r.success)[0];
		return {
			error: first?.reason ?? 'apply failed',
			op: first ? { op: first.op, path: first.path } : null,
			results: outcome.results
		};
	}

	return { success: true, digest: outcome.digest, results: outcome.results };
}

let bbf_dm_methods = {
	show: { call: show_handler, args: { path: '' } },
	get: { call: get_handler, args: { paths: [], typed: true } },
	names: { call: names_handler, args: { path: '', next_level: true } },
	set: { call: set_handler, args: { path: '', value: '' } },
	add: { call: add_handler, args: { path: '' } },
	del: { call: del_handler, args: { path: '' } },
	apply: { call: apply_handler, args: { file: '' } },
	operate: { call: operate_handler, args: { path: '', input: {} } },
	event: { call: event_handler, args: { path: '', args: {} } },
	batch: { call: batch_handler, args: { operations: [] } },
	'webui-show': { call: webui_show_handler, args: { path: '' } },
	'webui-transaction': { call: webui_transaction_handler, args: { digest: '', operations: [] } }
};

// The CWMP methods exist only where CWMP does. In USP mode obuspa owns the
// protocol state and these would be a second, idle claim on it.
if (ACTIVE_PROTOCOL == 'cwmp')
	for (let name, method in cwmp_methods)
		bbf_dm_methods[name] = method;

let bbf_dm = conn.publish('bbf-dm', bbf_dm_methods);

if (ACTIVE_PROTOCOL == 'cwmp')
	cwmp_init(bbf_dm);
