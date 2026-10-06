// Host test of the upty agent: the input checks, the window size check and a
// real shell on a PTY (input queue, SIGPIPE, teardown of background jobs).
// Run from the repository root with a host ucode that carries the
// uloop.process() setup callback (ubbf-openwrt ucode patch 111) and host
// builds of uwsc and uci:
//   ucode -L "$PWD/modules/pty/files/usr/share/ucode/*.uc" \
//     -L "<uwsc build>/*.so" -L "<ucode build>/*.so" tests/pty.uc
'use strict';

import * as uloop from 'uloop';
import { readfile, unlink } from 'fs';
import * as pty from 'upty.pty';
import { url_check, token_valid, ca_check } from 'upty.session';

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%J', got);
	let exp_json = sprintf('%J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

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

for (let c in URL_CASES) {
	let err = url_check(c[0]);
	let kind = (err == null) ? null : (match(err, /long/) ? 'long' : match(err, /required/) ? 'required' : 'path');
	assert_eq(`url_check ${c[0]}`, kind, c[1]);
}

assert_eq('token: 16 characters', token_valid('abcdefghijklmnop'), true);
assert_eq('token: 15 characters', token_valid('abcdefghijklmno'), false);
assert_eq('token: 129 characters', token_valid(sprintf('%0129d', 0)), false);
assert_eq('token: other characters', token_valid('abcdefghijklmno!'), false);
assert_eq('token: not a string', token_valid(12345678901234567), false);

assert_eq('ca: PEM', ca_check('-----BEGIN CERTIFICATE-----\nMII\n-----END CERTIFICATE-----\n'), null);
assert_eq('ca: not PEM', ca_check('MIIB') != null, true);
assert_eq('ca: too large', ca_check('-----BEGIN CERTIFICATE-----' + sprintf('%070000d', 0)) != null, true);

assert_eq('winsize: 80x24', pty.winsize_valid(80, 24), true);
assert_eq('winsize: 65535', pty.winsize_valid(65535, 65535), true);
assert_eq('winsize: 70000', pty.winsize_valid(70000, 24), false);
assert_eq('winsize: 0', pty.winsize_valid(0, 24), false);
assert_eq('winsize: -5', pty.winsize_valid(-5, 24), false);
assert_eq('winsize: 1.5', pty.winsize_valid(1.5, 24), false);
assert_eq('winsize: string', pty.winsize_valid('80', 24), false);
assert_eq('spawn: bad window refused', pty.spawn({ shell: '/bin/sh', args: [], env: {}, cols: 70000, rows: 24,
	on_data: () => null, on_exit: () => null }), null);

uloop.init();

const PASTE_PATH = '/tmp/upty-test-paste';
const PASTE_SIZE = 200 * 1024;

let output = '';
let shell_pid = 0;
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

assert_eq('spawn: shell started', term != null, true);
shell_pid = term.pid();

/**
 * Runs the event loop until the shell output matches a pattern, at most
 * 10 s.
 *
 * @param {RegExp} pattern - Expected output
 */
function output_wait(pattern) {
	let waited = 0;
	let check = uloop.interval(100, () => {
		waited += 100;
		if (match(output, pattern) || waited > 10000)
			uloop.end();
	});
	uloop.run();
	check.cancel();
}

// A canonical TTY line holds 4 KB, so the paste waits for raw mode. The
// markers are computed, so the echo of the typed command does not match.
unlink(PASTE_PATH);
term.write('stty raw -echo; echo ready-$((1 + 1))\n');
output_wait(/ready-2/);

term.write('sleep 777 &\n');
term.write('grep SigIgn /proc/self/status\n');
term.write(`head -c ${PASTE_SIZE} > ${PASTE_PATH}\n`);
assert_eq('write: paste queued', term.write(sprintf(`%0${PASTE_SIZE}d`, 0)), true);
term.write('echo done-$((6 * 7))\n');
output_wait(/done-42/);

let sig_ign = match(output, /SigIgn:[ \t]*([0-9a-f]+)/);
assert_eq('SIGPIPE: default in the shell', sig_ign ? (hex(sig_ign[1]) & (1 << 12)) == 0 : 'no output', true);
assert_eq('write: paste arrived whole', length(readfile(PASTE_PATH) ?? ''), PASTE_SIZE);
assert_eq('session: background job running', length(pty.session_pids(shell_pid)) >= 2, true);

term.close();
uloop.timer(3500, () => uloop.end());
uloop.run();

assert_eq('close: no process of the session left', pty.session_pids(shell_pid), []);
assert_eq('close: shell exit reported', exited, true);
unlink(PASTE_PATH);

printf('%d passed, %d failed\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
