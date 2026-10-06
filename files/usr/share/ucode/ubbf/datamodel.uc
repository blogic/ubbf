'use strict';

import { writefile, readfile, dirname, stat, mkdir, lsdir } from 'fs';
import * as digest from 'digest';
import * as ubus from 'ubus';
import * as schema_utils from 'ubbf.utils.schema';
import { acl_load, acl_filter_tree } from 'ubbf.acl';
import { log_debug, log_info, log_notice, log_warn, log_err, log_exception } from 'ubbf.utils.logging';
import { firewall_reconcile } from 'ubbf.utils.firewall-reconcile';
import { call as cache_call } from 'ubbf.utils.cache';
import { deviceinfo_get } from 'ubbf.utils.deviceinfo';
import { datetime_format } from 'ubbf.utils.helpers';
import { host_path_by_mac } from 'ubbf.utils.hosts';
import { ifstats_get, ifstats_reset } from 'ubbf.utils.ifstats';
import { netifd_status_get } from 'ubbf.utils.netifd';
import { popen_async } from 'ubbf.utils.process';
import { ACTIVE_PROTOCOL } from 'ubbf.utils.protocol';
import { op_trigger_flush, op_trigger_drop } from 'ubbf.utils.cwmp-op-trigger';
import {
	constraints as generated_constraints,
	object_meta as generated_object_meta
} from 'ubbf.schemas.constraints';
import { value_check } from 'ubbf.utils.validate';
import * as ubbf from 'ubbf';

import * as DHCPv4 from 'ubbf.tr181.DHCPv4';
import * as DHCPv6 from 'ubbf.tr181.DHCPv6';
import * as SSH from 'ubbf.tr181.SSH';
import * as IP from 'ubbf.tr181.IP';
import * as Ethernet from 'ubbf.tr181.Ethernet';
import * as Bridging from 'ubbf.tr181.Bridging';
import * as Time from 'ubbf.tr181.Time';
import * as LEDs from 'ubbf.tr181.LEDs';
import * as Hosts from 'ubbf.tr181.Hosts';
import * as Firewall from 'ubbf.tr181.Firewall';
import * as DNS from 'ubbf.tr181.DNS';
import * as NAT from 'ubbf.tr181.NAT';
import * as DeviceInfo from 'ubbf.tr181.DeviceInfo';
import * as Routing from 'ubbf.tr181.Routing';
import * as RouterAdvertisement from 'ubbf.tr181.RouterAdvertisement';
import * as NeighborDiscovery from 'ubbf.tr181.NeighborDiscovery';
import * as WiFi from 'ubbf.tr181.WiFi';
import * as WiFiDataElements from 'ubbf.tr181.WiFiDataElements';
import * as Diagnostics from 'ubbf.tr143.Diagnostics';
import * as IPLayerCapacity from 'ubbf.tr471.IPLayerCapacity';
import * as PacketCapture from 'ubbf.tr181.PacketCapture';
import * as LocalAgent from 'ubbf.tr181.LocalAgent';
import * as LANConfigSecurity from 'ubbf.tr181.LANConfigSecurity';
import * as UserInterface from 'ubbf.tr181.UserInterface';
import * as InterfaceStack from 'ubbf.tr181.InterfaceStack';
import * as USB from 'ubbf.tr181.USB';
import * as IEEE1905 from 'ubbf.tr181.IEEE1905';
import * as QoS from 'ubbf.tr181.QoS';
import * as PPP from 'ubbf.tr181.PPP';
import * as SoftwareModules from 'ubbf.tr181.SoftwareModules';
import * as BulkData from 'ubbf.tr181.BulkData';
import * as DynamicDNS from 'ubbf.tr181.DynamicDNS';
import * as PCP from 'ubbf.tr181.PCP';
import * as Users from 'ubbf.tr181.Users';
import * as Security from 'ubbf.tr181.Security';
import * as UnixDomainSockets from 'ubbf.tr181.UnixDomainSockets';
import * as Syslog from 'ubbf.tr181.Syslog';
import * as Device from 'ubbf.tr181.Device';
import * as ManagementServer from 'ubbf.tr181.ManagementServer';
import * as GatewayInfo from 'ubbf.tr181.GatewayInfo';

const optional_modules = [
	[ '/usr/sbin/umapd', IEEE1905.model, null ],
	[ ['/sbin/uxc', '/usr/bin/lxc-start', '/usr/bin/crun'], SoftwareModules.model, SoftwareModules.operations ],
];

const VALIDATE_ENFORCE = true;

const WEBUI_ACL_PATH = '/etc/ubbf/webui-acl.json';
const CONFIG_PATH = '/etc/ubbf/config.json';
const RUNTIME_DIR = '/tmp/ubbf';
const MODULES_DIR = '/usr/share/ucode/ubbf/modules';

const full_model = {
	...DHCPv4.model,
	...DHCPv6.model,
	...SSH.model,
	...IP.model,
	...Ethernet.model,
	...Bridging.model,
	...Time.model,
	...LEDs.model,
	...Hosts.model,
	...Firewall.model,
	...DNS.model,
	...NAT.model,
	...DeviceInfo.model,
	...Routing.model,
	...RouterAdvertisement.model,
	...NeighborDiscovery.model,
	...WiFi.model,
	...WiFiDataElements.model,
	...Diagnostics.model,
	...IPLayerCapacity.model,
	...PacketCapture.model,
	...LocalAgent.model,
	...LANConfigSecurity.model,
	...UserInterface.model,
	...InterfaceStack.model,
	...USB.model,
	...QoS.model,
	...PPP.model,
	...BulkData.model,
	...DynamicDNS.model,
	...PCP.model,
	...Users.model,
	...Security.model,
	// ...UnixDomainSockets.model,
	...Syslog.model,
	...Device.model,
	...ManagementServer.model,
	...GatewayInfo.model
};

const all_operations = {
	...Diagnostics.operations,
	...IPLayerCapacity.operations,
	...PacketCapture.operations,
	...DNS.operations,
	...DeviceInfo.operations,
	...Device.operations,
	...WiFiDataElements.operations,
	...WiFi.operations,
	...BulkData.operations,
	...DHCPv4.operations,
	...DHCPv6.operations,
	...Ethernet.operations,
	...IP.operations,
	...PPP.operations,
	...Bridging.operations,
	...USB.operations,
	...Users.operations,
	...SSH.operations
};

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
 * Builds the object an out-of-tree handler receives as `ubbf_module`.
 *
 * Everything a handler may use from ubbf is listed here as a literal key. A
 * namespace import cannot be passed through instead: the minifier rewrites
 * export names and the member accesses that use them, so an out-of-tree file
 * written against the real names would find only the mangled ones. Literal
 * object keys survive minification, which is the same reason the render scope
 * in renderer.uc is built this way.
 *
 * @returns {object} `ubbf`, `utils`, and empty `model` and `operations` for
 *   the handler to fill.
 */
function module_api_build() {
	return {
		ubbf,
		utils: {
			cache: { call: cache_call },
			deviceinfo: { deviceinfo_get },
			helpers: { datetime_format },
			hosts: { host_path_by_mac },
			ifstats: { ifstats_get, ifstats_reset },
			logging: { log_debug, log_info, log_notice, log_warn, log_err },
			netifd: { netifd_status_get },
			process: { popen_async },
		},
		model: {},
		operations: {},
	};
}

/**
 * Registers out-of-tree data model modules from MODULES_DIR.
 *
 * Each subdirectory that has one is entered through its `handler.uc`, which is
 * run with `include()` in a scope whose single entry, `ubbf_module`, is the
 * object from `module_api_build()`; the handler adds its entries to that
 * object's `model` and `operations`. A handler may `include()` sibling files
 * to split itself up; a relative include resolves against the handler's own
 * directory.
 *
 * `include()` rather than `require()` because a handler cannot end in a
 * top-level `return`: the minifier parses every file under usr/share/ucode as
 * a module and rejects a bare return, and `include()` is the only loader that
 * takes a scope, so the scope is the only channel that works both ways.
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
 * `export` nor `import`. It must also never import from `ubbf.*` even
 * indirectly: a minified image mangles those export names and the resulting
 * compile error cannot be caught here.
 *
 * Failures are logged and skipped rather than propagated. An uncaught throw at
 * this point aborts `vendor_ucode_init()` and the agent never starts, so one
 * broken third-party module must not be able to take the data model with it.
 *
 * Mutates `full_model` and `all_operations` in place, like
 * `optional_modules_register()` before it, and for the same reason: it has to
 * run before `protocol_filter()`, before `operation_patterns` is built, and
 * before the single `dm.register()`, which replaces the model rather than
 * merging into it.
 */
function external_modules_register() {
	for (let name in sort(lsdir(MODULES_DIR) ?? [])) {
		let handler = MODULES_DIR + '/' + name + '/handler.uc';

		// A module may carry only a render template, for a domain with
		// nothing to publish in the data model. renderer.uc picks that up
		// on its own glob.
		if (!stat(handler))
			continue;

		let api = module_api_build();

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

		log_info('module %s registered', name);
	}
}

external_modules_register();

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
	return proto == 'both' || proto == ACTIVE_PROTOCOL;
}

/**
 * Rebuilds one entry's schema without the members the other protocol owns.
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
		if (member_protocol_ok(value))
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
 * Drops model entries bound to the other management protocol, then projects
 * the surviving entries' schemas.
 *
 * Entries may carry a `protocol` member ('cwmp' or 'usp'); entries
 * without one serve both protocols. Runs after optional module
 * registration so gated entries are filtered too.
 *
 * `all_operations` is deliberately left whole: `bbf-dm operate` is published
 * in both modes and `bbf-cli` reaches it locally, so only the advertised
 * surface is protocol-bound, not the dispatch table.
 */
function protocol_filter() {
	let drop = [];
	for (let path in full_model) {
		let proto = full_model[path].protocol;
		if (proto && proto != ACTIVE_PROTOCOL)
			push(drop, path);
	}
	for (let path in drop)
		delete full_model[path];

	for (let path in full_model)
		entry_project(full_model[path]);
}

protocol_filter();

/**
 * Stamps the generated per-table facts onto the model.
 *
 * A model entry that states one keeps it: the spec describes the standard
 * object, and a handler that synthesises its rows differently is the
 * authority on its own table.
 */
function object_meta_apply() {
	for (let pattern, facts in generated_object_meta) {
		let entry = full_model[pattern];
		if (!entry)
			continue;

		for (let key, value in facts) {
			if (entry[key] == null)
				entry[key] = value;
		}
	}
}

object_meta_apply();

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
let pending_ops = {};
let op_counter = 0;
let in_transaction = false;

dm.register(full_model);
dm.register_operations(all_operations);

InterfaceStack.bind_dm(dm);

/**
 * Populates `Name` properties on instances using model-defined name handlers.
 *
 * Iterates the full model and runs each entry's `name(inst, data)` handler for
 * every instance that matches the entry's pattern. Uses a fixed-point loop so
 * a name handler that depends on a sibling instance's freshly computed name
 * eventually sees it; the loop terminates when a full pass produces no
 * changes.
 *
 * @param {object} data - The data tree to populate names on (mutated in place)
 */
function names_compute(data) {
	let changed = true;
	while (changed) {
		changed = false;
		for (let pattern in full_model) {
			let entry = full_model[pattern];
			if (!entry.name)
				continue;

			let pattern_parts = split(pattern, '.');
			let instance_paths = ubbf.collect_instances_for_pattern(
				pattern_parts, data, 0, '');

			for (let inst_path in instance_paths) {
				let inst = ubbf.navigate_data(data, split(inst_path, '.'));
				if (!inst || inst.Name)
					continue;

				let computed = entry.name(inst, data);
				if (computed) {
					inst.Name = computed;
					changed = true;
				}
			}
		}
	}
}

/**
 * Serialises the current configuration to disk.
 *
 * Always writes the runtime cache at `RUNTIME_DIR/config.json`. Writes the
 * persistent config at `CONFIG_PATH` only when the SHA-256 digest differs from
 * the previously stored digest. On a successful persistent write, updates the
 * stored digest and reloads the runtime tree.
 *
 * @returns {boolean|null} `true` when persistent config was rewritten,
 *                         `false` when content was unchanged,
 *                         `null` when the persistent write failed
 */
function config_persist() {
	let config = dm.config();
	let content = sprintf('%.J\n', config);
	writefile(RUNTIME_DIR + '/config.json', content);

	let new_hash = digest.sha256(content);
	let old_hash = dm.digest();

	if (new_hash == old_hash)
		return false;

	// Atomic write (writes to <path>.tmp, fsyncs, renames). Plain
	// writefile here would open(O_TRUNC) and only then write; if this
	// process is killed in that window the on-disk config.json ends up
	// empty and obuspa crash-loops on next start, at the
	// `die('config.json is required')` of the startup load.
	if (!ubbf.write_file_atomic(CONFIG_PATH, content)) {
		log_err('config_persist: failed to write %s', CONFIG_PATH);
		return null;
	}

	dm.set_digest(new_hash);
	dm.runtime_reload();

	ubus?.event('bbf-dm.digest', { digest: new_hash });

	return true;
}

/**
 * Begins a configuration transaction.
 *
 * Sets the in-transaction flag (so handlers read from the workspace clone)
 * and delegates to `dm.trans_start()` to snapshot the current config into a
 * workspace.
 *
 * @returns {number} Result of `dm.trans_start()`; 0 on success, negative on error
 */
export function trans_start() {
	log_info('transaction: start');
	in_transaction = true;
	return dm.trans_start();
};

// ucode resolves names in textual order, so the hook registry has to precede
// every persist path that runs it.
let commit_hooks = [];

/**
 * Registers a callback to run after the config has been persisted, whether by
 * a transaction, a whole-file apply or a reload of another writer's work.
 *
 * A hook that wants to know what changed compares against its own record: the
 * data model keeps no per-change journal.
 *
 * @param {function} cb - Called with no arguments after each persist
 */
export function on_commit(cb) {
	push(commit_hooks, cb);
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

/**
 * Commits the current configuration transaction.
 *
 * Promotes the workspace to live config, recomputes derived `Name` properties,
 * runs firewall reconciliation, persists the config to disk and triggers a
 * `bbf-device.apply` ubus call when the persisted content changed.
 *
 * @returns {number} 1 when applied successfully,
 *                   0 when committed with no persisted change,
 *                   negative on apply failure or transaction error
 */
export function trans_commit() {
	let rc = dm.trans_commit();
	if (rc <= 0)
		return rc;

	names_compute(dm.config());
	firewall_reconcile(full_model, dm.config());

	in_transaction = false;

	let persisted = config_persist();

	if (persisted) {
		log_info('transaction: commit - applying config');
		let result = ubus?.call('bbf-device', 'apply', { apply: true });
		if (!result?.success) {
			log_err('transaction: apply failed: %s', result?.error ?? 'unknown error');
			for (let entry in (result?.logs ?? []))
				log_err('  [%s] %s', entry.level, entry.msg);
			return -1;
		}
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
	let rc = dm.trans_abort();
	hooks_run(abort_hooks, 'abort hook');
	return rc;
};

/**
 * Loads a configuration JSON file and applies it as the live config.
 *
 * Replaces the current config with the file contents, recomputes derived
 * names, reconciles the firewall and triggers a `bbf-device.apply` ubus call.
 *
 * @param {string} file_path - Absolute path to the JSON config file
 * @returns {object} On success: `{ success: true, output, logs }`.
 *                   On failure: `{ success: false, error, output?, logs? }`
 *                   where `error` is one of `Cannot read file`, `Invalid JSON`,
 *                   `Failed to persist config`, or the apply error string.
 */
export function apply_config(file_path) {
	let new_config_file = readfile(file_path);
	if (!new_config_file)
		return { success: false, error: 'Cannot read file' };

	let new_config = json(new_config_file);
	if (!new_config)
		return { success: false, error: 'Invalid JSON' };

	dm.set_config(new_config);

	names_compute(dm.config());
	firewall_reconcile(full_model, dm.config());

	if (config_persist() == null)
		return { success: false, error: 'Failed to persist config' };

	let result = ubus?.call('bbf-device', 'apply', { apply: true });
	if (!result?.success)
		return { success: false, error: result?.error ?? 'Apply failed', output: result?.output, logs: result?.logs ?? [] };

	commit_hooks_run();

	return { success: true, output: result?.output, logs: result?.logs ?? [] };
};

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
 * @param {string} path - The operation path
 * @param {object} input - Input parameters for the operation
 * @param {string} command_key - Command key for tracking
 * @returns {object|null} Operation result or null on failure
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

	for (let name, rows in containers)
		params[base_path + '.' + name] = rows;

	dm.params_set(params);
	dm.runtime_reload();
}

/**
 * Runs an asynchronous operation.
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
			if (err == 0 && output)
				op_results_store(base_path, output, key_map);
			inner(inst, err, msg, output);
		};
	}

	let owns_trans = false;
	if (found.op.commit) {
		if (!in_transaction) {
			trans_start();
			owns_trans = true;
		}

		let inner = cb;
		cb = (inst, err, msg, output) => {
			if (err == 0)
				trans_commit();
			else
				trans_abort();
			inner(inst, err, msg, output);
		};
	}

	let root = in_transaction ? dm.config() : dm.runtime();
	try {
		if (found.instances != null)
			found.op.handler(input, instance, cb, found.instances, command_key, root);
		else
			found.op.handler(input, instance, cb, command_key, root);
	} catch (e) {
		log_exception(path, e);
		// the in_transaction re-check covers handlers that completed
		// synchronously (cb already committed/aborted) before throwing
		if (owns_trans && in_transaction)
			trans_abort();
		return -USP_ERR_COMMAND_FAILURE;
	}

	return 0;
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
 * @returns {object} On error: `{ error: <string>, path?: <string> }`.
 *                   For sync ops on success: `{ sync: true, output: <result> }`.
 *                   For async ops on success: `{ async: true, op_id: <number> }`.
 */
export function start_operation(path, input, opts) {
	let found = find_operation(path);
	if (!found)
		return { error: 'operation not found', path };

	let op = found.op;

	if (op.type == 'sync') {
		let root = in_transaction ? dm.config() : dm.runtime();
		try {
			let result;
			if (found.instances != null)
				result = op.handler(input, opts?.command_key, found.instances, root);
			else
				result = op.handler(input, opts?.command_key, root);
			if (result == null)
				return { error: 'operation failed' };
			return { sync: true, output: result };
		} catch (e) {
			log_exception(path, e);
			return { error: 'operation failed' };
		}
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


// Declared here and assigned once the model is registered, below: the helpers
// that follow read them, and ucode resolves names in textual order.
export let schema;
export let schema_readable;

/**
 * Converts a resolved path into its schema pattern by replacing
 * instance-number segments with {i}.
 *
 * @param {array} parts - Path segments
 * @returns {string} Key into `schema_readable.objects`
 */
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
	let info = schema_readable.objects[pattern]?.[name];
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

	if (!exists(schema_readable.objects, table))
		return false;

	// A table the CPE maintains itself is readable but not addable.
	return full_model[table]?.addable !== false;
};

/**
 * Flattens a resolved subtree into leaf paths. Keys beginning with a dot are
 * the tree's own metadata, not parameters.
 *
 * @param {object} node - Subtree node
 * @param {string} prefix - Path prefix including the trailing dot
 * @param {object} out - Destination for `<path>: <value>` entries
 */
function tree_leaves(node, prefix, out) {
	for (let key, val in node) {
		if (substr(key, 0, 1) == '.')
			continue;
		let full = prefix + key;
		if (type(val) == 'object')
			tree_leaves(val, full + '.', out);
		else
			out[full] = val;
	}
}

/**
 * Recursively emits every object and parameter below a subtree node.
 *
 * @param {object} node - Subtree node
 * @param {string} prefix - Path prefix including the trailing dot
 * @param {array} out - Destination for `{ path, writable }` entries
 */
/*
 * The schema pattern of the node being walked is carried down rather than
 * rebuilt from each full path: every child of one object shares its parent's
 * pattern, so recomputing it per row turns a tree walk into a split, a join and
 * a test per component for every parameter in the model.
 */
function names_walk(node, prefix, pattern, out) {
	for (let key, val in node) {
		if (substr(key, 0, 1) == '.')
			continue;

		let full = prefix + key;

		if (type(val) != 'object') {
			let info = schema_readable.objects[pattern]?.[key];
			push(out, { path: full, writable: !!info?.writable });
			continue;
		}

		let sub = pattern + '.' + (is_instance(key) ? '{i}' : key);
		push(out, {
			path: full + '.',
			writable: exists(schema_readable.objects, sub + '.{i}')
		});
		names_walk(val, full + '.', sub, out);
	}
}

/**
 * Expands leaf and partial paths into their leaf values.
 *
 * @param {array} paths - Leaf paths, or partial paths with a trailing dot
 * @returns {object} `{ leaves: { <path>: <value> }, unknown: [ <path> ] }`
 */
export function paths_expand(paths) {
	let leaves = {};
	let unknown = [];
	let want_get = false;

	for (let p in paths) {
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
			tree_leaves(subtree, p, leaves);
			continue;
		}
		leaves[p] = null;
		want_get = true;
	}

	if (want_get)
		dm.params_get(leaves);

	for (let p in paths) {
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
/**
 * Reports whether a write should be refused for the value it carries, and
 * logs the reason either way so a constraint the spec states more narrowly
 * than this CPE accepts shows up as a log line rather than a mystery fault.
 *
 * @param {string} path - Parameter being written
 * @param {*} value - Value as written
 * @param {object} info - param_schema() result for the parameter
 * @returns {boolean} True when the write must not proceed
 */
export function value_reject(path, value, info) {
	let why = value_check(info, value);
	if (!why)
		return false;

	log_notice('%s %s = %s: %s', VALIDATE_ENFORCE ? 'rejecting' : 'would reject',
		   path, value, why);

	return VALIDATE_ENFORCE;
};

export function operations_apply(operations) {
	// dm.trans_start() overwrites the single workspace slot, so a write that
	// started one here would discard whatever an async operation has staged
	// in it, and that operation's own commit would then write this one's
	// leftovers.
	if (in_transaction) {
		let busy = [];
		for (let op in operations)
			push(busy, { op: op.op, path: op.path, success: false,
				     reason: 'busy' });
		return { success: false, busy: true, digest: dm.get_digest(),
			 results: busy };
	}

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
			} else if (value_reject(op.path, op.value, info)) {
				result.success = false;
				result.reason = 'invalid_value';
			} else {
				let rc = dm.params_set({ [op.path]: op.value });
				if (rc < 0) {
					result.success = false;
					if (rc == -1)
						result.reason = 'invalid_path';
					else if (rc == -2)
						result.reason = 'not_found';
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
			let rc = dm.object_del(op.path);
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
	if (!dm.load(CONFIG_PATH))
		return false;
	dm.set_digest(digest.sha256(sprintf('%.J\n', dm.config())));
	commit_hooks_run();
	return true;
};

/**
 * Gets data for web UI, filtered by ACL permissions.
 *
 * @param {string} path - The data model path
 * @returns {object|null} ACL-filtered data tree, or null if ACL not found
 */
export function get_webui_data(path) {
	let acl = acl_load(WEBUI_ACL_PATH);
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

if (!dm.load(CONFIG_PATH))
	die('config.json is required');

// Baseline over the canonical serialisation, matching config_persist()'s
// comparison; hashing the raw file bytes instead makes every load look
// changed and forces a persist + apply per DM load (one per CWMP session).
dm.set_digest(digest.sha256(sprintf('%.J\n', dm.config())));

schema = schema_utils.extract(full_model);
schema_readable = schema_utils.extract_readable(full_model, generated_constraints);

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

writefile(RUNTIME_DIR + '/schema.json', sprintf('%.J\n', schema_readable));
writefile(RUNTIME_DIR + '/callbacks.json', sprintf('%.J\n', extract_callbacks(full_model)));

names_compute(dm.config());
firewall_reconcile(full_model, dm.config());

if (config_persist()) {
	log_info('load: config changed - applying');
	ubus?.call('bbf-device', 'apply', { apply: true });
}
