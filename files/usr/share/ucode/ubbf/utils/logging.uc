'use strict';

import {
	ulog_open, ulog,
	ULOG_SYSLOG, ULOG_STDIO, LOG_DAEMON,
	LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING, LOG_ERR
} from 'log';
import * as udebug from 'udebug';

let initialized;
let ring;

/**
 * Initialises the logging subsystem with syslog and optional udebug.
 *
 * The udebug ring is sized at 64 KiB / 512 entries: large enough to
 * retain a useful trace window across a typical TR-181 get cycle and a
 * subsequent operation invocation without over-committing RAM on the
 * embedded targets ubbf runs on.
 *
 * @param {string} ident - Syslog identifier string
 */
export function log_init(ident) {
	if (initialized)
		return;
	initialized = true;
	ulog_open(ULOG_SYSLOG | ULOG_STDIO, LOG_DAEMON, ident);

	udebug.init();
	ring = udebug.create_ring({
		name: ident,
		size: 64 * 1024,
		entries: 512
	});
};

/**
 * Logs a message at the specified priority.
 *
 * @param {number} priority - Syslog priority level
 * @param {string} msg - Message to log
 */
function log_msg(priority, msg) {
	// ulog needs a trailing newline so syslog/stderr lines are
	// terminated; the udebug ring stores discrete entries and the
	// reader appends its own framing, so the raw msg is added there.
	// The ring is null when udebug was not up at log_init time (early
	// boot); an unguarded add() is a VM-fatal reference error, which
	// killed cwmp-session's embedded DM mid-load and made the CPE
	// Inform with an empty DeviceId ("os::-").
	ulog(priority, msg + '\n');
	ring?.add(msg);
}

/**
 * Logs a debug message.
 *
 * @param {string} fmt - Format string
 * @param {...*} args - Format arguments
 */
export function log_debug(fmt, ...args) {
	log_msg(LOG_DEBUG, 'DEBUG: ' + sprintf(fmt, ...args));
};

/**
 * Logs an info message.
 *
 * @param {string} fmt - Format string
 * @param {...*} args - Format arguments
 */
export function log_info(fmt, ...args) {
	log_msg(LOG_INFO, sprintf(fmt, ...args));
};

/**
 * Logs a notice message.
 *
 * @param {string} fmt - Format string
 * @param {...*} args - Format arguments
 */
export function log_notice(fmt, ...args) {
	log_msg(LOG_NOTICE, sprintf(fmt, ...args));
};

/**
 * Logs a warning message.
 *
 * @param {string} fmt - Format string
 * @param {...*} args - Format arguments
 */
export function log_warn(fmt, ...args) {
	log_msg(LOG_WARNING, sprintf(fmt, ...args));
};

/**
 * Logs an error message.
 *
 * @param {string} fmt - Format string
 * @param {...*} args - Format arguments
 */
export function log_err(fmt, ...args) {
	log_msg(LOG_ERR, sprintf(fmt, ...args));
};

/**
 * Logs an exception with path context and stack trace.
 *
 * Only the innermost stack frame (stacktrace[0]) is emitted; deeper
 * frames are intentionally elided to keep operator-visible logs short.
 * Use the udebug ring or a debugger for full backtraces.
 *
 * @param {string} path - Path where the exception occurred
 * @param {object} e - Exception object with stacktrace
 */
export function log_exception(path, e) {
	log_msg(LOG_ERR, sprintf('EXCEPTION at path: %s', path));

	let lines = split(`Exception: ${e}\n${e.stacktrace[0].context}`, '\n');
	for (let line in lines)
		log_msg(LOG_ERR, line);
};
