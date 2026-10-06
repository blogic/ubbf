'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_debug, log_err } from 'ubbf.utils.logging';

/**
 * Build a shell command string from an argv-style list.
 *
 * Each element of `parts` is quoted with ubbf.shell_escape() so
 * interpolating user-controlled values cannot inject shell
 * metacharacters. Behaviour by element type:
 *
 *   string         shell-escaped (the safe default)
 *   int / double   formatted with %d, no escaping; fractional
 *                  doubles are truncated, convert manually if
 *                  fractional precision matters
 *   null           skipped entirely, so callers can express
 *                  conditional flags as
 *                    cond ? '--flag' : null, value
 *   {raw: 'text'}  inserted verbatim, no escaping, for literal
 *                  shell syntax such as redirections ('2>&1'),
 *                  pipes, or command substitution
 *   boolean        falls through to the %s default and yields the
 *                  literal strings 'true' / 'false'; pass an int
 *                  if a numeric flag value is required
 *
 * Anything else is stringified with %s and then shell-escaped.
 *
 * @param {array} parts - Argv-style list of command fragments
 * @returns {string} Shell command string ready for popen/system
 */
export function cmd_build(parts) {
	let out = [];
	for (let p in parts) {
		if (p == null)
			continue;
		if (type(p) == 'object' && p.raw != null) {
			push(out, p.raw);
			continue;
		}
		if (type(p) == 'int' || type(p) == 'double') {
			push(out, sprintf('%d', p));
			continue;
		}
		push(out, ubbf.shell_escape(sprintf('%s', p)));
	}
	return join(' ', out);
};

/**
 * Executes a command asynchronously using uloop task.
 *
 * `cmd` may be a shell command string or an argv-style array
 * that is passed through cmd_build(). The array form is the
 * safe default for user-controlled input; prefer it unless you
 * genuinely need shell syntax.
 *
 * On uloop.task creation failure the callback is invoked
 * synchronously with `{ error: 'failed to create task' }` and
 * null is returned, so callers must guard against a null task
 * before attaching further handlers.
 *
 * @param {string|array} cmd - Command string or cmd_build parts
 * @param {function} callback - Callback receiving result object
 * @param {object} opts - Options (capture_time: boolean)
 * @returns {object|null} The uloop task object, or null on creation failure
 */
export function popen_async(cmd, callback, opts) {
	opts ??= {};

	if (type(cmd) == 'array')
		cmd = cmd_build(cmd);

	log_debug('popen_async: %s', cmd);

	let called;

	let task = uloop.task(
		(pipe) => {
			try {
				let start_time = opts.capture_time ? time() : null;

				let p = fs.popen(cmd, 'r');
				if (!p) {
					log_err('popen_async: popen failed');
					pipe.send({ error: 'popen failed' });
					return;
				}

				let data = p.read('all');
				let exitcode = p.close();
				let end_time = opts.capture_time ? time() : null;

				log_debug('popen_async: exitcode=%d', exitcode);
				pipe.send({ data, exitcode, start_time, end_time });
			} catch (e) {
				log_err('popen_async: exception: %s', e);
				pipe.send({ error: sprintf('exception: %s', e) });
			}
		},
		(result) => {
			if (called)
				return;
			called = true;

			try {
				callback(result ?? { error: 'task returned null' });
			} catch (e) {
				log_err('popen_async: callback exception: %s', e);
			}
		}
	);

	if (!task) {
		log_err('popen_async: failed to create task');
		callback({ error: 'failed to create task' });
	}

	return task;
};
