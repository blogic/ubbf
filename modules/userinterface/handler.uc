'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const on_commit = ubbf_module.on_commit;
const config_apply = ubbf_module.config_apply;
const datetime_format = ubbf_module.utils.helpers.datetime_format;
const logging = ubbf_module.utils.logging;
const instance_map = ubbf_module.utils['instance-map'];

const fs = require('fs');
const ubus = require('ubus');
const uloop = require('uloop');

const schema = ubbf_module.schema;

let certificates = {};
include('../security/certificates.uc', { certificates, instance_map });

const CONFIG_PATH = '/etc/ubbf/config.json';

/**
 * Reports whether Device.UserInterface is enabled, the gate of every
 * HTTPAccess row.
 *
 * @param {object|null} ui - Device.UserInterface config
 * @returns {boolean}
 */
function ui_enabled(ui) {
	return ubbf.to_bool(ui?.Enable ?? 'true');
}

// ubbf-ui writes its signed-in sessions here. A file instead of a ubus call,
// so that the agent never waits on the web UI worker.
const UI_RUN_DIR = '/var/run/ubbf-ui';
const SESSIONS_PATH = `${UI_RUN_DIR}/sessions.json`;

// ubbf-ui writes the state of each listener here, by HTTPAccess instance,
// when it writes its uwsd configuration.
const STATUS_PATH = `${UI_RUN_DIR}/status.json`;
const STATUS_VALUES = [ 'Up', 'Down', 'Error' ];

// CreateWebSession() leaves one file per web session here, and ubbf-ui signs
// a connection in with its secret. The files hold the secrets, so only root
// can read them.
const WEBSESSIONS_DIR = `${UI_RUN_DIR}/websessions`;
const WEBSESSIONS_MAX = 16;

const TIMEOUT_MAX = 4294967295;

// uloop.timer() keeps its delay in a C int of milliseconds, so a longer
// AutoDisableDuration is waited out in steps of one day.
const TIMER_STEP_MAX = 86400;

// A reboot clears this directory, so the monotonic times in the record stay
// valid across a restart of the agent, and the window of AutoDisableDuration
// starts again at boot, when the clock may not be set yet.
const ACTIVATION_DIR = '/tmp/ubbf';
const ACTIVATION_PATH = `${ACTIVATION_DIR}/httpaccess-activation.json`;

let expiry_timers = {};

/**
 * Reads a JSON file.
 *
 * @param {string} path - File path
 * @returns {*} Parsed value, or null when the file is missing or invalid
 */
function json_load(path) {
	try {
		return json(fs.readfile(path) ?? 'null');
	} catch (e) {
		return null;
	}
}

/**
 * Returns the monotonic clock in seconds. CLOCK_MONOTONIC is the same for
 * every process, so the agent and ubbf-ui compare the same times.
 *
 * @returns {number} Seconds
 */
function mono_now() {
	return clock(true)[0];
}

/**
 * Reads the signed-in connections that ubbf-ui records.
 *
 * @returns {array} Array of session objects or empty array
 */
function sessions_get() {
	let sessions = json_load(SESSIONS_PATH)?.sessions;
	return (type(sessions) == 'array') ? sessions : [];
}

/**
 * Tests whether the AbsoluteTimeout of a web session ran out. ubbf-ui
 * removes the file of an expired web session; this check covers the time
 * until it does.
 *
 * @param {object} entry - Web session file content
 * @returns {boolean} True when expired
 */
function websession_expired(entry) {
	return entry.absolute > 0 && mono_now() - entry.created_mono >= entry.absolute;
}

/**
 * Reads the web sessions that CreateWebSession() made and that did not
 * expire.
 *
 * @returns {array} Web session entries
 */
function websessions_get() {
	let entries = [];

	for (let name in sort(fs.lsdir(WEBSESSIONS_DIR) ?? [])) {
		let entry = json_load(`${WEBSESSIONS_DIR}/${name}`);
		if (type(entry) == 'object' && entry.id && !websession_expired(entry))
			push(entries, entry);
	}

	return entries;
}

/**
 * Lists the sessions of one HTTPAccess row. A signed-in connection is one
 * session. A web session from CreateWebSession() is one session, also
 * before a browser opens it and while several connections use it; it shows
 * the address of the connection that signed in last.
 *
 * ubbf-ui records the Alias of the row with each session; the Alias is
 * unique, a port is not once listeners bind to their interface.
 *
 * @param {object} row - HTTPAccess row
 * @returns {array} `{ id, websession, user, ip, peer_port, protocol, start }`
 */
function sessions_rows(row) {
	let alias = row?.Alias;
	if (!alias)
		return [];

	let conns = filter(sessions_get(), (s) => s.alias == alias);
	let rows = filter(conns, (s) => !s.websession);

	for (let entry in websessions_get()) {
		if (entry.alias != alias)
			continue;

		let conn = filter(conns, (s) => s.websession == entry.id)[-1];
		push(rows, {
			id: entry.id,
			websession: true,
			ip: conn?.ip,
			peer_port: conn?.peer_port,
			protocol: conn?.protocol ?? row.Protocol,
			start: entry.created
		});
	}

	return rows;
}

/**
 * Converts a session object to TR-181 HTTPAccess_Session format.
 *
 * @param {object} session - Entry of sessions_rows()
 * @returns {object} TR-181 formatted Session object
 */
function session_to_object(session) {
	let out = {
		SessionID: session.id ?? '',
		User: session.user ? `Device.Users.User.${session.user}` : '',
		IPAddress: session.ip ?? '',
		Protocol: session.protocol ?? '',
		StartDate: datetime_format(session.start)
	};

	// A web session that no browser opened yet has no port, and TR-181
	// gives Port the range 1 to 65535.
	if (session.peer_port)
		out.Port = sprintf('%d', session.peer_port);

	return out;
}

/**
 * Lists the sessions of a row with the stable instance number of each.
 * TR-369 asks that an instance number does not change while the object
 * exists, and Delete() acts on the number that the controller read.
 *
 * @param {object} row - HTTPAccess row
 * @returns {object} Instance number to entry of sessions_rows()
 */
function sessions_numbered(row) {
	let sessions = sessions_rows(row);
	let table = `Device.UserInterface.HTTPAccess.${row?.Alias}.Session`;
	let ids = map(sessions, (s) => s.id);
	let by_id = {};

	for (let s in sessions)
		by_id[s.id] = s;

	instance_map.instance_prune(table, ids);

	return instance_map.instance_rows(table, ids, (id) => by_id[id]);
}

/**
 * Get handler for Device.UserInterface.HTTPAccess.{i}.Session.{i}.
 *
 * @param {object} ctx - Context with parent row and optional instance number
 * @returns {object|null} Single session or enumerated sessions
 */
function session_get(ctx) {
	let sessions = sessions_numbered(ctx.parent);

	if (ctx.instance == null) {
		let out = {};
		for (let n, session in sessions)
			out[n] = session_to_object(session);
		return out;
	}

	let session = sessions[`${ctx.instance}`];
	return session ? session_to_object(session) : null;
}

/**
 * Returns random bytes as hex digits.
 *
 * @param {number} count - Number of bytes
 * @returns {string|null} Hex string, or null when /dev/urandom fails
 */
function random_hex(count) {
	let f = fs.open('/dev/urandom', 'r');
	if (!f)
		return null;

	let data = f.read(count);
	f.close();

	return (length(data) == count) ? hexenc(data) : null;
}

/**
 * Returns the RoleName that a web session of a row gets: the first enabled
 * role of AllowedRoles, the same order in which a login picks the role.
 *
 * @param {object} row - HTTPAccess row
 * @param {object} root - Root config
 * @returns {string|null} RoleName
 */
function websession_role(row, root) {
	let roles = root?.Device?.Users?.Role ?? {};

	for (let ref in split(row.AllowedRoles ?? '', ',')) {
		let m = match(trim(ref), /^Device\.Users\.Role\.([0-9]+)\.?$/);
		let role = m ? roles[m[1]] : null;
		if (ubbf.to_bool(role?.Enable) && role?.RoleName)
			return role.RoleName;
	}

	return null;
}

/**
 * Parses a timeout argument of CreateWebSession().
 *
 * @param {*} value - Argument value
 * @returns {number|null} Seconds, or null when it is not an unsignedInt
 */
function timeout_parse(value) {
	if (value == null || value == '')
		return 0;

	let s = `${value}`;
	if (!match(s, /^[0-9]{1,10}$/))
		return null;

	let n = int(s);
	return (n <= TIMEOUT_MAX) ? n : null;
}

/**
 * Logs why CreateWebSession() failed; the controller gets only the code.
 *
 * @param {array} instances - [ HTTPAccess instance ]
 * @param {string} reason - Cause of the failure
 * @param {number|null} code - Negative USP error code, or null for 7022
 * @returns {number|null} code
 */
function websession_refuse(instances, reason, code) {
	logging.log_err('userinterface: HTTPAccess.%s.CreateWebSession(): %s', instances[0], reason);
	return code;
}

/**
 * Handler for Device.UserInterface.HTTPAccess.{i}.CreateWebSession(). The
 * session gets the first allowed role of the row and no user. The browser
 * opens Path on the listener of the row; ubbf-ui then signs it in.
 *
 * @param {object} input - { AbsoluteTimeout, IdleTimeout }
 * @param {string} command_key - Command tracking key
 * @param {array} instances - [ HTTPAccess instance ]
 * @param {object} root - Root config
 * @returns {object|null} { SessionID, Path }, or null on failure
 */
function websession_create(input, command_key, instances, root) {
	let ui = root?.Device?.UserInterface;
	let row = ui?.HTTPAccess?.[`${instances[0]}`];
	let absolute = timeout_parse(input?.AbsoluteTimeout);
	let idle = timeout_parse(input?.IdleTimeout);

	if (absolute == null || idle == null)
		return websession_refuse(instances, 'timeouts must be unsignedInt',
					 -USP_ERR_INVALID_COMMAND_ARGS);

	if (!row?.Alias)
		return websession_refuse(instances, 'the row has no Alias', null);

	if (!ui_enabled(ui) || !ubbf.to_bool(row.Enable))
		return websession_refuse(instances, 'the row is disabled', null);

	let role = websession_role(row, root);
	if (!role)
		return websession_refuse(instances, 'no enabled role in AllowedRoles', null);

	if (length(filter(websessions_get(), (e) => e.alias == row.Alias)) >= WEBSESSIONS_MAX)
		return websession_refuse(instances, sprintf('%d web sessions exist', WEBSESSIONS_MAX), null);

	let id = random_hex(8);
	let secret = random_hex(16);
	if (!id || !secret)
		return websession_refuse(instances, '/dev/urandom failed', null);

	let entry = {
		id: `ws-${id}`,
		alias: row.Alias,
		role,
		secret,
		absolute,
		idle,
		created: time(),
		created_mono: mono_now()
	};
	let path = `${WEBSESSIONS_DIR}/${entry.id}.json`;
	let tmp = `${path}.tmp`;

	fs.mkdir(UI_RUN_DIR, 0755);
	fs.mkdir(WEBSESSIONS_DIR, 0700);
	if (fs.writefile(tmp, sprintf('%J\n', entry)) == null || !fs.chmod(tmp, 0600) || !fs.rename(tmp, path)) {
		fs.unlink(tmp);
		return websession_refuse(instances, `failed to write ${path}`, null);
	}

	return { SessionID: entry.id, Path: `/session/${secret}` };
}

/**
 * Handler for Device.UserInterface.HTTPAccess.{i}.Session.{i}.Delete(). It
 * removes the file of a web session and tells ubbf-ui with a ubus event,
 * which goes to ubusd only, so the agent does not wait on the web UI.
 *
 * @param {object} input - No arguments
 * @param {string} command_key - Command tracking key
 * @param {array} instances - [ HTTPAccess instance, Session instance ]
 * @param {object} root - Root config
 * @returns {object|null} Empty result, or null when there is no session
 */
function session_delete(input, command_key, instances, root) {
	let row = root?.Device?.UserInterface?.HTTPAccess?.[`${instances[0]}`];
	let session = sessions_numbered(row)[`${instances[1]}`];
	if (!session)
		return null;

	if (session.websession)
		fs.unlink(`${WEBSESSIONS_DIR}/${session.id}.json`);

	if (!ubus.event('ubbf-ui.session-delete', { id: session.id }))
		logging.log_err('userinterface: failed to send the delete of session %s', session.id);

	return {};
}

/**
 * Splits a comma-separated list value.
 *
 * @param {string} value - List value
 * @returns {array} Trimmed, non-empty items
 */
function list_split(value) {
	let items = map(split(value ?? '', ','), (s) => trim(s));
	return filter(items, (s) => s != '');
}

/**
 * Tests whether a string is an IP prefix of one family, `address/length`.
 *
 * @param {string} prefix - Candidate prefix
 * @param {number} family - 4 or 6
 * @returns {boolean} True for a valid prefix
 */
function prefix_valid(prefix, family) {
	let parts = split(prefix, '/');
	if (length(parts) != 2)
		return false;

	let addr = iptoarr(parts[0]);
	let len = int(parts[1]);
	let bits = (family == 4) ? 32 : 128;

	return addr != null && length(addr) * 8 == bits &&
		match(parts[1], /^[0-9]+$/) != null && len <= bits;
}

/**
 * Returns the activation record: for each enabled HTTPAccess row, by Alias,
 * the time it was enabled (`date`, wall clock; `mono`, monotonic seconds),
 * its AutoDisableDuration and the monotonic `deadline`, 0 for none.
 *
 * @returns {object} Records by Alias
 */
function activation_load() {
	let record = json_load(ACTIVATION_PATH);
	return (type(record) == 'object') ? record : {};
}

/**
 * Builds the activation entry of an enabled row. A new entry starts at
 * `now`. A change of AutoDisableDuration starts the countdown again, so
 * that a controller which sets it on a row that is already enabled gets
 * the full duration.
 *
 * @param {object|null} prev - Entry of the last sync
 * @param {number} duration - AutoDisableDuration in seconds
 * @param {object} now - `{ date, mono }`
 * @returns {object} Entry
 */
function activation_entry(prev, duration, now) {
	let deadline = (duration > 0) ? now.mono + duration : 0;

	if (!prev)
		return { date: now.date, mono: now.mono, duration, deadline };

	if (prev.duration == duration)
		return prev;

	return { ...prev, duration, deadline };
}

/**
 * Disables the HTTPAccess row with an Alias, when its AutoDisableDuration
 * has run out.
 *
 * @param {string} alias - Alias of the row
 */
function row_expire(alias) {
	let rows = json_load(CONFIG_PATH)?.Device?.UserInterface?.HTTPAccess;

	for (let inst, row in rows) {
		if (row?.Alias != alias)
			continue;

		let path = `Device.UserInterface.HTTPAccess.${inst}.Enable`;
		let report = (result) => {
			if (result?.success)
				logging.log_info('userinterface: %s disabled, AutoDisableDuration ran out', path);
			else
				logging.log_err('userinterface: failed to disable %s', path);
		};
		let result = config_apply([ { op: 'set', path, value: 'false' } ], report);
		if (result)
			report(result);
		return;
	}
}

/**
 * Starts the expiry timer of one row. A deadline more than a day away is
 * reached in steps.
 *
 * @param {string} alias - Alias of the row
 * @param {number} deadline - Monotonic second at which the row expires
 */
function expiry_timer_add(alias, deadline) {
	let delay = min(max(deadline - mono_now(), 0), TIMER_STEP_MAX);

	expiry_timers[alias] = uloop.timer(delay * 1000, () => {
		delete expiry_timers[alias];
		if (mono_now() < deadline)
			return expiry_timer_add(alias, deadline);

		try {
			row_expire(alias);
		} catch (e) {
			logging.log_exception('userinterface: expiry', e);
		}
	});
}

/**
 * Arms one timer for each row with a deadline. A row whose deadline is
 * past expires on the next turn of the event loop, never inside the commit
 * hook, which runs while the transaction ends.
 *
 * @param {object} record - Activation record
 */
function expiry_arm(record) {
	for (let alias, timer in expiry_timers)
		timer.cancel();
	expiry_timers = {};

	for (let alias, entry in record)
		if (entry.deadline)
			expiry_timer_add(alias, entry.deadline);
}

/**
 * Removes the web sessions of every row that is not enabled, so that a
 * secret does not become valid again when its row is enabled later.
 * ubbf-ui closes their connections when it sees the files go.
 *
 * @param {object} record - Activation record, by Alias of the enabled rows
 */
function websessions_prune(record) {
	for (let entry in websessions_get()) {
		if (entry.alias in record)
			continue;
		if (!fs.unlink(`${WEBSESSIONS_DIR}/${entry.id}.json`))
			logging.log_err('userinterface: failed to remove web session %s', entry.id);
	}
}

/**
 * Commit hook: records when each HTTPAccess row became enabled, arms the
 * timers of AutoDisableDuration and removes the web sessions of the other
 * rows. A row counts as enabled while it and Device.UserInterface are
 * enabled.
 */
function activation_sync() {
	let ui = json_load(CONFIG_PATH)?.Device?.UserInterface;
	let ui_on = ui_enabled(ui);
	let prev = activation_load();
	let now = { date: time(), mono: mono_now() };
	let record = {};

	for (let inst, row in ui?.HTTPAccess) {
		if (!ui_on || !ubbf.to_bool(row?.Enable) || !row?.Alias)
			continue;

		let duration = int(row.AutoDisableDuration ?? '0');
		record[row.Alias] = activation_entry(prev[row.Alias], duration, now);
	}

	if (sprintf('%J', record) != sprintf('%J', prev)) {
		fs.mkdir(ACTIVATION_DIR, 0755);
		if (!fs.writefile(ACTIVATION_PATH, sprintf('%.J\n', record)))
			logging.log_err('userinterface: failed to write %s', ACTIVATION_PATH);
	}

	expiry_arm(record);
	websessions_prune(record);
}

/**
 * Get handler for Device.UserInterface.
 *
 * @param {object} ctx - Context with config
 * @returns {object} Computed UserInterface properties
 */
function userinterface_get(ctx) {
	let instances = ctx.config?.HTTPAccess;

	return {
		...ctx.config,
		HTTPAccessSupportedProtocols: 'HTTP,HTTPS',
		HTTPAccessNumberOfEntries: sprintf('%d', length(instances))
	};
}

/**
 * Tests whether the Interface or the CABundle of a row does not resolve.
 * The render then keeps the listener off, and the firewall hook opens
 * nothing.
 *
 * @param {object} row - HTTPAccess row
 * @param {object} root - Root config or runtime tree
 * @returns {boolean} True when a reference does not resolve
 */
function http_access_unresolved(row, root) {
	if (row.Interface && !ubbf.get(root, row.Interface)?.Name)
		return true;

	return !!row.CABundle && !certificates.cabundle_path_resolve(row.CABundle);
}

/**
 * Get handler for Device.UserInterface.HTTPAccess.{i}.
 *
 * @param {object} ctx - Context with config and root
 * @returns {object|null} HTTPAccess row with its Status, TimeLeft and
 *   ActivationDate
 */
function http_access_get(ctx) {
	if (!ctx.config)
		return null;

	let ui_on = ui_enabled(ctx.root?.Device?.UserInterface);
	let up = ui_on && ubbf.to_bool(ctx.config.Enable);
	let entry = up ? activation_load()[ctx.config.Alias] : null;
	let time_left = entry?.deadline ? max(entry.deadline - mono_now(), 0) : 0;
	let status = up ? json_load(STATUS_PATH)?.[`${ctx.instance}`]?.status : null;

	// The render keeps such a row off, so ubbf-ui sees only a disabled row
	if (up && http_access_unresolved(ctx.config, ctx.root))
		status = 'Error';

	return {
		...ctx.config,
		Status: (index(STATUS_VALUES, status) >= 0) ? status : 'Down',
		TimeLeft: sprintf('%d', time_left),
		ActivationDate: datetime_format(entry?.date)
	};
}

/**
 * Set handler for Device.UserInterface.HTTPAccess.{i}: Alias must not be
 * empty and no other row may hold it, because the timer, the sessions and
 * the web sessions of a row are keyed by it; each AllowedRoles
 * item must name a Device.Users.Role row, each source prefix must be of
 * its family, Interface must be empty or name a row of Device.IP.Interface
 * or Device.Logical.Interface, Certificate must be empty or name a row of
 * Device.Security.Certificate that has a private key, and CABundle must be
 * empty or name a row of Device.Security.CABundle.
 *
 * @param {object} ctx - Context with param, value and root
 * @returns {number} 0 on success, a negative USP error code to refuse
 */
function http_access_set(ctx) {
	switch (ctx.param) {
	case 'Alias':
		if (ctx.value == '')
			return -USP_ERR_INVALID_VALUE;
		let holders = filter(values(ctx.root?.Device?.UserInterface?.HTTPAccess ?? {}),
			(row) => row?.Alias == ctx.value);
		return (length(holders) > 1) ? -USP_ERR_UNIQUE_KEY_CONFLICT : 0;

	case 'AllowedRoles':
		let roles = ctx.root?.Device?.Users?.Role ?? {};
		for (let ref in list_split(ctx.value)) {
			let m = match(ref, /^Device\.Users\.Role\.([0-9]+)\.?$/);
			if (!m || !roles[m[1]])
				return -USP_ERR_INVALID_VALUE;
		}
		return 0;

	case 'IPv4AllowedSourcePrefix':
	case 'IPv6AllowedSourcePrefix':
		let family = (ctx.param == 'IPv4AllowedSourcePrefix') ? 4 : 6;
		for (let prefix in list_split(ctx.value))
			if (!prefix_valid(prefix, family))
				return -USP_ERR_INVALID_VALUE;
		return 0;

	case 'Interface':
		if (ctx.value == '')
			return 0;
		let iface = match(ctx.value, /^(Device\.(IP|Logical)\.Interface\.[0-9]+)\.?$/);
		return (iface && ubbf.get(ctx.root, iface[1])) ? 0 : -USP_ERR_INVALID_VALUE;

	case 'Certificate':
		if (ctx.value == '')
			return 0;
		if (!match(ctx.value, /^Device\.Security\.Certificate\.[0-9]+\.?$/))
			return -USP_ERR_INVALID_VALUE;
		let cert = certificates.certificate_path_resolve(ctx.value);
		return (cert && certificates.certificate_key_path(cert)) ? 0 : -USP_ERR_INVALID_VALUE;

	case 'CABundle':
		if (ctx.value != '' && !match(ctx.value, /^Device\.Security\.CABundle\.[0-9]+\.?$/))
			return -USP_ERR_INVALID_VALUE;
		if (ctx.value != '' && !certificates.cabundle_path_resolve(ctx.value))
			return -USP_ERR_INVALID_VALUE;
		return 0;
	}

	return 0;
}

/**
 * Builds the firewall claim of one address family of a listener, or null
 * when that family may not connect: TR-181 allows no connection while
 * AllowAll is false and the prefix list is empty.
 *
 * @param {object} inst - HTTPAccess instance data
 * @param {string} family - '4' or '6'
 * @param {string} alias - Alias of the claim
 * @param {string} port - Listen port
 * @returns {object|null} Service descriptor
 */
function http_access_claim(inst, family, alias, port) {
	let all = ubbf.to_bool(inst[`AllowAllIPv${family}`]);
	let prefixes = list_split(inst[`IPv${family}AllowedSourcePrefix`]);

	if (!all && !length(prefixes))
		return null;

	return {
		type: 'Service',
		alias: `${alias}-v${family}`,
		Interface: inst.Interface,
		Protocol: '6',
		DestPort: port,
		IPVersion: family,
		SourcePrefixes: all ? '' : join(',', prefixes),
		Action: 'Accept'
	};
}

/**
 * Firewall hook for Device.UserInterface.HTTPAccess.{i}.
 *
 * @param {object} inst - HTTPAccess instance data
 * @param {object} root - Root config data
 * @param {string} path - Instance path
 * @returns {array|null} Service descriptors for the web UI port
 */
function http_access_firewall(inst, root, path) {
	if (!ubbf.to_bool(inst.Enable) || !ui_enabled(root?.Device?.UserInterface))
		return null;
	if (!inst.Interface || inst.Interface == '')
		return null;

	if (http_access_unresolved(inst, root))
		return null;

	let iface = ubbf.get(root, inst.Interface);

	let port = sprintf('%s', inst.Port ?? '443');
	let alias = sprintf('cpe-webui-%s-%s', iface.Name, port);

	if (ubbf.to_bool(inst.AllowAllIPv4) && ubbf.to_bool(inst.AllowAllIPv6))
		return [{
			type: 'Service',
			alias,
			Interface: inst.Interface,
			Protocol: '6',
			DestPort: port,
			Action: 'Accept'
		}];

	return filter([
		http_access_claim(inst, '4', alias, port),
		http_access_claim(inst, '6', alias, port)
	], (claim) => claim != null);
}

model['Device.UserInterface'] = {
	schema: schema('UserInterface'),
	get: userinterface_get
};

model['Device.UserInterface.HTTPAccess'] = {};

model['Device.UserInterface.HTTPAccess.{i}'] = {
	schema: schema('HTTPAccess'),
	get: http_access_get,
	set: http_access_set,
	firewall: http_access_firewall
};

model['Device.UserInterface.HTTPAccess.{i}.Session'] = {};

model['Device.UserInterface.HTTPAccess.{i}.Session.{i}'] = {
	schema: schema('HTTPAccess_Session'),
	get: session_get,
	addable: false
};

operations['Device.UserInterface.HTTPAccess.{i}.CreateWebSession()'] = {
	type: 'sync',
	handler: websession_create
};

operations['Device.UserInterface.HTTPAccess.{i}.Session.{i}.Delete()'] = {
	type: 'sync',
	handler: session_delete
};

on_commit(activation_sync);
