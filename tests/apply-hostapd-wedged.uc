// The bbf-device apply method ends its dry run without a wait on a hostapd that
// answers no ubus call. The iwinfo of tests/device-hostapd-wedged models such a
// device: it waits 30 s when it loads. A render must not load iwinfo at all.
'use strict';

import * as fs from 'fs';
import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import { LIB_PATHS, device_apply_cmd, process_read } from 'device_apply';

const STAND_IN = `${fs.getcwd()}/tests/device-hostapd-wedged/iwinfo.uc`;
const WEDGED_DIR = '/tmp/ubbf/apply-wedged';
const MARKS = `${WEDGED_DIR}/marks`;
const IWINFO_ONLY = `${WEDGED_DIR}/modules`;
const PATHS_FIRST = `-L '${IWINFO_ONLY}/*.uc'`;
const CONFIG_PATH = `${WEDGED_DIR}/config.json`;
const SERVER = 'ntp.wedged.example';
const LIMIT_S = 10;

function now_s() {
	let t = clock(true);
	return t[0] + t[1] / 1e9;
}

describe('bbf-device apply on a wedged hostapd', () => {
	beforeEach(() => {
		state_clear();
		for (let dir in [ WEDGED_DIR, MARKS, IWINFO_ONLY ])
			fs.mkdir(dir);
		fs.symlink(STAND_IN, `${IWINFO_ONLY}/iwinfo.uc`);
	});

	it('finds the stand-in, which is still in its wait after 1 s', () => {
		let r = process_read(`WEDGED_MARKS=${MARKS} timeout 1 ucode ${PATHS_FIRST} ${LIB_PATHS} ` +
			`-e "import { phys } from 'iwinfo'; phys;" 2>&1`);

		assert.match([ 124, [ 'iwinfo' ] ], [ r.rc, fs.lsdir(MARKS) ], `the load marks the file and waits: ${r.out}`);
	});

	it('ends its dry run within the limit and does not load iwinfo', () => {
		fs.writefile(CONFIG_PATH, sprintf('%J', { Device: { Time: { Enable: 'true', Client: { '1': { Enable: 'true', Servers: SERVER } } } } }));

		let start = now_s();
		let r = process_read(`WEDGED_MARKS=${MARKS} ${device_apply_cmd(CONFIG_PATH, PATHS_FIRST)}`);
		let elapsed_s = now_s() - start;

		assert.match(0, r.rc, `the apply method runs: ${r.out}`);
		assert.match(true, index(r.out, SERVER) >= 0, `the dry run renders the config: ${r.out}`);
		assert.match([ [], true ], [ fs.lsdir(MARKS), elapsed_s < LIMIT_S ],
			`the dry run does not load iwinfo and ends within ${LIMIT_S} s, not ${elapsed_s} s`);
	});
});
