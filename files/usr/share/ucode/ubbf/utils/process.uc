'use strict';

import * as uloop from 'uloop';
import * as fs from 'fs';
import * as ubbf from 'ubbf';
import { log_debug, log_err, log_exception } from 'ubbf';

const TASK_POLL_MS = 1000;

// Added to the time limit of the processes a task starts, to give the
// watchdog timeout of task_run().
export const TASK_MARGIN_S = 60;

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

// A first word in single quotes is a word that cmd_build() escaped
const FIRST_WORD_RE = /^[ \t\n]*('([^']*)'|([^ \t\n'][^ \t\n]*))?/;

function first_word(text) {
	let m = match(text, FIRST_WORD_RE);
	return m[2] ?? m[3] ?? '';
}

/**
 * The arguments of a command can hold credentials (curl -u, mosquitto_pub
 * -P), so a log names the program alone.
 *
 * @param {string|array} cmd - Command string or cmd_build parts
 * @returns {string} argv[0] of the parts, or the first word of the string
 */
function cmd_program(cmd) {
	if (type(cmd) != 'array')
		return first_word(sprintf('%s', cmd));

	for (let p in cmd) {
		if (p == null)
			continue;
		if (type(p) == 'object' && p.raw != null)
			return first_word(sprintf('%s', p.raw));
		return sprintf('%s', p);
	}

	return '';
}

/**
 * Executes a command asynchronously using uloop task.
 *
 * `cmd` may be a shell command string or an argv-style array
 * that is passed through ubbf.cmd_build(). The array form is the
 * safe default for user-controlled input; prefer it unless you
 * genuinely need shell syntax.
 *
 * The callback runs once, also when the child dies; see task_run().
 *
 * @param {string|array} cmd - Command string or ubbf.cmd_build() parts
 * @param {function} callback - Callback receiving result object
 * @param {object} opts - Options (capture_time: boolean, timeout: seconds)
 * @returns {object|null} The uloop task object, or null on creation failure
 */
export function popen_async(cmd, callback, opts) {
	opts ??= {};

	log_debug('popen_async: %s', cmd_program(cmd));

	if (type(cmd) == 'array')
		cmd = ubbf.cmd_build(cmd);

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
