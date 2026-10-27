// Host test of the ubbf-device plugin loader (device/plugin-loader.uc) with
// the fixtures in tests/device-plugins/fixtures, and of the plugins that
// modules ship.
'use strict';

import { describe, it, assert } from 'utest';
import {
	plugins_load, plugins_init, plugins_methods, plugins_subscribe
} from 'ubbf.device.plugin-loader';

const REPO = sourcepath(0, true) + '/..';

// The loader imports a plugin by its module name, so the directories of
// the fixtures and of the shipped plugins go on the search path. They come
// last, so that the shared stand-ins of tests/lib keep precedence.
push(REQUIRE_SEARCH_PATH,
	REPO + '/tests/device-plugins/*.uc',
	REPO + '/modules/usfpd/files/usr/share/ucode/*.uc',
	REPO + '/modules/easymesh/files/usr/share/ucode/*.uc');

function names(plugins) {
	return map(plugins, (p) => p.name);
}

describe('device plugin loader', () => {
	it('loads, starts and subscribes the plugins that work', () => {
		let loaded = plugins_load(REPO + '/tests/device-plugins/fixtures', 'fixtures.');
		assert.match([ 'alpha', 'init_dies', 'methods_die', 'no_exports' ], names(loaded), 'plugins that load, in name order');

		let started = plugins_init(loaded);
		assert.match([ 'alpha', 'methods_die', 'no_exports' ], names(started), 'a plugin whose init() throws is left out');

		let alpha = started[0].mod;
		assert.match([ 'init' ], alpha.calls, 'init() runs once');

		let methods = plugins_methods(started, { reboot: { call: 'core', args: {} } });
		assert.match([ 'alpha_status', 'reboot' ], sort(keys(methods)),
			'the plugin adds its methods; a taken name stays with the core');
		assert.match('core', methods.reboot.call, 'the core method is kept');
		assert.match({ alpha: true }, methods.alpha_status.call(), 'the plugin method answers');

		plugins_subscribe(started);
		assert.match([ 'init', 'subscribe' ], alpha.calls, 'subscribe() runs after init(); a throwing subscribe() is contained');
	});

	it('loads nothing from a missing directory', () => {
		assert.match([], plugins_load(REPO + '/tests/device-plugins/none', 'none.'), 'a missing directory loads nothing');
	});

	it('loads the plugins that modules ship', () => {
		let shipped = plugins_load(REPO + '/modules/usfpd/files/usr/share/ucode/ubbf/device/plugins', 'ubbf.device.plugins.');
		assert.match([ 'sfp_allow' ], names(shipped), 'usfpd ships sfp_allow');
		assert.match('function', type(shipped[0]?.mod?.init), 'sfp_allow exports init()');

		shipped = plugins_load(REPO + '/modules/easymesh/files/usr/share/ucode/ubbf/device/plugins', 'ubbf.device.plugins.');
		assert.match([ 'easymesh_events' ], names(shipped), 'easymesh ships easymesh_events');
		assert.match([ 'event_data_clear', 'event_data_status' ], sort(keys(shipped[0]?.mod?.ubus_methods?.() ?? {})),
			'easymesh_events publishes the event data methods');
	});
});
