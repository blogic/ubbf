'use strict';

// Runs the wired 802.1x daemons of the ieee8021x module: a wpa_supplicant
// interface for each enabled row of Device.IEEE8021x.Supplicant (TR-181),
// and a hostapd interface for each enabled row of
// Device.IEEE8021x.X_UBBF_Authenticator. It carries out the policies of the
// supplicants, and opens and closes the authenticator ports in netifd. The
// agent reads the state from the daemons. Both daemons run as the user
// network, so their files are copies that this user can read.

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { log_info, log_err } from 'ubbf.utils.logging';

const CONFIG_PATH = '/etc/ubbf/config.json';
const MODULES_DIR = '/usr/share/ucode/ubbf/modules';
const RUN_USER = 'network';
const APPLY_DELAY_MS = 200;
const SUPPLICANT_SUFFIXES = [ '.conf', '.crt', '.key', '-ca.pem' ];
const AUTHENTICATOR_SUFFIX = '.hostapd';

// The hostapd notifications that end the authorisation of a station.
const STATION_GONE = [ 'disassoc', 'deauth', 'local-deauth', 'inactive-deauth' ];

let certificates = {};
include(`${MODULES_DIR}/security/certificates.uc`, { certificates });

let ieee8021x = {};
include(`${MODULES_DIR}/ieee8021x/shared.uc`, { ieee8021x, certificates });

const RUN_DIR = ieee8021x.RUN_DIR;

let root;
let running = {};
let ports = {};
let faults = {};
let apply_timer;
let port_subscriber;

/**
 * Loads the stored configuration.
 */
function config_load() {
	root = null;

	let data = fs.readfile(CONFIG_PATH);
	if (!data)
		return;

	try {
		root = json(data);
	} catch (e) {
		log_err('ieee8021x: invalid JSON in %s', CONFIG_PATH);
	}
}

/**
 * Logs why a row cannot run, once for each new reason.
 *
 * @param {string} label - The row, for example "Supplicant.1"
 * @param {string} msg - The reason
 */
function fault_log(label, msg) {
	if (faults[label] == msg)
		return;

	faults[label] = msg;
	log_err('ieee8021x: %s: %s', label, msg);
}

/**
 * Looks up the user and group ids of a user.
 *
 * @param {string} name - User name
 * @returns {object|null} `{ uid, gid }`, or null for an unknown user
 */
function user_ids(name) {
	for (let line in split(fs.readfile('/etc/passwd') ?? '', '\n')) {
		let fields = split(line, ':');
		if (fields[0] == name)
			return { uid: int(fields[2]), gid: int(fields[3]) };
	}

	return null;
}

/**
 * Writes a file that only the daemons read. The directory admits only its
 * owner, so the file is not exposed before chmod().
 *
 * @param {string} path - File path
 * @param {string} content - File content
 * @param {object|null} ids - Owner from user_ids()
 * @returns {boolean} True when the file is in place
 */
function private_write(path, content, ids) {
	let tmp = path + '.tmp';
	if (fs.writefile(tmp, content) == null)
		return false;

	fs.chmod(tmp, 0600);
	if (ids)
		fs.chown(tmp, ids.uid, ids.gid);

	return !!fs.rename(tmp, path);
}

/**
 * Copies the CA bundle of a plan for wpa_supplicant.
 *
 * @param {object} plan - Plan of supplicant_plan()
 * @returns {string|null} The certificates, or null when there are none
 */
function cabundle_read(plan) {
	let bundle = certificates.cabundle_find(certificates.scan(), plan.cabundle);
	let path = bundle ? certificates.cabundle_file_build(bundle) : null;

	return path ? fs.readfile(path) : null;
}

/**
 * Writes the configuration of a supplicant and the copies of its
 * certificate, key and CAs.
 *
 * @param {object} plan - Plan of supplicant_plan()
 * @param {object|null} ids - Owner from user_ids()
 * @returns {object|null} `{ conf, cert, key, ca, state }`, where state
 *   changes whenever wpa_supplicant must read the files again; null when a
 *   file cannot be written
 */
function files_write(plan, ids) {
	let base = `${RUN_DIR}/${plan.netdev}`;
	let files = {};
	let state = '';

	if (plan.cert) {
		let cert = fs.readfile(plan.cert);
		let key = fs.readfile(plan.key);
		files.cert = base + '.crt';
		files.key = base + '.key';
		if (cert == null || key == null || !private_write(files.cert, cert, ids) || !private_write(files.key, key, ids))
			return null;
		state += cert + key;
	}

	if (plan.cabundle != null) {
		let ca = cabundle_read(plan);
		files.ca = base + '-ca.pem';
		if (ca == null || !private_write(files.ca, ca, ids))
			return null;
		state += ca;
	}

	let conf = ieee8021x.supplicant_config(plan, files);
	files.conf = base + '.conf';
	if (!private_write(files.conf, conf, ids))
		return null;

	files.state = conf + state;
	return files;
}

/**
 * Tells whether wpa_supplicant runs an interface on a netdev.
 *
 * @param {string} netdev - Netdev name
 * @returns {boolean}
 */
function supplicant_present(netdev) {
	return ubus.call(`wpa_supplicant.${netdev}`, 'eapol_status', {}) != null;
}

/**
 * Sends a control interface command to the supplicant of a netdev.
 *
 * @param {string} netdev - Netdev name
 * @param {string} command - Command, for example "LOGOFF"
 */
function supplicant_command(netdev, command) {
	ubus.call(`wpa_supplicant.${netdev}`, 'control', { command });
}

/**
 * Stops the FailAuthentication timer of a supplicant.
 *
 * @param {object} entry - Entry of running
 */
function fail_timer_cancel(entry) {
	entry.fail_timer?.cancel();
	entry.fail_timer = null;
}

let fail_check;

/**
 * Starts the FailAuthentication timer: once MaxStart starts are sent and
 * not answered, wpa_supplicant assumes the port authorised (IEEE
 * 802.1X-2004 8.4.6, AssumeAuthentication). The check then logs off, and
 * after HeldPeriod logs on again, as after a failure.
 *
 * @param {string} netdev - Netdev name
 */
function fail_timer_arm(netdev) {
	let entry = running[netdev];
	fail_timer_cancel(entry);
	if (entry.row.StartFailurePolicy != 'FailAuthentication')
		return;

	let start_period = ubbf.to_int(entry.row.StartPeriod) ?? 30;
	let max_start = ubbf.to_int(entry.row.MaxStart) ?? 3;
	entry.fail_timer = uloop.timer((max_start + 1) * start_period * 1000, () => fail_check(netdev));
}

/**
 * Logs off a supplicant that wpa_supplicant assumed authorised, for
 * StartFailurePolicy FailAuthentication.
 *
 * @param {string} netdev - Netdev name
 */
fail_check = function(netdev) {
	let entry = running[netdev];
	if (!entry)
		return;

	entry.fail_timer = null;
	let eapol = ubus.call(`wpa_supplicant.${netdev}`, 'eapol_status', {});
	if (eapol?.pae_state != 'AUTHENTICATED' || eapol?.eap_state == 'SUCCESS')
		return;

	log_info('ieee8021x: no authenticator answers on %s, logging off', netdev);
	supplicant_command(netdev, 'LOGOFF');

	let held_period = ubbf.to_int(entry.row.HeldPeriod) ?? 60;
	entry.fail_timer = uloop.timer(held_period * 1000, () => {
		if (!running[netdev])
			return;
		supplicant_command(netdev, 'LOGON');
		fail_timer_arm(netdev);
	});
};

/**
 * Starts or updates the supplicant of a row. wpa_supplicant reads its file
 * only when the interface is added, so a changed file adds it again; the
 * timers are runtime settings and are set each time.
 *
 * @param {object} want - `{ label, instance, row, plan }` of rows_wanted()
 * @param {object|null} ids - Owner from user_ids()
 */
function supplicant_start(want, ids) {
	let netdev = want.plan.netdev;
	let files = files_write(want.plan, ids);
	if (!files) {
		fault_log(want.label, sprintf('cannot write the files for %s', netdev));
		return;
	}

	let entry = running[netdev];
	let present = supplicant_present(netdev);
	if (!present || entry?.state != files.state) {
		if (present)
			ubus.call('wpa_supplicant', 'config_remove', { iface: netdev });

		ubus.call('wpa_supplicant', 'config_add', { driver: 'wired', iface: netdev, config: files.conf });
		if (ubus.error()) {
			fault_log(want.label, sprintf('wpa_supplicant config_add %s: %s', netdev, ubus.error()));
			delete running[netdev];
			return;
		}
		ieee8021x.baseline_store(want.instance, null);
		log_info('ieee8021x: %s runs on %s', want.label, netdev);
	}

	if (entry)
		fail_timer_cancel(entry);
	running[netdev] = { state: files.state, row: want.row };
	delete faults[want.label];

	for (let command in ieee8021x.timer_commands(want.row))
		supplicant_command(netdev, command);

	fail_timer_arm(netdev);
}

/**
 * Logs off and removes the supplicant of a netdev, and removes its files.
 * Without the EAPOL-Logoff the authenticator keeps the port authorised
 * until its next reauthentication.
 *
 * @param {string} netdev - Netdev name
 */
function supplicant_stop(netdev) {
	if (running[netdev])
		fail_timer_cancel(running[netdev]);

	supplicant_command(netdev, 'LOGOFF');
	ubus.call('wpa_supplicant', 'config_remove', { iface: netdev });
	for (let suffix in SUPPLICANT_SUFFIXES)
		fs.unlink(`${RUN_DIR}/${netdev}${suffix}`);

	delete running[netdev];
	log_info('ieee8021x: supplicant on %s stopped', netdev);
}

/**
 * Opens or closes an authenticator port in netifd.
 *
 * @param {string} netdev - Netdev of the port
 * @param {boolean} authorized - True to let the port into the bridge
 */
function port_auth_set(netdev, authorized) {
	// set_state answers without data, so ubus.error() tells the outcome
	ubus.call('network.device', 'set_state', { name: netdev, auth_status: authorized });
	if (ubus.error())
		log_err('ieee8021x: set_state %s auth_status %s: %s', netdev, authorized, ubus.error());
	else
		log_info('ieee8021x: port %s %s', netdev, authorized ? 'authorised' : 'closed');
}

/**
 * Starts or updates the authenticator of a row. hostapd reads its file only
 * when the interface is added, so a changed file adds it again, which also
 * forgets the stations.
 *
 * @param {object} want - `{ label, instance, row, plan }` of rows_wanted()
 * @param {object|null} ids - Owner from user_ids()
 */
function authenticator_start(want, ids) {
	let netdev = want.plan.netdev;
	let conf = ieee8021x.authenticator_config(want.plan);
	let path = `${RUN_DIR}/${netdev}${AUTHENTICATOR_SUFFIX}`;
	let obj = `hostapd.${netdev}`;

	let present = ubus.call(obj, 'get_status', {}) != null;
	if (present && ports[netdev]?.state == conf)
		return;

	if (!private_write(path, conf, ids)) {
		fault_log(want.label, sprintf('cannot write the file for %s', netdev));
		return;
	}

	if (present)
		ubus.call('hostapd', 'config_remove', { iface: netdev });

	ubus.call('hostapd', 'config_add', { iface: netdev, config: path });
	if (ubus.error()) {
		fault_log(want.label, sprintf('hostapd config_add %s: %s', netdev, ubus.error()));
		delete ports[netdev];
		return;
	}

	ports[netdev] = { state: conf, stations: {} };
	delete faults[want.label];
	log_info('ieee8021x: %s runs on %s', want.label, netdev);

	port_subscriber?.subscribe(obj);
	port_auth_set(netdev, false);
}

/**
 * Removes the authenticator of a netdev and its file, and opens the port.
 * netifd gives a closed port its VLANs back only on an auth_status change,
 * not when a reload drops the `auth` option.
 *
 * @param {string} netdev - Netdev name
 */
function authenticator_stop(netdev) {
	port_auth_set(netdev, true);
	ubus.call('hostapd', 'config_remove', { iface: netdev });
	fs.unlink(`${RUN_DIR}/${netdev}${AUTHENTICATOR_SUFFIX}`);

	delete ports[netdev];
	log_info('ieee8021x: authenticator on %s stopped', netdev);
}

/**
 * Collects the rows of a table that can run, keyed by netdev. The first row
 * of a netdev wins; the set handler of the agent refuses a second one.
 *
 * @param {string} table - Supplicant or X_UBBF_Authenticator
 * @param {string} enable - Name of the Enable parameter of the table
 * @param {function} plan_fn - supplicant_plan() or authenticator_plan()
 * @param {object} taken - Netdevs in use, changed in place
 * @returns {object} `{ label, instance, row, plan }` keyed by netdev
 */
function rows_wanted(table, enable, plan_fn, taken) {
	let wanted = {};
	let rows = root?.Device?.IEEE8021x?.[table] ?? {};

	for (let key in sort(keys(rows), (a, b) => +a - +b)) {
		let row = rows[key];
		let label = `${table}.${key}`;
		if (!ubbf.is_instance_key(key) || type(row) != 'object' || !ubbf.to_bool(row[enable])) {
			delete faults[label];
			continue;
		}

		let plan = plan_fn(root, row);
		if (plan.error) {
			fault_log(label, plan.error);
			continue;
		}
		if (taken[plan.netdev]) {
			fault_log(label, sprintf('%s is in use by %s', plan.netdev, taken[plan.netdev]));
			continue;
		}

		taken[plan.netdev] = label;
		wanted[plan.netdev] = { label, instance: key, row, plan };
	}

	return wanted;
}

/**
 * Starts, updates and stops the daemons to match the rows.
 */
function apply() {
	apply_timer = null;

	let ids = user_ids(RUN_USER);
	fs.mkdir(RUN_DIR, 0700);
	if (ids)
		fs.chown(RUN_DIR, ids.uid, ids.gid);

	let taken = {};
	let supplicants = rows_wanted('Supplicant', 'Enable', ieee8021x.supplicant_plan, taken);
	let authenticators = rows_wanted('X_UBBF_Authenticator', 'enable', ieee8021x.authenticator_plan, taken);

	for (let netdev in keys(running))
		if (!supplicants[netdev])
			supplicant_stop(netdev);
	for (let netdev in keys(ports))
		if (!authenticators[netdev])
			authenticator_stop(netdev);

	for (let netdev, want in supplicants)
		supplicant_start(want, ids);
	for (let netdev, want in authenticators)
		authenticator_start(want, ids);
}

/**
 * Runs apply() soon, once for a burst of events.
 */
function apply_schedule() {
	if (apply_timer)
		apply_timer.set(APPLY_DELAY_MS);
	else
		apply_timer = uloop.timer(APPLY_DELAY_MS, apply);
}

/**
 * Renews the addresses of the netifd interfaces on a netdev, for
 * AuthenticationSuccessPolicy RenewConnection.
 *
 * @param {string} netdev - Netdev name
 */
function connection_renew(netdev) {
	for (let iface in ubus.call('network.interface', 'dump', {})?.interface ?? []) {
		if (!iface.up)
			continue;
		if (iface.l3_device != netdev && iface.device != netdev)
			continue;

		ubus.call(`network.interface.${iface.interface}`, 'renew', {});
		log_info('ieee8021x: renewing %s after the authentication on %s', iface.interface, netdev);
	}
}

/**
 * Handles a control event of a supplicant.
 *
 * @param {string} netdev - Netdev name
 * @param {string} event - Event text, for example "CTRL-EVENT-EAP-SUCCESS ..."
 */
function ctrl_event(netdev, event) {
	let entry = running[netdev];
	if (!entry || index(event ?? '', 'CTRL-EVENT-EAP-SUCCESS') != 0)
		return;

	fail_timer_cancel(entry);
	if (entry.row.AuthenticationSuccessPolicy == 'RenewConnection')
		connection_renew(netdev);
}

/**
 * Handles a notification of the hostapd of an authenticator port. The
 * port is open while hostapd authorises at least one station on it.
 *
 * @param {string} netdev - Netdev of the port
 * @param {string} type - Notification type
 * @param {object} data - Notification data with the station address
 */
function station_event(netdev, type, data) {
	let port = ports[netdev];
	let mac = lc(data?.address ?? '');
	if (!port || mac == '')
		return;

	let was_open = length(port.stations) > 0;
	if (type == 'sta-authorized')
		port.stations[mac] = true;
	else if (index(STATION_GONE, type) >= 0)
		delete port.stations[mac];
	else
		return;

	let open = length(port.stations) > 0;
	if (open != was_open)
		port_auth_set(netdev, open);
}

/**
 * Handles the link loss of an authenticator port. netifd closes the port
 * by itself; hostapd forgets the stations, so they authenticate again when
 * the link comes back.
 *
 * @param {string} netdev - Netdev of the port
 */
function port_link_down(netdev) {
	let port = ports[netdev];
	if (!port)
		return;

	port.stations = {};
	ubus.call(`hostapd.${netdev}`, 'del_clients', {});
}

/**
 * Handles the notifications of the netifd devices. A new or linked netdev
 * can be one that a row waits for.
 *
 * @param {object} req - Notification
 * @returns {number} 0
 */
function device_notify(req) {
	if (req.type == 'add' || req.type == 'link_up')
		apply_schedule();
	else if (req.type == 'link_down')
		port_link_down(req.data?.name);

	return 0;
}

/**
 * Handles the control events of the supplicants.
 *
 * @param {object} req - Notification
 * @returns {number} 0
 */
function supplicant_notify(req) {
	if (req.type == 'ctrl-event')
		ctrl_event(req.data?.ifname, req.data?.event);

	return 0;
}

/**
 * Handles the station notifications of the authenticators.
 *
 * @param {object} req - Notification
 * @returns {number} 0
 */
function port_notify(req) {
	station_event(req.data?.ifname, req.type, req.data);

	return 0;
}

/**
 * Follows a change of the stored configuration.
 */
function digest_event() {
	config_load();
	apply_schedule();
}

/**
 * A restarted wpad has no interfaces left, so they start again. The
 * hostapd object of a port can appear after config_add returned, so the
 * subscription follows the object.
 *
 * @param {string} type - Event type
 * @param {object} data - Event data with the object path
 */
function object_event(type, data) {
	let path = data?.path ?? '';

	if (index(path, 'hostapd.') == 0 && ports[substr(path, length('hostapd.'))]) {
		port_subscriber?.subscribe(path);
		return;
	}

	if (path == 'wpa_supplicant') {
		for (let netdev, entry in running)
			entry.state = null;
	} else if (path == 'hostapd') {
		for (let netdev, port in ports)
			port.state = null;
	} else {
		return;
	}

	apply_schedule();
}

/**
 * Loads the rows and starts their daemons. The files of an earlier run
 * name the netdevs whose interfaces may still run.
 */
export function init() {
	config_load();

	for (let path in fs.glob(`${RUN_DIR}/*.conf`) ?? [])
		running[replace(fs.basename(path), /\.conf$/, '')] = { state: null, row: {} };
	for (let path in fs.glob(`${RUN_DIR}/*${AUTHENTICATOR_SUFFIX}`) ?? [])
		ports[replace(fs.basename(path), /\.hostapd$/, '')] = { state: null, stations: {} };

	ubus.listener('bbf-dm.digest', digest_event);
	ubus.listener('ubus.object.add', object_event);
	apply_schedule();
};

/**
 * Follows the netifd devices and the control events of the supplicants.
 * The authenticator ports are subscribed one by one, so the WiFi BSSs of
 * hostapd gain no subscriber. A notification does not name the object that
 * sent it, so each source has its own subscriber.
 */
export function subscribe() {
	ubus.subscriber(device_notify, null, [ 'network.device' ]);
	ubus.subscriber(supplicant_notify, null, [ 'wpa_supplicant.*' ]);
	port_subscriber = ubus.subscriber(port_notify);
};
