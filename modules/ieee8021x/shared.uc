'use strict';

// Included with { ieee8021x, certificates } as the scope, by handler.uc in
// the agent and by the ubbf-device plugin, so both read a Supplicant row the
// same way. Each function is added to the ieee8021x object; certificates is
// the object of modules/security/certificates.uc. The scope ends with the
// include, so the functions use the binding below.

const fs = require('fs');
const ubbf = require('ubbf');

const certs = certificates;

const RUN_DIR = '/var/run/ubbf-ieee8021x';

// The eapol_sm counters of wpa_supplicant cannot be cleared, so
// Stats.Reset() keeps the values it saw and the reads subtract them.
const STATS_BASELINE_PATH = '/tmp/ubbf/ieee8021x-stats.json';

// TR-181 names the interface to authenticate on, for example an
// Ethernet.Link; a bridge port stands for the LAN port below it.
const INTERFACE_RE = /^Device\.(Ethernet\.(Interface|Link)|Bridging\.Bridge\.[0-9]+\.Port)\.[0-9]+\.?$/;
const NETDEV_RE = /^[A-Za-z0-9_.@-]+$/;
const LOWER_LAYER_DEPTH = 3;

// The same values as the schema defaults, for a row that stores none.
const TIMERS = [
	[ 'heldPeriod', 'HeldPeriod', 60 ],
	[ 'authPeriod', 'AuthPeriod', 30 ],
	[ 'startPeriod', 'StartPeriod', 30 ],
	[ 'maxStart', 'MaxStart', 3 ]
];

/**
 * Returns the row an Interface value refers to.
 *
 * @param {object} root - Configuration tree
 * @param {string} path - Interface value
 * @returns {object|null} The row, or null for a value that is not an
 *   Ethernet.Interface, Ethernet.Link or bridge port row
 */
function interface_row(root, path) {
	if (type(path) != 'string' || !match(path, INTERFACE_RE))
		return null;

	let row = ubbf.navigate_data(root, ubbf.path_to_parts(path));
	return (type(row) == 'object') ? row : null;
}

/**
 * Resolves an Interface value to the netdev to authenticate on. The Name
 * of an Ethernet row is its netdev; a bridge port is named after the port
 * it stands for, so its netdev is found through LowerLayers.
 *
 * @param {object} root - Configuration tree
 * @param {string} path - Interface value
 * @param {number} depth - LowerLayers levels followed so far
 * @returns {string|null} Netdev name, or null when none exists
 */
function netdev_resolve(root, path, depth) {
	if (depth > LOWER_LAYER_DEPTH)
		return null;

	let row = interface_row(root, path);
	if (!row)
		return null;

	let name = row.Name;
	if (type(name) == 'string' && match(name, NETDEV_RE) && fs.stat(`/sys/class/net/${name}`))
		return name;

	let lower = trim(split(row.LowerLayers ?? '', ',')[0]);
	return netdev_resolve(root, lower, depth + 1);
}

/**
 * Returns the Device.Security.CABundle instance of a reference.
 *
 * @param {string} ref - CABundle value
 * @returns {number|null} Instance number, or null for a malformed value
 */
function cabundle_instance(ref) {
	let m = (type(ref) == 'string') ? match(ref, /^Device\.Security\.CABundle\.([0-9]+)\.?$/) : null;
	return m ? +m[1] : null;
}

/**
 * Checks the TLS settings of a row and adds them to a plan.
 *
 * @param {object} plan - Plan of supplicant_plan(), changed in place
 * @param {object} tls - EAPTLS object of the row
 * @returns {string|null} The fault, or null when the settings are usable
 */
function tls_plan(plan, tls) {
	plan.cert = certs.certificate_path_resolve(tls.Certificate);
	plan.key = plan.cert ? certs.certificate_key_path(plan.cert) : null;
	if (!plan.key)
		return sprintf('EAPTLS.Certificate %s is not a certificate with a key', tls.Certificate ?? '');

	// MutualAuthenticationEnable makes the supplicant check the server too,
	// which needs the CAs to check it against.
	if (!ubbf.to_bool(tls.MutualAuthenticationEnable))
		return null;

	plan.cabundle = cabundle_instance(tls.CABundle);
	if (plan.cabundle == null || !certs.cabundle_path_resolve(tls.CABundle))
		return sprintf('EAPTLS.CABundle %s is not a CA bundle with certificates', tls.CABundle ?? '');

	return null;
}

/**
 * Works out what a Supplicant row asks wpa_supplicant to do.
 *
 * @param {object} root - Configuration tree
 * @param {object} row - Supplicant row
 * @returns {object} `{ netdev, identity, methods, password, cert, key,
 *   cabundle }`, or `{ error }` for a row that cannot run
 */
function supplicant_plan(root, row) {
	let netdev = netdev_resolve(root, row?.Interface, 0);
	if (!netdev)
		return { error: sprintf('Interface %s has no netdev', row?.Interface ?? '') };

	let plan = { netdev, identity: row.EAPIdentity ?? '', methods: [] };
	if (plan.identity == '')
		return { error: 'EAPIdentity is empty' };

	let md5 = row.EAPMD5 ?? {};
	if (ubbf.to_bool(md5.Enable)) {
		plan.password = md5.SharedSecret ?? '';
		if (plan.password == '')
			return { error: 'EAPMD5.SharedSecret is empty' };
		push(plan.methods, 'MD5');
	}

	let tls = row.EAPTLS ?? {};
	if (ubbf.to_bool(tls.Enable)) {
		let error = tls_plan(plan, tls);
		if (error)
			return { error };
		push(plan.methods, 'TLS');
	}

	if (!length(plan.methods))
		return { error: 'neither EAPMD5 nor EAPTLS is enabled' };

	return plan;
}

/**
 * Returns the wpa_supplicant configuration of a plan. The identity and the
 * password are hex strings, which wpa_supplicant takes as they are, so no
 * value can end the string or add a line.
 *
 * @param {object} plan - Plan of supplicant_plan()
 * @param {object} files - Paths of the copies `{ cert, key, ca }` that
 *   wpa_supplicant can read
 * @returns {string} Configuration file text
 */
function supplicant_config(plan, files) {
	let lines = [
		'ctrl_interface=/var/run/wpa_supplicant',
		'ap_scan=0',
		'network={',
		'\tkey_mgmt=IEEE8021X',
		'\teapol_flags=0',
		`\teap=${join(' ', plan.methods)}`,
		`\tidentity=${hexenc(plan.identity)}`
	];

	if (plan.password != null)
		push(lines, `\tpassword=${hexenc(plan.password)}`);
	if (files.cert)
		push(lines, `\tclient_cert="${files.cert}"`, `\tprivate_key="${files.key}"`);
	if (files.ca)
		push(lines, `\tca_cert="${files.ca}"`);

	push(lines, '}', '');
	return join('\n', lines);
}

/**
 * Returns the EAPOL timers of a row as wpa_supplicant SET commands.
 *
 * @param {object} row - Supplicant row
 * @returns {array} Commands such as "SET EAPOL::heldPeriod 60"
 */
function timer_commands(row) {
	return map(TIMERS, (t) => sprintf('SET EAPOL::%s %d', t[0], ubbf.to_int(row?.[t[1]]) ?? t[2]));
}

// The same values as the schema defaults, for a row that stores none.
const AUTHENTICATOR_DEFAULTS = {
	auth_server_port: 1812,
	acct_server_port: 1813,
	eap_reauth_period: 3600
};

// hostapd reads one option per line and takes the rest of the line as the
// value, so a value must not hold a line break.
const LINE_BREAK_RE = /[\r\n]/;

/**
 * Checks the RADIUS settings of an X_UBBF_Authenticator row.
 *
 * @param {object} plan - Plan of authenticator_plan()
 * @returns {string|null} The fault, or null when the settings are usable
 */
function radius_check(plan) {
	if (!iptoarr(plan.auth_server_addr))
		return sprintf('auth_server_addr %s is not an IP address', plan.auth_server_addr);
	if (plan.auth_server_shared_secret == '')
		return 'auth_server_shared_secret is empty';

	if (plan.acct_server_addr != '' && !iptoarr(plan.acct_server_addr))
		return sprintf('acct_server_addr %s is not an IP address', plan.acct_server_addr);
	if (plan.acct_server_addr != '' && plan.acct_server_shared_secret == '')
		return 'acct_server_shared_secret is empty';

	for (let key in [ 'auth_server_shared_secret', 'acct_server_shared_secret', 'nas_identifier' ])
		if (match(plan[key], LINE_BREAK_RE))
			return sprintf('%s holds a line break', key);

	return null;
}

/**
 * Works out what an X_UBBF_Authenticator row asks hostapd to do.
 *
 * @param {object} root - Configuration tree
 * @param {object} row - X_UBBF_Authenticator row
 * @returns {object} The hostapd settings with the netdev, or `{ error }`
 *   for a row that cannot run
 */
function authenticator_plan(root, row) {
	let netdev = netdev_resolve(root, row?.interface, 0);
	if (!netdev)
		return { error: sprintf('interface %s has no netdev', row?.interface ?? '') };

	let plan = { netdev };
	for (let key in [ 'auth_server_addr', 'auth_server_shared_secret', 'acct_server_addr',
			  'acct_server_shared_secret', 'nas_identifier' ])
		plan[key] = row[key] ?? '';
	for (let key, value in AUTHENTICATOR_DEFAULTS)
		plan[key] = ubbf.to_int(row[key]) ?? value;

	let error = radius_check(plan);
	return error ? { error } : plan;
}

/**
 * Returns the hostapd configuration of a plan: a wired port that a RADIUS
 * server authorises.
 *
 * @param {object} plan - Plan of authenticator_plan()
 * @returns {string} Configuration file text
 */
function authenticator_config(plan) {
	let lines = [
		'driver=wired',
		`interface=${plan.netdev}`,
		'ctrl_interface=/var/run/hostapd',
		'ieee8021x=1',
		'eapol_version=2',
		'use_pae_group_addr=1',
		`eap_reauth_period=${plan.eap_reauth_period}`,
		'dynamic_own_ip_addr=1',
		`auth_server_addr=${plan.auth_server_addr}`,
		`auth_server_port=${plan.auth_server_port}`,
		`auth_server_shared_secret=${plan.auth_server_shared_secret}`
	];

	if (plan.acct_server_addr != '')
		push(lines, `acct_server_addr=${plan.acct_server_addr}`, `acct_server_port=${plan.acct_server_port}`,
			`acct_server_shared_secret=${plan.acct_server_shared_secret}`);
	if (plan.nas_identifier != '')
		push(lines, `nas_identifier=${plan.nas_identifier}`);

	push(lines, '');
	return join('\n', lines);
}

/**
 * Loads the Stats.Reset() baselines.
 *
 * @returns {object} Counters keyed by instance number
 */
function baselines_load() {
	try {
		return json(fs.readfile(STATS_BASELINE_PATH) ?? '{}') ?? {};
	} catch (e) {
		return {};
	}
}

/**
 * Stores or drops the Stats.Reset() baseline of one instance.
 *
 * @param {number|string} instance - Instance number
 * @param {object|null} counters - Counters to subtract, or null to drop it
 * @returns {boolean} True when the file holds the result
 */
function baseline_store(instance, counters) {
	let baselines = baselines_load();
	let key = sprintf('%d', instance);

	if (counters == null && !(key in baselines))
		return true;

	if (counters == null)
		delete baselines[key];
	else
		baselines[key] = counters;

	return fs.writefile(STATS_BASELINE_PATH, sprintf('%J', baselines)) != null;
}

ieee8021x.RUN_DIR = RUN_DIR;
ieee8021x.baselines_load = baselines_load;
ieee8021x.baseline_store = baseline_store;
ieee8021x.authenticator_plan = authenticator_plan;
ieee8021x.authenticator_config = authenticator_config;
ieee8021x.INTERFACE_RE = INTERFACE_RE;
ieee8021x.interface_row = interface_row;
ieee8021x.netdev_resolve = (root, path) => netdev_resolve(root, path, 0);
ieee8021x.supplicant_plan = supplicant_plan;
ieee8021x.supplicant_config = supplicant_config;
ieee8021x.timer_commands = timer_commands;
