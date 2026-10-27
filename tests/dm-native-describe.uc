// Host test of the native module loader for a module that does not answer
// describe: the loader leaves it out and no process of it stays behind.
// tests/dm-native/silent-host stands in for dm-host. Run from the
// repository root:
//   ucode -L "$PWD/files/usr/share/ucode/*.uc" -L "<build of ucode-mod-ubbf>/*.so" \
//     -L "<dir with a udebug stub>/*.uc" tests/dm-native-describe.uc
'use strict';

import * as uloop from 'uloop';
import { readfile, writefile, unlink } from 'fs';
import { native_modules_register } from 'ubbf.utils.dm-native';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function children() {
	let self = split(readfile('/proc/self/stat'), ' ')[0];
	return filter(split(trim(readfile(`/proc/self/task/${self}/children`) ?? ''), ' '), (p) => p != '');
}

function loop_run(ms) {
	let t = uloop.timer(ms, () => uloop.end());
	uloop.run();
	t.cancel();
}

uloop.init();

let module_path = sprintf('/tmp/dm-native-describe.%d.so', time());
writefile(module_path, '');

let model = {}, operations = {};
let names = native_modules_register(model, operations, {
	glob: module_path,
	host: sourcepath(0, true) + '/dm-native/silent-host',
	respawn_ms: 100
});

check('not registered', names, []);
check('no model entries', model, {});

// past the respawn delay and the deferred kill of the loader
loop_run(500);
check('no process left', children(), []);

unlink(module_path);
printf('passed: %d failed: %d\n', pass, fail);
exit(fail ? 1 : 0);
