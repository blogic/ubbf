// Host test of the userinterface module: the AutoDisableDuration timer for
// values beyond a C int of milliseconds, the firewall hook for Enable 1,
// the Interface check, Status from ubbf-ui, CreateWebSession() arguments,
// stable Session numbers and the removal of web sessions of a disabled row.
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf from 'ubbf';
import { generate } from 'ubbf.render.renderer';

// This process numbers rows, as the agent does.
ubbf.instance_map_own(true);

const RUN_DIR = '/var/run/ubbf-ui';
const WEBSESSIONS_DIR = `${RUN_DIR}/websessions`;

function config(rows) {
	return { Device: {
		IP: { Interface: { '2': { Enable: 'true', Name: 'lan' } } },
		Users: { Role: { '1': { Enable: 'true', RoleName: 'admin' } } },
		UserInterface: { Enable: 'true', HTTPAccess: rows }
	} };
}

function row(alias, extra) {
	return {
		Enable: 'true', Alias: alias, Protocol: 'HTTPS', Port: '443',
		Interface: 'Device.IP.Interface.2', AllowAllIPv4: 'true', AllowAllIPv6: 'true',
		AllowedRoles: 'Device.Users.Role.1', ...(extra ?? {})
	};
}

function config_store(root) {
	fs.mkdir('/etc/ubbf', 0755);
	fs.writefile('/etc/ubbf/config.json', sprintf('%J', root));
}

let applied = [];
let commit_hook;

const api = {
	ubbf: proto({ datetime_format: (t) => t }, ubbf),
	utils: {},
	schema: (k) => k,
	on_commit: (fn) => { commit_hook = fn; },
	config_apply: (ops) => { push(applied, ...ops); return { success: true }; },
	model: {},
	operations: {}
};
include('/usr/share/ucode/ubbf/modules/userinterface/handler.uc', { ubbf_module: api });

const entry = api.model['Device.UserInterface.HTTPAccess.{i}'];
const session = api.model['Device.UserInterface.HTTPAccess.{i}.Session.{i}'];
const create = api.operations['Device.UserInterface.HTTPAccess.{i}.CreateWebSession()'].handler;
const remove = api.operations['Device.UserInterface.HTTPAccess.{i}.Session.{i}.Delete()'].handler;

describe('userinterface HTTPAccess', () => {
	beforeEach(() => {
		mock.global.patch('uci', { data: {} });
		state_clear();
		system([ 'rm', '-rf', RUN_DIR ]);
		applied = [];
	});

	it('opens the port for Enable 1 as for true', () => {
		let root = config({ '1': row('a', { Enable: '1' }) });
		assert.match(1, length(entry.firewall(root.Device.UserInterface.HTTPAccess['1'], root, '') ?? []));
	});

	it('opens nothing for a CABundle that does not resolve', () => {
		let root = config({ '1': row('a', { CABundle: 'Device.Security.CABundle.99' }) });
		assert.match(null, entry.firewall(root.Device.UserInterface.HTTPAccess['1'], root, ''));
	});

	it('accepts only an interface row as Interface', () => {
		let root = config({ '1': row('a') });
		for (let c in [ [ '', 0 ], [ 'Device.IP.Interface.2', 0 ], [ 'Device.IP.Interface.2.', 0 ],
				[ 'Device.IP.Interface.9', -USP_ERR_INVALID_VALUE ], [ 'foo', -USP_ERR_INVALID_VALUE ] ])
			assert.match(c[1], entry.set({ param: 'Interface', value: c[0], root }), `Interface '${c[0]}'`);
	});

	it('accepts an Alias that is not empty and not held by another row', () => {
		let root = config({ '1': row('a'), '2': row('b') });
		assert.match(-USP_ERR_INVALID_VALUE, entry.set({ param: 'Alias', value: '', root }), 'Alias empty');
		root.Device.UserInterface.HTTPAccess['2'].Alias = 'a';
		assert.match(-USP_ERR_UNIQUE_KEY_CONFLICT, entry.set({ param: 'Alias', value: 'a', root }), 'Alias of another row');
		root.Device.UserInterface.HTTPAccess['2'].Alias = 'c';
		assert.match(0, entry.set({ param: 'Alias', value: 'c', root }), 'Alias free');
	});

	it('renders the listener off when its Interface does not resolve', () => {
		let uci = generate(config({ '1': row('a', { Interface: 'Device.IP.Interface.9' }) }), [], true).uci;
		assert.match(true, !!match(uci, /webui\.@server\[-1\]\.enabled='?0/), 'unresolved Interface: listener off');
		assert.match(false, !!match(uci, /webui\.@server\[-1\]\.interface/), 'unresolved Interface: no interface option');
	});

	it('takes Status from ubbf-ui and from the references', () => {
		fs.mkdir(RUN_DIR, 0755);
		let root = config({ '1': row('a'), '2': row('b'), '3': row('c', { Enable: 'false' }) });
		fs.writefile(`${RUN_DIR}/status.json`, sprintf('%J', { '1': { status: 'Up' }, '2': { status: 'Error', reason: 'x' }, '3': { status: 'Up' } }));
		assert.match([ 'Up', 'Error', 'Down' ],
			map([ 1, 2, 3 ], (i) => entry.get({ instance: i, config: root.Device.UserInterface.HTTPAccess[`${i}`], root }).Status),
			'Status per ubbf-ui');
		fs.unlink(`${RUN_DIR}/status.json`);
		assert.match('Down', entry.get({ instance: 1, config: root.Device.UserInterface.HTTPAccess['1'], root }).Status,
			'Status without ubbf-ui');
		root = config({ '1': row('a', { Interface: 'Device.IP.Interface.9' }), '2': row('b', { CABundle: 'Device.Security.CABundle.99' }) });
		assert.match([ 'Error', 'Error' ],
			map([ 1, 2 ], (i) => entry.get({ instance: i, config: root.Device.UserInterface.HTTPAccess[`${i}`], root }).Status),
			'Status with an unresolved reference');
	});

	it('rejects bad timeouts of CreateWebSession()', () => {
		fs.mkdir(RUN_DIR, 0755);
		let root = config({ '1': row('a') });
		for (let t in [ 'abc', '-1', '4294967296', '99999999999' ])
			assert.match(-USP_ERR_INVALID_COMMAND_ARGS, create({ AbsoluteTimeout: t }, '', [ 1 ], root), `AbsoluteTimeout ${t}`);
		assert.match(-USP_ERR_INVALID_COMMAND_ARGS, create({ IdleTimeout: '4294967296' }, '', [ 1 ], root), 'IdleTimeout too large');
	});

	it('keeps the Session numbers with their sessions and removes the web sessions of a disabled row', () => {
		fs.mkdir(RUN_DIR, 0755);
		let root = config({ '1': row('a') });
		let ws1 = create({ AbsoluteTimeout: '4294967295' }, '', [ 1 ], root);
		assert.match('string', type(ws1?.SessionID), 'largest unsignedInt accepted');

		fs.writefile(`${RUN_DIR}/sessions.json`, sprintf('%J', { sessions: [
			{ id: 'c1', alias: 'a', ip: '192.0.2.1', peer_port: 40001, protocol: 'HTTPS', user: '1', start: 1 },
			{ id: 'c2', alias: 'a', ip: '192.0.2.2', peer_port: 40002, protocol: 'HTTPS', user: '1', start: 2 }
		] }));
		let parent = root.Device.UserInterface.HTTPAccess['1'];
		let rows = session.get({ parent });
		assert.match([ 'c1', 'c2', ws1.SessionID ], map(sort(keys(rows)), (k) => rows[k].SessionID), 'three sessions');
		assert.match(false, exists(rows['3'], 'Port'), 'unused web session has no Port');
		assert.match('40002', rows['2'].Port, 'connection has its Port');

		fs.writefile(`${RUN_DIR}/sessions.json`, sprintf('%J', { sessions: [
			{ id: 'c2', alias: 'a', ip: '192.0.2.2', peer_port: 40002, protocol: 'HTTPS', user: '1', start: 2 }
		] }));
		let ws2 = create({}, '', [ 1 ], root);
		rows = session.get({ parent });
		assert.match('c2', rows['2']?.SessionID, 'c2 keeps number 2');
		assert.match(ws1.SessionID, rows['3']?.SessionID, 'web session keeps number 3');
		assert.match(ws2.SessionID, rows['4']?.SessionID, 'new web session gets number 4');
		assert.match(null, rows['1'], 'number 1 is gone');
		assert.match(ws1.SessionID, session.get({ parent, instance: 3 })?.SessionID, 'single read by number');

		assert.match({}, remove({}, '', [ 1, 3 ], root), 'Delete() of number 3');
		assert.match(false, !!fs.access(`${WEBSESSIONS_DIR}/${ws1.SessionID}.json`), 'Delete() removed the file of that web session');
		assert.match(true, !!fs.access(`${WEBSESSIONS_DIR}/${ws2.SessionID}.json`), 'the other web session stays');
		assert.match(null, remove({}, '', [ 1, 3 ], root), 'Delete() of a gone number');

		config_store(config({ '1': row('a', { Enable: 'false' }) }));
		commit_hook();
		assert.match([], fs.lsdir(WEBSESSIONS_DIR), 'web sessions of a disabled row removed');
	});

	// AutoDisableDuration beyond 2^31 ms: the row expires neither at once nor
	// never; a short one expires.
	it('expires a row after AutoDisableDuration, also beyond 2^31 ms', () => {
		uloop.init();
		for (let c in [ [ '1', 1 ], [ '2147484', 0 ], [ '4294968', 0 ], [ '2592000', 0 ] ]) {
			let timed = config({ '1': row('a', { AutoDisableDuration: c[0] }) });

			applied = [];
			fs.unlink('/tmp/ubbf/httpaccess-activation.json');
			config_store(timed);
			commit_hook();
			uloop.timer(2500, () => uloop.end());
			uloop.run();

			let left = +entry.get({ instance: 1, config: timed.Device.UserInterface.HTTPAccess['1'], root: timed }).TimeLeft;
			assert.match(c[1], length(applied), `AutoDisableDuration ${c[0]}: writes within 2.5 s`);
			assert.match(c[1] == 0, left >= int(c[0]) - 3 && left > 0, `AutoDisableDuration ${c[0]}: TimeLeft counts down`);
		}
	});
});
