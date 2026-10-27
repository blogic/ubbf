// The state that tests/run.sh gives all test files in one namespace: a
// test that needs a clean state calls state_clear() in its setup().
'use strict';

import * as fs from 'fs';

const STATE_DIRS = [ '/tmp/ubbf', '/etc/ubbf' ];

function tree_remove(path) {
	if (fs.lstat(path)?.type == 'directory') {
		for (let name in fs.lsdir(path) ?? [])
			tree_remove(`${path}/${name}`);
		fs.rmdir(path);
		return;
	}

	fs.unlink(path);
}

/**
 * Empties /tmp/ubbf and /etc/ubbf.
 */
export function state_clear() {
	for (let dir in STATE_DIRS) {
		tree_remove(dir);
		fs.mkdir(dir);
	}
};
