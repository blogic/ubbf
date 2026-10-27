'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;

const fs = require('fs');

const schema = ubbf_module.schema;

const ddns = {};

include(sourcepath(0, true) + '/common.uc', {
	ubbf,
	dm_visible: utils['dm-version'].dm_visible,
	upstream_interface_ref: ubbf.upstream_interface_ref,
	ddns
});

// ddns-scripts reads a provider from the custom directory first.
const DDNS_SERVICES_DIRS = [ '/usr/share/ddns/custom', '/usr/share/ddns/default' ];
const DDNS_RUN_DIR = '/var/run/ddns';
const DDNS_LOG_DIR = '/var/log/ddns';

// The generic service: the module builds the /nic/update URL of
// ServerAddress and ServerPort itself.
const GENERIC_SERVICE = 'dyndns2';
const SUPPORTED_PROTOCOLS = [ 'HTTP', 'HTTPS' ];
const SUPPORTED_SERVICES_MAX = 1024;

// The last log line of ddns-scripts that tells the outcome, newest first,
// and the TR-181 LastError of each failure.
const LOG_OUTCOMES = [
	[ /Update successful|Forced update successful|Rerun IP check/, null ],
	[ /No or private or invalid IP|No update send/, 'MISCONFIGURATION_ERROR' ],
	[ /IP update not accepted|Updating IP at DDNS provider failed/, 'PROTOCOL_ERROR' ],
	[ /Error: '28'/, 'TIMEOUT_ERROR' ],
	[ /Transfer failed|Error: '[0-9]+'/, 'CONNECTION_ERROR' ],
	[ /DNS server|DNS Resolver|resolve/, 'DNS_ERROR' ],
	[ /Can not detect current IP|Failed to detect IP|TERMINATE/, 'MISCONFIGURATION_ERROR' ]
];

/**
 * Lists the provider names of ddns-scripts plus the generic service.
 *
 * @returns {string[]} Sorted service names
 */
function services_list() {
	let names = [ GENERIC_SERVICE ];

	for (let dir in DDNS_SERVICES_DIRS)
		for (let file in fs.glob(dir + '/*.json') ?? []) {
			let m = match(file, /\/([^\/]+)\.json$/);
			if (m && index(names, m[1]) < 0)
				push(names, m[1]);
		}

	return sort(names);
}

/**
 * SupportedServices: the services, cut to whole names within the 1024
 * characters TR-181 allows.
 *
 * @returns {string} Comma-separated list
 */
function supported_services_get() {
	let list = '';

	for (let name in services_list()) {
		let next = list ? list + ',' + name : name;
		if (length(next) > SUPPORTED_SERVICES_MAX)
			break;
		list = next;
	}

	return list;
}

/**
 * Host and port of the update URL of a named provider.
 *
 * @param {string} service - Provider name
 * @param {string} protocol - HTTP or HTTPS
 * @returns {object} { host, port }, empty strings when unknown
 */
function provider_address(service, protocol) {
	for (let dir in DDNS_SERVICES_DIRS) {
		let data = fs.readfile(`${dir}/${service}.json`);
		if (!data)
			continue;

		let url;
		try {
			url = json(data)?.ipv4?.url ?? '';
		} catch (e) {
			return { host: '', port: '' };
		}

		let m = match(url, /^https?:\/\/([^\/@]*@)?(\[[^\]]+\]|[^\/:]+)(:([0-9]+))?/);
		if (!m)
			return { host: '', port: '' };

		return { host: trim(m[2], '[]'), port: m[4] ?? ((protocol == 'HTTP') ? '80' : '443') };
	}

	return { host: '', port: '' };
}

/**
 * Get handler for Device.DynamicDNS.
 *
 * @param {object} ctx - Context with config
 * @returns {object} DynamicDNS properties with instance counts
 */
function dynamicdns_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		ClientNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Client)),
		ServerNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Server)),
		SupportedServices: supported_services_get()
	};
}

/**
 * Get handler for Device.DynamicDNS.Server.{i}. A named provider has its
 * own update URL, so ServerAddress and ServerPort report its host; the
 * generic service uses the stored values.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Server row
 */
function server_get(ctx) {
	let row = {
		...ubbf.ctx_config(ctx),
		Protocol: ctx.config?.Protocol || 'HTTPS',
		SupportedProtocols: join(',', SUPPORTED_PROTOCOLS)
	};

	if (!row.ServiceName || row.ServiceName == GENERIC_SERVICE)
		return row;

	let addr = provider_address(row.ServiceName, row.Protocol);

	return { ...row, ServerAddress: addr.host, ServerPort: addr.port || '0' };
}

/**
 * Set handler for Device.DynamicDNS.Server.{i}: ServiceName must be one of
 * SupportedServices and ServerAddress a host name or an IP address. The
 * schema enumerates Protocol.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function server_set(ctx) {
	let ok = true;

	if (ctx.param == 'ServiceName')
		ok = ctx.value == '' || index(services_list(), ctx.value) >= 0;
	else if (ctx.param == 'ServerAddress')
		ok = ddns.server_address_valid(ctx.value);

	if (ok)
		return 0;

	ubbf.log_warn('DynamicDNS.Server.%s.%s: value refused', ctx.instance, ctx.param);
	return -USP_ERR_INVALID_VALUE;
}

/**
 * Seconds since boot.
 *
 * @returns {number|null} Uptime, null when unknown
 */
function uptime_get() {
	let m = match(fs.readfile('/proc/uptime') ?? '', /^([0-9]+)/);
	return m ? +m[1] : null;
}

/**
 * Tells whether the updater of a section runs.
 *
 * @param {string} section - ddns-scripts section name
 * @returns {boolean} true while its process exists
 */
function updater_running(section) {
	let pid = trim(fs.readfile(`${DDNS_RUN_DIR}/${section}.pid`) ?? '');
	return match(pid, /^[0-9]+$/) != null && fs.stat(`/proc/${pid}`) != null;
}

/**
 * Reads the outcome of a section from the files of ddns-scripts.
 *
 * @param {string} section - ddns-scripts section name
 * @returns {object} { state: 'Updated'|'Updating'|'Error', error, updated }
 *   with `updated` the uptime of the last accepted update
 */
function section_state(section) {
	let updated = +trim(fs.readfile(`${DDNS_RUN_DIR}/${section}.update`) ?? '') || null;
	let lines = split(fs.readfile(`${DDNS_LOG_DIR}/${section}.log`) ?? '', '\n');

	for (let i = length(lines) - 1; i >= 0; i--) {
		for (let outcome in LOG_OUTCOMES) {
			if (!match(lines[i], outcome[0]))
				continue;

			if (!outcome[1])
				return { state: 'Updated', updated };

			let answer = fs.readfile(`${DDNS_RUN_DIR}/${section}.dat`) ?? '';
			let error = (outcome[1] == 'PROTOCOL_ERROR' && match(answer, /badauth|401|unauthori/i))
				? 'AUTHENTICATION_ERROR' : outcome[1];

			return { state: 'Error', error, updated };
		}
	}

	return { state: updater_running(section) ? 'Updating' : 'Error', error: 'MISCONFIGURATION_ERROR', updated };
}

/**
 * The sections of the enabled hostnames of a client.
 *
 * @param {object} root - Configuration root
 * @param {object} client - Client row
 * @param {*} instance - Client instance number
 * @returns {object} Hostname instance to array of section names
 */
function client_sections(root, client, instance) {
	let targets = ddns.client_networks(root, client);
	let both = length(targets) > 1;
	let result = {};

	for (let h, hostname in client.Hostname ?? {}) {
		if (type(hostname) != 'object' || !ubbf.to_bool(hostname.Enable) || !hostname.Name)
			continue;

		result[h] = map(targets, (t) => ddns.section_name(instance, h, t.family, both));
	}

	return result;
}

/**
 * Tells why a client cannot run, as TR-181 Error_Misconfigured.
 *
 * @param {object} root - Configuration root
 * @param {object} client - Client row
 * @returns {boolean} true when the server, the service, the hostnames or
 *   the addresses do not allow an update
 */
function client_misconfigured(root, client) {
	let server = client.Server ? ubbf.navigate_data(root, ubbf.path_to_parts(rtrim(client.Server, '.'))) : null;

	if (!server || !ubbf.to_bool(server.Enable) || !server.ServiceName)
		return true;
	if (server.ServiceName == GENERIC_SERVICE && !server.ServerAddress)
		return true;

	return !length(ddns.client_networks(root, client));
}

/**
 * Status and LastError of a client: Disabled, Error_Misconfigured, Error
 * when a section failed, Updated when every section updated, else
 * Connecting.
 *
 * @param {object} root - Configuration root
 * @param {object} client - Client row
 * @param {*} instance - Client instance number
 * @returns {object} { Status, LastError }
 */
function client_status(root, client, instance) {
	if (!ubbf.to_bool(client.Enable))
		return { Status: 'Disabled', LastError: 'NO_ERROR' };

	let sections = client_sections(root, client, instance);
	if (client_misconfigured(root, client) || !length(sections))
		return { Status: 'Error_Misconfigured', LastError: 'MISCONFIGURATION_ERROR' };

	let all_updated = true;

	for (let h, names in sections)
		for (let section in names) {
			let st = section_state(section);
			if (st.state == 'Error')
				return { Status: 'Error', LastError: st.error };
			if (st.state != 'Updated')
				all_updated = false;
		}

	return { Status: all_updated ? 'Updated' : 'Connecting', LastError: 'NO_ERROR' };
}

/**
 * Get handler for Device.DynamicDNS.Client.{i}.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Client properties with hostname count and status
 */
function client_get(ctx) {
	return {
		...ubbf.ctx_config(ctx),
		...client_status(ctx.root, ctx.config ?? {}, ctx.instance),
		HostnameNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Hostname)),
		Password: ''
	};
}

/**
 * Set handler for Device.DynamicDNS.Client.{i}: Server must name a Server
 * row and Interface an IP.Interface.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function client_set(ctx) {
	if (ctx.param == 'Server' && !ddns.server_ref_valid(ctx.value))
		return -USP_ERR_INVALID_VALUE;
	if (ctx.param == 'Interface' && !ddns.interface_ref_valid(ctx.value))
		return -USP_ERR_INVALID_VALUE;

	return 0;
}

/**
 * Instance number of a client row. The dispatcher hands the parent row
 * from the same tree as the root, without its number.
 *
 * @param {object} root - Configuration root
 * @param {object} client - Client row
 * @returns {string|null} Instance number
 */
function client_instance_of(root, client) {
	for (let n, row in root?.Device?.DynamicDNS?.Client ?? {})
		if (row === client)
			return n;

	return null;
}

/**
 * Get handler for Device.DynamicDNS.Client.{i}.Hostname.{i}.
 *
 * @param {object} ctx - Context with config, parent client and instance
 * @returns {object} Hostname row with Status and LastUpdate
 */
function hostname_get(ctx) {
	let row = ubbf.ctx_config(ctx);
	let client = ctx.parent ?? {};

	if (!ubbf.to_bool(row.Enable) || !ubbf.to_bool(client.Enable))
		return { ...row, Status: 'Disabled', LastUpdate: ubbf.datetime_format(0) };

	let client_instance = client_instance_of(ctx.root, client);
	let sections = client_sections(ctx.root, client, client_instance)[ctx.instance] ?? [];
	let status = length(sections) ? 'Registered' : 'UpdateNeeded';
	let updated = null;

	for (let section in sections) {
		let st = section_state(section);
		if (st.state == 'Error')
			status = 'Error';
		else if (st.state != 'Updated' && status != 'Error')
			status = 'Updating';
		if (st.updated != null)
			updated = max(updated ?? 0, st.updated);
	}

	let uptime = uptime_get();
	let last = (updated != null && uptime != null) ? time() - (uptime - updated) : 0;

	return { ...row, Status: status, LastUpdate: ubbf.datetime_format(last) };
}

/**
 * Set handler for Device.DynamicDNS.Client.{i}.Hostname.{i}: Name must be
 * a host name.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function hostname_set(ctx) {
	if (ctx.param == 'Name' && ctx.value != '' && !ddns.hostname_valid(ctx.value))
		return -USP_ERR_INVALID_VALUE;

	return 0;
}

model['Device.DynamicDNS'] = {
	schema: schema('DynamicDNS'),
	get: dynamicdns_get
};

model['Device.DynamicDNS.Client'] = {};

model['Device.DynamicDNS.Client.{i}'] = {
	schema: schema('Client'),
	get: client_get,
	set: client_set
};

model['Device.DynamicDNS.Client.{i}.Hostname'] = {};

model['Device.DynamicDNS.Client.{i}.Hostname.{i}'] = {
	schema: schema('Client_Hostname'),
	get: hostname_get,
	set: hostname_set
};

model['Device.DynamicDNS.Server'] = {};

model['Device.DynamicDNS.Server.{i}'] = {
	schema: schema('Server'),
	get: server_get,
	set: server_set
};
