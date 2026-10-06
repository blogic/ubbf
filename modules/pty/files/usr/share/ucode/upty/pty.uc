// PTY allocation and shell spawning for the uPTY agent.
//
// ucode's io module supplies the PTY primitives (ptmx, grantpt, unlockpt,
// ptsname, TIOCSWINSZ via ioctl), and uloop.process()'s setup callback runs in
// the child between fork() and exec(), which is where the slave becomes the
// child's stdio. setsid(2) and TIOCSCTTY are the one part neither can express,
// so the child execs setsid(1), which does both before exec'ing the shell.
// setsid(1) and kill(1) are busybox applets.

'use strict';

import * as io from 'io';
import * as uloop from 'uloop';
import * as struct from 'struct';
import { IOC_DIR_WRITE, lsdir, readfile } from 'fs';

import { log_err, log_info } from 'upty.log';

const TIOCSWINSZ = 0x5414;
const SETSID = '/usr/bin/setsid';
const READ_CHUNK = 4096;
const CHILD_FD_MAX = 64;
const KILL_GRACE_MS = 3000;

// Operator input that the shell has not read yet. A paste larger than this
// while the shell does not read ends the session rather than losing bytes.
const INPUT_QUEUE_MAX = 1024 * 1024;

export const WINSIZE_MAX = 65535;

function winsize_pack(cols, rows) {
	return struct.pack('HHHH', rows, cols, 0, 0);
}

/**
 * Tells whether a window size is one the kernel takes.
 *
 * @param {*} cols - Terminal width
 * @param {*} rows - Terminal height
 * @returns {boolean} true for two integers from 1 to WINSIZE_MAX
 */
export function winsize_valid(cols, rows) {
	return type(cols) == 'int' && type(rows) == 'int' &&
		cols >= 1 && cols <= WINSIZE_MAX && rows >= 1 && rows <= WINSIZE_MAX;
};

// The child inherits every descriptor the agent holds open, the control
// websocket and the ubus socket among them. Nothing below stdio belongs to an
// operator shell.
function child_fds_close() {
	for (let fd = 3; fd < CHILD_FD_MAX; fd++)
		io.from(fd)?.close();
}

/**
 * Lists the processes of a session.
 *
 * @param {number} sid - Session ID, the PID of the session leader
 * @returns {string[]} PIDs
 */
export function session_pids(sid) {
	let pids = [];

	for (let name in lsdir('/proc') ?? []) {
		if (!match(name, /^[0-9]+$/))
			continue;

		// The command name in field 2 can hold spaces and parentheses, so
		// the fields are counted from the last ')'
		let stat = readfile(`/proc/${name}/stat`);
		let rest = stat ? split(substr(stat, rindex(stat, ')') + 2), ' ') : [];

		if (+rest[3] == sid)
			push(pids, name);
	}

	return pids;
};

/**
 * Sends a signal to every process of a session.
 *
 * @param {number} sid - Session ID
 * @param {string} sig - Signal name for kill(1)
 */
function session_signal(sid, sig) {
	if (sid < 1)
		return;

	let pids = session_pids(sid);

	if (length(pids))
		system([ 'kill', `-${sig}`, ...pids ]);
}

/**
 * Allocates a PTY and starts a shell attached to it.
 *
 * @param {object} opts
 * @param {string} opts.shell Absolute path of the shell to run
 * @param {string[]} opts.args Arguments passed to the shell
 * @param {object} opts.env Environment for the shell
 * @param {number} opts.cols Initial terminal width
 * @param {number} opts.rows Initial terminal height
 * @param {function} opts.on_data Called with each chunk the shell writes
 * @param {function} opts.on_exit Called with the shell's exit code
 * @returns {?object} Session handle, or null if the PTY or the shell failed
 */
export function spawn(opts) {
	if (!winsize_valid(opts.cols, opts.rows)) {
		log_err('window size %J x %J refused', opts.cols, opts.rows);
		return null;
	}

	let master = io.open('/dev/ptmx', io.O_RDWR | io.O_NOCTTY | io.O_NONBLOCK);

	if (!master) {
		log_err('cannot open /dev/ptmx: %s', io.error());
		return null;
	}

	if (!master.grantpt() || !master.unlockpt()) {
		log_err('cannot unlock pty: %s', io.error());
		master.close();
		return null;
	}

	let pts = master.ptsname();

	if (!pts) {
		log_err('cannot resolve pty slave: %s', io.error());
		master.close();
		return null;
	}

	let handle = null;
	let handle_events = 0;
	let reading = false;
	let input = '';
	let proc = null;
	let sid = 0;

	master.ioctl(IOC_DIR_WRITE, TIOCSWINSZ, null, winsize_pack(opts.cols, opts.rows));

	function drain() {
		let data = master.read(READ_CHUNK);

		// null is EIO once the last slave closes, "" is a plain EOF; either
		// way the shell is gone and the exit callback is about to fire
		if (data === null || length(data) == 0) {
			reading = false;
			return;
		}

		opts.on_data(data);
	}

	function input_flush() {
		let n = master.write(input);

		if (n > 0)
			input = substr(input, n);
	}

	let handle_update;

	function on_event(events, eof, error) {
		if ((eof || error) && length(input))
			input = '';
		else if (events & uloop.ULOOP_WRITE)
			input_flush();

		if (events & uloop.ULOOP_READ)
			drain();

		handle_update();
	}

	// The master is watched for reading while the agent drains it and for
	// writing while operator input waits; one handle carries both.
	handle_update = function() {
		let wanted = (master && reading ? uloop.ULOOP_READ : 0) |
			(master && length(input) ? uloop.ULOOP_WRITE : 0);

		if (wanted == handle_events)
			return;

		handle?.delete();
		handle = wanted ? uloop.handle(master.fileno(), on_event, wanted) : null;
		handle_events = wanted;
	};

	function pause() {
		reading = false;
		handle_update();
	}

	function resume() {
		reading = true;
		handle_update();
	}

	function child_setup() {
		let slave = io.open(pts, io.O_RDWR);

		if (!slave)
			return;

		slave.dup2(0);
		slave.dup2(1);
		slave.dup2(2);
		slave.close();
		child_fds_close();

		// uloop ignores SIGPIPE, and an ignored signal stays ignored
		// across exec, which would break `cmd | head` in the shell
		signal('PIPE', 'default');
	}

	// setsid(1) -c performs setsid() plus TIOCSCTTY on its stdin before
	// exec'ing the shell, giving the shell a controlling terminal and with it
	// job control. child_setup() has already made the slave that stdin.
	// The child of uloop.process() is no process group leader, so setsid(1)
	// does not fork and the shell PID is the session ID.
	proc = uloop.process(SETSID, [ '-c', opts.shell, ...opts.args ], opts.env,
		(code) => {
			pause();
			proc = null;
			opts.on_exit(code);
		},
		child_setup);

	if (!proc) {
		log_err('cannot spawn %s: %s', opts.shell, uloop.error());
		master.close();
		return null;
	}

	sid = proc.pid();
	resume();
	log_info('pty %s: %s pid %d, %dx%d', pts, opts.shell, sid, opts.cols, opts.rows);

	return {
		pts,

		pid: function() {
			return proc ? proc.pid() : 0;
		},

		/**
		 * Queues operator keystrokes for the shell.
		 *
		 * @param {string} data Raw bytes, NUL bytes permitted
		 * @returns {boolean} false when the shell does not read and the
		 *   queue is full
		 */
		write: function(data) {
			if (!master)
				return false;

			if (length(input) + length(data) > INPUT_QUEUE_MAX)
				return false;

			input += data;
			input_flush();
			handle_update();

			return true;
		},

		/**
		 * Applies a new terminal window size.
		 *
		 * @param {number} cols
		 * @param {number} rows
		 * @returns {boolean}
		 */
		resize: function(cols, rows) {
			if (!master || !winsize_valid(cols, rows))
				return false;

			return master.ioctl(IOC_DIR_WRITE, TIOCSWINSZ, null,
			                    winsize_pack(cols, rows)) != null;
		},

		/**
		 * Stops draining the PTY. The kernel buffer then fills and the shell
		 * blocks on write, which is the backpressure we want.
		 */
		pause,

		/** Resumes draining after pause(). */
		resume,

		/** @returns {boolean} whether the PTY is currently being drained */
		draining: function() {
			return reading;
		},

		/**
		 * Terminates every process of the session and releases the PTY.
		 * Idempotent. Background jobs are in other process groups of the
		 * session, so the hang-up of the terminal alone does not reach them.
		 *
		 * @param {boolean} [now] Kill at once, for an agent that exits and
		 *   runs no timer any more
		 */
		close: function(now) {
			reading = false;
			input = '';

			if (master) {
				handle?.delete();
				handle = null;
				handle_events = 0;
				master.close();
				master = null;
			}

			if (!sid)
				return;

			let target = sid;
			sid = 0;

			session_signal(target, 'HUP');

			if (now)
				session_signal(target, 'KILL');
			else
				uloop.timer(KILL_GRACE_MS, () => session_signal(target, 'KILL'));
		}
	};
};
