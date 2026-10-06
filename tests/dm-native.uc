// Host test of the native module loader and dm-host. Needs dm-host and the
// test module dmtest.so (CMake option UBBF_DM_TEST_MODULE) and ubbf.so.
// Run from the repository root; the search paths have to be absolute:
//   DM_HOST_DIR=<build of src/dm-host> ucode -L "$PWD/files/usr/share/ucode/*.uc" \
//     -L "<build of ucode-mod-ubbf>/*.so" -L "<dir with a udebug stub>/*.uc" tests/dm-native.uc
'use strict';

import * as uloop from 'uloop';
import { readfile } from 'fs';
import { native_modules_register, native_modules_notify } from 'ubbf.utils.dm-native';

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

function loop_run(ms) {
	let t = uloop.timer(ms, () => uloop.end());
	uloop.run();
	t.cancel();
}

function parent_pid(pid) {
	let stat = readfile(`/proc/${pid}/stat`);
	let m = stat ? match(stat, /^[0-9]+ \(.*\) [A-Z] ([0-9]+)/) : null;
	return m ? +m[1] : null;
}

function dm_host_pids() {
	let out = [];
	for (let line in split(readfile('/proc/self/task/' + split(readfile('/proc/self/stat'), ' ')[0] + '/children') ?? '', ' '))
		if (line != '')
			push(out, +line);
	return out;
}

let dir = getenv('DM_HOST_DIR');
if (!dir) {
	printf('DM_HOST_DIR not set\n');
	exit(1);
}

uloop.init();

let model = {}, operations = {}, events = [];
let names = native_modules_register(model, operations, {
	glob: dir + '/dmtest.so',
	host: dir + '/dm-host',
	respawn_ms: 200,
	event: (path, args) => push(events, path)
});

assert_eq('registered', names, [ 'dmtest' ]);
assert_eq('patterns', sort(keys(model)),
	[ 'Device.X_UBBF_DMTest', 'Device.X_UBBF_DMTest.Item', 'Device.X_UBBF_DMTest.Item.{i}' ]);
assert_eq('item entry', { since: model['Device.X_UBBF_DMTest.Item.{i}'].since, addable: model['Device.X_UBBF_DMTest.Item.{i}'].addable },
	{ since: '2.20', addable: false });
assert_eq('container has no get', model['Device.X_UBBF_DMTest.Item'].get, null);
assert_eq('operation types', map(sort(keys(operations)), (k) => operations[k].type),
	[ 'sync', 'sync', 'sync', 'sync', 'async', 'async' ]);

let root = { Device: { Ethernet: { Interface: { '1': { Name: 'eth0' } } } } };
let get = model['Device.X_UBBF_DMTest'].get;
let item = model['Device.X_UBBF_DMTest.Item.{i}'].get;

assert_eq('get with config and needs', get({ config: { Name: 'x' }, root }),
	{ Value: 'hello', Name: 'x', Needs: 'yes' });
assert_eq('get without needs', get({ root: {} }), { Value: 'hello', Name: '', Needs: 'no' });
assert_eq('item 2', item({ instance: 2, root }), { Index: '2' });
assert_eq('item 5 absent', item({ instance: 5, root }), null);

let echo = operations['Device.X_UBBF_DMTest.Echo()'].handler;
assert_eq('echo', echo({ Text: 'hi' }, 'key', root), { Text: 'hi' });
assert_eq('fail', operations['Device.X_UBBF_DMTest.Fail()'].handler({}, '', root), -7022);

let later = null;
operations['Device.X_UBBF_DMTest.Later()'].handler({}, 7, (inst, err, msg, output) => {
	later = { inst, err, output };
	uloop.end();
}, 'key', root);
loop_run(2000);
assert_eq('async completes', later, { inst: 7, err: 0, output: { Result: 'done' } });

// An async operation that misses its deadline fails once; the late
// completion of the module is dropped.
let slow = [];
operations['Device.X_UBBF_DMTest.Slow()'].handler({}, 3, (inst, err, msg, output) => {
	push(slow, { inst, err, msg });
}, 'key', root);
loop_run(2500);
assert_eq('missed deadline fails once', slow,
	[ { inst: 3, err: USP_ERR_COMMAND_FAILURE, msg: 'module did not complete in 1 s' } ]);

let children = dm_host_pids();
assert_eq('one child', length(children), 1);
assert_eq('child of this process', parent_pid(children[0]), +split(readfile('/proc/self/stat'), ' ')[0]);

// A crash ends the request; the module comes back after the respawn delay.
assert_eq('crash returns null', operations['Device.X_UBBF_DMTest.Crash()'].handler({}, '', root), null);
loop_run(600);
let after_crash = dm_host_pids();
assert_eq('respawned after crash', length(after_crash) == 1 && after_crash[0] != children[0], true);
assert_eq('echo after crash', echo({ Text: 'again' }, '', root), { Text: 'again' });

// A hang hits the request timeout, the process is killed and restarted.
let t0 = clock(true)[0];
assert_eq('hang returns null', operations['Device.X_UBBF_DMTest.Hang()'].handler({}, '', root), null);
let waited = clock(true)[0] - t0;
assert_eq('hang waits for the timeout', waited >= 1 && waited <= 4, true);
loop_run(600);
assert_eq('echo after hang', echo({ Text: 'back' }, '', root), { Text: 'back' });

// commit and abort reach the module without an error.
native_modules_notify('commit', root);
native_modules_notify('abort', root);
assert_eq('echo after notify', echo({ Text: 'n' }, '', root), { Text: 'n' });

// Crash loop: more than 5 quick crashes and the module stays down.
for (let i = 0; i < 6; i++) {
	operations['Device.X_UBBF_DMTest.Crash()'].handler({}, '', root);
	loop_run(500);
}
assert_eq('stays down after crash loop', length(dm_host_pids()), 0);
assert_eq('get after crash loop', get({ root }), null);

printf('\n  passed: %d\n  failed: %d\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
