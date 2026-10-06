'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const ubus = require('ubus');
const fs = require('fs');
const multicast_lib = require('multicast');

const schema = ubbf_module.schema;

const IP_INTERFACE_RE = regexp('^Device\\.IP\\.Interface\\.[0-9]+$');
const BRIDGE_RE = regexp('^Device\\.Bridging\\.Bridge\\.[0-9]+$');

/**
 * Tests whether a procd service has a running instance (uncached).
 *
 * @param {string} name - Service name
 * @returns {boolean} True while the service runs
 */
function service_running_fetch(name) {
	let list = ubus.call('service', 'list', { name });

	for (let inst_name, inst in list?.[name]?.instances ?? {})
		if (inst?.running)
			return true;

	return false;
}

/**
 * Tests whether omcproxy runs (cached).
 *
 * @returns {boolean} True while the daemon runs
 */
function backend_running() {
	return utils.cache.call(service_running_fetch, 'omcproxy');
}

/**
 * Reads the bridge multicast database (uncached).
 *
 * @returns {array} MDB entries of all bridges, `bridge -j -s mdb show`
 */
function mdb_fetch() {
	let p = fs.popen('bridge -j -s mdb show 2>/dev/null');
	if (!p)
		return [];

	let data = p.read('all');
	p.close();

	let parsed;
	try {
		parsed = json(data);
	} catch (e) {
		return [];
	}

	let entries = [];
	for (let bridge in (type(parsed) == 'array') ? parsed : [])
		push(entries, ...(bridge?.mdb ?? []));

	return entries;
}

/**
 * Returns the receivers of a group: the bridge ports with a membership.
 *
 * Entries of the bridge itself are the memberships of the device, not of
 * a receiver, and are left out.
 *
 * @param {string} group - Group address
 * @returns {array} MDB entries of the group
 */
function group_clients_get(group) {
	return filter(utils.cache.call(mdb_fetch),
		(e) => e.grp == group && e.port != e.dev);
}

/**
 * Returns the layer 3 device of a Device.IP.Interface reference.
 *
 * @param {object} root - Data model root
 * @param {string} ref - Device.IP.Interface.{i} path
 * @returns {string|null} Netdev name, or null when the reference does not
 *          resolve or the interface is not up
 */
function interface_device_get(root, ref) {
	let name = ubbf.interface_to_name(root, ref);
	if (!name)
		return null;

	let status = utils.netifd.netifd_status_get(name);
	return status?.l3_device ?? status?.device;
}

/**
 * Returns the active IPv4 groups that the proxy forwards from an upstream
 * interface, from the kernel multicast forwarding cache. One row per
 * group; several sources of a group share the row.
 *
 * @param {object} root - Data model root
 * @param {object} proxy - Stored Proxy row
 * @returns {array} Group addresses
 */
function proxy_groups_get(root, proxy) {
	let upstream = interface_device_get(root, proxy?.UpstreamInterface);
	if (!upstream)
		return [];

	let groups = [];
	for (let route in multicast_lib.mr_cache_parse())
		if (route.iif == upstream && index(groups, route.group) < 0)
			push(groups, route.group);

	return groups;
}

/**
 * Tests whether a Proxy row can be rendered: its upstream reference
 * resolves and at least one enabled downstream reference resolves.
 *
 * @param {object} root - Data model root
 * @param {object} proxy - Stored Proxy row
 * @returns {boolean} True when the render writes the row
 */
function proxy_valid(root, proxy) {
	if (!ubbf.interface_to_name(root, proxy?.UpstreamInterface))
		return false;

	for (let inst, iface in proxy?.Interface ?? {}) {
		if (!ubbf.is_instance_key(inst) || !ubbf.to_bool(iface?.Enable))
			continue;
		if (ubbf.interface_to_name(root, iface.Interface))
			return true;
	}

	return false;
}

/**
 * Returns the Status of a Proxy row.
 *
 * @param {object} root - Data model root
 * @param {object} proxy - Stored Proxy row
 * @returns {string} Disabled, Error_Misconfigured, Error or Enabled
 */
function proxy_status(root, proxy) {
	if (!ubbf.to_bool(proxy.Enable))
		return 'Disabled';
	if (!proxy_valid(root, proxy))
		return 'Error_Misconfigured';
	return backend_running() ? 'Enabled' : 'Error';
}

/**
 * Returns the Status of a downstream Interface row.
 *
 * @param {object} root - Data model root
 * @param {object} iface - Stored Interface row
 * @returns {string} Disabled, Error, Down or Up
 */
function proxy_interface_status(root, iface) {
	if (!ubbf.to_bool(iface.Enable))
		return 'Disabled';
	if (!ubbf.interface_to_name(root, iface.Interface))
		return 'Error';
	if (!backend_running() || !interface_device_get(root, iface.Interface))
		return 'Down';
	return 'Up';
}

/**
 * Returns the Status of a Snooping row. The render applies a row only
 * when its Interface names a bridge.
 *
 * @param {object} root - Data model root
 * @param {object} snoop - Stored Snooping row
 * @returns {string} Disabled, Error_Misconfigured or Enabled
 */
function snooping_status(root, snoop) {
	if (!ubbf.to_bool(snoop.Enable) || snoop.Mode == 'Disabled')
		return 'Disabled';
	if (!match(snoop.Interface ?? '', BRIDGE_RE) || !ubbf.get(root, snoop.Interface)?.Name)
		return 'Error_Misconfigured';
	return 'Enabled';
}

/**
 * Get handler for Device.X_UBBF.MulticastProxy.
 *
 * @param {object} ctx - Context with config, schema defaults when nothing
 *        is stored
 * @returns {object} Stored parameters with Status
 */
function multicast_proxy_get(ctx) {
	let status = 'Disabled';
	if (ubbf.to_bool(ctx.config?.Enable))
		status = backend_running() ? 'Enabled' : 'Error';

	return { ...ctx.config, Status: status };
}

/**
 * Get handler for Device.X_UBBF.MulticastProxy.Proxy.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} Stored parameters with Status
 */
function proxy_get(ctx) {
	if (!ctx.config)
		return null;

	return { ...ctx.config, Status: proxy_status(ctx.root, ctx.config) };
}

/**
 * Get handler for Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface.{i}.
 *
 * @param {object} ctx - Context with config, parent and root
 * @returns {object|null} Stored parameters with Status
 */
function proxy_interface_get(ctx) {
	if (!ctx.config)
		return null;

	return { ...ctx.config, Status: proxy_interface_status(ctx.root, ctx.config) };
}

/**
 * Converts one group to its ActiveGroup row.
 *
 * @param {string} group - Group address
 * @returns {object} ActiveGroup parameters
 */
function group_to_object(group) {
	return {
		GroupAddress: group,
		ClientNumberOfEntries: sprintf('%d', length(group_clients_get(group)))
	};
}

/**
 * Converts one MDB entry to its Client row.
 *
 * @param {object} entry - MDB entry
 * @returns {object} Client parameters
 */
function client_to_object(entry) {
	return {
		SourceAddress: entry.src ?? '',
		Interface: entry.port ?? '',
		Timeout: sprintf('%d', int(+trim(entry.timer ?? '0')))
	};
}

/**
 * Get handler for Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.
 *
 * @param {object} ctx - Context with parent Proxy row and instance
 * @returns {object|null} One row or the enumerated rows
 */
function active_group_get(ctx) {
	let groups = proxy_groups_get(ctx.root, ctx.parent);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(groups, group_to_object);

	let group = ubbf.get_by_instance(groups, ctx.instance);
	return group ? group_to_object(group) : null;
}

/**
 * Get handler for
 * Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client.{i}.
 *
 * @param {object} ctx - Context with the ActiveGroup row as parent
 * @returns {object|null} One row or the enumerated rows
 */
function active_group_client_get(ctx) {
	let group = ctx.parent?.GroupAddress;
	let clients = group ? group_clients_get(group) : [];

	if (ctx.instance == null)
		return ubbf.enumerate_instances(clients, client_to_object);

	let client = ubbf.get_by_instance(clients, ctx.instance);
	return client ? client_to_object(client) : null;
}

/**
 * Get handler for Device.X_UBBF.MulticastProxy.Snooping.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} Stored parameters with Status
 */
function snooping_get(ctx) {
	if (!ctx.config)
		return null;

	return { ...ctx.config, Status: snooping_status(ctx.root, ctx.config) };
}

/**
 * Tests a comma-separated list of IPv4 and IPv6 prefixes.
 *
 * @param {string} value - AltNet value
 * @returns {boolean} True when every item is an address with a prefix
 *          length that fits its family
 */
function prefixes_valid(value) {
	for (let item in ubbf.csv_to_list(value)) {
		let parts = split(item, '/');
		let addr = (length(parts) == 2) ? iptoarr(parts[0]) : null;
		if (!addr || !match(parts[1], /^[0-9]+$/))
			return false;
		if (int(parts[1]) > length(addr) * 8)
			return false;
	}

	return true;
}

/**
 * Tests an interface reference: empty, or a path that the pattern accepts.
 *
 * @param {string} value - Reference
 * @param {object} re - Pattern of the accepted paths
 * @returns {boolean} True when the value is acceptable
 */
function reference_valid(value, re) {
	return value == '' || !!match(value, re);
}

/**
 * Set handler for Device.X_UBBF.MulticastProxy.Proxy.{i}.
 *
 * AltNet goes into the omcproxy command line, so it must hold IPv4 or
 * IPv6 prefixes only.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function proxy_set(ctx) {
	if (ctx.param == 'AltNet' && !prefixes_valid(ctx.value))
		return -1;
	if (ctx.param == 'UpstreamInterface' && !reference_valid(ctx.value, IP_INTERFACE_RE))
		return -1;
	return 0;
}

/**
 * Set handler for Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface.{i}.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function proxy_interface_set(ctx) {
	if (ctx.param == 'Interface' && !reference_valid(ctx.value, IP_INTERFACE_RE))
		return -1;
	return 0;
}

/**
 * Set handler for Device.X_UBBF.MulticastProxy.Snooping.{i}.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function snooping_set(ctx) {
	if (ctx.param == 'Interface' && !reference_valid(ctx.value, BRIDGE_RE))
		return -1;
	return 0;
}

model['Device.X_UBBF.MulticastProxy'] = {
	schema: schema('MulticastProxy'),
	get: multicast_proxy_get
};

model['Device.X_UBBF.MulticastProxy.Proxy'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}'] = {
	schema: schema('Proxy'),
	get: proxy_get,
	set: proxy_set
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface.{i}'] = {
	schema: schema('Proxy_Interface'),
	get: proxy_interface_get,
	set: proxy_interface_set
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}'] = {
	schema: schema('Proxy_ActiveGroup'),
	get: active_group_get,
	maxInstances: 0
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client.{i}'] = {
	schema: schema('Proxy_ActiveGroup_Client'),
	get: active_group_client_get,
	maxInstances: 0
};

model['Device.X_UBBF.MulticastProxy.Snooping'] = {
};

model['Device.X_UBBF.MulticastProxy.Snooping.{i}'] = {
	schema: schema('Snooping'),
	get: snooping_get,
	set: snooping_set
};
