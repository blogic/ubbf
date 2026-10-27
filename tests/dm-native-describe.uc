// Host test of the native module loader for a module that does not answer
// describe: the loader leaves it out and no process of it stays behind.
// tests/dm-native/silent-host stands in for dm-host.
'use strict';

import { describe, it, assert } from 'utest';
import * as uloop from 'uloop';
import { readfile, writefile, unlink } from 'fs';
import { native_modules_register } from 'ubbf.utils.dm-native';

function children() {
	let self = split(readfile('/proc/self/stat'), ' ')[0];
	return filter(split(trim(readfile(`/proc/self/task/${self}/children`) ?? ''), ' '), (p) => p != '');
}

function loop_run(ms) {
	let t = uloop.timer(ms, () => uloop.end());
	uloop.run();
	t.cancel();
}

describe('native module loader without describe', () => {
	it('leaves the module out and ends its process', () => {
		uloop.init();

		let module_path = sprintf('/tmp/dm-native-describe.%d.so', time());
		writefile(module_path, '');

		let model = {}, operations = {};
		let names = native_modules_register(model, operations, {
			glob: module_path,
			host: sourcepath(0, true) + '/dm-native/silent-host',
			respawn_ms: 100
		});

		assert.match([], names, 'not registered');
		assert.match({}, model, 'no model entries');

		// past the respawn delay and the deferred kill of the loader
		loop_run(500);
		assert.match([], children(), 'no process left');

		unlink(module_path);
	});
});
