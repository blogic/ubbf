'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const utils = ubbf_module.utils;

const fs = require('fs');

const schema = ubbf_module.schema;

const BULKDATA_MAX_PROFILES = 5;
const BULKDATA_MIN_REPORTING_INTERVAL = 1;
const STATE_FILE = '/var/run/ubbf-bulkdata/state.json';

// A CWMP image has no USP events, so it cannot push a report as Push!.
const PROTOCOLS = fs.stat('/usr/sbin/cwmpd') ? [ 'HTTP', 'MQTT' ] : [ 'HTTP', 'MQTT', 'USPEventNotif' ];
const ENCODINGS = [ 'JSON', 'CSV' ];
const COMPRESSIONS = [ 'None', 'GZIP' ];
const METHODS = [ 'POST', 'PUT' ];

/**
 * Reads the state the daemon writes, when the daemon still runs.
 *
 * The daemon is not asked over ubus: this handler runs in the agent's
 * thread, and the daemon calls the agent while it collects a report, so
 * each would wait for the other.
 *
 * @returns {object|null} `{ pid, profiles }`, or null without a live daemon
 */
function daemon_state_get() {
	let st;

	try {
		st = json(fs.readfile(STATE_FILE) ?? 'null');
	} catch (e) {
		return null;
	}

	if (type(st?.pid) != 'int' || !fs.stat(sprintf('/proc/%d', st.pid)))
		return null;

	return st;
}

/**
 * Gets the Device.BulkData object data with computed status.
 *
 * @param {object} ctx - Handler context with config and root
 * @returns {object} BulkData object with status and capabilities
 */
function bulkdata_get(ctx) {
	let status = 'Disabled';

	if (ubbf.to_bool(ctx.config?.Enable)) {
		let st = daemon_state_get();
		let failing = filter(values(st?.profiles ?? {}), (p) => p.enable && !p.is_working);

		status = (!st || length(failing)) ? 'Error' : 'Enabled';
	}

	return {
		...ubbf.ctx_config(ctx),
		Status: status,
		MinReportingInterval: sprintf('%d', BULKDATA_MIN_REPORTING_INTERVAL),
		Protocols: join(',', PROTOCOLS),
		EncodingTypes: join(',', ENCODINGS),
		ParameterWildCardSupported: 'true',
		MaxNumberOfProfiles: sprintf('%d', BULKDATA_MAX_PROFILES),
		MaxNumberOfParameterReferences: '-1'
	};
}

/**
 * Gets a BulkData profile instance.
 *
 * @param {object} ctx - Handler context with config
 * @returns {object|null} Profile data or null
 */
function profile_get(ctx) {
	return ctx.config ?? null;
}

/**
 * Set handler for Device.BulkData.Profile.{i}: only the protocols and
 * encodings the daemon implements.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function profile_set(ctx) {
	if (ctx.param == 'Protocol' && index(PROTOCOLS, ctx.value) < 0)
		return -1;

	if (ctx.param == 'EncodingType' && index(ENCODINGS, ctx.value) < 0)
		return -1;

	return 0;
}

/**
 * Gets HTTP transport settings for a BulkData profile.
 *
 * @param {object} ctx - Handler context with config
 * @returns {object|null} HTTP config with supported methods or null
 */
function profile_http_get(ctx) {
	if (!ctx.config)
		return null;

	return {
		...ctx.config,
		CompressionsSupported: join(',', filter(COMPRESSIONS, (c) => c != 'None')),
		MethodsSupported: join(',', METHODS),
		Password: ''
	};
}

/**
 * Set handler for Device.BulkData.Profile.{i}.HTTP. The URL reaches curl,
 * so it must be an HTTP or HTTPS URL. Reports are not kept across a reboot,
 * so PersistAcrossReboot cannot be true.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function profile_http_set(ctx) {
	switch (ctx.param) {
	case 'URL':
		return (ctx.value == '' || match(ctx.value, /^https?:\/\/[^ ]+$/)) ? 0 : -1;
	case 'Compression':
		return (index(COMPRESSIONS, ctx.value) >= 0) ? 0 : -1;
	case 'Method':
		return (index(METHODS, ctx.value) >= 0) ? 0 : -1;
	case 'PersistAcrossReboot':
		return ubbf.to_bool(ctx.value) ? -1 : 0;
	}

	return 0;
}

/**
 * Set handler for Device.BulkData.Profile.{i}.CSVEncoding: one character,
 * and a row separator of one character or CR LF.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function csv_encoding_set(ctx) {
	if (ctx.param == 'RowSeparator')
		return (length(ctx.value) == 1 || ctx.value == '\r\n') ? 0 : -1;

	if (ctx.param == 'FieldSeparator' || ctx.param == 'EscapeCharacter')
		return (length(ctx.value) == 1) ? 0 : -1;

	return 0;
}

/**
 * Set handler for the Reference of a Parameter or RequestURIParameter row:
 * the path, with any instance or wildcard, must be in the supported data
 * model (TR-369 A.1). The rows it names need not exist yet.
 *
 * @param {object} ctx - Set context with param and value
 * @returns {number} 0 to accept, -1 to refuse
 */
function reference_set(ctx) {
	if (ctx.param != 'Reference' || ctx.value == '')
		return 0;

	let path = replace(ctx.value, /\.\*(\.|$)/g, (m, tail) => '.1' + tail);

	return utils.path.path_kind(path) ? 0 : -1;
}

model['Device.BulkData'] = {
	schema: schema('BulkData'),
	get: bulkdata_get
};

model['Device.BulkData.Profile'] = {};

model['Device.BulkData.Profile.{i}'] = {
	schema: schema('Profile'),
	get: profile_get,
	set: profile_set,
	maxInstances: BULKDATA_MAX_PROFILES
};

model['Device.BulkData.Profile.{i}.Parameter'] = {};

model['Device.BulkData.Profile.{i}.Parameter.{i}'] = {
	schema: schema('Profile_Parameter'),
	set: reference_set
};

model['Device.BulkData.Profile.{i}.JSONEncoding'] = {
	schema: schema('Profile_JSONEncoding')
};

model['Device.BulkData.Profile.{i}.CSVEncoding'] = {
	schema: schema('Profile_CSVEncoding'),
	set: csv_encoding_set
};

model['Device.BulkData.Profile.{i}.HTTP'] = {
	schema: schema('Profile_HTTP'),
	get: profile_http_get,
	set: profile_http_set
};

model['Device.BulkData.Profile.{i}.HTTP.RequestURIParameter'] = {};

model['Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}'] = {
	schema: schema('HTTP_RequestURIParameter'),
	set: reference_set
};

model['Device.BulkData.Profile.{i}.MQTT'] = {
	schema: schema('Profile_MQTT')
};
