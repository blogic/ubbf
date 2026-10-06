'use strict';

import * as uci from 'uci';
import * as ubus from 'ubus';
import { readfile } from 'fs';
import * as schemas from 'ubbf.schemas.ManagementServer';
import * as ubbf from 'ubbf';
import { cr_url_compose } from 'ubbf.utils.cr_url';
import { log_err } from 'ubbf.utils.logging';
import { datetime_format } from 'ubbf.utils.helpers';

const CWMP_STATE_PATH = '/etc/ubbf/cwmp-state.json';

// ACS-binding writes waiting for the transaction to commit. datamodel.uc
// registers the flush and drop below; this module cannot reach on_commit
// itself, because datamodel.uc imports it.
let staged = [];

// ManagementServer ACS-binding fields -> persistent flash UCI
// (/etc/config/cwmp). Kept here rather than config.json so a profile
// apply cannot wipe the ACS binding, and so cwmpd/cr.uc can read it at
// boot before the /var/run/uci overlay is rendered (power-cut resilience).
const ACS_UCI = {
	EnableCWMP:                { section: 'cwmp', option: 'enabled', bool: true },
	URL:                       { section: 'acs',  option: 'url' },
	Username:                  { section: 'acs',  option: 'username' },
	Password:                  { section: 'acs',  option: 'password' },
	PeriodicInformEnable:      { section: 'acs',  option: 'periodic_inform_enable', bool: true },
	PeriodicInformInterval:    { section: 'acs',  option: 'periodic_inform_interval' },
	PeriodicInformTime:        { section: 'acs',  option: 'periodic_inform_time' },
	// 3.2.1.1 calls these m and k. cwmpd wants m in milliseconds and k in
	// thousandths, while TR-181 states m in seconds and k as a plain
	// multiplier, so both are scaled on the way out.
	CWMPRetryMinimumWaitInterval: { section: 'acs', option: 'retry_wait_min', scale: 1000 },
	CWMPRetryIntervalMultiplier:  { section: 'acs', option: 'retry_interval_mult' },
	ConnectionRequestUsername: { section: 'cpe',  option: 'userid' },
	ConnectionRequestPassword: { section: 'cpe',  option: 'passwd' },
	X_UBBF_InformWatchdogTime: { section: 'acs',  option: 'watchdog_time' },
	X_UBBF_TLSMinVersion:      { section: 'acs',  option: 'tls_min_version' },
	X_UBBF_TLSCipherList:      { section: 'acs',  option: 'tls_cipher_list' }
};

// Fields cwmpd needs for its ACS connection: a change is pushed live via
// the cwmpd set_config ubus method so it reconnects without a restart. CR
// credentials are deliberately excluded -- only the uwsd CR listener
// (cr.uc) reads them, live, so provisioning them restarts nothing.
const ACS_CONNECT_FIELDS = [
	'EnableCWMP', 'URL', 'Username', 'Password',
	'PeriodicInformEnable', 'PeriodicInformInterval', 'PeriodicInformTime',
	'CWMPRetryMinimumWaitInterval', 'CWMPRetryIntervalMultiplier',
	'X_UBBF_InformWatchdogTime', 'X_UBBF_TLSMinVersion', 'X_UBBF_TLSCipherList'
];


/**
 * Reads the ParameterKey from the CWMP protocol state file, where cwmp-dm
 * persists it atomically with each successful SPV/AddObject/DeleteObject
 * (TR-069 A.3.2.1).
 *
 * @returns {string} Stored ParameterKey, or empty string
 */
function parameter_key_get() {
	let raw = readfile(CWMP_STATE_PATH);
	if (!raw)
		return '';
	let state;
	try {
		state = json(raw);
	} catch (e) {
		return '';
	}
	return state?.parameter_key ?? '';
}

/**
 * Get handler for Device.ManagementServer.
 *
 * Overlays the ACS binding from persistent flash UCI (/etc/config/cwmp)
 * so GPV reflects what is actually in force. Passwords read back empty per
 * TR-069 credential semantics. AliasBasedAddressing and
 * InstanceWildcardsSupported stay false until cwmpd implements TR-069
 * 3.6.1 / 3.6.2.
 *
 * @param {object} ctx - Context with config
 * @returns {object} ManagementServer properties
 */
function management_server_get(ctx) {
	let result = { ...ubbf.ctx_config(ctx) };

	let c = uci.cursor();
	let enabled = c.get('cwmp', 'cwmp', 'enabled');
	if (enabled != null)
		result.EnableCWMP = (enabled == '1') ? 'true' : 'false';
	let url = c.get('cwmp', 'acs', 'url');
	if (url != null)
		result.URL = url;
	let user = c.get('cwmp', 'acs', 'username');
	if (user != null)
		result.Username = user;
	let cruser = c.get('cwmp', 'cpe', 'userid');
	if (cruser != null)
		result.ConnectionRequestUsername = cruser;
	let pi_enable = c.get('cwmp', 'acs', 'periodic_inform_enable');
	if (pi_enable != null)
		result.PeriodicInformEnable = (pi_enable == '1') ? 'true' : 'false';
	let pi_interval = c.get('cwmp', 'acs', 'periodic_inform_interval');
	if (pi_interval != null)
		result.PeriodicInformInterval = pi_interval;
	let pi_time = c.get('cwmp', 'acs', 'periodic_inform_time');
	if (pi_time != null)
		result.PeriodicInformTime = pi_time;
	// Back from cwmpd's milliseconds to the seconds TR-181 states.
	let retry_min = c.get('cwmp', 'acs', 'retry_wait_min');
	if (retry_min != null)
		result.CWMPRetryMinimumWaitInterval = sprintf('%d', (+retry_min) / 1000);
	let retry_mult = c.get('cwmp', 'acs', 'retry_interval_mult');
	if (retry_mult != null)
		result.CWMPRetryIntervalMultiplier = retry_mult;
	let watchdog_time = c.get('cwmp', 'acs', 'watchdog_time');
	if (watchdog_time != null)
		result.X_UBBF_InformWatchdogTime = watchdog_time;
	let tls_min = c.get('cwmp', 'acs', 'tls_min_version');
	if (tls_min != null)
		result.X_UBBF_TLSMinVersion = tls_min;
	let tls_ciphers = c.get('cwmp', 'acs', 'tls_cipher_list');
	if (tls_ciphers != null)
		result.X_UBBF_TLSCipherList = tls_ciphers;

	result.X_UBBF_LastSuccessfulSession =
		datetime_format(ubus?.call('cwmp', 'status')?.last_success);

	result.Password = '';
	result.ConnectionRequestPassword = '';
	result.ConnectionRequestURL = cr_url_compose();
	result.ParameterKey = parameter_key_get();
	result.AliasBasedAddressing = 'false';
	result.InstanceWildcardsSupported = 'false';
	return result;
}

/**
 * Pushes the current ACS connection parameters to cwmpd via its set_config
 * ubus method, so a URL/credential change reconnects live without a procd
 * restart. Best-effort: if cwmpd is down the values are already persisted
 * in UCI and it reads them at next start.
 */
function cwmpd_reconfig() {
	let c = uci.cursor();
	let cfg = {
		enabled:                  (c.get('cwmp', 'cwmp', 'enabled') == '1'),
		url:                      c.get('cwmp', 'acs', 'url') ?? '',
		username:                 c.get('cwmp', 'acs', 'username') ?? '',
		password:                 c.get('cwmp', 'acs', 'password') ?? '',
		periodic_inform_enabled:  (c.get('cwmp', 'acs', 'periodic_inform_enable') == '1'),
		periodic_inform_interval: +(c.get('cwmp', 'acs', 'periodic_inform_interval') ?? '300'),
		periodic_inform_time:     c.get('cwmp', 'acs', 'periodic_inform_time') ?? '',
		retry_wait_min:           +(c.get('cwmp', 'acs', 'retry_wait_min') ?? '5000'),
		retry_interval_mult:      +(c.get('cwmp', 'acs', 'retry_interval_mult') ?? '2000'),
		watchdog_time:            c.get('cwmp', 'acs', 'watchdog_time') ?? '',
		tls_min_version:          c.get('cwmp', 'acs', 'tls_min_version') ?? '1.2',
		tls_cipher_list:          c.get('cwmp', 'acs', 'tls_cipher_list') ?? ''
	};

	// The URL family follows the ACS address, so a new ACS URL can change it.
	let cr_url = cr_url_compose();
	if (cr_url)
		cfg.cr_url = cr_url;

	ubus?.call('cwmp', 'set_config', cfg);
}

/**
 * Set handler for Device.ManagementServer.
 *
 * Persists the ACS-binding fields to /etc/config/cwmp (flash) and keeps
 * them out of config.json, so a profile apply cannot wipe the ACS binding.
 * All other ManagementServer parameters fall through to the generic store.
 *
 * @param {object} ctx - Context with path, param, value, root
 * @returns {number} 0 on success, -1 on failure
 */
function management_server_set(ctx) {
	let m = ACS_UCI[ctx.param];
	if (m == null)
		return 0;

	let value = ctx.value;
	if (m.bool)
		value = ubbf.to_bool(ctx.value) ? '1' : '0';
	else if (m.scale)
		value = sprintf('%d', (+ctx.value) * m.scale);

	push(staged, { param: ctx.param, section: m.section, option: m.option, value });

	let ms = ctx.root?.Device?.ManagementServer;
	if (ms)
		ms[ctx.param] = '';

	return 0;
}

/**
 * Writes the staged ACS binding to flash and tells cwmpd about it.
 *
 * Deferred to commit because neither half can be rolled back: a
 * SetParameterValues is atomic, and writing the ACS URL from inside the
 * transaction would survive an abort caused by any later parameter in the
 * same request, which with a bad URL strands the device.
 */
export function staged_flush() {
	if (!length(staged))
		return;

	let c = uci.cursor();
	let reconnect = false;

	for (let entry in staged) {
		c.set('cwmp', entry.section, entry.option, entry.value);
		if (index(ACS_CONNECT_FIELDS, entry.param) >= 0)
			reconnect = true;
	}
	staged = [];

	if (!c.commit('cwmp')) {
		log_err('ManagementServer: uci commit failed, ACS binding unchanged');
		return;
	}

	if (reconnect)
		cwmpd_reconfig();
};

/**
 * Discards the staged ACS binding after an abandoned transaction, so it
 * cannot ride along into the next one.
 */
export function staged_drop() {
	staged = [];
};

export const model = {
	'Device.ManagementServer': {
		schema: schemas.ManagementServer,
		get: management_server_get,
		set: management_server_set,
		protocol: 'cwmp'
	}
};
