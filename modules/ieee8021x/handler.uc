'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.
//
// The ubbf-device plugin of this module runs wpa_supplicant and hostapd;
// this file reads their state and passes the commands on.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const schema = ubbf_module.schema;
const schema_defaults = ubbf_module.schema_defaults;
const cache_call = ubbf_module.utils.cache.call;
const cache_invalidate = ubbf_module.utils.cache.invalidate;
const logging = ubbf_module.utils.logging;
const instance_map = ubbf_module.utils['instance-map'];

const ubus = require('ubus');

let certificates = {};
include('../security/certificates.uc', { certificates });

let ieee8021x = {};
include('shared.uc', { ieee8021x, certificates });

const PAE_STATES = {
	DISCONNECTED: 'Disconnected',
	LOGOFF: 'Logoff',
	CONNECTING: 'Connecting',
	AUTHENTICATING: 'Authenticating',
	AUTHENTICATED: 'Authenticated',
	HELD: 'Held',
	RESTART: 'Restart'
};

const STATS_MIB = {
	ReceivedFrames: 'dot1xSuppEapolFramesRx',
	TransmittedFrames: 'dot1xSuppEapolFramesTx',
	TransmittedStartFrames: 'dot1xSuppEapolStartFramesTx',
	TransmittedLogoffFrames: 'dot1xSuppEapolLogoffFramesTx',
	TransmittedResponseFrames: 'dot1xSuppEapolRespFramesTx',
	ReceivedRequestIdFrames: 'dot1xSuppEapolReqIdFramesRx',
	ReceivedRequestFrames: 'dot1xSuppEapolReqFramesRx',
	ReceivedInvalidFrames: 'dot1xSuppInvalidEapolFramesRx',
	ReceivedLengthErrorFrames: 'dot1xSuppEapLengthErrorFramesRx'
};

const CAPABILITIES = { MD5: 'EAP-MD5', TLS: 'EAP-TLS' };

/**
 * Fetches the EAPOL state of a wpa_supplicant interface (uncached).
 *
 * @param {string} netdev - Netdev the supplicant runs on
 * @returns {object|null} Reply of eapol_status, or null without a supplicant
 */
function eapol_status_fetch(netdev) {
	return ubus.call(`wpa_supplicant.${netdev}`, 'eapol_status', {});
}

/**
 * Gets the EAPOL state of a wpa_supplicant interface (cached).
 *
 * @param {string} netdev - Netdev the supplicant runs on
 * @returns {object|null} Reply of eapol_status, or null without a supplicant
 */
function eapol_status_get(netdev) {
	return cache_call(eapol_status_fetch, netdev);
}

/**
 * Sends a control interface command to the supplicant of a netdev.
 *
 * @param {string} netdev - Netdev the supplicant runs on
 * @param {string} command - Command, for example "LOGOFF"
 * @returns {boolean} True when wpa_supplicant answered OK
 */
function supplicant_command(netdev, command) {
	let reply = ubus.call(`wpa_supplicant.${netdev}`, 'control', { command });
	cache_invalidate(eapol_status_fetch);
	return trim(reply?.result ?? '') == 'OK';
}

/**
 * Lists the EAP methods of TR-181 that the wpa_supplicant build has.
 *
 * @param {string} netdev - Netdev of a running supplicant
 * @returns {string} Comma-separated AuthenticationCapabilities
 */
function capabilities_get(netdev) {
	let reply = ubus.call(`wpa_supplicant.${netdev}`, 'control', { command: 'GET_CAPABILITY eap' });
	let names = split(trim(reply?.result ?? ''), ' ');

	return join(',', filter(map(names, (n) => CAPABILITIES[n]), (c) => c != null));
}

/**
 * Works out the state of a Supplicant row.
 *
 * @param {object} root - Configuration tree
 * @param {object} row - Supplicant row
 * @returns {object} `{ status, netdev, eapol }`; eapol is the reply of
 *   eapol_status while a supplicant runs
 */
function supplicant_state(root, row) {
	if (!ubbf.to_bool(row?.Enable))
		return { status: 'Disabled' };

	let plan = ieee8021x.supplicant_plan(root, row);
	if (plan.error)
		return { status: 'Error_Misconfigured' };

	let eapol = eapol_status_get(plan.netdev);
	return { status: eapol ? 'Enabled' : 'Error', netdev: plan.netdev, eapol };
}

/**
 * Returns the row of a Supplicant instance.
 *
 * @param {object} root - Configuration tree
 * @param {number} instance - Instance number
 * @returns {object|null} The row, or null
 */
function supplicant_row(root, instance) {
	return root?.Device?.IEEE8021x?.Supplicant?.[sprintf('%d', instance)];
}

/**
 * Reads the frame counters of an eapol_status reply.
 *
 * @param {object} eapol - Reply of eapol_status
 * @returns {object} Counters keyed by TR-181 name
 */
function counters_read(eapol) {
	let counters = {};
	for (let name, mib in STATS_MIB)
		counters[name] = int(eapol?.mib?.[mib] ?? 0);

	return counters;
}

/**
 * Get handler for Device.IEEE8021x.
 *
 * @param {object} ctx - Context with config
 * @returns {object} The object with the number of Supplicant rows
 */
function ieee8021x_get(ctx) {
	return {
		SupplicantNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.Supplicant)),
		X_UBBF_AuthenticatorNumberOfEntries: sprintf('%d', ubbf.instance_count(ctx.config?.X_UBBF_Authenticator))
	};
}

/**
 * Get handler for Device.IEEE8021x.Supplicant.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} The row with its runtime values
 */
function supplicant_get(ctx) {
	if (!ctx.config)
		return null;

	let state = supplicant_state(ctx.root, ctx.config);

	return {
		...schema_defaults('Supplicant'),
		...ubbf.ctx_config(ctx),
		Status: state.status,
		PAEState: PAE_STATES[state.eapol?.pae_state] ?? 'Disconnected',
		AuthenticationCapabilities: state.eapol ? capabilities_get(state.netdev) : ''
	};
}

/**
 * Get handler for Device.IEEE8021x.Supplicant.{i}.Stats.
 *
 * @param {object} ctx - Context with the row as parent
 * @returns {object} The counters since the last Stats.Reset()
 */
function stats_get(ctx) {
	let stats = { ...schema_defaults('Supplicant_Stats') };
	let eapol = supplicant_state(ctx.root, ctx.parent).eapol;
	if (!eapol)
		return stats;

	let counters = counters_read(eapol);
	let base = ieee8021x.baselines_load()[sprintf('%d', ctx.instances?.[0])] ?? {};

	// The plugin drops the baseline when it adds the interface again; until
	// then a counter below its baseline counts from zero.
	for (let name, value in counters) {
		let since = base[name] ?? 0;
		stats[name] = sprintf('%d', (value >= since) ? value - since : value);
	}

	stats.LastFrameVersion = sprintf('%d', int(eapol.mib?.dot1xSuppLastEapolFrameVersion ?? 0));
	stats.LastFrameSourceMACAddress = uc(eapol.mib?.dot1xSuppLastEapolFrameSource ?? '');
	stats.SuccessCount = sprintf('%d', eapol.success_count ?? 0);
	stats.FailureCount = sprintf('%d', eapol.failure_count ?? 0);

	return stats;
}

/**
 * Tells whether another row of the module uses a port. A port has either
 * a supplicant or an authenticator.
 *
 * @param {object} root - Configuration tree
 * @param {string} table - Table of the written row
 * @param {number} instance - Instance number of the written row
 * @param {string} value - Interface value
 * @returns {boolean} True when the value is taken
 */
function interface_taken(root, table, instance, value) {
	let wanted = rtrim(value, '.');

	for (let t, param in { Supplicant: 'Interface', X_UBBF_Authenticator: 'interface' }) {
		for (let key, row in root?.Device?.IEEE8021x?.[t] ?? {}) {
			if ((t == table && +key == instance) || type(row) != 'object')
				continue;
			if (rtrim(row[param] ?? '', '.') == wanted)
				return true;
		}
	}

	return false;
}

/**
 * Checks a write of the interface of a row: a port row that no other row
 * uses. Interface is a unique key of the Supplicant table.
 *
 * @param {object} ctx - Set context
 * @param {string} table - Table of the written row
 * @returns {number} 0, or a negative USP error code
 */
function interface_check(ctx, table) {
	if (ctx.value == '')
		return 0;

	if (!ieee8021x.interface_row(ctx.root, ctx.value))
		return -USP_ERR_INVALID_VALUE;

	return interface_taken(ctx.root, table, ctx.instance, ctx.value) ? -USP_ERR_UNIQUE_KEY_CONFLICT : 0;
}

/**
 * Set handler for Device.IEEE8021x.Supplicant.{i}.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function supplicant_set(ctx) {
	return (ctx.param == 'Interface') ? interface_check(ctx, 'Supplicant') : 0;
}

/**
 * Fetches the state of the hostapd of a port (uncached).
 *
 * @param {string} netdev - Netdev of the port
 * @returns {object|null} Reply of get_status, or null without a hostapd
 */
function hostapd_status_fetch(netdev) {
	return ubus.call(`hostapd.${netdev}`, 'get_status', {});
}

/**
 * Fetches the stations that the hostapd of a port knows (uncached).
 *
 * @param {string} netdev - Netdev of the port
 * @returns {object} Station flags keyed by MAC address
 */
function hostapd_clients_fetch(netdev) {
	return ubus.call(`hostapd.${netdev}`, 'get_clients', {})?.clients ?? {};
}

/**
 * Works out the state of an X_UBBF_Authenticator row.
 *
 * @param {object} root - Configuration tree
 * @param {object} row - X_UBBF_Authenticator row
 * @returns {object} `{ status, netdev }`; netdev is set while hostapd runs
 *   the port
 */
function authenticator_state(root, row) {
	if (!ubbf.to_bool(row?.enable))
		return { status: 'Disabled' };

	let plan = ieee8021x.authenticator_plan(root, row);
	if (plan.error)
		return { status: 'Error_Misconfigured' };

	let hostapd = cache_call(hostapd_status_fetch, plan.netdev);
	if (hostapd?.driver != 'wired')
		return { status: 'Error' };

	return { status: 'Enabled', netdev: plan.netdev };
}

/**
 * Returns the stations of a port, keyed by their stable instance numbers.
 *
 * @param {number} instance - Instance number of the X_UBBF_Authenticator row
 * @param {string|null} netdev - Netdev of the port while hostapd runs it
 * @returns {object} client rows keyed by instance number
 */
function clients_get(instance, netdev) {
	let clients = netdev ? cache_call(hostapd_clients_fetch, netdev) : {};
	let table = sprintf('Device.IEEE8021x.X_UBBF_Authenticator.%d.client', instance);

	return instance_map.instance_rows(table, sort(keys(clients)), (mac) => ({
		mac_address: uc(mac),
		authorized: clients[mac]?.authorized ? 'true' : 'false'
	}), true);
}

/**
 * Get handler for Device.IEEE8021x.X_UBBF_Authenticator.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} The row with its runtime values
 */
function authenticator_get(ctx) {
	if (!ctx.config)
		return null;

	let state = authenticator_state(ctx.root, ctx.config);

	return {
		...schema_defaults('X_UBBF_Authenticator'),
		...ubbf.ctx_config(ctx),
		status: state.status,
		client_number_of_entries: sprintf('%d', length(clients_get(ctx.instance, state.netdev)))
	};
}

/**
 * Get handler for Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}.
 *
 * @param {object} ctx - Context with the row as parent
 * @returns {object|null} One station, or all stations in enumerate mode
 */
function client_get(ctx) {
	let state = authenticator_state(ctx.root, ctx.parent);
	let rows = clients_get(ctx.instances?.[0], state.netdev);

	if (ctx.instance == null)
		return rows;

	return rows[sprintf('%d', ctx.instance)];
}

/**
 * Set handler for Device.IEEE8021x.X_UBBF_Authenticator.{i}.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function authenticator_set(ctx) {
	switch (ctx.param) {
	case 'interface':
		return interface_check(ctx, 'X_UBBF_Authenticator');

	case 'auth_server_addr':
	case 'acct_server_addr':
		return (ctx.value == '' || iptoarr(ctx.value)) ? 0 : -USP_ERR_INVALID_VALUE;

	case 'auth_server_shared_secret':
	case 'acct_server_shared_secret':
	case 'nas_identifier':
		return match(ctx.value, /[\r\n]/) ? -USP_ERR_INVALID_VALUE : 0;
	}

	return 0;
}

/**
 * Set handler for Device.IEEE8021x.Supplicant.{i}.EAPTLS.
 *
 * @param {object} ctx - Set context
 * @returns {number} 0, or a negative USP error code
 */
function eaptls_set(ctx) {
	if (ctx.value == '')
		return 0;

	switch (ctx.param) {
	case 'Certificate':
		let cert = certificates.certificate_path_resolve(ctx.value);
		return (cert && certificates.certificate_key_path(cert)) ? 0 : -USP_ERR_INVALID_VALUE;

	case 'CABundle':
		return certificates.cabundle_path_resolve(ctx.value) ? 0 : -USP_ERR_INVALID_VALUE;
	}

	return 0;
}

/**
 * Returns the netdev of a running supplicant for a command.
 *
 * @param {object} root - Configuration tree
 * @param {array} instances - Instance numbers of the command path
 * @returns {string|null} Netdev, or null when no supplicant runs
 */
function command_netdev(root, instances) {
	let state = supplicant_state(root, supplicant_row(root, instances?.[0]));
	if (!state.eapol) {
		logging.log_err('IEEE8021x Supplicant.%d: no supplicant runs', instances?.[0]);
		return null;
	}

	return state.netdev;
}

/**
 * Sync handler for Device.IEEE8021x.Supplicant.{i}.Reset(): logs off and
 * starts the authentication again.
 *
 * @param {object} input - Command input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers of the command path
 * @param {object} root - Configuration tree
 * @returns {object|null} Empty object, or null on failure
 */
function supplicant_reset(input, command_key, instances, root) {
	let netdev = command_netdev(root, instances);
	if (!netdev)
		return null;

	return (supplicant_command(netdev, 'LOGOFF') && supplicant_command(netdev, 'LOGON')) ? {} : null;
}

/**
 * Sync handler for Device.IEEE8021x.Supplicant.{i}.Disconnect(): logs off
 * until the next Reset() or a change of the row.
 *
 * @param {object} input - Command input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers of the command path
 * @param {object} root - Configuration tree
 * @returns {object|null} Empty object, or null on failure
 */
function supplicant_disconnect(input, command_key, instances, root) {
	let netdev = command_netdev(root, instances);
	if (!netdev)
		return null;

	return supplicant_command(netdev, 'LOGOFF') ? {} : null;
}

/**
 * Sync handler for Device.IEEE8021x.Supplicant.{i}.Stats.Reset().
 *
 * @param {object} input - Command input (unused)
 * @param {string} command_key - Command key (unused)
 * @param {array} instances - Instance numbers of the command path
 * @param {object} root - Configuration tree
 * @returns {object|null} Empty object, or null on failure
 */
function stats_reset(input, command_key, instances, root) {
	let netdev = command_netdev(root, instances);
	if (!netdev)
		return null;

	let eapol = eapol_status_get(netdev);
	ubus.call(`wpa_supplicant.${netdev}`, 'eapol_reset', {});
	cache_invalidate(eapol_status_fetch);

	return ieee8021x.baseline_store(instances[0], counters_read(eapol)) ? {} : null;
}

model['Device.IEEE8021x'] = {
	schema: schema('IEEE8021x'),
	get: ieee8021x_get
};

model['Device.IEEE8021x.Supplicant'] = {
};

model['Device.IEEE8021x.X_UBBF_Authenticator'] = {
};

model['Device.IEEE8021x.Supplicant.{i}'] = {
	schema: schema('Supplicant'),
	get: supplicant_get,
	set: supplicant_set
};

model['Device.IEEE8021x.X_UBBF_Authenticator.{i}'] = {
	schema: schema('X_UBBF_Authenticator'),
	get: authenticator_get,
	set: authenticator_set
};

model['Device.IEEE8021x.Supplicant.{i}.Stats'] = {
	schema: schema('Supplicant_Stats'),
	get: stats_get
};

model['Device.IEEE8021x.Supplicant.{i}.EAPMD5'] = {
	schema: schema('Supplicant_EAPMD5')
};

model['Device.IEEE8021x.Supplicant.{i}.EAPTLS'] = {
	schema: schema('Supplicant_EAPTLS'),
	set: eaptls_set
};

model['Device.IEEE8021x.X_UBBF_Authenticator.{i}.client'] = {
};

model['Device.IEEE8021x.X_UBBF_Authenticator.{i}.client.{i}'] = {
	schema: schema('X_UBBF_Authenticator_client'),
	get: client_get
};

operations['Device.IEEE8021x.Supplicant.{i}.Reset()'] = {
	type: 'sync',
	handler: supplicant_reset
};

operations['Device.IEEE8021x.Supplicant.{i}.Disconnect()'] = {
	type: 'sync',
	handler: supplicant_disconnect
};

operations['Device.IEEE8021x.Supplicant.{i}.Stats.Reset()'] = {
	type: 'sync',
	handler: stats_reset
};
