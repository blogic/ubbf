// Host test of the pty module handler: Status, Enable and LastError, and
// the result of StartSession(). Run from the repository root with the
// native module built for the host; tests/pty/ holds a stand-in for the
// ubus module that answers for the agent:
//   ucode -L "$PWD/tests/pty/*.uc" -L "$PWD/files/usr/share/ucode/*.uc" \
//     -L "<host build>/*.so" tests/pty-handler.uc
'use strict';

import * as ubbf from 'ubbf';

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

let api = {
	ubbf,
	utils: {},
	schema: (k) => k,
	model: {},
	operations: {}
};

include('../modules/pty/handler.uc', { ubbf_module: api });

let get = api.model['Device.X_UBBF.UPTY'].get;
let start = api.operations['Device.X_UBBF.UPTY.StartSession()'].handler;

global.UPTY_CALLS = [];
global.UPTY_REPLY = {};

assert_eq('get: agent down', get({ config: null }), { Enable: 'true', Status: 'Unavailable', LastError: '' });

global.UPTY_REPLY.status = { state: 'idle', enabled: false, last_error: '' };
assert_eq('get: disabled', get({ config: { Enable: 'false' } }), { Enable: 'false', Status: 'Disabled', LastError: '' });

global.UPTY_REPLY.status = { state: 'active', enabled: true, last_error: '' };
assert_eq('get: active', get({ config: {} }).Status, 'Active');

global.UPTY_REPLY.status = { state: 'idle', enabled: true, last_error: 'SSL handshake failed' };
assert_eq('get: last error', get({ config: {} }), { Enable: 'true', Status: 'Idle', LastError: 'SSL handshake failed' });

const INPUT = { Token: 'abcdefghijklmnop', URL: 'wss://172.16.100.1:9446/ws/agent' };

global.UPTY_REPLY.start = { started: true };
global.UPTY_CALLS = [];
assert_eq('start: started', start({ ...INPUT, AllowInsecure: 'false' }, 'key-1', {}), { Status: 'Started', Message: '' });
assert_eq('start: arguments for the agent', global.UPTY_CALLS[0].args,
	{ token: INPUT.Token, url: INPUT.URL, command_key: 'key-1', allow_insecure: false });

global.UPTY_CALLS = [];
assert_eq('start: AllowInsecure not a boolean', start({ ...INPUT, AllowInsecure: 'yes' }, '', {}), -USP_ERR_INVALID_COMMAND_ARGS);
assert_eq('start: agent not asked', length(global.UPTY_CALLS), 0);

global.UPTY_REPLY.start = { error: 'token missing or malformed', invalid: true };
assert_eq('start: invalid input', start(INPUT, '', {}), -USP_ERR_INVALID_COMMAND_ARGS);

global.UPTY_REPLY.start = { error: 'busy, session already active' };
assert_eq('start: refusal', start(INPUT, '', {}), { Status: 'Error', Message: 'busy, session already active' });

global.UPTY_REPLY.start = null;
assert_eq('start: agent down', start(INPUT, '', {}).Status, 'Error');

printf('%d passed, %d failed\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
