'use strict';

// Native data model modules: C handlers in shared objects, each run by
// dm-host in a process of its own, so a fault in one ends that process and
// not the data model. obuspa talks to each over a ubus channel.
// Plan: docs/plans/UBBF-NATIVE-DM-MODULES.md (local workspace).

import * as ubus from 'ubus';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { glob } from 'fs';
import { log_info, log_warn, log_err } from 'ubbf';

const DM_HOST = '/usr/libexec/ubbf/dm-host';
const MODULES_GLOB = '/usr/lib/ubbf/dm/*.so';
const DM_API = 2;

// A get blocks the data model until the module answers; a module that
// takes longer is treated as hung.
const REQUEST_TIMEOUT_S = 2;

// An async operation that the module accepted and did not complete in this
// time fails, unless the module gave the operation a timeout of its own.
const ASYNC_TIMEOUT_S = 60;

// The respawn rule and defaults of procd (instance_exit() in
// procd/service/instance.c): an exit before RESPAWN_THRESHOLD_S counts as a
// crash, a longer run resets the count, and after more than RESPAWN_RETRY
// counted crashes the module stays down.
const RESPAWN_THRESHOLD_S = 3600;
const RESPAWN_TIMEOUT_MS = 5000;
const RESPAWN_RETRY = 5;

let modules = [];
let hooks = {};

/**
 * Returns the monotonic time in seconds.
 *
 * @returns {number} Seconds
 */
function now() {
	return clock(true)[0];
}

/**
 * Forwards a message that a module sends on its own.
 *
 * @param {object} m - Module state
 * @param {object} req - Channel request: type and args
 * @returns {object} Empty reply
 */
function child_request(m, req) {
	let args = req.args ?? {};

	switch (req.type) {
	case 'event':
		hooks.event?.(args.path, args.args ?? {});
		break;

	case 'log':
		log_info('module %s: %s', m.name ?? m.path, args.msg);
		break;

	case 'complete':
		let p = m.pending[`${args.id}`];
		delete m.pending[`${args.id}`];
		p?.timer.cancel();
		p?.done(args.err ?? 0, args.msg, args.output ?? {});
		break;
	}

	return {};
}

let module_start;

/**
 * Ends a module process after a crash, a hang or a lost channel, and starts
 * it again by the procd rule.
 *
 * @param {object} m - Module state
 * @param {string} reason - For the log
 */
function module_down(m, reason) {
	if (!m.pid)
		return;

	let chan = m.chan, pid = m.pid;
	m.chan = null;
	m.pid = null;

	// This runs inside a callback of the channel or inside a request on it;
	// freeing the channel there leaves libubus with a dangling context.
	uloop.timer(0, () => {
		chan?.disconnect();
		ubbf.module_kill(pid);
	});

	for (let id, p in m.pending) {
		p.timer.cancel();
		p.done(USP_ERR_COMMAND_FAILURE, 'module process ended', {});
	}
	m.pending = {};

	if (now() - m.started < RESPAWN_THRESHOLD_S)
		m.crashes++;
	else
		m.crashes = 0;

	if (m.crashes > RESPAWN_RETRY) {
		log_err('module %s: %s; in a crash loop after %d crashes, not restarted', m.path, reason, m.crashes);
		return;
	}

	let delay = hooks.respawn_ms ?? RESPAWN_TIMEOUT_MS;
	log_warn('module %s: %s; restart in %d ms', m.path, reason, delay);
	m.timer = uloop.timer(delay, () => module_start(m));
}

/**
 * Starts the dm-host process of a module and opens its channel.
 *
 * @param {object} m - Module state
 * @returns {boolean} True when the process runs
 */
module_start = function(m) {
	m.timer = null;
	m.started = now();

	let child = ubbf.module_spawn(hooks.host ?? DM_HOST, m.path);
	if (!child) {
		log_err('module %s: dm-host did not start', m.path);
		return false;
	}

	let pid = child.pid;

	m.pid = pid;
	m.chan = ubus.open_channel(child.fd, (req) => child_request(m, req), () => {
		// A channel ended by module_down() can report its close after the
		// next process started; that one must stay.
		if (m.pid == pid)
			module_down(m, 'channel closed');
	}, REQUEST_TIMEOUT_S);

	if (!m.chan) {
		module_down(m, 'no channel');
		return false;
	}

	return true;
};

/**
 * Sends a request to a module and waits for the reply. A module that does
 * not answer in time is ended.
 *
 * @param {object} m - Module state
 * @param {string} method - describe, get, operate, commit or abort
 * @param {object} data - Request data
 * @returns {object|null} Reply, or null when the module had none
 */
function request(m, method, data) {
	if (!m.chan)
		return null;

	let rv = m.chan.request({ method, data });
	if (rv == null && m.chan?.error(true) == ubus.STATUS_TIMEOUT)
		module_down(m, sprintf('no reply to %s in %d s', method, REQUEST_TIMEOUT_S));

	return rv;
}

/**
 * Collects the configuration subtrees a module named in `needs`.
 *
 * @param {object} m - Module state
 * @param {object|null} root - Configuration or runtime tree
 * @returns {object} Path to subtree
 */
function needs_collect(m, root) {
	let out = {};

	for (let path in m.needs) {
		let value = root ? ubbf.get(root, path) : null;
		if (value != null)
			out[path] = value;
	}

	return out;
}

/**
 * Builds the get handler of an object, which forwards to the module.
 *
 * @param {object} m - Module state
 * @param {string} pattern - Object pattern
 * @returns {function} Get handler
 */
function get_forward(m, pattern) {
	return (ctx) => {
		let data = {
			pattern,
			path: ctx.path ?? pattern,
			instance: ctx.instance ?? 0,
			needs: needs_collect(m, ctx.root)
		};

		if (ctx.config != null)
			data.config = ctx.config;
		if (ctx.parent != null)
			data.parent = ctx.parent;

		return request(m, 'get', data);
	};
}

/**
 * Builds the handler of a sync operation. It returns the output, a negative
 * USP_ERR_* code, or null.
 *
 * @param {object} m - Module state
 * @param {string} path - Operation pattern
 * @returns {function} Operation handler
 */
function sync_op_forward(m, path) {
	let with_instances = index(path, '{i}') >= 0;

	return (input, command_key, instances) => {
		let rv = request(m, 'operate', {
			path,
			input: input ?? {},
			command_key: command_key ?? '',
			instances: with_instances ? (instances ?? []) : []
		});

		if (rv == null)
			return null;

		return rv.err ? -rv.err : (rv.output ?? {});
	};
}

/**
 * Builds the handler of an async operation. The module answers at once with
 * an id and reports the outcome later with a `complete` message.
 *
 * @param {object} m - Module state
 * @param {string} path - Operation pattern
 * @returns {function} Operation handler
 */
function async_op_forward(m, path, timeout_s) {
	let with_instances = index(path, '{i}') >= 0;
	let deadline_s = timeout_s || ASYNC_TIMEOUT_S;

	return (input, instance, cb, a4, a5) => {
		let rv = request(m, 'operate', {
			path,
			input: input ?? {},
			command_key: (with_instances ? a5 : a4) ?? '',
			instances: with_instances ? (a4 ?? []) : []
		});

		if (rv?.id != null) {
			let id = `${rv.id}`;
			let p = { done: (err, msg, output) => cb(instance, err, msg, output) };

			p.timer = uloop.timer(deadline_s * 1000, () => {
				if (m.pending[id] !== p)
					return;
				delete m.pending[id];
				p.done(USP_ERR_COMMAND_FAILURE, sprintf('module did not complete in %d s', deadline_s), {});
			});
			m.pending[id] = p;
			return;
		}

		if (rv == null) {
			cb(instance, USP_ERR_COMMAND_FAILURE, 'module did not answer', {});
			return;
		}

		cb(instance, rv.err ?? 0, rv.msg, rv.output ?? {});
	};
}

/**
 * Resolves a schema key of a module: through the `schema(name, key)` hook of
 * the caller, which knows the schema tables and the schema.uc files, else
 * the table name when schema-<name>.so is open.
 *
 * @param {string} name - Module name
 * @param {string} key - Schema key
 * @returns {string|object|null} Table name or schema object, or null
 */
function schema_resolve(name, key) {
	if (hooks.schema)
		return hooks.schema(name, key);

	return (index(ubbf.schema_tables(), name) >= 0) ? `${name}.${key}` : null;
}

/**
 * Checks the description of a module and turns it into model entries and
 * operations.
 *
 * @param {object} m - Module state
 * @param {object} d - Reply to `describe`
 * @param {object} model - Model to add to
 * @param {object} operations - Operations to add to
 * @returns {boolean} False when the module cannot be used
 */
function module_register(m, d, model, operations) {
	if (d?.api != DM_API || !d?.name) {
		log_err('module %s: no description of API %d', m.path, DM_API);
		return false;
	}

	let entries = {};
	for (let obj in d.objects ?? []) {
		let entry = {};

		if (obj.schema) {
			entry.schema = schema_resolve(d.name, obj.schema);
			if (entry.schema == null) {
				log_err('module %s: no schema %s', m.path, obj.schema);
				return false;
			}
		}

		entries[obj.pattern] = { entry, obj };
	}

	m.name = d.name;
	m.needs = d.needs ?? [];

	for (let pattern, e in entries) {
		let entry = e.entry, obj = e.obj;

		if (obj.get)
			entry.get = get_forward(m, obj.pattern);
		if (obj.since)
			entry.since = obj.since;
		if (obj.until)
			entry.until = obj.until;
		if (!obj.addable)
			entry.addable = false;
		if (obj.max_instances != null)
			entry.maxInstances = obj.max_instances;

		model[pattern] = entry;
	}

	for (let op in d.operations ?? []) {
		operations[op.path] = op.async
			? { type: 'async', handler: async_op_forward(m, op.path, op.timeout) }
			: { type: 'sync', handler: sync_op_forward(m, op.path) };
	}

	return true;
}

/**
 * Starts each native module, asks it for its objects and operations, and adds
 * them to the model. A module that does not start or describe itself is
 * logged and left out.
 *
 * @param {object} model - Model to add to
 * @param {object} operations - Operations to add to
 * @param {object} [opts] - `event(path, args)`, `schema(name, key)`; for host
 *                          tests also `glob`, `host` and `respawn_ms`
 * @returns {array} Names of the registered modules
 */
export function native_modules_register(model, operations, opts) {
	hooks = opts ?? {};
	let names = [];

	for (let path in sort(glob(hooks.glob ?? MODULES_GLOB) ?? [])) {
		let m = { path, pid: null, chan: null, crashes: 0, pending: {}, needs: [] };

		if (!module_start(m))
			continue;

		if (!module_register(m, request(m, 'describe', { api: DM_API }), model, operations)) {
			let chan = m.chan;
			m.chan = null;
			chan?.disconnect();
			ubbf.module_kill(m.pid);
			continue;
		}

		push(modules, m);
		push(names, m.name);
		log_info('native module %s registered from %s', m.name, path);
	}

	return names;
};

/**
 * Tells each running native module that the configuration was persisted or
 * that a transaction was abandoned.
 *
 * @param {string} method - commit or abort
 * @param {object|null} root - Configuration tree
 */
export function native_modules_notify(method, root) {
	for (let m in modules)
		request(m, method, { config: needs_collect(m, root) });
};
