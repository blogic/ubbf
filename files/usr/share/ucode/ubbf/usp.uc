#!/usr/bin/env ucode
'use strict';

import {
	dm, schema, trans_start, trans_commit, trans_abort,
	run_sync_op, run_async_op, param_schema, object_writable, value_reject
} from 'ubbf.datamodel';
import { log_init, log_info } from 'ubbf.utils.logging';
import 'ubbf.ubus-object';

log_init('ubbf-usp');

log_info('registering callbacks');

/**
 * Callback table registered with the USP runtime.
 *
 * Each entry is a callback the USP core invokes when the agent receives a
 * matching protocol message. Handlers either return a value or 0 on success
 * and a negated `USP_ERR_*` constant on failure.
 */
usp_set_cb({
	/**
	 * Returns the registered TR-181 schema for the USP core.
	 *
	 * @returns {object} The compiled schema object
	 */
	get_schema: function() {
		return schema;
	},

	/**
	 * Reports whether the device is at factory defaults.
	 *
	 * @returns {number} Always 0 (not at factory defaults)
	 */
	get_factory_defaults: function() {
		return 0;
	},

	/**
	 * Refreshes runtime instances for a given path.
	 *
	 * @param {string} path - Data model path to refresh
	 * @returns {array} Array of refreshed instance paths
	 */
	refresh_instances: function(path) {
		return dm.refresh_instances(path);
	},

	/**
	 * Resolves parameter values for the supplied path map.
	 *
	 * The `paths` object is mutated in place: each key is set to the
	 * resolved value.
	 *
	 * @param {object} paths - Map keyed by parameter path with null values
	 * @returns {number} Always 0; failures are not propagated
	 */
	params_get: function(paths) {
		dm.params_get(paths);

		// TR-369 8.9.2.2: without a SecuredRoles assignment a secured
		// parameter is hidden, and the agent answers a null value
		// regardless of what it holds. ubbf implements no such role.
		for (let path in paths) {
			if (param_schema(path)?.secured)
				paths[path] = '';
		}

		return 0;
	},

	/**
	 * Applies the supplied parameter values via the data model.
	 *
	 * obuspa negates a negative return into a USP error code, so handler
	 * rejections using the plain -1 convention are mapped to
	 * USP_ERR_INVALID_VALUE; already-encoded -7xxx codes pass through.
	 *
	 * @param {object} params - Map of parameter path to value
	 * @returns {number} 0 on success, negated USP error code on failure
	 */
	params_set: function(params) {
		for (let path, value in params)
			if (value_reject(path, value, param_schema(path)))
				return -USP_ERR_INVALID_VALUE;

		let rc = dm.params_set(params);
		if (rc >= 0)
			return rc;
		if (rc == -2)
			return -USP_ERR_OBJECT_DOES_NOT_EXIST;
		return rc <= -7000 ? rc : -USP_ERR_INVALID_VALUE;
	},

	/**
	 * Adds a new object instance under the given path.
	 *
	 * @param {string} path - Multi-instance object path
	 * @returns {number} New instance number, or a negated USP error code
	 */
	object_add: function(path) {
		if (!object_writable(rtrim(path, '.')))
			return -USP_ERR_OBJECT_NOT_CREATABLE;
		return dm.object_add(path);
	},

	/**
	 * Deletes an object instance at the given path.
	 *
	 * @param {string} path - Instance path to delete
	 * @returns {number} 0 on success, negative on error
	 */
	object_del: function(path) {
		// obuspa expects idempotent delete semantics: a missing
		// instance (dm rc 1) counts as success
		let rc = dm.object_del(path);
		return (rc > 0) ? 0 : rc;
	},

	/**
	 * Runs a synchronous TR-181 operation.
	 *
	 * Copies handler result entries into `output` so the USP core can
	 * read the operation result.
	 *
	 * @param {string} path - Operation path
	 * @param {object} input - Operation input parameters
	 * @param {object} output - Mutable output object populated on success
	 * @param {string} command_key - USP command key for tracking
	 * @returns {number} 0 on success, `-USP_ERR_COMMAND_FAILURE` on error
	 */
	sync_op: function(path, input, output, command_key) {
		log_info('sync_op: %s', path);

		let result = run_sync_op(path, input, command_key);
		if (result == null)
			return -USP_ERR_COMMAND_FAILURE;

		for (let k in result)
			output[k] = result[k];

		return 0;
	},

	/**
	 * Starts an asynchronous TR-181 operation.
	 *
	 * The internal `complete` closure is invoked when the operation
	 * finishes; it forwards the result to `usp_operation_complete()` so
	 * the USP core can deliver an OperationComplete notification to the
	 * controller. The closure return value is ignored by the framework.
	 *
	 * @param {string} path - Operation path
	 * @param {object} input - Operation input parameters
	 * @param {number} instance - Operation instance number
	 * @param {string} command_key - USP command key for tracking
	 * @returns {number} 0 when the operation was successfully started,
	 *                   negative `USP_ERR_*` value on dispatch failure
	 */
	async_op: function(path, input, instance, command_key) {
		log_info('async_op: %s (instance=%d, command_key=%s)', path, instance, command_key);

		let complete = (inst, err, msg, output) => {
			log_info('operation_complete: inst=%d err=%d msg=%s output_keys=%s',
				 inst, err, msg, keys(output));
			let rc = usp_operation_complete(inst, err, msg, output);
			log_info('operation_complete: usp_operation_complete returned %s', rc);
		};

		let rc = run_async_op(path, input, instance, complete, command_key);
		if (rc != 0)
			log_info('async_op: %s failed with %d', path, rc);
		return rc;
	},

	/**
	 * Begins a USP-initiated transaction.
	 *
	 * @returns {number} Result of `trans_start()`; 0 on success, negative on error
	 */
	trans_start: function() {
		return trans_start();
	},

	/**
	 * Commits the current USP-initiated transaction.
	 *
	 * @returns {number} 0 on success, negated USP error code when the
	 *                   commit or the apply that follows it failed
	 */
	trans_commit: function() {
		return (trans_commit() < 0) ? -USP_ERR_INTERNAL_ERROR : 0;
	},

	/**
	 * Aborts the current USP-initiated transaction.
	 *
	 * @returns {number} Result of `trans_abort()`; 0 on success, negative on error
	 */
	trans_abort: function() {
		return trans_abort();
	}
});

log_info('data model ready');
