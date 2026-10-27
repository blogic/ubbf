// Host test of the pty module handler: Status, Enable and LastError, and
// the result of StartSession(). A ubus mock answers for the upty agent.
'use strict';

import { describe, it, assert, mock } from 'utest';
import * as ubbf from 'ubbf';

let api = {
	ubbf,
	utils: {},
	schema: (k) => k,
	model: {},
	operations: {}
};

include('../modules/pty/handler.uc', { ubbf_module: api });

const get = api.model['Device.X_UBBF.UPTY'].get;
const start = api.operations['Device.X_UBBF.UPTY.StartSession()'].handler;

const INPUT = { Token: 'abcdefghijklmnop', URL: 'wss://172.16.100.1:9446/ws/agent' };

function agent_set(replies) {
	let calls = [];
	mock.global.patch('ubus', { behavior: {
		call: (object, method, args) => {
			if (object != 'upty')
				return null;
			push(calls, { method, args });
			return replies[method];
		},
		error: () => 'Not found'
	} });
	return calls;
}

describe('UPTY status', () => {
	it('is Unavailable while the agent is down', () => {
		agent_set({});
		assert.match({ Enable: 'true', Status: 'Unavailable', LastError: '' }, get({ config: null }));
	});

	it('is Disabled when disabled', () => {
		agent_set({ status: { state: 'idle', enabled: false, last_error: '' } });
		assert.match({ Enable: 'false', Status: 'Disabled', LastError: '' }, get({ config: { Enable: 'false' } }));
	});

	it('is Active with a session', () => {
		agent_set({ status: { state: 'active', enabled: true, last_error: '' } });
		assert.match('Active', get({ config: {} }).Status);
	});

	it('reports the last error of the agent', () => {
		agent_set({ status: { state: 'idle', enabled: true, last_error: 'SSL handshake failed' } });
		assert.match({ Enable: 'true', Status: 'Idle', LastError: 'SSL handshake failed' }, get({ config: {} }));
	});
});

describe('UPTY StartSession()', () => {
	it('passes the arguments to the agent', () => {
		let calls = agent_set({ start: { started: true } });
		assert.match({ Status: 'Started', Message: '' }, start({ ...INPUT, AllowInsecure: 'false' }, 'key-1', {}));
		assert.match({ token: INPUT.Token, url: INPUT.URL, command_key: 'key-1', allow_insecure: false }, calls[0].args);
	});

	it('rejects an AllowInsecure that is not a boolean without asking the agent', () => {
		let calls = agent_set({ start: { started: true } });
		assert.match(-USP_ERR_INVALID_COMMAND_ARGS, start({ ...INPUT, AllowInsecure: 'yes' }, '', {}));
		assert.match(0, length(calls));
	});

	it('rejects the input that the agent finds invalid', () => {
		agent_set({ start: { error: 'token missing or malformed', invalid: true } });
		assert.match(-USP_ERR_INVALID_COMMAND_ARGS, start(INPUT, '', {}));
	});

	it('reports a refusal of the agent', () => {
		agent_set({ start: { error: 'busy, session already active' } });
		assert.match({ Status: 'Error', Message: 'busy, session already active' }, start(INPUT, '', {}));
	});

	it('reports an Error while the agent is down', () => {
		agent_set({ start: null });
		assert.match('Error', start(INPUT, '', {}).Status);
	});
});
