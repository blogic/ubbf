// Host test of the native module loader and dm-host. Needs dm-host and the
// test module dmtest.so (CMake option UBBF_DM_TEST_MODULE) in DM_HOST_DIR,
// the build of src/dm-host; without them the test is skipped.
'use strict';

import { describe, it, skip, assert } from 'utest';
import * as uloop from 'uloop';
import { access, readfile } from 'fs';
import { native_modules_register, native_modules_notify } from 'ubbf.utils.dm-native';

const dir = getenv('DM_HOST_DIR');
const host_it = (dir && access(dir + '/dm-host') && access(dir + '/dmtest.so')) ? it : skip;

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

describe('native module loader', () => {
	host_it('registers dmtest, serves it through dm-host and restarts dm-host', () => {
		uloop.init();

		let model = {}, operations = {}, events = [];
		let names = native_modules_register(model, operations, {
			glob: dir + '/dmtest.so',
			host: dir + '/dm-host',
			respawn_ms: 200,
			event: (path, args) => push(events, path)
		});

		assert.match([ 'dmtest' ], names);
		assert.match([ 'Device.X_UBBF_DMTest', 'Device.X_UBBF_DMTest.Item', 'Device.X_UBBF_DMTest.Item.{i}' ],
			sort(keys(model)));
		assert.match({ since: '2.20', addable: false },
			{ since: model['Device.X_UBBF_DMTest.Item.{i}'].since, addable: model['Device.X_UBBF_DMTest.Item.{i}'].addable });
		assert.match(null, model['Device.X_UBBF_DMTest.Item'].get, 'container has no get');
		assert.match([ 'sync', 'sync', 'sync', 'sync', 'async', 'async' ],
			map(sort(keys(operations)), (k) => operations[k].type));

		let root = { Device: { Ethernet: { Interface: { '1': { Name: 'eth0' } } } } };
		let get = model['Device.X_UBBF_DMTest'].get;
		let item = model['Device.X_UBBF_DMTest.Item.{i}'].get;

		assert.match({ Value: 'hello', Name: 'x', Needs: 'yes' }, get({ config: { Name: 'x' }, root }));
		assert.match({ Value: 'hello', Name: '', Needs: 'no' }, get({ root: {} }));
		assert.match({ Index: '2', Path: 'Device.X_UBBF_DMTest.Item.2' }, item({ instance: 2, instances: [ 2 ], root }));
		assert.match(null, item({ instance: 5, root }));

		let echo = operations['Device.X_UBBF_DMTest.Echo()'].handler;
		assert.match({ Text: 'hi' }, echo({ Text: 'hi' }, 'key', root));
		assert.match(-7022, operations['Device.X_UBBF_DMTest.Fail()'].handler({}, '', root));

		let later = null;
		operations['Device.X_UBBF_DMTest.Later()'].handler({}, 7, (inst, err, msg, output) => {
			later = { inst, err, output };
			uloop.end();
		}, 'key', root);
		loop_run(2000);
		assert.match({ inst: 7, err: 0, output: { Result: 'done' } }, later, 'async completes');

		// An async operation that misses its deadline fails once; the late
		// completion of the module is dropped.
		let slow = [];
		operations['Device.X_UBBF_DMTest.Slow()'].handler({}, 3, (inst, err, msg, output) => {
			push(slow, { inst, err, msg });
		}, 'key', root);
		loop_run(2500);
		assert.match([ { inst: 3, err: USP_ERR_COMMAND_FAILURE, msg: 'module did not complete in 1 s' } ], slow);

		let children = dm_host_pids();
		assert.match(1, length(children), 'one child');
		assert.match(+split(readfile('/proc/self/stat'), ' ')[0], parent_pid(children[0]), 'child of this process');

		// A crash ends the request; the module comes back after the respawn delay.
		assert.match(null, operations['Device.X_UBBF_DMTest.Crash()'].handler({}, '', root));
		loop_run(600);
		let after_crash = dm_host_pids();
		assert.match(true, length(after_crash) == 1 && after_crash[0] != children[0], 'respawned after crash');
		assert.match({ Text: 'again' }, echo({ Text: 'again' }, '', root));

		// A hang hits the request timeout, the process is killed and restarted.
		let t0 = clock(true)[0];
		assert.match(null, operations['Device.X_UBBF_DMTest.Hang()'].handler({}, '', root));
		let waited = clock(true)[0] - t0;
		assert.match(true, waited >= 1 && waited <= 4, 'hang waits for the timeout');
		loop_run(600);
		assert.match({ Text: 'back' }, echo({ Text: 'back' }, '', root));

		native_modules_notify('commit', root);
		native_modules_notify('abort', root);
		assert.match({ Text: 'n' }, echo({ Text: 'n' }, '', root), 'echo after commit and abort');

		// More than 5 quick crashes and the module stays down.
		for (let i = 0; i < 6; i++) {
			operations['Device.X_UBBF_DMTest.Crash()'].handler({}, '', root);
			loop_run(500);
		}
		assert.match(0, length(dm_host_pids()), 'stays down after crash loop');
		assert.match(null, get({ root }), 'get after crash loop');
	});
});
