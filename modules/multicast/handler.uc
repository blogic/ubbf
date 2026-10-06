'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;

const ubus = require('ubus');
const fs = require('fs');

let schemas = {};
include('schema.uc', { schemas });

/**
 * @param {object} ctx - Context with root config
 * @returns {string} Backend name ('igmpproxy' or 'omcproxy')
 */
function backend_get(ctx) {
	return ctx.root?.Device?.X_UBBF?.MulticastProxy?.Backend ?? 'igmpproxy';
}

/**
 * @param {string} backend - Backend name
 * @returns {boolean} Whether the backend process is running
 */
function backend_running(backend) {
	if (backend == 'igmpproxy') {
		let p = fs.popen('pidof igmpproxy');
		if (!p)
			return false;
		let pid = p.read('all');
		p.close();
		return !!trim(pid);
	}

	let status = ubus.call('mcast', 'status', {}) ?? {};
	return !!status.running;
}

/**
 * Retrieves omcproxy statistics via ubus.
 *
 * @returns {object} mcast stats with snooping and group data
 */
function mcast_stats_get() {
	return ubus.call('mcast', 'stats', {}) ?? {};
}

/**
 * @param {object} ctx - Context with config
 * @returns {object} Status parameter
 */
function multicast_proxy_get(ctx) {
	let enabled = ctx.config?.Enable == 'true';

	if (!enabled)
		return { Status: 'Disabled' };

	if (!backend_running(backend_get(ctx)))
		return { Status: 'Error' };

	return { Status: 'Enabled' };
}

/**
 * @param {object} ctx - Context with config and root
 * @returns {object} Status parameter
 */
function proxy_get(ctx) {
	let enabled = ctx.config?.Enable == 'true';

	if (!enabled)
		return { Status: 'Disabled' };

	if (!backend_running(backend_get(ctx)))
		return { Status: 'Error' };

	return { Status: 'Enabled' };
}

/**
 * @param {object} ctx - Context with config and root
 * @returns {object} Status parameter
 */
function proxy_interface_get(ctx) {
	let enabled = ctx.config?.Enable == 'true';

	if (!enabled)
		return { Status: 'Disabled' };

	if (!backend_running(backend_get(ctx)))
		return { Status: 'Down' };

	return { Status: 'Up' };
}

/**
 * @param {object} ctx - Context with config, parent and instance
 * @returns {object|null} Active group data keyed by instance number
 */
function active_group_get(ctx) {
	if (backend_get(ctx) == 'igmpproxy')
		return ctx.instance != null ? null : {};

	let stats = mcast_stats_get();
	let upstream_if = ubbf.interface_to_name(ctx.root, ctx.parent?.UpstreamInterface);
	let result = {};
	let idx = 1;

	for (let entry in stats.snooping ?? []) {
		if (entry.interface != upstream_if)
			continue;

		for (let group in entry.groups ?? []) {
			let client_count = length(group.clients ?? []);

			result[sprintf('%d', idx)] = {
				GroupAddress: group.groupaddr ?? '',
				ClientNumberOfEntries: sprintf('%d', client_count)
			};
			idx++;
		}
	}

	if (ctx.instance != null)
		return result[ctx.instance] ?? null;

	return result;
}

/**
 * @param {object} ctx - Context with config, parent hierarchy and instance
 * @returns {object|null} Client data keyed by instance number
 */
function active_group_client_get(ctx) {
	if (backend_get(ctx) == 'igmpproxy')
		return ctx.instance != null ? null : {};

	let stats = mcast_stats_get();

	let proxy_path = ctx.path;
	let m = match(proxy_path, /Proxy\.(\d+)\.ActiveGroup\.(\d+)/);
	if (!m)
		return null;

	let proxy_inst = m[1];
	let group_inst = int(m[2]);

	let proxy_config = ctx.root?.Device?.X_UBBF?.MulticastProxy?.Proxy?.[proxy_inst];
	let upstream_if = ubbf.interface_to_name(ctx.root, proxy_config?.UpstreamInterface);

	let result = {};
	let group_idx = 1;

	for (let entry in stats.snooping ?? []) {
		if (entry.interface != upstream_if)
			continue;

		for (let group in entry.groups ?? []) {
			if (group_idx != group_inst) {
				group_idx++;
				continue;
			}

			let client_idx = 1;
			for (let client in group.clients ?? []) {
				result[sprintf('%d', client_idx)] = {
					SourceAddress: client.ipaddr ?? '',
					Interface: client.device ?? '',
					Timeout: sprintf('%d', client.timeout ?? 0)
				};
				client_idx++;
			}
			break;
		}
	}

	if (ctx.instance != null)
		return result[ctx.instance] ?? null;

	return result;
}

/**
 * @param {object} ctx - Context with config
 * @returns {object} Status parameter
 */
function snooping_get(ctx) {
	let enabled = ctx.config?.Enable == 'true';
	let mode = ctx.config?.Mode;

	if (!enabled || mode == 'Disabled')
		return { Status: 'Disabled' };

	return { Status: 'Enabled' };
}

model['Device.X_UBBF.MulticastProxy'] = {
	schema: schemas.MulticastProxy,
	get: multicast_proxy_get
};

model['Device.X_UBBF.MulticastProxy.Proxy'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}'] = {
	schema: schemas.Proxy,
	get: proxy_get
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.Interface.{i}'] = {
	schema: schemas.Proxy_Interface,
	get: proxy_interface_get
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}'] = {
	schema: schemas.Proxy_ActiveGroup,
	get: active_group_get
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client'] = {
};

model['Device.X_UBBF.MulticastProxy.Proxy.{i}.ActiveGroup.{i}.Client.{i}'] = {
	schema: schemas.Proxy_ActiveGroup_Client,
	get: active_group_client_get
};

model['Device.X_UBBF.MulticastProxy.Snooping'] = {
};

model['Device.X_UBBF.MulticastProxy.Snooping.{i}'] = {
	schema: schemas.Snooping,
	get: snooping_get
};
