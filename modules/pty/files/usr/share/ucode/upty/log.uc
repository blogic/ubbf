// Syslog wrapper for the uPTY agent.

'use strict';

import {
	ulog_open, ulog,
	ULOG_SYSLOG, LOG_DAEMON,
	LOG_DEBUG, LOG_INFO, LOG_WARNING, LOG_ERR
} from 'log';

let initialized = false;
let debug_enabled = false;

/**
 * Writes one record. The text is passed as an argument of '%s', because
 * ulog() takes a format, and text from the server or uwsc can hold '%'.
 * Control characters would split or forge records.
 *
 * @param {number} priority - Syslog priority
 * @param {array} args - sprintf() format and arguments
 */
function log_msg(priority, args) {
	ulog(priority, '%s', replace(sprintf(...args), /[[:cntrl:]]/g, '?'));
}

/**
 * Opens the syslog connection. Only syslog: procd also sends the stderr
 * of the daemon to syslog, so a second channel would log every line twice.
 *
 * @param {string} ident - Syslog identity
 * @param {boolean} [debug] - Whether log_debug() output is emitted
 */
export function log_init(ident, debug) {
	if (initialized)
		return;

	initialized = true;
	debug_enabled = debug ?? false;
	ulog_open(ULOG_SYSLOG, LOG_DAEMON, ident);
};

/**
 * Enables or disables debug output after log_init().
 *
 * @param {boolean} enabled - Whether log_debug() output is emitted
 */
export function log_debug_set(enabled) {
	debug_enabled = enabled;
};

/**
 * Logs at debug priority when debug output is enabled.
 *
 * @param {...*} args - sprintf() format and arguments
 */
export function log_debug(...args) {
	if (debug_enabled)
		log_msg(LOG_DEBUG, args);
};

/**
 * Logs at info priority.
 *
 * @param {...*} args - sprintf() format and arguments
 */
export function log_info(...args) {
	log_msg(LOG_INFO, args);
};

/**
 * Logs at warning priority.
 *
 * @param {...*} args - sprintf() format and arguments
 */
export function log_warn(...args) {
	log_msg(LOG_WARNING, args);
};

/**
 * Logs at error priority.
 *
 * @param {...*} args - sprintf() format and arguments
 */
export function log_err(...args) {
	log_msg(LOG_ERR, args);
};
