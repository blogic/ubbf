'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;

const ubus = require('ubus');

let schemas = {};
include('schema.uc', { schemas });

/**
 * Fetches discovered mDNS services from umdns.
 *
 * @returns {array} Array of service objects with TR-181 fields
 */
function umdns_services_get() {
	let browse = ubus?.call('umdns', 'browse', {});
	if (!browse)
		return [];

	let services = [];
	for (let svc_type, instances in browse) {
		// DNS-SD "_http._tcp" to the TR-181 forms "http" and "TCP".
		let m = match(svc_type, /^_([^.]+)\._([^.]+)$/);
		let app_proto = m ? m[1] : svc_type;
		let trans_proto = m ? uc(m[2]) : '';

		if (type(instances) != 'object')
			continue;

		for (let inst_name, inst in instances) {
			let txt_records = {};
			let txt_idx = 1;
			if (type(inst.txt) == 'string' && inst.txt != '') {
				let eq = index(inst.txt, '=');
				if (eq > 0) {
					txt_records[sprintf('%d', txt_idx)] = {
						Key: substr(inst.txt, 0, eq),
						Value: substr(inst.txt, eq + 1)
					};
					txt_idx++;
				}
			} else if (type(inst.txt) == 'array') {
				for (let entry in inst.txt) {
					let eq = index(entry, '=');
					if (eq > 0) {
						txt_records[sprintf('%d', txt_idx)] = {
							Key: substr(entry, 0, eq),
							Value: substr(entry, eq + 1)
						};
						txt_idx++;
					}
				}
			}

			push(services, {
				...schemas.SD_Service.defaults,
				InstanceName: inst_name,
				ApplicationProtocol: app_proto,
				TransportProtocol: trans_proto,
				Domain: inst.domain ?? 'local',
				Port: sprintf('%d', inst.port ?? 0),
				Host: inst.host ?? '',
				Target: inst.host ?? '',
				TimeToLive: sprintf('%d', inst.ttl ?? 0),
				Status: 'Enabled',
				TextRecordNumberOfEntries: sprintf('%d', txt_idx - 1),
				TextRecord: txt_records
			});
		}
	}

	return services;
}

/**
 * Get handler for Device.DNS.SD.
 *
 * @param {object} ctx - Context with config
 * @returns {object} SD properties with instance counts
 */
function sd_get(ctx) {
	let umdns_reachable = (ubus?.call('umdns', 'browse', {}) != null);
	let enabled = ubbf.to_bool(ctx.config?.Enable);
	let status;
	if (!enabled)
		status = 'Disabled';
	else if (umdns_reachable)
		status = 'Enabled';
	else
		status = 'Error';

	return {
		...ubbf.ctx_config(ctx),
		Status: status,
		AdvertiseNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Advertise)),
		ServiceNumberOfEntries: sprintf('%d', length(umdns_services_get()))
	};
}

/**
 * Get handler for Device.DNS.SD.Advertise.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Advertise entry with computed fields
 */
function sd_advertise_get(ctx) {
	let sd_enabled = ubbf.to_bool(ctx.parent?.Enable);
	let enabled = ubbf.to_bool(ctx.config?.Enable);

	let status = 'Disabled';
	if (enabled && sd_enabled) {
		let announcements = ubus?.call('umdns', 'announcements', {});
		let instance_name = ctx.config?.InstanceName || `service_${ctx.instance}`;
		let svc_key = replace(lc(instance_name), /[^a-z0-9_]/g, '_');
		if (announcements?.[svc_key])
			status = 'Enabled';
	}

	return {
		...ubbf.ctx_config(ctx),
		Status: status,
		TextRecordNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.TextRecord))
	};
}

/**
 * Get handler for Device.DNS.SD.Service.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object|null} Discovered service entry or enumerated entries
 */
function sd_service_get(ctx) {
	let services = umdns_services_get();

	if (ctx.instance != null) {
		let idx = ctx.instance - 1;
		if (idx >= 0 && idx < length(services))
			return services[idx];
		return null;
	}

	return ubbf.enumerate_instances(services, (s) => s);
}

/**
 * Firewall hook for Device.DNS.SD.
 * Declares UDP/5353 Service for each downstream interface.
 *
 * @param {object} inst - DNS.SD config object
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptors for mDNS
 */
function dns_sd_firewall(inst, root, path) {
	if (inst.Enable != 'true')
		return null;

	let ip_ifaces = ubbf.get(root, 'Device.IP.Interface');
	if (type(ip_ifaces) != 'object')
		return null;

	let descriptors = [];

	for (let key, iface in ip_ifaces) {
		if (type(iface) != 'object')
			continue;
		if (!ubbf.to_bool(iface.Enable))
			continue;
		if (ubbf.to_bool(iface.Upstream))
			continue;
		if (!iface.Name)
			continue;

		push(descriptors, {
			type: 'Service',
			alias: sprintf('cpe-mdns-%s', iface.Name),
			Interface: sprintf('Device.IP.Interface.%s', key),
			Protocol: 'udp',
			DestPort: '5353',
			Action: 'Accept'
		});
	}

	return length(descriptors) > 0 ? descriptors : null;
}

model['Device.DNS.SD'] = {
	schema: schemas.SD,
	get: sd_get,
	firewall: dns_sd_firewall
};

model['Device.DNS.SD.Advertise'] = {
};

model['Device.DNS.SD.Advertise.{i}'] = {
	schema: schemas.SD_Advertise,
	get: sd_advertise_get
};

model['Device.DNS.SD.Advertise.{i}.TextRecord'] = {
};

model['Device.DNS.SD.Advertise.{i}.TextRecord.{i}'] = {
	schema: schemas.Advertise_TextRecord
};

model['Device.DNS.SD.Service'] = {
};

model['Device.DNS.SD.Service.{i}'] = {
	schema: schemas.SD_Service,
	get: sd_service_get
};

model['Device.DNS.SD.Service.{i}.TextRecord'] = {
};

model['Device.DNS.SD.Service.{i}.TextRecord.{i}'] = {
	schema: schemas.Service_TextRecord
};
