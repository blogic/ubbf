// UCI-backed configuration for the uPTY agent.
//
// Everything the agent will not let a server decide lives here: the shell it
// runs, whether plaintext is permitted at all, and the limits that bound a
// session. A controller can ask for plaintext per session, but only where
// allow_insecure permits it.

'use strict';

import * as uci from 'uci';

import { log_err, log_warn } from 'upty.log';

const CONFIG = 'upty';
const SECTION = 'agent';

const DEFAULTS = {
	enabled: true,
	shell: '/bin/sh',
	// A login shell sources /etc/profile, so the operator gets the device's
	// own prompt, PATH and aliases rather than anything invented here
	shell_args: [ '-l' ],
	term: 'xterm-256color',
	ca_cert: '',
	allow_insecure: false,
	verify_peer: true,
	max_session: 3600,
	idle_timeout: 900,
	debug: false
};

let config = { ...DEFAULTS };

function bool_get(section, name, fallback) {
	let value = section[name];

	if (value == null)
		return fallback;

	return value == '1' || value == 'true' || value == 'yes' || value == 'on';
}

function int_get(section, name, fallback) {
	let value = +section[name];

	// UCI values are strings; a missing or non-numeric one must not silently
	// become 0 and disable a limit
	if (section[name] == null || type(value) != 'int' || value < 0)
		return fallback;

	return value;
}

/**
 * Reads the upty config: /var/run/uci/upty, which ubbf renders from the
 * shadow file /etc/ubbf/shadow/upty and Device.X_UBBF.UPTY.Enable, else
 * /etc/config/upty. Missing options fall back to the built-in defaults,
 * which are deliberately restrictive.
 *
 * @returns {boolean} true if the config was read
 */
export function load() {
	let cursor = uci.cursor();

	if (!cursor) {
		log_err('cannot open UCI cursor, using defaults');
		return false;
	}

	if (!cursor.load(CONFIG)) {
		log_warn('no %s config, using defaults', CONFIG);
		return false;
	}

	let section = cursor.get_all(CONFIG, SECTION);

	if (!section) {
		log_warn('no %s.%s section, using defaults', CONFIG, SECTION);
		return false;
	}

	config = {
		enabled: bool_get(section, 'enabled', DEFAULTS.enabled),
		shell: section.shell ?? DEFAULTS.shell,
		shell_args: section.shell_args ?? DEFAULTS.shell_args,
		term: section.term ?? DEFAULTS.term,
		ca_cert: section.ca_cert ?? DEFAULTS.ca_cert,
		allow_insecure: bool_get(section, 'allow_insecure', DEFAULTS.allow_insecure),
		verify_peer: bool_get(section, 'verify_peer', DEFAULTS.verify_peer),
		max_session: int_get(section, 'max_session', DEFAULTS.max_session),
		idle_timeout: int_get(section, 'idle_timeout', DEFAULTS.idle_timeout),
		debug: bool_get(section, 'debug', DEFAULTS.debug)
	};

	// A single-valued UCI option arrives as a string, a list as an array
	if (type(config.shell_args) == 'string')
		config.shell_args = [ config.shell_args ];

	return true;
};

/** @returns {object} the current configuration */
export function get() {
	return config;
};

/**
 * Environment handed to the operator's shell. Deliberately built here and not
 * taken from the server: TERM aside, a session must not be able to inject
 * variables such as PATH or LD_PRELOAD into a root shell.
 *
 * @returns {object}
 */
export function shell_env() {
	// PATH is a floor, not a policy: /etc/profile overrides it in a login
	// shell, but a device without one must still have a usable shell
	return {
		TERM: config.term,
		PATH: '/usr/sbin:/usr/bin:/sbin:/bin',
		HOME: '/root',
		SHELL: config.shell,
		UPTY_SESSION: '1'
	};
};
