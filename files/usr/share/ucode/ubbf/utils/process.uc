'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_debug, log_err, log_exception } from 'ubbf.utils.logging';

const TASK_POLL_MS = 1000;

// Added to the time limit of the processes a task starts, to give the
// watchdog timeout of task_run().
export const TASK_MARGIN_S = 60;

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
 * Runs a function in a forked uloop task and calls the callback once.
 *
 * `fn` runs in the child and returns the result object, which the
 * callback receives in the parent. The callback gets `{ error }` instead
 * when `fn` raises, when the child ends without a result (it was killed,
 * or `fn` returned null), or when the task runs longer than
 * `opts.timeout` seconds; on a timeout the child gets SIGTERM and the
 * result has `timeout: true`. uloop calls no callback for a child that
 * ends without a message, so the parent polls `task.finished()`.
 *
 * A process that the child started keeps running after a timeout, so
 * such a process needs its own time limit below `opts.timeout`.
 *
 * On a failure to create the task the callback runs at once and null is
 * returned.
 *
 * @param {function} fn - Child function, returns the result object
 * @param {function} callback - Called once with the result object
 * @param {object} opts - Options (timeout: seconds, absent for none)
 * @returns {object|null} The uloop task object, or null on creation failure
 */
export function task_run(fn, callback, opts) {
	opts ??= {};

	let done;
	let poll;
	let start = clock(true)[0];

	function finish(result) {
		if (done)
			return;
		done = true;
		poll?.cancel();

		try {
			callback(result);
		} catch (e) {
			log_exception('task_run', e);
		}
	}

	let task = uloop.task(
		(pipe) => {
			try {
				return fn();
			} catch (e) {
				log_err('task_run: exception: %s', e);
				return { error: sprintf('exception: %s', e) };
			}
		},
		(result) => {
			if (result != null)
				finish(result);
		}
	);

	if (!task) {
		log_err('task_run: failed to create task');
		finish({ error: 'failed to create task' });
		return null;
	}

	poll = uloop.interval(TASK_POLL_MS, () => {
		if (task.finished()) {
			log_err('task_run: task ended without a result');
			finish({ error: 'task ended without a result' });
			return;
		}

		if (!opts.timeout || clock(true)[0] - start < opts.timeout)
			return;

		log_err('task_run: task timed out after %d s', opts.timeout);
		task.kill();
		finish({ error: 'timed out', timeout: true });
	});

	return task;
};

/**
 * Executes a command asynchronously using uloop task.
 *
 * `cmd` may be a shell command string or an argv-style array
 * that is passed through cmd_build(). The array form is the
 * safe default for user-controlled input; prefer it unless you
 * genuinely need shell syntax.
 *
 * The callback runs once, also when the child dies; see task_run().
 *
 * @param {string|array} cmd - Command string or cmd_build parts
 * @param {function} callback - Callback receiving result object
 * @param {object} opts - Options (capture_time: boolean, timeout: seconds)
 * @returns {object|null} The uloop task object, or null on creation failure
 */
export function popen_async(cmd, callback, opts) {
	opts ??= {};

	if (type(cmd) == 'array')
		cmd = cmd_build(cmd);

	log_debug('popen_async: %s', cmd);

	return task_run(() => {
		let start_time = opts.capture_time ? time() : null;

		let p = fs.popen(cmd, 'r');
		if (!p) {
			log_err('popen_async: popen failed');
			return { error: 'popen failed' };
		}

		let data = p.read('all');
		let exitcode = p.close();
		let end_time = opts.capture_time ? time() : null;

		log_debug('popen_async: exitcode=%d', exitcode);
		return { data, exitcode, start_time, end_time };
	}, callback, opts);
};
