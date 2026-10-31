// ubbf-device loads its modules without a wait on a hostapd that answers no
// ubus call: it publishes bbf-device only after they loaded, and every apply
// fails until then. tests/device-hostapd-wedged models such a device. The test
// runs the import statements of /usr/sbin/ubbf-device and the plugin loader on
// the plugins that modules ship, in a plain ucode process, so that it covers
// every module the daemon loads and none of its start actions.
'use strict';

import * as fs from 'fs';
import { describe, it, assert } from 'utest';

const REPO = fs.getcwd();
const TESTS = `${REPO}/tests`;
const MARKS = '/tmp/wedged-marks';
const SCRIPT = '/tmp/wedged-load.uc';
const LIMIT_S = 10;
const IMPORT_RE = regexp('^import ([^;]|\n)*;', 'g');
const PLUGIN_DIRS = sort(fs.glob(`${REPO}/modules/*/files/usr/share/ucode/ubbf/device/plugins`));

function now_s() {
	let t = clock(true);
	return t[0] + t[1] / 1e9;
}

function load_script() {
	let imports = map(match(fs.readfile(`${REPO}/files/usr/sbin/ubbf-device`), IMPORT_RE) ?? [], (m) => m[0]);
	assert.match(true, length(imports) >= 15, 'ubbf-device imports its modules');

	return join('\n', imports) + `
for (let dir in ${sprintf('%J', PLUGIN_DIRS)})
	for (let plugin in plugins_load(dir, PLUGIN_PREFIX))
		printf('%s\\n', plugin.name);
print('loaded\\n');
`;
}

describe('ubbf-device on a wedged hostapd', () => {
	it('loads its modules and plugins without iwinfo and nl80211', () => {
		fs.mkdir(MARKS);
		fs.writefile(SCRIPT, load_script());

		let paths = join(' ', map(PLUGIN_DIRS, (d) => `-L '${replace(d, /\/ubbf\/device\/plugins$/, '')}/*.uc'`));
		let start = now_s();
		let p = fs.popen(`WEDGED_MARKS=${MARKS} ucode -L '${TESTS}/device-hostapd-wedged/*.uc' -L '${TESTS}/lib/*.uc' ` +
			`-L /usr/share/ucode -L '${getenv('UBBF_BUILD_DIR')}/*.so' ${paths} ${SCRIPT} 2>&1`, 'r');
		let out = p.read('all');
		let rc = p.close();
		let elapsed_s = now_s() - start;

		assert.match([ 0, 'easymesh_events\nhardware\nieee8021x\nsfp_allow\nloaded\n' ], [ rc, out ],
			`every module and shipped plugin loads: ${out}`);
		assert.match([], fs.lsdir(MARKS), 'none of them loads iwinfo or nl80211');
		assert.match(true, elapsed_s < LIMIT_S, `they load within ${LIMIT_S} s, not ${elapsed_s} s`);
	});
});
