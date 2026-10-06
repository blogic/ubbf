// The uPTY session: one outbound WebSocket bridged to one local PTY.
//
// The agent is idle until something calls start() over ubus. It then dials the
// server, waits to be accepted, and spawns a shell only once the server says an
// operator is actually watching. Every limit that matters is enforced here
// rather than trusted to the far end.

'use strict';

import * as ws from 'uwsc';
import * as uloop from 'uloop';
import { mkdir, lstat, writefile, chmod, unlink } from 'fs';

import * as pty from 'upty.pty';
import * as config from 'upty.config';
import * as identity from 'upty.identity';
import { log_debug, log_err, log_info, log_warn } from 'upty.log';

const PROTO_VERSION = 1;
const AGENT_NAME = 'upty/1.0';

// Pause the PTY once this many bytes are queued in the WebSocket send buffer.
// uwsc's buffer is a fixed 64KB and overflowing it discards data silently, so
// the mark sits well below it.
const SEND_HIGH_WATER = 32 * 1024;

const CONNECT_TIMEOUT_MS = 15000;
const PING_TIMEOUT_MS = 30000;
const LIMIT_TICK_MS = 10000;

const TOKEN_RE = /^[A-Za-z0-9_-]{16,128}$/;

// Scheme, an authority without user info, and a path; the token is appended
// as the query, so the URL has none and no fragment.
const URL_RE = /^wss?:\/\/[][A-Za-z0-9.:_-]+\/[^?# [:cntrl:]]*$/;
const URL_MAX = 512;

// uwsc takes a CA as a file path, so a certificate handed over per session
// has to be written out for the duration of that session. /var/run is
// writable by root only, so no other user can put a link in its place.
const SESSION_CA_DIR = '/var/run/upty';
const SESSION_CA_PATH = SESSION_CA_DIR + '/ca.pem';
const SESSION_CA_MAX = 64 * 1024;

let state = 'idle';
let conn = null;
let term = null;
let session_no = 0;
let server_url = null;
let session_ca = null;
let started_at = 0;
let last_activity = 0;
let last_error = '';
let limit_timer = null;

function now() {
	return time();
}

function activity_mark() {
	last_activity = now();
}

function control_send(msg) {
	if (!conn)
		return false;

	log_debug('-> %J', msg);

	return conn.send(msg);
}

/**
 * Ends the session and returns the agent to idle. Safe to call from any state.
 *
 * @param {string} reason Logged, and sent as the WebSocket close reason
 * @param {boolean} [failed] Whether the reason is kept as LastError
 * @param {boolean} [at_once] Kill the shell's processes at once, for an
 *   agent that exits
 */
function teardown(reason, failed, at_once) {
	if (state == 'idle')
		return;

	log_info('session %d ended: %s', session_no, reason);

	if (failed)
		last_error = reason;

	if (limit_timer) {
		limit_timer.cancel();
		limit_timer = null;
	}

	if (term) {
		term.close(at_once);
		term = null;
	}

	if (conn) {
		conn.close(1000, reason);
		conn = null;
	}

	if (session_ca) {
		unlink(session_ca);
		session_ca = null;
	}

	state = 'idle';
	server_url = null;
	started_at = 0;
}

function limits_check() {
	let cfg = config.get();
	let elapsed = now() - started_at;

	if (cfg.max_session > 0 && elapsed >= cfg.max_session) {
		teardown('session time limit reached');
		return;
	}

	if (cfg.idle_timeout > 0 && (now() - last_activity) >= cfg.idle_timeout)
		teardown('idle timeout');
}

function shell_start(cols, rows) {
	let cfg = config.get();

	if (term) {
		log_warn('start ignored, shell already running');
		return;
	}

	try {
		term = pty.spawn({
			shell: cfg.shell,
			args: cfg.shell_args,
			env: config.shell_env(),
			cols: cols,
			rows: rows,
			on_data: function(data) {
				activity_mark();

				if (!conn.send(data, true)) {
					log_warn('send failed, dropping session');
					teardown('send failed', true);
					return;
				}

				// Stop draining before the send buffer can overflow; on_drain
				// resumes us once it has emptied again
				if (conn.pending() > SEND_HIGH_WATER)
					term.pause();
			},
			on_exit: function(code) {
				log_info('shell exited with %d', code);
				control_send({ type: 'exit', code: code });
				teardown('shell exited');
			}
		});
	} catch (e) {
		log_err('pty spawn failed: %s', e);
		term = null;
	}

	if (!term) {
		control_send({ type: 'error', message: 'failed to start the shell' });
		teardown('shell start failed', true);
		return;
	}

	state = 'active';
	activity_mark();
	control_send({ type: 'started', pid: term.pid() });
}

function control_handle(msg) {
	log_debug('<- %J', msg);

	switch (msg.type) {
	case 'accept':
		if (state != 'connecting') {
			log_warn('accept in state %s ignored', state);
			break;
		}
		state = 'connected';
		log_info('session %d accepted by server', session_no);
		break;

	case 'reject':
		log_warn('session %d rejected: %s', session_no, msg.reason ?? 'no reason');
		teardown('rejected by server', true);
		break;

	case 'start':
		if (state != 'connected') {
			log_warn('start in state %s ignored', state);
			break;
		}

		if (!pty.winsize_valid(msg.cols ?? 80, msg.rows ?? 24)) {
			control_send({ type: 'error', message: 'invalid window size' });
			teardown('invalid window size from server', true);
			break;
		}

		shell_start(msg.cols ?? 80, msg.rows ?? 24);
		break;

	case 'resize':
		term?.resize(msg.cols, msg.rows);
		break;

	case 'stop':
		teardown('stopped by server');
		break;

	default:
		log_warn('unknown control message %s', msg.type ?? '(none)');
	}
}

function on_connect() {
	log_info('session %d connected to %s', session_no, server_url);

	control_send({
		type: 'hello',
		proto: PROTO_VERSION,
		agent: AGENT_NAME,
		device: identity.describe()
	});

	activity_mark();
}

function on_recv(message) {
	activity_mark();

	if (message.binary) {
		if (term && !term.write(message.data)) {
			control_send({ type: 'error', message: 'input queue full' });
			teardown('input queue full', true);
		}
		return;
	}

	try {
		control_handle(json(message.data));
	} catch (e) {
		log_warn('malformed control message: %s', e);
	}
}

function on_drain() {
	// The send buffer has emptied, so the PTY can be read again
	if (term && !term.draining())
		term.resume();
}

/**
 * Makes the uwsc callbacks of one session. uwsc can call a callback of a
 * closed connection until it frees it, so each callback checks that its
 * session is still the current one.
 *
 * @param {number} no - Session number
 * @returns {object} on_connect, on_recv, on_drain, on_disconnect, on_error
 */
function callbacks_make(no) {
	let current = () => no == session_no && state != 'idle';

	return {
		on_connect: (c) => current() && on_connect(),
		on_recv: (c, message) => current() && on_recv(message),
		on_drain: (c) => current() && on_drain(),
		on_disconnect: (c) => current() && teardown('server closed the connection', state == 'connecting'),
		on_error: (c, error) => {
			if (!current())
				return;
			log_err('websocket error: %s', error);
			teardown(error, true);
		}
	};
}

/**
 * Validates the URL a controller asked us to dial.
 *
 * @param {string} url
 * @returns {?string} An error message, or null when the URL is acceptable
 */
export function url_check(url) {
	if (type(url) != 'string' || !length(url))
		return 'url is required';

	if (length(url) > URL_MAX)
		return 'url is too long';

	if (!match(url, URL_RE))
		return 'url must be ws:// or wss:// with a host and a path, without query or fragment';

	return null;
}

/**
 * Validates a token handed over by a controller.
 *
 * @param {*} token
 * @returns {boolean} true for 16 to 128 characters of [A-Za-z0-9_-]
 */
export function token_valid(token) {
	return type(token) == 'string' && match(token, TOKEN_RE) != null;
}

/**
 * Validates a CA certificate handed over by a controller.
 *
 * @param {string} pem
 * @returns {?string} An error message, or null when the PEM is acceptable
 */
export function ca_check(pem) {
	if (length(pem) > SESSION_CA_MAX)
		return 'CA certificate is too large';

	if (index(pem, '-----BEGIN CERTIFICATE-----') < 0)
		return 'CA certificate is not PEM';

	return null;
}

/**
 * Writes a per-session CA certificate where uwsc can read it. The directory
 * must be a real directory of root with mode 0700.
 *
 * @param {string} pem
 * @returns {?string} The file path, or null when it could not be written
 */
function session_ca_write(pem) {
	mkdir(SESSION_CA_DIR, 0700);

	let st = lstat(SESSION_CA_DIR);

	if (st?.type != 'directory' || st.uid != 0 || (st.mode & 0777) != 0700) {
		log_err('%s is not a private directory of root', SESSION_CA_DIR);
		return null;
	}

	if (writefile(SESSION_CA_PATH, pem) == null)
		return null;

	chmod(SESSION_CA_PATH, 0600);

	return SESSION_CA_PATH;
}

/**
 * Checks a start request.
 *
 * @param {object} args - token, url, allow_insecure, ca_cert
 * @returns {?object} The refusal: `error`, and `invalid` for input a
 *   controller must correct; null when the request can start
 */
function start_check(args) {
	let cfg = config.get();

	if (!cfg.enabled)
		return { error: 'upty is disabled in configuration' };

	if (state != 'idle')
		return { error: `busy, session already ${state}` };

	if (!token_valid(args.token))
		return { error: 'token missing or malformed', invalid: true };

	let url_error = url_check(args.url);

	if (url_error)
		return { error: url_error, invalid: true };

	if (type(args.ca_cert) == 'string' && length(args.ca_cert)) {
		let ca_error = ca_check(args.ca_cert);

		if (ca_error)
			return { error: ca_error, invalid: true };
	}

	// Plaintext carries the session, the token and the shell in the clear.
	// The device configuration is the ceiling, a session can only lower it.
	let plaintext = substr(args.url, 0, 5) == 'ws://';

	if (plaintext && !(cfg.allow_insecure && (args.allow_insecure ?? true)))
		return { error: 'plaintext ws:// refused by the device configuration' };

	return null;
}

function start_handler(req) {
	let cfg = config.get();
	let args = req.args ?? {};
	let refusal = start_check(args);

	if (refusal)
		return refusal;

	if (type(args.ca_cert) == 'string' && length(args.ca_cert)) {
		session_ca = session_ca_write(args.ca_cert);

		if (!session_ca)
			return { error: 'cannot store the session CA certificate' };
	}

	session_no++;
	server_url = args.url;
	last_error = '';

	let opts = {
		connection_timeout: CONNECT_TIMEOUT_MS,
		ping_timeout: PING_TIMEOUT_MS,
		// An operator may legitimately stare at an idle prompt; the session
		// limits below are ours to enforce, not the transport's
		idle_timeout: 0,
		// A one-shot session must never redial on its own
		reconnect_timeout: 0,
		ssl_verify: cfg.verify_peer,
		user_agent: AGENT_NAME,
		...callbacks_make(session_no)
	};

	// An empty ca_cert would be taken as a path and fail the handshake
	if (session_ca)
		opts.ca_cert = session_ca;
	else if (length(cfg.ca_cert))
		opts.ca_cert = cfg.ca_cert;

	state = 'connecting';

	let c = ws.connect(`${server_url}?token=${args.token}`, opts);

	// on_error can run inside connect() and end the session before the
	// connection is known here
	if (!c || state == 'idle') {
		c?.close(1000, 'connect failed');
		log_err('connect to %s failed', server_url ?? args.url);
		teardown('connect failed', true);
		return { error: last_error };
	}

	conn = c;

	started_at = now();
	activity_mark();
	limit_timer = uloop.interval(LIMIT_TICK_MS, limits_check);

	log_info('session %d dialling %s, command key %J', session_no, server_url, args.command_key ?? '');

	return { started: true };
}

function stop_handler(req) {
	if (state == 'idle')
		return { stopped: false };

	teardown(req.args?.reason ?? 'stopped locally');

	return { stopped: true };
}

function status_handler(req) {
	let cfg = config.get();

	let status = {
		state: state,
		enabled: cfg.enabled,
		shell: cfg.shell,
		last_error: last_error
	};

	if (state == 'idle')
		return status;

	status.session = session_no;
	status.url = server_url;
	status.uptime = now() - started_at;
	status.idle = now() - last_activity;
	status.socket = conn ? conn.state() : 'none';
	status.pending = conn ? conn.pending() : 0;

	if (term) {
		status.pid = term.pid();
		status.pts = term.pts;
		status.draining = term.draining();
	}

	return status;
}

/**
 * The ubus method table published as the `upty` object.
 *
 * @returns {object}
 */
export function ubus_methods() {
	return {
		start: {
			call: start_handler,
			args: { token: '', url: '', allow_insecure: false, ca_cert: '', command_key: '' }
		},
		stop: {
			call: stop_handler,
			args: { reason: '' }
		},
		status: {
			call: status_handler,
			args: {}
		}
	};
};

/** Ends a running session when the configuration disabled the agent. */
export function config_changed() {
	if (!config.get().enabled)
		teardown('disabled in configuration');
};

/** Ends any running session. Called on daemon shutdown. */
export function shutdown() {
	teardown('agent shutting down', false, true);
};
