'use strict';

// The CWMP side of the data model, hosted by whichever process publishes
// bbf-dm. It owns everything TR-069 needs that the data model itself does not
// carry: the ParameterKey, notification attributes, the AccessList and the
// value-change baseline. The per-session cwmp-session process owns none of it
// and reaches all of it through the cwmp-* methods below, so one tree serves
// the ACS and every local consumer alike.
//
// Faults are decided here, next to the schema, and travel as `{ fault: <code> }`
// so the session relays them without computing anything.

import { readfile, writefile, rename, unlink } from 'fs';
import * as ubus from 'ubus';
import {
	dm, param_schema, paths_expand, names_list, operations_apply, on_commit
} from 'ubbf.datamodel';
import { log_info, log_err } from 'ubbf.utils.logging';

const STATE_PATH = '/etc/ubbf/cwmp-state.json';

// TR-069 A.2.3.1 carries every value as a typed string. DECIMAL has no xsd
// counterpart the CPE may claim, so it travels as a string.
const XSD_TYPES = {
	DM_STRING: 'xsd:string',
	DM_DATETIME: 'xsd:dateTime',
	DM_BOOL: 'xsd:boolean',
	DM_INT: 'xsd:int',
	DM_UINT: 'xsd:unsignedInt',
	DM_ULONG: 'xsd:unsignedLong',
	DM_LONG: 'xsd:long',
	DM_BASE64: 'xsd:base64Binary',
	DM_HEXBIN: 'xsd:hexBinary',
	DM_DECIMAL: 'xsd:decimal'
};

// A.5.1
const FAULT_INTERNAL = 9002;
const FAULT_INVALID_ARGUMENTS = 9003;
const FAULT_RESOURCES = 9004;
const FAULT_INVALID_PARAM = 9005;
const FAULT_INVALID_VALUE = 9007;
const FAULT_READ_ONLY = 9008;
const FAULT_NOTIFICATION_REQUEST = 9009;

// The reasons operations_apply reports, in TR-069 terms.
const FAULT_FOR_REASON = {
	value_required: FAULT_INVALID_ARGUMENTS,
	unknown: FAULT_INVALID_PARAM,
	invalid_path: FAULT_INVALID_PARAM,
	readonly: FAULT_READ_ONLY,
	rejected: FAULT_INVALID_VALUE,
	invalid_value: FAULT_INVALID_VALUE,
	max_instances: FAULT_RESOURCES,
	busy: FAULT_RESOURCES,
	not_found: FAULT_INVALID_PARAM,
	unknown_op: FAULT_INTERNAL,
	apply_failed: FAULT_INTERNAL
};

// A.3.2.4: 3 to 6 are the lightweight notification levels, an optional feature
// this CPE does not implement.
const NOTIFY_MAX = 2;

// A.3.2.4 Forced Active Notification: the CPE reports these whatever the ACS
// asks for, and refuses to have them changed.
const FORCED_ACTIVE = [
	'Device.DeviceInfo.SoftwareVersion',
	'Device.DeviceInfo.ProvisioningCode',
	'Device.ManagementServer.ConnectionRequestURL'
];

let generation = 0;

function state_load() {
	let state;
	let raw = readfile(STATE_PATH);
	if (raw) {
		try {
			state = json(raw);
		} catch (e) {
			log_err('corrupt %s: %s', STATE_PATH, e);
		}
	}
	if (type(state) != 'object')
		state = {};
	state.parameter_key ??= '';
	state.attributes ??= {};
	state.access ??= {};
	state.last_seen ??= {};
	state.pending ??= {};
	state.reported ??= {};
	return state;
}

function state_save(state) {
	let tmp = STATE_PATH + '.tmp';
	if (writefile(tmp, sprintf('%.J\n', state)) == null)
		return false;
	if (!rename(tmp, STATE_PATH)) {
		unlink(tmp);
		return false;
	}
	return true;
}

function value_str(val) {
	if (val == null)
		return '';
	if (type(val) == 'string')
		return val;
	return sprintf('%s', val);
}

function xsd_type(path) {
	return XSD_TYPES[param_schema(path)?.type] ?? 'xsd:string';
}

function secured(path) {
	return !!param_schema(path)?.secured;
}

function notify_level(state, path) {
	if (index(FORCED_ACTIVE, path) >= 0)
		return 2;
	return int(state.attributes[path] ?? '0') ?? 0;
}

/**
 * Records every notified parameter whose value has moved since it was last
 * seen, and reports whether any of them asks for a session now.
 *
 * Compared against last_seen rather than the value at the previous Inform,
 * because Table 8 wants a change reported even when the value has since
 * returned to what the ACS was last told.
 *
 * @param {object} state - Loaded state, mutated in place
 * @returns {object} `{ changed, active }`
 */
function pending_collect(state) {
	let watched = {};
	for (let path in state.attributes)
		watched[path] = true;
	for (let path in FORCED_ACTIVE)
		watched[path] = true;

	let paths = keys(watched);
	if (!length(paths))
		return { changed: false, active: false };

	let expanded = paths_expand(paths);
	let changed = false;
	let active = false;

	for (let path, value in expanded.leaves) {
		if (!notify_level(state, path))
			continue;

		let now = value_str(value);
		if (state.last_seen[path] === now)
			continue;

		state.pending[path] = { value: now, type: xsd_type(path) };
		changed = true;
		if (notify_level(state, path) >= 2)
			active = true;
	}

	return { changed, active };
}

/**
 * Looks for value changes and tells whoever cares. Runs after anything this
 * process persists, and after a reload picks up another writer's work.
 *
 * A value moved by something that never passes through here, a driver or
 * netifd, is not seen: those are reported at the next Inform instead, where
 * the pending set is recomputed against live values.
 */
function value_change_check() {
	let state = state_load();
	let found = pending_collect(state);
	if (!found.changed)
		return;

	generation++;
	if (!state_save(state))
		log_err('value change: failed to persist pending set');

	ubus.event('bbf-dm.value-change', {
		active: found.active,
		generation,
		paths: keys(state.pending)
	});
}

/**
 * Advances the baseline for parameters the ACS itself wrote.
 *
 * TR-069 3.2.1: a change the ACS made is not reported back to it. A write
 * carrying a ParameterKey came from the ACS; one without came from a local
 * caller and must be reported.
 */
function baseline_advance(state, paths) {
	for (let path in paths) {
		if (!notify_level(state, path))
			continue;
		let one = paths_expand([path]);
		state.last_seen[path] = value_str(one.leaves[path]);
		delete state.pending[path];
	}
}

function fault_of(outcome) {
	let first = filter(outcome.results, (r) => !r.success)[0];
	return FAULT_FOR_REASON[first?.reason] ?? FAULT_INTERNAL;
}

// A single ubus message may not exceed UBUS_MAX_MSGLEN, a 1 MiB compile-time
// constant shared by ubusd and libubus. An oversized one is not refused: it is
// lost, and the sender is disconnected with every object it published. A whole
// tree is bigger than that, so answers go out in parts, which ubus carries as
// several data frames closed by the final reply. The budget counts the strings
// rather than the encoding, which is larger, so it stays well under the cap.
const CHUNK_BYTES = 192 * 1024;

// Per entry, on top of the strings: the table and its three named fields,
// padded, plus what the array and the outer table cost.
const ENTRY_OVERHEAD = 64;

function params_stream(req, params) {
	let chunk = [];
	let bytes = 0;

	req.defer();

	for (let p in params) {
		push(chunk, p);
		bytes += ENTRY_OVERHEAD + length(p.path) +
			 length(p.value ?? '') + length(p.type ?? '');

		if (bytes < CHUNK_BYTES)
			continue;

		req.reply({ params: chunk }, ubus.STATUS_CONTINUE);
		chunk = [];
		bytes = 0;
	}

	req.reply({ params: chunk });
	return req;
}

function cwmp_names(req) {
	let path = req.args?.path ?? '';
	let next_level = !!req.args?.next_level;

	// A.3.2.3: an empty path names the whole model, and asking for its next
	// level answers with the root object alone.
	if (path == '') {
		if (next_level)
			return params_stream(req, [ { path: 'Device.', writable: false } ]);
		path = 'Device.';
	}

	// A.3.2.3: a parameter name is a valid path, but it has no next level.
	if (substr(path, -1) != '.' && next_level)
		return { fault: FAULT_INVALID_ARGUMENTS };

	let params = names_list(path, next_level);
	if (params == null)
		return { fault: FAULT_INVALID_PARAM };

	return params_stream(req, params);
}

function cwmp_get(req) {
	let paths = req.args?.paths ?? [];
	let expanded = paths_expand(paths);

	// A.3.2.2: one name the CPE cannot resolve faults the whole request. The
	// Inform asks with partial set, because losing its DeviceId and whole
	// ParameterList to one parameter missing from the schema is worse than
	// reporting the rest.
	if (length(expanded.unknown) && !req.args?.partial)
		return { fault: FAULT_INVALID_PARAM };

	let params = [];
	for (let path, value in expanded.leaves) {
		let info = param_schema(path);

		// TR-181 states of every secured parameter that reading it returns
		// an empty string regardless of the actual value unless the reader
		// holds a secured role, which CWMP has no notion of. The parameter
		// still exists, is still listed and stays writable.
		push(params, {
			path,
			value: info?.secured ? '' : value_str(value),
			type: XSD_TYPES[info?.type] ?? 'xsd:string'
		});
	}

	return params_stream(req, params);
}

function cwmp_set(req) {
	let params = req.args?.params ?? [];
	let key = req.args?.key ?? '';
	let state = state_load();

	// A.3.2.1: an empty list sets the ParameterKey and nothing else.
	if (!length(params)) {
		state.parameter_key = key;
		if (!state_save(state))
			return { fault: FAULT_INTERNAL };
		return { status: 0, digest: dm.get_digest() };
	}

	// Name and writability first, so a request that cannot apply is refused
	// before anything is staged, and every offending name is named.
	let faults = [];
	for (let p in params) {
		let info = param_schema(p.path);
		if (!info)
			push(faults, { path: p.path, fault: FAULT_INVALID_PARAM });
		else if (!info.writable)
			push(faults, { path: p.path, fault: FAULT_READ_ONLY });
	}
	if (length(faults))
		return { fault: FAULT_INVALID_ARGUMENTS, params: faults };

	let ops = [];
	for (let p in params)
		push(ops, { op: 'set', path: p.path, value: p.value });

	let outcome = operations_apply(ops);
	if (!outcome.success) {
		// Nothing is wrong with any one parameter, so this is not a
		// SetParameterValuesFault.
		if (outcome.busy)
			return { fault: FAULT_RESOURCES };

		let per_param = [];
		for (let i = 0; i < length(outcome.results); i++) {
			let r = outcome.results[i];
			if (!r.success)
				push(per_param, {
					path: r.path,
					fault: FAULT_FOR_REASON[r.reason] ?? FAULT_INTERNAL
				});
		}
		if (length(per_param))
			return { fault: FAULT_INVALID_ARGUMENTS, params: per_param };
		return { fault: fault_of(outcome) };
	}

	// Only a request that fully applied changes the key (A.3.2.1).
	state.parameter_key = key;
	let written = [];
	for (let p in params)
		push(written, p.path);
	baseline_advance(state, written);
	if (!state_save(state))
		return { fault: FAULT_INTERNAL };

	return { status: 0, digest: outcome.digest };
}

function cwmp_add(req) {
	let path = req.args?.path;
	if (!path)
		return { fault: FAULT_INVALID_PARAM };

	let outcome = operations_apply([{ op: 'add', path }]);
	if (!outcome.success)
		return { fault: fault_of(outcome) };

	let state = state_load();
	state.parameter_key = req.args?.key ?? '';
	if (!state_save(state))
		return { fault: FAULT_INTERNAL };

	return { instance: outcome.results[0].instance, status: 0 };
}

function cwmp_del(req) {
	let path = req.args?.path;
	if (!path)
		return { fault: FAULT_INVALID_PARAM };

	let outcome = operations_apply([{ op: 'del', path }]);
	if (!outcome.success)
		return { fault: fault_of(outcome) };

	let state = state_load();
	state.parameter_key = req.args?.key ?? '';

	// A.3.2.4: removing an object is not a value change, so anything pending
	// beneath it goes with it.
	for (let pending in keys(state.pending))
		if (substr(pending, 0, length(path)) == path)
			delete state.pending[pending];

	if (!state_save(state))
		return { fault: FAULT_INTERNAL };

	return { status: 0 };
}

function cwmp_attributes_get(req) {
	let expanded = paths_expand(req.args?.paths ?? []);
	if (length(expanded.unknown))
		return { fault: FAULT_INVALID_PARAM };

	let state = state_load();
	let params = [];
	for (let path in expanded.leaves) {
		push(params, {
			path,
			notification: sprintf('%d', notify_level(state, path)),
			access_list: state.access[path] ? [ 'Subscriber' ] : []
		});
	}

	return { params };
}

function cwmp_attributes_set(req) {
	let attrs = req.args?.attrs ?? [];
	let state = state_load();

	for (let attr in attrs) {
		let notification_change = !!attr.notification_change;
		let access_change = !!attr.access_list_change;
		if (!notification_change && !access_change)
			continue;

		let level = int(attr.notification ?? '0') ?? 0;
		if (notification_change && (level < 0 || level > NOTIFY_MAX))
			return { fault: FAULT_NOTIFICATION_REQUEST };

		let expanded = paths_expand([ attr.path ]);
		if (length(expanded.unknown))
			return { fault: FAULT_INVALID_PARAM };

		for (let path, value in expanded.leaves) {
			// A.3.2.4: a parameter the data model requires to be Forced
			// Active keeps notification 2 whatever the ACS asks for, and
			// the request is ignored rather than refused. The rest of the
			// same request still applies; notify_level() reports the 2.
			if (notification_change && index(FORCED_ACTIVE, path) < 0) {
				state.attributes[path] = sprintf('%d', level);
				if (level) {
					// Seed the baseline so subscribing does not itself
					// look like a change at the next Inform.
					state.last_seen[path] = value_str(value);
				} else {
					delete state.last_seen[path];
					delete state.pending[path];
				}
			}

			if (access_change) {
				let subscriber = false;
				for (let entity in (attr.access_list ?? []))
					if (entity == 'Subscriber')
						subscriber = true;
				if (subscriber)
					state.access[path] = true;
				else
					delete state.access[path];
			}
		}
	}

	if (!state_save(state))
		return { fault: FAULT_INTERNAL };

	return {};
}

/**
 * The value changes waiting to be reported, with the generation that names
 * them. The session puts these in the Inform; the baseline only moves once
 * the ACS has acknowledged it (3.7.1.5), which is what the ack below does.
 */
function cwmp_inform_pending(req) {
	let state = state_load();

	// Recompute against live values, so parameters that move without passing
	// through this process are reported too.
	pending_collect(state);

	generation++;
	state.reported = {};
	let params = [];
	for (let path, entry in state.pending) {
		// The baseline keeps the real value so the next scan can still see a
		// change; only what goes to the ACS is blanked.
		state.reported[path] = entry.value;
		push(params, {
			path,
			value: secured(path) ? '' : entry.value,
			type: entry.type
		});
	}

	if (!state_save(state))
		log_err('inform pending: failed to persist the reported set');

	return { generation, params };
}

/**
 * The ACS acknowledged the Inform, so what was handed out becomes the
 * baseline. A session that died before this leaves the reported set
 * unpromoted and the next Inform recomputes it, which is what 3.7.1.5 asks.
 */
function cwmp_inform_delivered(req) {
	let state = state_load();

	for (let path, value in state.reported) {
		state.last_seen[path] = value;
		if (state.pending[path]?.value === value)
			delete state.pending[path];
	}
	state.reported = {};

	if (!state_save(state))
		return { fault: FAULT_INTERNAL };

	return {};
}

function cwmp_parameter_key(req) {
	return { key: state_load().parameter_key };
}

export const methods = {
	'cwmp-names': { call: cwmp_names, args: { path: '', next_level: true } },
	'cwmp-get': { call: cwmp_get, args: { paths: [], partial: true } },
	'cwmp-set': { call: cwmp_set, args: { params: [], key: '' } },
	'cwmp-add': { call: cwmp_add, args: { path: '', key: '' } },
	'cwmp-del': { call: cwmp_del, args: { path: '', key: '' } },
	'cwmp-attributes-get': { call: cwmp_attributes_get, args: { paths: [] } },
	'cwmp-attributes-set': { call: cwmp_attributes_set, args: { attrs: [] } },
	'cwmp-inform-pending': { call: cwmp_inform_pending, args: {} },
	'cwmp-inform-delivered': { call: cwmp_inform_delivered, args: { generation: 0 } },
	'cwmp-parameter-key': { call: cwmp_parameter_key, args: {} }
};

/**
 * Arms value-change detection. Called once the object is published.
 */
export function init() {
	on_commit(value_change_check);
	log_info('cwmp-dm: CWMP methods published');
};
