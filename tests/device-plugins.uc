// Host test of the ubbf-device plugin loader (device/plugin-loader.uc) with
// the fixtures in tests/device-plugins/fixtures, and of the plugins that
// modules ship. tests/hosts/ holds a stand-in for udebug, tests/usfpd/ one
// for ubus. Run from the repository root:
//   ucode -L "$PWD/tests/device-plugins/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/tests/usfpd/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "$PWD/modules/usfpd/files/usr/share/ucode" \
//     -L "$PWD/modules/easymesh/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/device-plugins.uc
'use strict';

import {
	plugins_load, plugins_init, plugins_methods, plugins_subscribe
} from 'ubbf.device.plugin-loader';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const REPO = sourcepath(0, true) + '/..';

function names(plugins) {
	return map(plugins, (p) => p.name);
}

let loaded = plugins_load(REPO + '/tests/device-plugins/fixtures', 'fixtures.');
check('plugins that load, in name order', names(loaded),
	[ 'alpha', 'init_dies', 'methods_die', 'no_exports' ]);

let started = plugins_init(loaded);
check('a plugin whose init() throws is left out', names(started),
	[ 'alpha', 'methods_die', 'no_exports' ]);

let alpha = started[0].mod;
check('init() runs once', alpha.calls, [ 'init' ]);

let methods = plugins_methods(started, { reboot: { call: 'core', args: {} } });
check('the plugin adds its methods; a taken name stays with the core',
	sort(keys(methods)), [ 'alpha_status', 'reboot' ]);
check('the core method is kept', methods.reboot.call, 'core');
check('the plugin method answers', methods.alpha_status.call(), { alpha: true });

plugins_subscribe(started);
check('subscribe() runs after init(); a throwing subscribe() is contained',
	alpha.calls, [ 'init', 'subscribe' ]);

check('a missing directory loads nothing', plugins_load(REPO + '/tests/device-plugins/none', 'none.'), []);

let shipped = plugins_load(REPO + '/modules/usfpd/files/usr/share/ucode/ubbf/device/plugins',
	'ubbf.device.plugins.');
check('usfpd ships sfp_allow', names(shipped), [ 'sfp_allow' ]);
check('sfp_allow exports init()', type(shipped[0]?.mod?.init), 'function');

shipped = plugins_load(REPO + '/modules/easymesh/files/usr/share/ucode/ubbf/device/plugins',
	'ubbf.device.plugins.');
check('easymesh ships easymesh_events', names(shipped), [ 'easymesh_events' ]);
check('easymesh_events publishes the event data methods',
	sort(keys(shipped[0]?.mod?.ubus_methods?.() ?? {})), [ 'event_data_clear', 'event_data_status' ]);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
