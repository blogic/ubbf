// Host test of the userinterface module: the AutoDisableDuration timer for
// values beyond a C int of milliseconds, the firewall hook for Enable 1,
// the Interface check, Status from ubbf-ui, CreateWebSession() arguments,
// stable Session numbers and the removal of web sessions of a disabled row.
// Run from the repository root with the native module built for the host:
//   tests/render/run.sh <host build> tests/userinterface.uc
'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import * as ubbf from 'ubbf';
import { generate } from 'ubbf.render.renderer';
import { instance_numbers, instance_key, instance_rows, instance_seed, instance_prune } from 'ubbf.utils.instance-map';

const RUN_DIR = '/var/run/ubbf-ui';
const WEBSESSIONS_DIR = `${RUN_DIR}/websessions`;

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

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
	ubbf,
	utils: {
		helpers: { datetime_format: (t) => t },
		logging: { log_err: () => null, log_info: () => null, log_exception: (l, e) => warn(`${e}\n`) },
		'instance-map': { instance_numbers, instance_key, instance_rows, instance_seed, instance_prune }
	},
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

// Firewall hook: a boolean written as 1 opens the port as true does.
let root = config({ '1': row('a', { Enable: '1' }) });
check('Enable 1 opens the port', length(entry.firewall(root.Device.UserInterface.HTTPAccess['1'], root, '') ?? []), 1);

// A CABundle that does not resolve keeps the listener off and its port shut.
root = config({ '1': row('a', { CABundle: 'Device.Security.CABundle.99' }) });
check('unresolved CABundle opens nothing', entry.firewall(root.Device.UserInterface.HTTPAccess['1'], root, ''), null);

// Interface must name an interface row.
root = config({ '1': row('a') });
for (let c in [ [ '', 0 ], [ 'Device.IP.Interface.2', 0 ], [ 'Device.IP.Interface.2.', 0 ],
		[ 'Device.IP.Interface.9', -USP_ERR_INVALID_VALUE ], [ 'foo', -USP_ERR_INVALID_VALUE ] ])
	check(`Interface '${c[0]}'`, entry.set({ param: 'Interface', value: c[0], root }), c[1]);

// Alias keys the timer and the sessions: not empty, not held by another row.
root = config({ '1': row('a'), '2': row('b') });
check('Alias empty', entry.set({ param: 'Alias', value: '', root }), -USP_ERR_INVALID_VALUE);
root.Device.UserInterface.HTTPAccess['2'].Alias = 'a';
check('Alias of another row', entry.set({ param: 'Alias', value: 'a', root }), -USP_ERR_UNIQUE_KEY_CONFLICT);
root.Device.UserInterface.HTTPAccess['2'].Alias = 'c';
check('Alias free', entry.set({ param: 'Alias', value: 'c', root }), 0);

// The render keeps a listener off when its Interface does not resolve.
let uci = generate(config({ '1': row('a', { Interface: 'Device.IP.Interface.9' }) }), [], true).uci;
check('unresolved Interface: listener off', !!match(uci, /webui\.@server\[-1\]\.enabled='?0/), true);
check('unresolved Interface: no interface option', !!match(uci, /webui\.@server\[-1\]\.interface/), false);

// Status follows what ubbf-ui wrote.
fs.mkdir(RUN_DIR, 0755);
root = config({ '1': row('a'), '2': row('b'), '3': row('c', { Enable: 'false' }) });
fs.writefile(`${RUN_DIR}/status.json`, sprintf('%J', { '1': { status: 'Up' }, '2': { status: 'Error', reason: 'x' }, '3': { status: 'Up' } }));
check('Status per ubbf-ui', map([ 1, 2, 3 ], (i) => entry.get({ instance: i, config: root.Device.UserInterface.HTTPAccess[`${i}`], root }).Status),
	[ 'Up', 'Error', 'Down' ]);
fs.unlink(`${RUN_DIR}/status.json`);
check('Status without ubbf-ui', entry.get({ instance: 1, config: root.Device.UserInterface.HTTPAccess['1'], root }).Status, 'Down');
root = config({ '1': row('a', { Interface: 'Device.IP.Interface.9' }), '2': row('b', { CABundle: 'Device.Security.CABundle.99' }) });
check('Status with an unresolved reference', map([ 1, 2 ], (i) => entry.get({ instance: i, config: root.Device.UserInterface.HTTPAccess[`${i}`], root }).Status),
	[ 'Error', 'Error' ]);

// CreateWebSession(): bad timeouts are bad arguments.
root = config({ '1': row('a') });
for (let t in [ 'abc', '-1', '4294967296', '99999999999' ])
	check(`AbsoluteTimeout ${t}`, create({ AbsoluteTimeout: t }, '', [ 1 ], root), -USP_ERR_INVALID_COMMAND_ARGS);
check('IdleTimeout too large', create({ IdleTimeout: '4294967296' }, '', [ 1 ], root), -USP_ERR_INVALID_COMMAND_ARGS);
let ws1 = create({ AbsoluteTimeout: '4294967295' }, '', [ 1 ], root);
check('largest unsignedInt accepted', type(ws1?.SessionID), 'string');

// Session numbers stay with their session.
fs.writefile(`${RUN_DIR}/sessions.json`, sprintf('%J', { sessions: [
	{ id: 'c1', alias: 'a', ip: '192.0.2.1', peer_port: 40001, protocol: 'HTTPS', user: '1', start: 1 },
	{ id: 'c2', alias: 'a', ip: '192.0.2.2', peer_port: 40002, protocol: 'HTTPS', user: '1', start: 2 }
] }));
let parent = root.Device.UserInterface.HTTPAccess['1'];
let rows = session.get({ parent });
check('three sessions', map(sort(keys(rows)), (k) => rows[k].SessionID), [ 'c1', 'c2', ws1.SessionID ]);
check('unused web session has no Port', exists(rows['3'], 'Port'), false);
check('connection has its Port', rows['2'].Port, '40002');

fs.writefile(`${RUN_DIR}/sessions.json`, sprintf('%J', { sessions: [
	{ id: 'c2', alias: 'a', ip: '192.0.2.2', peer_port: 40002, protocol: 'HTTPS', user: '1', start: 2 }
] }));
let ws2 = create({}, '', [ 1 ], root);
rows = session.get({ parent });
check('c2 keeps number 2', rows['2']?.SessionID, 'c2');
check('web session keeps number 3', rows['3']?.SessionID, ws1.SessionID);
check('new web session gets number 4', rows['4']?.SessionID, ws2.SessionID);
check('number 1 is gone', rows['1'], null);
check('single read by number', session.get({ parent, instance: 3 })?.SessionID, ws1.SessionID);

check('Delete() of number 3', remove({}, '', [ 1, 3 ], root), {});
check('Delete() removed the file of that web session', !!fs.access(`${WEBSESSIONS_DIR}/${ws1.SessionID}.json`), false);
check('the other web session stays', !!fs.access(`${WEBSESSIONS_DIR}/${ws2.SessionID}.json`), true);
check('Delete() of a gone number', remove({}, '', [ 1, 3 ], root), null);

// A disabled row loses its web sessions at the commit.
config_store(config({ '1': row('a', { Enable: 'false' }) }));
commit_hook();
check('web sessions of a disabled row removed', fs.lsdir(WEBSESSIONS_DIR), []);

// AutoDisableDuration beyond 2^31 ms: the row expires neither at once nor
// never; a short one expires.
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
	check(`AutoDisableDuration ${c[0]}: writes within 2.5 s`, length(applied), c[1]);
	check(`AutoDisableDuration ${c[0]}: TimeLeft counts down`, left >= int(c[0]) - 3 && left > 0, c[1] == 0);
}

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
