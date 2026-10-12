'use strict';

import { writefile, readfile, dirname, stat, mkdir, lsdir } from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { acl_role_load, acl_filter_tree } from 'ubbf';
import { log_info, log_warn, log_err, log_exception } from 'ubbf';
import { firewall_reconcile, firewall_rules_expired, firewall_expiry_next } from 'ubbf';
import { order_snapshot, orders_compute } from 'ubbf';
import { last_change_get } from 'ubbf.utils.netdev_change';
import {
	host_path_by_mac, host_path_by_ip, hosts_build, hosts_downstream_get,
	hosts_numbered, host_by_instance,
	hosts_state_get, hosts_inactive_remove
} from 'ubbf.utils.hosts';
import { ifstats_get, ifstats_basic_get, ifstats_reset } from 'ubbf.utils.ifstats';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { interface_resolve } from 'ubbf.utils.path';
import { popen_async, task_run, TASK_MARGIN_S } from 'ubbf.utils.process';
import { DM_MINOR, DM_VERSION_ERROR, dm_visible, tag_minor } from 'ubbf.utils.dm-version';
import { op_trigger_flush, op_trigger_drop } from 'ubbf.utils.cwmp-op-trigger';
import { modules_registered } from 'ubbf.utils.modules';
import { native_modules_register, native_modules_notify } from 'ubbf.utils.dm-native';
import { schedule_refs_check, schedule_refs_prune } from 'ubbf';
import {
	client_query_get, ubus_topology_get, local_device_get, local_api_data_get,
	device_api_data_get, radios_bss_sort, steering_stats_get, steering_history_get,
	topology_devices_get
} from 'ubbf.utils.wifi-dataelements';
import { capability_radios_get } from 'ubbf.utils.capabilities';
import { radio_instances_for_bands } from 'ubbf.utils.wifi_radio';
import { lower_layer_resolve_vlan } from 'ubbf.render.ubbf_helpers';
import * as ubbf from 'ubbf';

import * as DHCPv4 from 'ubbf.tr181.DHCPv4';
import * as DHCPv6 from 'ubbf.tr181.DHCPv6';
import * as SSH from 'ubbf.tr181.SSH';
import * as IP from 'ubbf.tr181.IP';
import * as Ethernet from 'ubbf.tr181.Ethernet';
import * as Bridging from 'ubbf.tr181.Bridging';
import * as Time from 'ubbf.tr181.Time';
import * as Hosts from 'ubbf.tr181.Hosts';
import * as Firewall from 'ubbf.tr181.Firewall';
import * as DNS from 'ubbf.tr181.DNS';
import * as NAT from 'ubbf.tr181.NAT';
import * as DeviceInfo from 'ubbf.tr181.DeviceInfo';
import * as Routing from 'ubbf.tr181.Routing';
import * as RouterAdvertisement from 'ubbf.tr181.RouterAdvertisement';
import * as NeighborDiscovery from 'ubbf.tr181.NeighborDiscovery';
import * as WiFi from 'ubbf.tr181.WiFi';
import * as Diagnostics from 'ubbf.tr143.Diagnostics';
import * as LocalAgent from 'ubbf.tr181.LocalAgent';
import * as InterfaceStack from 'ubbf.tr181.InterfaceStack';
import * as UnixDomainSockets from 'ubbf.tr181.UnixDomainSockets';
import * as Device from 'ubbf.tr181.Device';
import * as ManagementServer from 'ubbf.tr181.ManagementServer';
import * as GatewayInfo from 'ubbf.tr181.GatewayInfo';

const optional_modules = [
];

const CONFIG_PATH = '/etc/ubbf/config.json';
const RUNTIME_DIR = '/tmp/ubbf';
// The config holds the account and WiFi secrets
const CONFIG_MODE = 0600;
const MODULES_DIR = '/usr/share/ucode/ubbf/modules';

const full_model = {
	...DHCPv4.model,
	...DHCPv6.model,
	...SSH.model,
	...IP.model,
	...Ethernet.model,
	...Bridging.model,
	...Time.model,
	...Hosts.model,
	...Firewall.model,
	...DNS.model,
	...NAT.model,
	...DeviceInfo.model,
	...Routing.model,
	...RouterAdvertisement.model,
	...NeighborDiscovery.model,
	...WiFi.model,
	...Diagnostics.model,
	...LocalAgent.model,
	...InterfaceStack.model,
	// ...UnixDomainSockets.model,
	...Device.model,
	...ManagementServer.model,
	...GatewayInfo.model
};

const all_operations = {
	...Diagnostics.operations,
	...DNS.operations,
	...DeviceInfo.operations,
	...Device.operations,
	...WiFi.operations,
	...DHCPv4.operations,
	...DHCPv6.operations,
	...Ethernet.operations,
	...IP.operations,
	...Bridging.operations,
	...SSH.operations
};

const member_extensions = {};

// ucode resolves names in textual order, so the hook registry has to precede
// every persist path that runs it and module_api_build(), which hands it to
// the out-of-tree modules.
let commit_hooks = [];

/**
 * Registers a callback to run after the config has been persisted, whether by
 * a transaction, a whole-file apply, a reload of another writer's work or the
 * load at start-up.
 *
 * A hook that wants to know what changed compares against its own record: the
 * data model keeps no per-change journal.
 *
 * @param {function} cb - Called with no arguments after each persist
 */
export function on_commit(cb) {
	push(commit_hooks, cb);
};

let precommit_hooks = [];

/**
 * Registers a check that runs before a transaction is committed. A hook that
 * returns a string refuses the commit, which then fails and is aborted; use
 * it when a commit hook could not carry out the change, since a commit hook
 * cannot fail the commit.
 *
 * @param {function} cb - Called with no arguments, returns null or a reason
 */
export function on_precommit(cb) {
	push(precommit_hooks, cb);
};

let abort_hooks = [];

/**
 * Registers a callback to run when a transaction is abandoned.
 *
 * The counterpart to `on_commit`: a handler that stages a side effect for
 * commit needs to be told when that commit is never coming, or the staged
 * work rides along into the next transaction.
 *
 * @param {function} cb - Called with no arguments after each abort
 */
export function on_abort(cb) {
	push(abort_hooks, cb);
};

/**
 * Runs a hook list. A hook that throws must not take the transaction with
 * it, so each is guarded.
 *
 * @param {array} hooks - Callbacks to run
 * @param {string} what - Label for the log line when one throws
 */
function hooks_run(hooks, what) {
	for (let cb in hooks) {
		try {
			cb();
		} catch (e) {
			log_exception(what, e);
		}
	}
}

function commit_hooks_run() {
	hooks_run(commit_hooks, 'commit hook');
}

// Registered here rather than by the modules themselves: both are imported
// by this one, so neither can reach on_commit without a cycle.
on_commit(ManagementServer.staged_flush);
on_abort(ManagementServer.staged_drop);
on_commit(op_trigger_flush);
on_abort(op_trigger_drop);

// operations_apply() needs the write gate, which exists only after the
// modules have registered, so the module API reaches it through this binding.
let module_writer;

/**
 * Applies set, add and del operations for an out-of-tree module, for a
 * change that the agent makes itself, such as a timer that expires.
 *
 * @param {array} operations - `{ op, path, value? }` entries
 * @param {function} done - Called with the outcome of queued operations
 * @returns {object|null} null when queued, else
 *                        `{ success, digest, results }`
 */
function module_config_apply(operations, done) {
	return module_writer(operations, done);
}

/**
 * Registers optional modules based on filesystem dependency checks.
 *
 * Mutates the module-scoped `full_model` and `all_operations` objects after
 * their literal initialisation, since each entry depends on a runtime probe
 * (binary present on disk). Must run before `operation_patterns` is built so
 * that optional `{i}` patterns are included in the dispatch table.
 */
function optional_modules_register() {
	for (let entry in optional_modules) {
		let dep = entry[0];
		let model = entry[1];
		let operations = entry[2];
		let found;

		if (type(dep) == 'array') {
			for (let bin in dep) {
				if (stat(bin)) {
					found = true;
					break;
				}
			}
		} else {
			found = !!stat(dep);
		}

		if (!found)
			continue;

		if (model) {
			for (let path in model)
				full_model[path] = model[path];
		}

		if (operations) {
			for (let path in operations)
				all_operations[path] = operations[path];
		}
	}
}

optional_modules_register();

/**
 * Returns the Device.Hosts.Host path of a MAC address for a module that
 * refers to a host, or an empty string while no module provides the Host
 * table, so that the reference never names a row that does not exist.
 *
 * @param {object} root - TR-181 config root
 * @param {string} mac - MAC address
 * @returns {string} Host path, or empty string
 */
function host_reference_get(root, mac) {
	if (!exists(full_model, 'Device.Hosts.Host.{i}'))
		return '';

	return host_path_by_mac(root, mac);
}

/**
 * Returns the Device.Hosts.Host path of an IPv4 or IPv6 address, with the
 * same rule as host_reference_get().
 *
 * @param {object} root - TR-181 config root
 * @param {string} ip - IP address
 * @returns {string} Host path, or empty string
 */
function host_ip_reference_get(root, ip) {
	if (!exists(full_model, 'Device.Hosts.Host.{i}'))
		return '';

	return host_path_by_ip(root, ip);
}

/**
 * Builds the object an out-of-tree handler receives as `ubbf_module`.
 *
 * Everything a handler may use from ubbf is listed here. A handler cannot load
 * the helpers itself: `include()` compiles it with module mode off, so
 * `import` is a syntax error, and `require()` cannot compile a file that uses
 * `export`, which every `ubbf.*` module does.
 *
 * `schema(key)` names the schema that the module's schema.uc sets as
 * `schemas.<key>`. When schema-<name>.so is installed, it returns the table
 * name `<name>.<key>`, so the schema stays in the shared pages of that table
 * instead of becoming ucode objects in every process. Without the table, it
 * includes schema.uc once and returns the object. `schema_defaults(key)`
 * returns the defaults of that schema in both cases.
 *
 * `members` maps the pattern of a core object to a schema whose commands
 * and events join the schema of that object. A module cannot register the
 * core pattern in `model`, because the merge keeps the last writer and the
 * core handler would be lost.
 *
 * @param {string} name - Module directory name
 * @returns {object} `ubbf`, `utils`, `schema`, `schema_defaults`, the hook
 *   registrars `on_commit` and `on_abort`, the writer `config_apply`, and
 *   empty `model`, `operations` and `members` for the handler to fill.
 */
// The module API is built before dm exists; the value is set after ubbf.create().
let model_path_known;

function module_api_build(name) {
	let table = index(ubbf.schema_tables(), name) >= 0;
	let objects;

	function objects_get() {
		if (!objects) {
			objects = {};
			include(MODULES_DIR + '/' + name + '/schema.uc', { schemas: objects });
		}

		return objects;
	}

	return {
		ubbf,
		utils: {
			'dm-version': { dm_visible },
			netdev_change: { last_change_get },
			hosts: {
				host_path_by_mac: host_reference_get,
				host_path_by_ip: host_ip_reference_get,
				hosts_build, hosts_downstream_get, hosts_numbered, host_by_instance,
				hosts_state_get, hosts_inactive_remove
			},
			ifstats: { ifstats_get, ifstats_basic_get, ifstats_reset },
			netifd: { netifd_status_get },
			path: { interface_resolve, path_kind: (p) => model_path_known(p) },
			process: { popen_async, task_run, TASK_MARGIN_S },
			'wifi-dataelements': {
				client_query_get, ubus_topology_get,
				local_device_get, local_api_data_get, device_api_data_get, radios_bss_sort,
				steering_stats_get, steering_history_get, topology_devices_get
			},
			capabilities: { capability_radios_get },
			wifi_radio: { radio_instances_for_bands },
			ubbf_helpers: { lower_layer_resolve_vlan },
		},
		schema: (key) => table ? `${name}.${key}` : objects_get()[key],
		schema_defaults: (key) => table
			? ubbf.schema_defaults(`${name}.${key}`)
			: objects_get()[key]?.defaults,
		on_commit,
		on_precommit,
		on_abort,
		config_apply: module_config_apply,
		model: {},
		operations: {},
		members: {},
	};
}

/**
 * Registers out-of-tree data model modules from MODULES_DIR.
 *
 * Each subdirectory that has one is entered through its `handler.uc`, which is
 * run with `include()` in a scope whose single entry, `ubbf_module`, is the
 * object from `module_api_build()`; the handler adds its entries to that
 * object's `model`, `operations` and `members`. A handler may `include()`
 * sibling files to split itself up; a relative include resolves against the
 * handler's own directory.
 *
 * `include()` rather than `require()` because `include()` is the only loader
 * that takes a scope, so the scope is the only channel that works both ways.
 *
 * The scope exists only while the include runs. uc_callfunc() swaps the VM's
 * global scope for it and restores the original afterwards, and a free name
 * inside a function is looked up in whatever the global scope is when the
 * function executes. So a handler's top-level code sees `ubbf_module`, but a
 * get handler called later from obuspa does not, and under strict
 * declarations that is a reference error. A handler therefore copies what its
 * functions need into file-level locals at the top of the file, which are
 * upvalues and survive; the single scope key is what lets it write
 * `const ubbf = ubbf_module.ubbf;` without shadowing the source.
 *
 * Both loaders compile with module mode off, so a handler can use neither
 * `export` nor `import`.
 *
 * Failures are logged and skipped rather than propagated. An uncaught throw at
 * this point aborts `vendor_ucode_init()` and the agent never starts, so one
 * broken third-party module must not be able to take the data model with it.
 *
 * Mutates `full_model`, `all_operations` and `member_extensions` in place,
 * like `optional_modules_register()` before it, and for the same reason: it
 * has to run before `model_filter()`, before `operation_patterns` is
 * built, and before the single `dm.register()`, which replaces the model
 * rather than merging into it.
 */
function external_modules_register() {
	for (let name in sort(lsdir(MODULES_DIR) ?? [])) {
		let handler = MODULES_DIR + '/' + name + '/handler.uc';

		// A module may carry only a render template, for a domain with
		// nothing to publish in the data model. renderer.uc picks that up
		// on its own glob.
		if (!stat(handler))
			continue;

		let api = module_api_build(name);

		try {
			include(handler, { ubbf_module: api });
		}
		catch (e) {
			log_err('module %s: handler failed to load: %s', name, e);
			continue;
		}

		if (!length(api.model) && !length(api.operations)) {
			log_err('module %s: handler registered no model or operations', name);
			continue;
		}

		for (let path in api.model)
			full_model[path] = api.model[path];

		for (let path in api.operations)
			all_operations[path] = api.operations[path];

		for (let pattern, schema in api.members) {
			member_extensions[pattern] ??= [];
			push(member_extensions[pattern], { schema });
		}

		modules_registered[name] = true;
		log_info('module %s registered', name);
	}
}

external_modules_register();

// Same point as the ucode modules: before model_filter() and dm.register().
// The event hook resolves the agent's global at call time, as not every
// process that loads this file defines usp_datamodel_event.
let native_apis = {};
for (let name in native_modules_register(full_model, all_operations, {
	event: (path, args) => global.usp_datamodel_event?.(path, args),
	schema: (name, key) => (native_apis[name] ??= module_api_build(name)).schema(key)
}))
	modules_registered[name] = true;

/**
 * Replaces schema names with the schemas/ exports when no core schema table
 * is installed, so the entries take the object path below.
 */
function schema_names_resolve() {
	if (index(ubbf.schema_tables(), 'core') >= 0)
		return;

	for (let path, entry in full_model) {
		if (type(entry.schema) == 'string')
			entry.schema = ubbf.schema_get(entry.schema);
	}
}

schema_names_resolve();

const COMMAND_TYPES = { sync: true, async: true, event: true };

/**
 * Reports whether a schema member belongs to the active protocol.
 *
 * TR-181 defines commands and events only in its USP-flavour root, and
 * TR-069 has neither an Operate RPC nor this event mechanism, so an
 * object-valued member declaring one of those types is USP-only unless it
 * says otherwise. Plain parameters are shared.
 *
 * @param {*} value - A member of a schema's `schema` table
 * @returns {boolean} True when the member stays
 */
function member_protocol_ok(value) {
	if (type(value) != 'object' || !COMMAND_TYPES[value.type])
		return true;

	let proto = value.protocol ?? 'usp';
	return proto == 'both' || proto == ubbf.active_protocol();
}

/**
 * Logs a version tag that tag_visible() ignores because it is malformed.
 *
 * @param {string} where - Pattern or schema member the tag belongs to
 * @param {string} key - `since` or `until`
 * @param {*} tag - The tag
 */
function tag_check(where, key, tag) {
	if (tag != null && tag_minor(tag) == null)
		log_err('%s: %s tag %J is not 2.<minor>, ignored', where, key, tag);
}

/**
 * Reports whether a schema member is part of the active data model: it
 * belongs to the active protocol and exists in the active TR-181 version.
 *
 * @param {object} schema - The schema object holding the member
 * @param {string} name - Member name
 * @param {*} value - The member's entry in `schema.schema`
 * @returns {boolean} True when the member stays
 */
function member_visible(schema, name, value) {
	let since = schema.since?.[name];
	let until = schema.until?.[name];

	tag_check(`${schema.path}${name}`, 'since', since);
	tag_check(`${schema.path}${name}`, 'until', until);

	return member_protocol_ok(value) && dm_visible(since, until);
}

/**
 * Rebuilds one entry's schema without the members that the other protocol
 * owns or that the active TR-181 version does not have.
 *
 * `defaults` is projected alongside `schema` because the native module
 * materialises a defaulted key in the tree, and the GetParameterNames walk
 * enumerates the tree rather than the schema; a member dropped from one and
 * not the other would still be advertised.
 *
 * Schema exports are shared by reference between patterns, so the projection
 * builds a copy rather than mutating what a sibling entry also points at.
 *
 * @param {object} entry - A `full_model` entry
 */
function entry_project(entry) {
	let members = entry.schema?.schema;
	if (!members)
		return;

	let keep = {};
	let dropped = false;

	for (let name, value in members) {
		if (member_visible(entry.schema, name, value))
			keep[name] = value;
		else
			dropped = true;
	}

	if (!dropped)
		return;

	let defaults = {};
	for (let name, value in (entry.schema.defaults ?? {})) {
		if (exists(keep, name))
			defaults[name] = value;
	}

	entry.schema = { ...entry.schema, schema: keep, defaults };
}

/**
 * Reports whether a model entry exists in the active TR-181 version.
 *
 * @param {string} path - Object pattern of the entry
 * @param {object} entry - The entry, with optional `since` and `until`
 * @returns {boolean} True when the entry stays
 */
function entry_version_ok(path, entry) {
	tag_check(path, 'since', entry.since);
	tag_check(path, 'until', entry.until);

	return dm_visible(entry.since, entry.until);
}

/**
 * Returns the members of the schema of one model entry.
 *
 * An entry names a schema in a schema table, or carries the schema object
 * when no table holds it.
 *
 * @param {object} entry - Model entry
 * @returns {object|null} Member name to dm_type value or command definition
 */
function schema_members(entry) {
	return (type(entry.schema) == 'string')
		? ubbf.schema_get(entry.schema)?.schema
		: entry.schema?.schema;
}

/**
 * Copies the commands and events of a schema into a member table.
 *
 * Only object-valued members are copied: a plain parameter would be
 * advertised while the dispatcher has no value for it.
 *
 * @param {object} members - Member table to extend
 * @param {object} entry - `{ schema }` that a module added to the pattern
 */
function commands_add(members, entry) {
	for (let name, value in (schema_members(entry) ?? {}))
		if (type(value) == 'object')
			members[name] = value;
}

/**
 * Returns the schema members of a model entry, with the commands and events
 * that modules add to its pattern.
 *
 * @param {object} entry - Model entry
 * @param {string} pattern - Object pattern of the entry
 * @returns {object|null} Member name to dm_type value or command definition
 */
function entry_members(entry, pattern) {
	let members = schema_members(entry);
	let extensions = member_extensions[pattern];

	if (!extensions)
		return members;

	members = { ...(members ?? {}) };

	for (let extension in extensions)
		commands_add(members, extension);

	return members;
}

/**
 * Reports whether the schema of the object of an operation has the command
 * as a member of the active protocol.
 *
 * @param {string} path - Operation path, for example `Device.X.{i}.Reset()`
 * @returns {boolean} True when the command is a member
 */
function operation_member(path) {
	let dot = rindex(path, '.');
	let pattern = substr(path, 0, dot);
	let entry = full_model[pattern];
	if (!entry)
		return false;

	let value = entry_members(entry, pattern)?.[substr(path, dot + 1)];
	return value != null && member_protocol_ok(value);
}

/**
 * Removes the operations whose command the active TR-181 version hides.
 *
 * `declared` lists the operations that were members before the version was
 * selected. An operation that no schema declares stays, as before.
 *
 * @param {array} declared - Operation paths
 */
function operations_version_drop(declared) {
	for (let path in declared)
		if (!operation_member(path))
			delete all_operations[path];
}

/**
 * Removes the operations below the patterns that the active TR-181 version
 * does not have.
 *
 * @param {array} patterns - Object patterns removed from the model
 */
function operations_drop(patterns) {
	for (let path in keys(all_operations)) {
		for (let pattern in patterns) {
			if (index(path, pattern + '.') != 0)
				continue;

			delete all_operations[path];
			break;
		}
	}
}

/**
 * Drops model entries bound to the other management protocol or absent from
 * the active TR-181 version, then projects the surviving entries' schemas.
 *
 * Entries may carry a `protocol` member ('cwmp' or 'usp'); entries
 * without one serve both protocols. Entries and schema members may carry
 * `since` and `until` version tags; utils/dm-version.uc has the rule. Runs
 * after optional and out-of-tree module registration so their entries are
 * filtered too.
 *
 * For the protocol, `all_operations` is deliberately left whole: `bbf-dm
 * operate` is published in both modes and `bbf-cli` reaches it locally, so
 * only the advertised surface is protocol-bound, not the dispatch table. An
 * object the version does not have loses its operations too, and so does a
 * command member the version hides, since no mode may act on data the
 * version hides.
 *
 * @returns {array} Patterns of the dropped entries
 */
function model_filter() {
	if (DM_VERSION_ERROR)
		log_warn('%s', DM_VERSION_ERROR);

	let drop = [];
	let hidden = [];

	for (let path, entry in full_model) {
		if (entry.protocol && entry.protocol != ubbf.active_protocol())
			push(drop, path);
		else if (!entry_version_ok(path, entry))
			push(hidden, path);
	}

	for (let path in [ ...drop, ...hidden ])
		delete full_model[path];

	operations_drop(hidden);

	// Entries naming a table schema are projected inside ubbf.so.
	ubbf.schema_protocol_set(ubbf.active_protocol());
	let declared = filter(keys(all_operations), operation_member);
	ubbf.schema_version_set(DM_MINOR);

	for (let path in full_model)
		entry_project(full_model[path]);

	for (let pattern, entries in member_extensions)
		for (let entry in entries)
			entry_project(entry);

	operations_version_drop(declared);

	return [ ...drop, ...hidden ];
}

const model_dropped = model_filter();

/**
 * Returns a set handler that checks ScheduleRef and passes every other
 * parameter to the set handler of the model entry.
 *
 * @param {function|null} set - Set handler of the entry
 * @returns {function} Set handler
 */
function schedule_ref_set(set) {
	return (ctx) => (ctx.param == 'ScheduleRef')
		? schedule_refs_check(ctx.value, ctx.root, !!modules_registered.schedules)
		: (set ? set(ctx) : 0);
}

/**
 * Gives every object with a ScheduleRef parameter a check of that
 * parameter. TR-181 makes ScheduleRef a strong reference to
 * Device.Schedules.Schedule, a table of the schedules module: without the
 * module the object accepts only an empty value.
 */
function schedule_ref_checks_install() {
	for (let pattern, entry in full_model)
		if (schema_members(entry)?.ScheduleRef != null)
			entry.set = schedule_ref_set(entry.set);
}

schedule_ref_checks_install();

const operation_patterns = {};
for (let pattern in all_operations) {
	if (index(pattern, '{i}') < 0)
		continue;

	let regex_str = replace(pattern, /\./g, '\\.');
	regex_str = replace(regex_str, /\(\)/g, '\\(\\)');
	regex_str = replace(regex_str, /\{i\}/g, '([0-9]+)');
	regex_str = '^' + regex_str + '$';

	operation_patterns[pattern] = regexp(regex_str);
}

export let dm = ubbf.create();

// The agent gives the instance numbers; the render and ubbf-device only
// read them.
ubbf.instance_map_own(true);
model_path_known = (p) => dm.path_known(p) ?? 0;
let pending_ops = {};
let op_counter = 0;
let in_transaction = false;
let orders_before;
let config_before;
let apply_pending = false;

// A USP transaction spans several calls from obuspa, and the event loop runs
// between them. dm holds one workspace, so every other writer waits at this
// gate until that transaction ends.
const write_gate = ubbf.write_gate_create(() => in_transaction,
	(gate) => uloop.timer(0, () => gate.drain()), log_exception);

dm.register(full_model);
dm.register_operations(all_operations);
dm.register_hidden(model_dropped);

InterfaceStack.bind_dm(dm);

on_commit(() => native_modules_notify('commit', dm.config()));
on_abort(() => native_modules_notify('abort', dm.config()));

/**
 * Writes the live config (dm.config_persist()) and announces a new digest
 * on ubus when the persistent file changed.
 *
 * @returns {boolean|null} `true` when persistent config was rewritten,
 *                         `false` when content was unchanged,
 *                         `null` when the persistent write failed
 */
function config_persist() {
	let persisted = dm.config_persist(CONFIG_PATH, RUNTIME_DIR + '/config.json', CONFIG_MODE);

	if (persisted)
		ubus?.event('bbf-dm.digest', { digest: dm.digest() });

	return persisted;
}

/**
 * Begins a configuration transaction.
 *
 * Sets the in-transaction flag (so handlers read from the workspace clone)
 * and delegates to `dm.trans_start()` to snapshot the current config into a
 * workspace.
 *
 * A second transaction is refused: dm has one workspace, and a second
 * `dm.trans_start()` would drop what the first one staged.
 *
 * @returns {number} Result of `dm.trans_start()`; 0 on success, negative on error
 */
export function trans_start() {
	if (in_transaction) {
		log_err('transaction: start refused, a transaction is already open');
		return -1;
	}

	log_info('transaction: start');
	in_transaction = true;
	config_before = dm.config();
	orders_before = order_snapshot(config_before);
	return dm.trans_start();
};

/**
 * Aborts the current configuration transaction.
 *
 * Discards the workspace clone and clears the in-transaction flag so handlers
 * resume reading from the live config.
 *
 * @returns {number} Result of `dm.trans_abort()`; 0 on success, negative on error
 */
export function trans_abort() {
	log_info('transaction: abort');
	in_transaction = false;
	config_before = null;
	write_gate.release();
	let rc = dm.trans_abort();
	hooks_run(abort_hooks, 'abort hook');
	return rc;
};

/**
 * Undoes a commit whose apply failed, so that the controller's error holds:
 * the live tree and config.json go back to the configuration before the
 * transaction, and the abort hooks drop what the set handlers staged. The
 * apply stops at its dry run when it fails, so the system still runs that
 * configuration. When config.json cannot be written back, the stored config
 * stays live and the next commit applies it again.
 *
 * @param {object|null} previous - The live config at trans_start()
 * @param {boolean} persisted - True when the commit wrote config.json
 */
function commit_rollback(previous, persisted) {
	if (persisted && previous) {
		log_err('transaction: restoring the config from before the transaction');
		dm.set_config(previous);
		if (config_persist() == null) {
			dm.config_load(CONFIG_PATH);
			apply_pending = true;
		}
	}
	else {
		apply_pending = true;
	}

	hooks_run(abort_hooks, 'abort hook');
}

/**
 * Commits the current configuration transaction.
 *
 * Promotes the workspace to live config, recomputes derived `Name` properties,
 * runs firewall reconciliation, persists the config to disk and triggers a
 * `bbf-device.apply` ubus call when the persisted content changed. When the
 * apply fails, commit_rollback() restores the previous config.
 *
 * @returns {number} 1 when applied successfully,
 *                   0 when committed with no persisted change,
 *                   negative on apply failure or transaction error
 */
export function trans_commit() {
	for (let cb in precommit_hooks) {
		let reason;
		try {
			reason = cb();
		} catch (e) {
			log_exception('precommit hook', e);
			reason = 'the check failed';
		}

		if (reason) {
			log_err('transaction: commit refused: %s', reason);
			trans_abort();
			return -1;
		}
	}

	let previous = config_before;
	config_before = null;

	let rc = dm.trans_commit();
	if (rc <= 0)
		return rc;

	orders_compute(dm.config(), orders_before);
	dm.names_compute();
	firewall_reconcile(full_model, dm.config());
	schedule_refs_prune(dm.config());

	in_transaction = false;
	write_gate.release();

	let persisted = config_persist();

	// The live tree must not hold what the disk does not: an acknowledged
	// change would be gone after a restart.
	if (persisted == null) {
		log_err('transaction: commit not persisted, restoring the stored config');
		dm.config_load(CONFIG_PATH);
		hooks_run(abort_hooks, 'abort hook');
		return -1;
	}

	// The digest moves with the persisted content, so a retry of a commit
	// whose apply failed is unchanged and has to apply again.
	if (persisted || apply_pending) {
		log_info('transaction: commit - applying config');
		let result = ubus?.call('bbf-device', 'apply', { apply: true });
		if (!result?.success) {
			log_err('transaction: apply failed: %s', result?.error ?? 'unknown error');
			for (let entry in (result?.logs ?? []))
				log_err('  [%s] %s', entry.level, entry.msg);
			commit_rollback(previous, persisted);
			return -1;
		}
		apply_pending = false;
		persisted = true;
	}
	else {
		log_info('transaction: commit - no changes');
	}

	// Hooks run for a commit that persisted nothing too: a handler that
	// pushes a value somewhere other than the tree, as the ACS binding
	// does, leaves the tree identical and would otherwise never be told
	// its transaction succeeded.
	commit_hooks_run();

	return persisted ? 1 : 0;
};

/**
 * Replaces the live config, persists it and applies it to the system.
 *
 * @param {object} config - The new configuration tree
 * @returns {object} On success: `{ success: true, output, logs }`.
 *                   On failure: `{ success: false, error, output?, logs? }`
 */
function config_replace(config) {
	let before = order_snapshot(dm.config());
	ubbf.config_pins_take(config);
	dm.set_config(config);

	orders_compute(dm.config(), before);
	dm.names_compute();
	firewall_reconcile(full_model, dm.config());
	schedule_refs_prune(dm.config());

	if (config_persist() == null)
		return { success: false, error: 'Failed to persist config' };

	let result = ubus?.call('bbf-device', 'apply', { apply: true });
	if (!result?.success)
		return { success: false, error: result?.error ?? 'Apply failed', output: result?.output, logs: result?.logs ?? [] };

	commit_hooks_run();

	return { success: true, output: result?.output, logs: result?.logs ?? [] };
}

/**
 * Reads and parses a configuration JSON file.
 *
 * @param {string} file_path - Absolute path to the JSON config file
 * @returns {object} `{ config }`, or `{ error }` with `Cannot read file` or
 *                   `Invalid JSON`
 */
function config_file_read(file_path) {
	let content = readfile(file_path);
	if (!content)
		return { error: 'Cannot read file' };

	let config;
	try {
		config = json(content);
	} catch (e) {
		config = null;
	}

	if (type(config) != 'object')
		return { error: 'Invalid JSON' };

	return { config };
}

/**
 * Loads a configuration JSON file and applies it as the live config.
 *
 * Replaces the current config with the file contents, recomputes derived
 * names, reconciles the firewall and triggers a `bbf-device.apply` ubus call.
 * The file is read at once; while a USP transaction is open the apply waits
 * at the write gate and `done` gets its result.
 *
 * @param {string} file_path - Absolute path to the JSON config file
 * @param {function} done - Called with the result of a queued apply
 * @returns {object|null} null when the apply is queued.
 *                   On success: `{ success: true, output, logs }`.
 *                   On failure: `{ success: false, error, output?, logs? }`
 *                   where `error` is one of `Cannot read file`, `Invalid JSON`,
 *                   `Failed to persist config`, or the apply error string.
 */
export function apply_config(file_path, done) {
	let file = config_file_read(file_path);
	if (file.error)
		return { success: false, error: file.error };

	return write_gate.write(() => config_replace(file.config), done);
};

/**
 * Replaces the live config and applies the previous one again when the new
 * one fails, so the device does not stay on a half-applied config.
 *
 * @param {object} config - The new configuration tree
 * @returns {object} `{ success, error?, rolled_back? }`
 */
function config_replace_or_rollback(config) {
	let previous = json(sprintf('%J', dm.config()));
	let result = config_replace(config);
	if (result.success)
		return result;

	log_err('restore: apply failed (%s), applying the previous config again', result.error);
	let rollback = config_replace(previous);
	if (!rollback.success)
		log_err('restore: the previous config failed to apply as well: %s', rollback.error);

	return { ...result, rolled_back: rollback.success };
}

/**
 * Restores the live config from a file, for VendorConfigFile.Restore().
 *
 * @param {string} file_path - Absolute path to the JSON config file
 * @param {function} done - Called with the result of a queued restore
 * @returns {object|null} null when the restore is queued, else
 *                        `{ success, error?, rolled_back? }`
 */
function config_restore(file_path, done) {
	let file = config_file_read(file_path);
	if (file.error)
		return { success: false, error: file.error };

	return write_gate.write(() => config_replace_or_rollback(file.config), done);
}

ubbf.config_restore_hook_set(config_restore);

/**
 * Finds an operation handler for a given path.
 *
 * @param {string} path - The operation path
 * @returns {object|null} Object with op handler and instances array, or null if not found
 */
export function find_operation(path) {
	if (path in all_operations)
		return { op: all_operations[path], instances: null };

	for (let pattern in operation_patterns) {
		let m = match(path, operation_patterns[pattern]);
		if (m) {
			let instances = [];
			for (let i = 1; i < length(m); i++)
				push(instances, int(m[i]));
			return { op: all_operations[pattern], instances };
		}
	}

	return null;
};

/**
 * Runs a synchronous operation.
 *
 * A handler returns its output object, a negative `USP_ERR_*` code for a
 * failure with that code, or null for a failure with
 * `USP_ERR_COMMAND_FAILURE`.
 *
 * @param {string} path - The operation path
 * @param {object} input - Input parameters for the operation
 * @param {string} command_key - Command key for tracking
 * @returns {object|number|null} Operation result, negative USP error code,
 *                               or null on failure
 */
export function run_sync_op(path, input, command_key) {
	let found = find_operation(path);
	if (!found || !found.op || found.op.type != 'sync') {
		log_info('run_sync_op: no handler for %s', path);
		return null;
	}

	log_info('run_sync_op: dispatching %s', path);

	let root = in_transaction ? dm.config() : dm.runtime();
	try {
		if (found.instances != null)
			return found.op.handler(input, command_key, found.instances, root);
		return found.op.handler(input, command_key, root);
	} catch (e) {
		log_exception(path, e);
		return null;
	}
};

/**
 * Persists async-operation output as parameter values under a base path.
 *
 * Writes each `output[key]` to `base_path + '.' + (key_map[key] ?? key)` via
 * `dm.params_set`, then reloads the runtime tree so callers observe the
 * stored values immediately. The `key_map` argument lets callers rename
 * output keys to data-model parameter names without copying the output object.
 *
 * Dotted output keys (e.g. `RouteHops.1.Host`) are result-table rows; they
 * are collected into one nested container write per table so params_set
 * needs no model pattern below the diagnostics object, and so each run
 * replaces the whole table instead of leaving rows from a longer earlier run.
 *
 * @param {string} base_path - Data model base path to store results under
 * @param {object} output - Operation output keyed by source key name
 * @param {object|null} key_map - Optional source-to-target key rename map
 */
function op_results_store(base_path, output, key_map) {
	let params = {};
	let containers = {};

	for (let key, value in output) {
		let mapped = key_map?.[key] ?? key;
		let parts = split(mapped, '.');
		if (length(parts) < 2) {
			params[base_path + '.' + mapped] = value;
			continue;
		}

		containers[parts[0]] ??= {};
		let node = containers[parts[0]];
		for (let i = 1; i < length(parts) - 1; i++) {
			node[parts[i]] ??= {};
			node = node[parts[i]];
		}
		node[parts[length(parts) - 1]] = value;
	}

	// A table with no rows has no dotted keys, only its count; it still
	// has to replace the rows of the run before.
	for (let key in output) {
		let m = match(key, /^([A-Za-z0-9_]+)NumberOfEntries$/);
		if (m)
			containers[m[1]] ??= {};
	}

	for (let name, rows in containers)
		params[base_path + '.' + name] = rows;

	dm.params_set(params);
	dm.runtime_reload();
}

/**
 * Calls the handler of an asynchronous operation.
 *
 * @param {string} path - The operation path
 * @param {object} found - Result of `find_operation()`
 * @param {object} input - Input parameters for the operation
 * @param {number} instance - Instance number
 * @param {function} cb - Completion callback for the handler
 * @param {string} command_key - Command key for tracking
 * @returns {number} 0 when the handler returned, negative when it threw
 */
function async_op_call(path, found, input, instance, cb, command_key) {
	let root = in_transaction ? dm.config() : dm.runtime();
	try {
		if (found.instances != null)
			found.op.handler(input, instance, cb, found.instances, command_key, root);
		else
			found.op.handler(input, instance, cb, command_key, root);
	} catch (e) {
		log_exception(path, e);
		return -USP_ERR_COMMAND_FAILURE;
	}

	return 0;
}

/**
 * Runs an operation that changes the config in its own transaction.
 *
 * The operation holds the transaction, and with it the write gate, until it
 * completes. So it has to complete before its handler returns; one that does
 * not is rolled back and fails, or every other writer would wait for it.
 *
 * @param {string} path - The operation path
 * @param {object} found - Result of `find_operation()`
 * @param {object} input - Input parameters for the operation
 * @param {number} instance - Instance number
 * @param {function} cb - Completion callback
 * @param {string} command_key - Command key for tracking
 * @returns {number} Status code (0 for success, negative for error)
 */
function async_op_commit_run(path, found, input, instance, cb, command_key) {
	if (trans_start() < 0)
		return -USP_ERR_COMMAND_FAILURE;

	let settled = false;
	let commit_cb = (inst, err, msg, output) => {
		if (settled) {
			log_err('%s: completed after its transaction was rolled back', path);
			return;
		}

		settled = true;
		if (err == 0)
			trans_commit();
		else
			trans_abort();
		cb(inst, err, msg, output);
	};

	let rc = async_op_call(path, found, input, instance, commit_cb, command_key);
	if (settled)
		return rc;

	settled = true;
	trans_abort();
	if (rc != 0)
		return rc;

	log_err('%s: returned before it completed, its changes are rolled back', path);
	cb(instance, USP_ERR_COMMAND_FAILURE, 'Operation did not complete', {});
	return 0;
}

/**
 * Runs an asynchronous operation.
 *
 * An operation that changes the config waits at the write gate while a USP
 * transaction is open; it then starts later and reports through `complete_cb`.
 *
 * @param {string} path - The operation path
 * @param {object} input - Input parameters for the operation
 * @param {number} instance - Instance number
 * @param {function} complete_cb - Callback function when operation completes
 * @param {string} command_key - Command key for tracking
 * @returns {number} Status code (0 for success, negative for error)
 */
export function run_async_op(path, input, instance, complete_cb, command_key) {
	let found = find_operation(path);
	if (!found || !found.op || found.op.type != 'async') {
		log_info('run_async_op: no handler for %s (found=%s)', path, found);
		return -USP_ERR_COMMAND_FAILURE;
	}

	log_info('run_async_op: dispatching %s', path);

	let cb = complete_cb;

	if (found.op.store_results) {
		let inner = cb;
		let base_path = found.op.store_results;
		let key_map = found.op.output_key_map;
		cb = (inst, err, msg, output) => {
			if (err != 0 || !output)
				return inner(inst, err, msg, output);

			let store = () => {
				op_results_store(base_path, output, key_map);
				return { success: true };
			};
			let report = () => inner(inst, err, msg, output);
			if (write_gate.write(store, report))
				report();
		};
	}

	if (!found.op.commit)
		return async_op_call(path, found, input, instance, cb, command_key);

	let run = () => ({
		rc: async_op_commit_run(path, found, input, instance, cb, command_key)
	});
	let report = (result) => {
		if (result.rc != 0)
			cb(instance, USP_ERR_COMMAND_FAILURE, 'Operation failed to start', {});
	};

	return write_gate.write(run, report)?.rc ?? 0;
};

/**
 * Handles completion of an async operation.
 *
 * @param {number} op_id - Operation identifier
 * @param {number} inst - Instance number
 * @param {number} err - Error code (0 for success)
 * @param {string} msg - Error message if applicable
 * @param {object} output - Operation output data
 */
export function operation_complete(op_id, inst, err, msg, output) {
	let pending = pending_ops[op_id];
	if (!pending)
		return;

	if (pending.usp_cb) {
		delete pending_ops[op_id];
		pending.usp_cb(inst, err, msg, output);
	} else if (pending.ubus_req) {
		delete pending_ops[op_id];
		if (err == 0)
			pending.ubus_req.reply({ success: true, output });
		else
			pending.ubus_req.reply({ success: false, error: err, message: msg });
	} else {
		pending.completed = true;
		pending.result = { err, msg, output };
	}
};

/**
 * Defers a ubus request for an async operation.
 *
 * @param {number} op_id - Operation identifier
 * @param {object} ubus_req - The ubus request to defer
 */
export function operation_defer(op_id, ubus_req) {
	let pending = pending_ops[op_id];
	if (!pending)
		return;

	if (pending.completed) {
		delete pending_ops[op_id];
		let r = pending.result;
		if (r.err == 0)
			ubus_req.reply({ success: true, output: r.output });
		else
			ubus_req.reply({ success: false, error: r.err, message: r.msg });
	} else {
		pending.ubus_req = ubus_req;
	}
};

/**
 * Starts a data model operation (sync or async).
 *
 * @param {string} path - The operation path
 * @param {object} input - Input parameters
 * @param {object} opts - Options with usp_cb, ubus_req, command_key
 * @returns {object} On error: `{ error: <string>, path?: <string>,
 *                   code?: <number> }`, `code` being the USP error code
 *                   that a sync handler returned.
 *                   For sync ops on success: `{ sync: true, output: <result> }`.
 *                   For async ops on success: `{ async: true, op_id: <number> }`.
 */
export function start_operation(path, input, opts) {
	let found = find_operation(path);
	if (!found)
		return { error: 'operation not found', path };

	if (found.op.type == 'sync') {
		let result = run_sync_op(path, input, opts?.command_key);
		if (type(result) == 'int')
			return { error: 'operation failed', code: -result };
		if (result == null)
			return { error: 'operation failed' };
		return { sync: true, output: result };
	}

	for (let id in pending_ops) {
		if (pending_ops[id].completed)
			delete pending_ops[id];
	}

	let op_id = ++op_counter;
	pending_ops[op_id] = {
		usp_cb: opts?.usp_cb,
		ubus_req: opts?.ubus_req
	};

	let complete_cb = (inst, err, msg, output) => {
		operation_complete(op_id, inst, err, msg, output);
	};

	let status = run_async_op(path, input, opts?.instance ?? 1, complete_cb, opts?.command_key);
	if (status != 0) {
		delete pending_ops[op_id];
		return { error: 'operation start failed' };
	}

	return { async: true, op_id };
};

/**
 * Returns a list of all available operations.
 *
 * @returns {array} Array of operation objects with path and type
 */
export function list_operations() {
	let ops = [];
	for (let path in all_operations) {
		if (!member_protocol_ok(all_operations[path]))
			continue;
		push(ops, { path, type: all_operations[path].type });
	}
	return ops;
};


/**
 * Describes one parameter of an object pattern, or a command or an event
 * that a module adds to it.
 *
 * @param {string} pattern - Object pattern, a key of the model
 * @param {string} name - Parameter name
 * @returns {object|null} Facts as `ubbf.schema_param_info()` returns them
 */
function pattern_param_info(pattern, name) {
	let info = ubbf.schema_param_info(full_model[pattern]?.schema, name);

	if (info)
		return info;

	for (let extension in (member_extensions[pattern] ?? [])) {
		info = ubbf.schema_param_info(extension?.schema, name);
		if (info?.command)
			return info;
	}

	return null;
}

/**
 * Builds the schema the USP core registers.
 *
 * Built on request rather than kept, because the core reads it once at start
 * and a copy held for the life of the agent costs memory.
 *
 * @returns {object} `{ objects, events }` as `ubbf.schema_extract()` returns
 */
export function schema_build() {
	return ubbf.schema_extract(full_model, entry_members);
};

/**
 * Reports whether a path component is an instance number.
 *
 * Scanning the bytes rather than matching /^[0-9]+$/, because a walk of the
 * whole tree asks this for every component of every path and the regex costs
 * roughly twice as much per call.
 *
 * @param {string} s - One path component
 * @returns {boolean} True when the component is all digits
 */
function is_instance(s) {
	let n = length(s);

	if (!n)
		return false;

	for (let i = 0; i < n; i++) {
		let c = ord(s, i);
		if (c < 48 || c > 57)
			return false;
	}

	return true;
}

/**
 * Converts a resolved path into its schema pattern by replacing
 * instance-number segments with {i}.
 *
 * @param {array} parts - Path segments
 * @returns {string} Key into `full_model`
 */
function parts_to_pattern(parts) {
	let out = [];
	for (let p in parts)
		push(out, is_instance(p) ? '{i}' : p);
	return join('.', out);
}

/**
 * Looks up a leaf parameter in the schema.
 *
 * @param {string} path - Full parameter path, no trailing dot
 * @returns {object|null} `{ writable, type }` plus whatever the schema's
 *                        constraints declare, or null when the schema does not
 *                        describe it
 */
export function param_schema(path) {
	let parts = split(path, '.');
	let name = parts[-1];
	let pattern = parts_to_pattern(slice(parts, 0, length(parts) - 1));
	let info = pattern_param_info(pattern, name);
	if (!info)
		return null;
	return { ...info, writable: !!info.writable };
};

/**
 * Reports whether an object path is a multi-instance table, which is what
 * decides whether a caller may add under it.
 *
 * @param {string} path - Object path without trailing dot
 * @returns {boolean} True when instances live below this path
 */
export function object_writable(path) {
	let pattern = parts_to_pattern(split(path, '.'));
	let table = pattern + '.{i}';

	if (!exists(full_model, table))
		return false;

	// A table the CPE maintains itself is readable but not addable.
	return ubbf.schema_entry_addable(full_model[table]);
};

/**
 * Expands leaf and partial paths into their leaf values.
 *
 * @param {array} paths - Leaf paths, partial paths with a trailing dot, or
 *                        paths with `*` in place of an instance number
 * @returns {object} `{ leaves: { <path>: <value> }, unknown: [ <path> ] }`
 */
export function paths_expand(paths) {
	let leaves = {};
	let unknown = [];
	let want_get = false;
	let expanded = [];

	for (let p in paths)
		push(expanded, ...dm.wildcard_expand(p));

	for (let p in expanded) {
		if (substr(p, -1) == '.') {
			// An object the model does not describe is unknown; one it
			// describes but that holds nothing is an empty answer. The
			// subtree dispatch returns an empty object for both.
			if (!dm.path_known(p)) {
				push(unknown, p);
				continue;
			}
			let subtree = dm.get_subtree_with_state(p);
			if (type(subtree) != 'object') {
				push(unknown, p);
				continue;
			}
			ubbf.tree_leaves(subtree, p, leaves);
			continue;
		}
		leaves[p] = null;
		want_get = true;
	}

	if (want_get)
		dm.params_get(leaves);

	for (let p in expanded) {
		if (substr(p, -1) == '.')
			continue;
		if (leaves[p] == null && !param_schema(p)) {
			delete leaves[p];
			push(unknown, p);
		}
	}

	return { leaves, unknown };
};

export const PATH_NONE = 0;
export const PATH_OBJECT = 1;
export const PATH_PARAM = 2;

/**
 * Reports what the model says a path is.
 *
 * @param {string} path - Resolved path; a trailing dot asks about an object
 * @returns {number} PATH_NONE, PATH_OBJECT or PATH_PARAM
 */
export function path_kind(path) {
	return dm.path_known(path) ?? PATH_NONE;
};

/**
 * Lists the objects and parameters below an object path.
 *
 * @param {string} path - Object path with a trailing dot, or a parameter name
 * @param {boolean} next_level - Only direct children when true
 * @returns {array|null} `[{ path, writable }]`, objects carrying a trailing
 *                       dot, or null when the path does not resolve
 */
export function names_list(path, next_level) {
	// The walk runs in the native module, which already holds the model and
	// the hydrated tree: doing it here means shipping the whole tree into the
	// VM to derive a schema pattern and a writability lookup per row.
	let native = dm.names(path, !!next_level);
	if (native != null)
		return native;

	// The native walk takes object paths only. A.3.2.3 also allows a full
	// parameter name, which answers with that one parameter.
	let info = (substr(path, -1) == '.') ? null : param_schema(path);
	if (!info)
		return null;

	return [ { path, writable: !!info.writable } ];
};

/**
 * Offers a delete to the table handler before the configuration is touched.
 *
 * A table flagged `runtime_instances` shows rows the CPE maintains itself
 * next to the persisted ones (UPnP port mappings and pinholes). Those rows
 * have no configuration to remove; the handler's `del` hook removes them at
 * their source and reports true, and the persisted path is left alone. The
 * hook runs outside the configuration transaction: a later failure in the
 * same batch does not bring such a row back.
 *
 * A hook can also refuse the delete with a negative USP error code, for a
 * row that TR-181 forbids to remove (`StaticUser`, `StaticRole`).
 *
 * @param {string} path - Object path of the instance, with or without dot
 * @returns {number|null} 0 when a handler removed the row, a negative code
 *                        when it refused the delete, null when the persisted
 *                        path has to be deleted
 */
function runtime_del(path) {
	let object_path = rtrim(path, '.');
	let parts = split(object_path, '.');
	let instance = int(parts[-1]);

	if (type(instance) != 'int')
		return null;

	for (let pattern in full_model) {
		let entry = full_model[pattern];

		if (type(entry.del) != 'function' || !ubbf.pattern_matches_path(pattern, object_path))
			continue;

		let rc = entry.del({ path: object_path, instance });
		if (rc == true)
			return 0;
		if (type(rc) == 'int' && rc < 0)
			return rc;

		return null;
	}

	return null;
}

/**
 * Deletes an instance: through the table handler's `del` hook when it takes
 * the row, else from the configuration.
 *
 * @param {string} path - Object path of the instance, with or without dot
 * @returns {number} 0 on success, 1 when the instance does not exist,
 *                   negative on error
 */
export function object_delete(path) {
	return runtime_del(path) ?? dm.object_del(path);
};

/**
 * Tells whether the object of a parameter exists only as a runtime row,
 * one that a get handler makes and nothing stores. params_set() answers
 * such a write like one to an absent instance, but the row is there and
 * read-only.
 *
 * @param {string} param_path - Parameter path of the refused write
 * @returns {boolean} True when the object of the parameter exists
 */
export function runtime_row_exists(param_path) {
	let object_path = substr(param_path, 0, rindex(param_path, '.') + 1);

	return length(dm.get_subtree_with_state(object_path) ?? {}) > 0;
};

/**
 * Applies a list of set/add/del operations as one transaction.
 *
 * Every operation is evaluated and given a result before the outcome is
 * decided, because a caller reporting faults to its own protocol needs all of
 * them: TR-069 A.3.2.1 requires SetParameterValuesFault to name every
 * parameter that failed, not just the first. The transaction is aborted after
 * the loop when any operation failed, so the set still applies atomically.
 *
 * `dm.params_set` is called one path at a time: it reports only the first
 * error across a whole object, which cannot be attributed to an operation.
 *
 * Reasons are protocol-neutral; each front end maps them to its own
 * vocabulary: `value_required`, `unknown`, `readonly`, `invalid_path`,
 * `rejected`, `max_instances`, `not_found`, `unknown_op`, `apply_failed`.
 *
 * @param {array} operations - `[{ op, path, value? }]`
 * @returns {object} `{ success, digest, results }`, each result carrying
 *                   `{ op, path, instance?, success, reason? }`
 */
function operations_run(operations) {
	trans_start();

	let results = [];
	let failed = false;

	for (let op in operations) {
		let result = { op: op.op, path: op.path, success: true };

		if (!op.path) {
			result.success = false;
			result.reason = 'invalid_path';
		} else if (op.op == 'set') {
			let info = param_schema(op.path);
			if (op.value == null) {
				result.success = false;
				result.reason = 'value_required';
			} else if (!info) {
				result.success = false;
				result.reason = 'unknown';
			} else if (!info.writable) {
				result.success = false;
				result.reason = 'readonly';
			} else {
				let rc = dm.params_set({ [op.path]: op.value });
				if (rc < 0) {
					result.success = false;
					if (rc == -1)
						result.reason = 'invalid_path';
					else if (rc == -2)
						result.reason = runtime_row_exists(op.path) ? 'readonly' : 'not_found';
					else if (rc == -4)
						result.reason = 'invalid_value';
					else
						result.reason = 'rejected';
				}
			}
		} else if (op.op == 'add') {
			if (!object_writable(rtrim(op.path, '.'))) {
				result.success = false;
				result.reason = 'invalid_path';
			} else {
				let instance = dm.object_add(op.path);
				if (!instance) {
					result.success = false;
					result.reason = 'max_instances';
				} else {
					result.instance = instance;
				}
			}
		} else if (op.op == 'del') {
			let rc = object_delete(op.path);
			if (rc != 0) {
				result.success = false;
				result.reason = (rc > 0) ? 'not_found' : 'rejected';
			}
		} else {
			result.success = false;
			result.reason = 'unknown_op';
		}

		if (!result.success)
			failed = true;
		push(results, result);
	}

	if (failed) {
		trans_abort();
		return { success: false, digest: dm.get_digest(), results };
	}

	if (trans_commit() < 0) {
		for (let r in results) {
			r.success = false;
			r.reason = 'apply_failed';
		}
		return { success: false, digest: dm.get_digest(), results };
	}

	return { success: true, digest: dm.get_digest(), results };
}

/**
 * Applies set, add and del operations in one transaction.
 *
 * While a USP transaction is open the operations wait at the write gate and
 * `done` gets the outcome.
 *
 * @param {array} operations - `{ op, path, value? }` entries
 * @param {function} done - Called with the outcome of queued operations
 * @returns {object|null} null when queued, else
 *                        `{ success, digest, results }`
 */
export function operations_apply(operations, done) {
	return write_gate.write(() => operations_run(operations), done);
};

module_writer = operations_apply;

let firewall_expiry_timer;

/**
 * Deletes the firewall rules whose ExpiryDate has passed and arms a timer
 * for the next one (TR-181 Firewall.Chain.{i}.Rule.{i}.ExpiryDate).
 */
function firewall_expiry_arm() {
	firewall_expiry_timer?.cancel();
	firewall_expiry_timer = null;

	let now = time();
	let expired = firewall_rules_expired(dm.config(), now);

	// A commit hook runs inside the commit; delete after it ends
	if (length(expired))
		uloop.timer(0, () => {
			let result = operations_apply(map(expired, (path) => ({ op: 'del', path })), () => null);
			if (result && !result.success)
				log_err('firewall: deleting expired rules %J failed', expired);
		});

	// Re-check at least daily, since the wall clock can move (NTP)
	let next = firewall_expiry_next(dm.config(), now);
	if (next != null)
		firewall_expiry_timer = uloop.timer(min(next - now, 86400) * 1000 + 1000, firewall_expiry_arm);
}

on_commit(firewall_expiry_arm);

/**
 * Runs a write that has to see the config it changes as it is when the
 * write runs, such as a check of the digest before `operations_apply()`.
 *
 * @param {function} job - Does the write, returns its result object
 * @param {function} done - Called with the result of a queued write
 * @returns {object|null} The result, or null when the write is queued
 */
export function config_write(job, done) {
	return write_gate.write(job, done);
};

/**
 * Reloads the config from disk and restores the digest to match it.
 *
 * `dm.load()` replaces the config without touching the hash, which leaves
 * `config_persist` comparing against a hash of something else: a later commit
 * that happens to restore the previous content compares equal and is not
 * written, so memory and disk diverge. Every reload has to go through here.
 *
 * @returns {boolean} True when the config was loaded
 */
export function config_reload() {
	if (!dm.config_load(CONFIG_PATH))
		return false;
	commit_hooks_run();
	return true;
};

/**
 * Gets the ACL of a web UI session role. Only an enabled Device.Users.Role
 * has one, so a disabled or deleted role grants nothing even when its file
 * is still installed.
 *
 * @param {string} role - RoleName of the session
 * @returns {object|null} ACL object, or null when the role has none
 */
export function webui_acl_get(role) {
	for (let inst, row in dm.config()?.Device?.Users?.Role ?? {})
		if (row?.RoleName == role && ubbf.to_bool(row?.Enable ?? 'false'))
			return acl_role_load(role);

	return null;
};

/**
 * Gets data for web UI, filtered by the ACL of the session role.
 *
 * @param {string} path - The data model path
 * @param {string} role - RoleName of the session
 * @returns {object|null} ACL-filtered data tree, or null if ACL not found
 */
export function get_webui_data(path, role) {
	let acl = webui_acl_get(role);
	if (!acl)
		return null;

	let data = dm.get_subtree_with_state(path);
	let base_path = path ? path : 'Device';

	if (base_path == 'Device')
		return acl_filter_tree(acl, data?.Device ?? data, 'Device');

	return acl_filter_tree(acl, data, base_path);
};

if (!stat(RUNTIME_DIR))
	mkdir(RUNTIME_DIR);

if (!dm.config_load(CONFIG_PATH))
	die('config.json is required');

/**
 * Builds a callbacks-only view of the data model for offline inspection.
 *
 * @param {object} model - The full data model registration object
 * @returns {object} `{ objects: { <path>: { get: <fn> } } }` for every entry
 *                   that defines a `get` handler
 */
function extract_callbacks(model) {
	let callbacks = { objects: {} };

	for (let path in model) {
		let obj = model[path];
		if (obj.get)
			callbacks.objects[path] = { get: obj.get };
	}

	return callbacks;
}

writefile(RUNTIME_DIR + '/callbacks.json', sprintf('%.J\n', extract_callbacks(full_model)));

orders_compute(dm.config(), null);
dm.names_compute();
firewall_reconcile(full_model, dm.config());
schedule_refs_prune(dm.config());

if (config_persist()) {
	log_info('load: config changed - applying');
	ubus?.call('bbf-device', 'apply', { apply: true });
}

// The config can come from outside the agent: default_config after a factory
// reset, or a file written while it was down. A hook that reconciles the
// system with the config therefore runs once at start-up as well.
commit_hooks_run();
