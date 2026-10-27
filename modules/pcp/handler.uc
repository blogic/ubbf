'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const on_commit = ubbf_module.on_commit;
const on_abort = ubbf_module.on_abort;
const config_apply = ubbf_module.config_apply;
const cache_call = ubbf_module.ubbf.cache_call;

const fs = require('fs');
const uloop = require('uloop');

const schema = ubbf_module.schema;

const CONFIG_PATH = '/etc/ubbf/config.json';

// ubbf-pcp writes the result of each server and mapping here.
const STATUS_PATH = '/tmp/ubbf/pcp-status.json';

// The lease of each mapping with a Lifetime: when it started and when it
// runs out. /tmp is cleared at boot, so a lease starts again then, which
// the monotonic times need.
const LEASE_DIR = '/tmp/ubbf';
const LEASE_PATH = `${LEASE_DIR}/pcp-leases.json`;

const MAPPING_TABLES = [ 'InboundMapping', 'OutboundMapping' ];

let lease_timers = {};
let lease_renew = {};

/**
 * Reads a JSON file.
 *
 * @param {string} path - File path
 * @returns {*} Parsed value, or null when the file is missing or invalid
 */
function json_load(path) {
	let data = fs.readfile(path);
	if (!data)
		return null;

	try {
		return json(data);
	} catch (e) {
		return null;
	}
}

/**
 * Reads the results of ubbf-pcp (uncached).
 *
 * @returns {object} `{ servers, mappings }` by TR-181 path
 */
function daemon_status_fetch() {
	let status = json_load(STATUS_PATH);
	return {
		servers: status?.servers ?? {},
		mappings: status?.mappings ?? {}
	};
}

/**
 * Reads the results of ubbf-pcp (cached).
 *
 * @returns {object} `{ servers, mappings }` by TR-181 path
 */
function daemon_status_get() {
	return cache_call(daemon_status_fetch);
}

/**
 * Returns the monotonic clock in seconds.
 *
 * @returns {number} Seconds
 */
function mono_now() {
	return clock(true)[0];
}

/**
 * Finds the client and server instance of a server row. The dispatcher
 * passes the parent row as the object of the runtime tree, not a copy.
 *
 * @param {object} root - Runtime tree
 * @param {object} server_row - Server row
 * @returns {object|null} `{ path, client, server }`
 */
function server_locate(root, server_row) {
	for (let ck, client in root?.Device?.PCP?.Client ?? {}) {
		for (let sk, server in client?.Server ?? {}) {
			if (server === server_row)
				return { path: `Device.PCP.Client.${ck}.Server.${sk}`, client, server };
		}
	}
	return null;
}

/**
 * Finds the client instance of a client row.
 *
 * @param {object} root - Runtime tree
 * @param {object} client_row - Client row
 * @returns {string|null} Instance number
 */
function client_locate(root, client_row) {
	for (let ck, client in root?.Device?.PCP?.Client ?? {})
		if (client === client_row)
			return ck;
	return null;
}

/**
 * Tells whether Device.PCP.Enable is true.
 *
 * @param {object} root - Runtime tree
 * @returns {boolean} True when the PCP stack is enabled
 */
function stack_enabled(root) {
	return ubbf.to_bool(root?.Device?.PCP?.Enable);
}

/**
 * Returns the Device.IP.Interface path of a netifd interface name.
 *
 * @param {object} root - Runtime tree
 * @param {string} name - netifd interface name
 * @returns {string} Path, or '' when no row has that Name
 */
function ip_interface_path(root, name) {
	for (let k, iface in root?.Device?.IP?.Interface ?? {})
		if (name && iface?.Name == name)
			return `Device.IP.Interface.${k}`;
	return '';
}

/**
 * Get handler for Device.PCP.
 *
 * @param {object} ctx - Context with config
 * @returns {object} PCP root properties
 */
function pcp_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		SupportedVersions: '0,1,2',
		OptionList: '1,3',
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client))
	};
}

/**
 * Get handler for Device.PCP.Client.{i}.
 *
 * @param {object} ctx - Context with config, instance and root
 * @returns {object|null} Client properties
 */
function client_get(ctx) {
	if (!ctx.config)
		return null;

	let enabled = ubbf.to_bool(ctx.config.Enable);
	let status = !enabled ? 'Disabled' : stack_enabled(ctx.root) ? 'Enabled' : 'StackDisabled';
	let servers = daemon_status_get().servers;
	let wan = '';

	for (let sk in keys(ctx.config.Server ?? {})) {
		wan = ip_interface_path(ctx.root,
			servers[`Device.PCP.Client.${ctx.instance}.Server.${sk}`]?.wan_interface);
		if (wan)
			break;
	}

	return {
		...ubbf.ctx_config(ctx),
		Status: status,
		WANInterface: wan,
		THIRDPARTYStatus: (status == 'Enabled' && ubbf.to_bool(ctx.config.THIRDPARTYEnable))
			? 'Enabled' : 'Disabled',
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config.Server))
	};
}

/**
 * Get handler for Device.PCP.Client.{i}.Server.{i}.
 *
 * @param {object} ctx - Context with config, parent and root
 * @returns {object|null} Server properties
 */
function server_get(ctx) {
	if (!ctx.config)
		return null;

	let ck = client_locate(ctx.root, ctx.parent);
	let path = `Device.PCP.Client.${ck}.Server.${ctx.instance}`;
	let active = stack_enabled(ctx.root) && ubbf.to_bool(ctx.parent?.Enable) &&
		ubbf.to_bool(ctx.config.Enable ?? 'true');
	let st = active ? daemon_status_get().servers[path] : null;

	return {
		...ubbf.ctx_config(ctx),
		Status: active ? (st?.status ?? 'Connecting') : 'Disabled',
		ServerAddressInUse: st?.address ?? '',
		AdditionalServerAddresses: st?.additional ?? '',
		ExternalIPAddress: st?.external_ip ?? '',
		CurrentVersion: sprintf('%d', st?.version ?? 0),
		InboundMappingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config.InboundMapping)),
		OutboundMappingNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config.OutboundMapping))
	};
}

/**
 * Returns the remaining Lifetime of a mapping row, as TR-181 defines it:
 * the requested Lifetime counts down from the time the row became active.
 *
 * @param {string} path - Row path
 * @param {object} row - Mapping row
 * @returns {string} Seconds
 */
function lifetime_remaining(path, row) {
	let lease = json_load(LEASE_PATH)?.[path];
	if (!lease?.deadline)
		return row.Lifetime ?? '0';
	return sprintf('%d', max(lease.deadline - mono_now(), 0));
}

/**
 * Returns the get handler of InboundMapping.{i} or OutboundMapping.{i}.
 *
 * @param {string} table - Table name below the server
 * @returns {function} Get handler
 */
function mapping_get_handler(table) {
	return (ctx) => {
		if (!ctx.config)
			return null;

		let srv = server_locate(ctx.root, ctx.parent);
		let path = `${srv?.path}.${table}.${ctx.instance}`;
		let active = srv && stack_enabled(ctx.root) && ubbf.to_bool(srv.client?.Enable) &&
			ubbf.to_bool(srv.server?.Enable ?? 'true') && ubbf.to_bool(ctx.config.Enable);
		let st = active ? daemon_status_get().mappings[path] : null;
		let result = {
			...ubbf.ctx_config(ctx),
			Status: active ? (st?.status ?? 'Error') : 'Disabled',
			ErrorCode: sprintf('%d', st?.error_code ?? 0),
			AssignedExternalIPAddress: st?.external_ip ?? '',
			AssignedExternalPort: sprintf('%d', st?.external_port ?? 0),
			Lifetime: active ? lifetime_remaining(path, ctx.config) : (ctx.config.Lifetime ?? '0')
		};

		if (table == 'InboundMapping') {
			result.AssignedExternalPortEndRange = '0';
			result.FilterNumberOfEntries = sprintf('%d', ubbf.instance_count(ctx.config.Filter));
		}

		return result;
	};
}

/**
 * Set handler of the mapping tables: a write of Lifetime starts the lease
 * again, also with the same value, so the commit hook is told.
 *
 * @param {object} ctx - Context with path and param
 * @returns {number} 0
 */
function mapping_set(ctx) {
	if (ctx.param == 'Lifetime')
		lease_renew[replace(ctx.path, /\.Lifetime$/, '')] = true;
	return 0;
}

/**
 * Deletes a mapping row whose Lifetime ran out (TR-181: "the CPE MUST
 * automatically delete the corresponding table entry").
 *
 * @param {string} path - Row path
 */
function lease_expire(path) {
	let report = (result) => {
		if (result?.success)
			ubbf.log_info('pcp: %s deleted, its Lifetime ran out', path);
		else
			ubbf.log_err('pcp: failed to delete %s', path);
	};
	let result = config_apply([ { op: 'del', path } ], report);
	if (result)
		report(result);
}

/**
 * Arms the expiry timer of one lease.
 *
 * @param {string} path - Row path
 * @param {number} delay - Milliseconds until the lease runs out
 */
function lease_timer_add(path, delay) {
	lease_timers[path] = uloop.timer(delay, () => {
		delete lease_timers[path];
		try {
			lease_expire(path);
		} catch (e) {
			ubbf.log_exception('pcp: lease', e);
		}
	});
}

/**
 * Collects the active mapping rows with a Lifetime from the stored
 * configuration.
 *
 * @param {object} cfg - Stored configuration
 * @returns {object} Lifetime in seconds by row path
 */
function leases_wanted(cfg) {
	let wanted = {};
	let pcp = cfg?.Device?.PCP;

	if (!ubbf.to_bool(pcp?.Enable))
		return wanted;

	for (let ck, client in pcp.Client ?? {}) {
		if (!ubbf.to_bool(client?.Enable))
			continue;

		for (let sk, server in client.Server ?? {}) {
			if (!ubbf.to_bool(server?.Enable ?? 'true'))
				continue;

			for (let table in MAPPING_TABLES) {
				for (let mk, m in server[table] ?? {}) {
					let lifetime = ubbf.to_int(m?.Lifetime) ?? 0;
					if (ubbf.to_bool(m?.Enable) && lifetime > 0)
						wanted[`Device.PCP.Client.${ck}.Server.${sk}.${table}.${mk}`] = lifetime;
				}
			}
		}
	}

	return wanted;
}

/**
 * Commit hook: starts the lease of each mapping that became active or got
 * a new Lifetime, drops the others, and arms one timer per lease. A lease
 * that ran out expires on the next turn of the event loop, never inside
 * the hook.
 */
function leases_sync() {
	let prev = json_load(LEASE_PATH) ?? {};
	let now = mono_now();
	let leases = {};

	for (let path, lifetime in leases_wanted(json_load(CONFIG_PATH))) {
		let old = prev[path];
		leases[path] = (old && old.lifetime == lifetime && !lease_renew[path])
			? old : { lifetime, deadline: now + lifetime };
	}

	lease_renew = {};

	if (sprintf('%J', leases) != sprintf('%J', prev)) {
		fs.mkdir(LEASE_DIR, 0755);
		if (!fs.writefile(LEASE_PATH, sprintf('%J\n', leases)))
			ubbf.log_err('pcp: failed to write %s', LEASE_PATH);
	}

	for (let path, timer in lease_timers)
		timer.cancel();
	lease_timers = {};

	for (let path, lease in leases)
		lease_timer_add(path, max(lease.deadline - now, 0) * 1000);
}

model['Device.PCP'] = {
	schema: schema('PCP'),
	get: pcp_get
};

model['Device.PCP.Client'] = {};

model['Device.PCP.Client.{i}'] = {
	schema: schema('Client'),
	get: client_get
};

model['Device.PCP.Client.{i}.Server'] = {};

model['Device.PCP.Client.{i}.Server.{i}'] = {
	schema: schema('Client_Server'),
	get: server_get
};

model['Device.PCP.Client.{i}.Server.{i}.InboundMapping'] = {};

model['Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}'] = {
	schema: schema('Server_InboundMapping'),
	get: mapping_get_handler('InboundMapping'),
	set: mapping_set
};

model['Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.Filter'] = {};

model['Device.PCP.Client.{i}.Server.{i}.InboundMapping.{i}.Filter.{i}'] = {
	schema: schema('InboundMapping_Filter')
};

model['Device.PCP.Client.{i}.Server.{i}.OutboundMapping'] = {};

model['Device.PCP.Client.{i}.Server.{i}.OutboundMapping.{i}'] = {
	schema: schema('Server_OutboundMapping'),
	get: mapping_get_handler('OutboundMapping'),
	set: mapping_set
};

on_commit(leases_sync);
on_abort(() => {
	lease_renew = {};
});
