// Host test of the upty agent: the input checks, the window size check and a
// real shell on a PTY (input queue, SIGPIPE, teardown of background jobs).
// It needs a ucode whose uloop.process() takes a function as the executable
// (OpenWrt ucode patch 101), and modules/pty/files/usr/share/ucode and a
// uwsc module on the search path.
'use strict';

import { describe, it, assert } from 'utest';
import * as uloop from 'uloop';
import { readfile, unlink } from 'fs';
import * as pty from 'upty.pty';
import { url_check, token_valid, ca_check } from 'upty.session';

const URL_CASES = [
	[ 'wss://172.16.100.1:9446/ws/agent', null ],
	[ 'ws://172.16.100.1:9446/ws/agent', null ],
	[ 'wss://[2001:db8::1]:9446/ws/agent', null ],
	[ 'wss://host.example/', null ],
	[ 'wss://host.example', 'path' ],
	[ 'wss://host.example/ws?x=1', 'path' ],
	[ 'wss://host.example/ws#f', 'path' ],
	[ 'wss://host.example/w s', 'path' ],
	[ 'wss://host.example/ws\r\nX: y', 'path' ],
	[ 'wss://user@host.example/ws', 'path' ],
	[ 'https://host.example/ws', 'path' ],
	[ 'wss://host.example/' + sprintf('%0600d', 0), 'long' ],
	[ '', 'required' ],
	[ null, 'required' ]
];

const PASTE_PATH = '/tmp/upty-test-paste';
const PASTE_SIZE = 200 * 1024;

describe('upty input checks', () => {
	it('checks the URL of the server', () => {
		for (let c in URL_CASES) {
			let err = url_check(c[0]);
			let kind = (err == null) ? null : (match(err, /long/) ? 'long' : match(err, /required/) ? 'required' : 'path');
			assert.match(c[1], kind, `url_check ${c[0]}`);
		}
	});

	it('takes a token of 16 to 128 allowed characters', () => {
		assert.match(true, token_valid('abcdefghijklmnop'));
		assert.match(false, token_valid('abcdefghijklmno'));
		assert.match(false, token_valid(sprintf('%0129d', 0)));
		assert.match(false, token_valid('abcdefghijklmno!'));
		assert.match(false, token_valid(12345678901234567));
	});

	it('takes a CA certificate in PEM of limited size', () => {
		assert.match(null, ca_check('-----BEGIN CERTIFICATE-----\nMII\n-----END CERTIFICATE-----\n'));
		assert.match(true, ca_check('MIIB') != null);
		assert.match(true, ca_check('-----BEGIN CERTIFICATE-----' + sprintf('%070000d', 0)) != null);
	});

	it('takes a window size of 1 to 65535 integer cells', () => {
		assert.match(true, pty.winsize_valid(80, 24));
		assert.match(true, pty.winsize_valid(65535, 65535));
		assert.match(false, pty.winsize_valid(70000, 24));
		assert.match(false, pty.winsize_valid(0, 24));
		assert.match(false, pty.winsize_valid(-5, 24));
		assert.match(false, pty.winsize_valid(1.5, 24));
		assert.match(false, pty.winsize_valid('80', 24));
		assert.match(null, pty.spawn({ shell: '/bin/sh', args: [], env: {}, cols: 70000, rows: 24,
			on_data: () => null, on_exit: () => null }), 'spawn refuses a bad window');
	});
});

describe('upty shell on a PTY', () => {
	it('queues input, keeps SIGPIPE default and ends the whole session', () => {
		uloop.init();

		let output = '';
		let exited = false;

		let term = pty.spawn({
			shell: '/bin/sh',
			args: [],
			env: { PATH: '/usr/sbin:/usr/bin:/sbin:/bin', TERM: 'dumb' },
			cols: 80,
			rows: 24,
			on_data: (data) => { output += data; },
			on_exit: () => { exited = true; }
		});

		assert.match(true, term != null, 'shell started');
		let shell_pid = term.pid();

		let output_wait = (pattern) => {
			let waited = 0;
			let timer = uloop.interval(100, () => {
				waited += 100;
				if (match(output, pattern) || waited > 10000)
					uloop.end();
			});
			uloop.run();
			timer.cancel();
		};

		// A canonical TTY line holds 4 KB, so the paste waits for raw mode. The
		// markers are computed, so the echo of the typed command does not match.
		unlink(PASTE_PATH);
		term.write('stty raw -echo; echo ready-$((1 + 1))\n');
		output_wait(/ready-2/);

		term.write('sleep 777 &\n');
		term.write('grep SigIgn /proc/self/status\n');
		term.write(`head -c ${PASTE_SIZE} > ${PASTE_PATH}\n`);
		assert.match(true, term.write(sprintf(`%0${PASTE_SIZE}d`, 0)), 'paste queued');
		term.write('echo done-$((6 * 7))\n');
		output_wait(/done-42/);

		let sig_ign = match(output, /SigIgn:[ \t]*([0-9a-f]+)/);
		assert.match(true, sig_ign ? (hex(sig_ign[1]) & (1 << 12)) == 0 : 'no output', 'SIGPIPE default in the shell');
		assert.match(PASTE_SIZE, length(readfile(PASTE_PATH) ?? ''), 'paste arrived whole');
		assert.match(true, length(pty.session_pids(shell_pid)) >= 2, 'background job running');

		term.close();
		uloop.timer(3500, () => uloop.end());
		uloop.run();

		assert.match([], pty.session_pids(shell_pid), 'no process of the session left');
		assert.match(true, exited, 'shell exit reported');
		unlink(PASTE_PATH);
	});
});
