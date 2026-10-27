'use strict';

// import() resolves module names only, not paths, and a name segment allows
// only letters, digits and '_' (uc_require_path() in ucode lib.c).

import * as fs from 'fs';
import { log_err, log_exception, log_info } from 'ubbf.utils.logging';

export const PLUGIN_DIR = '/usr/share/ucode/ubbf/device/plugins';
export const PLUGIN_PREFIX = 'ubbf.device.plugins.';

/**
 * Loads each plugin in a directory. A plugin that does not load is logged
 * and left out, so one broken package cannot stop the daemon.
 *
 * @param {string} dir - Directory of the plugin files
 * @param {string} prefix - Module name prefix of that directory
 * @returns {array} Loaded plugins as { name, mod }, in name order
 */
export function plugins_load(dir, prefix) {
	let plugins = [];

	for (let path in sort(fs.glob(`${dir}/*.uc`) ?? [])) {
		let name = replace(fs.basename(path), /\.uc$/, '');
		if (!match(name, /^[A-Za-z0-9_]+$/)) {
			log_err('plugin %s: the name allows only letters, digits and _', path);
			continue;
		}

		try {
			push(plugins, { name, mod: import(prefix + name) });
			log_info('plugin %s loaded', name);
		} catch (e) {
			log_exception(`plugin ${name}`, e);
		}
	}

	return plugins;
};

/**
 * Calls init() of each plugin. A plugin whose init() throws is logged and
 * removed, so that its methods are not published.
 *
 * @param {array} plugins - Plugins from plugins_load()
 * @returns {array} The plugins whose init() succeeded or that have none
 */
export function plugins_init(plugins) {
	return filter(plugins, (plugin) => {
		try {
			plugin.mod.init?.();
			return true;
		} catch (e) {
			log_exception(`plugin ${plugin.name} init`, e);
			return false;
		}
	});
};

/**
 * Returns the ubus methods of one plugin. A plugin whose ubus_methods()
 * throws is logged and publishes no methods.
 *
 * @param {object} plugin - Plugin from plugins_init()
 * @returns {object} Method table of the plugin
 */
function plugin_methods_get(plugin) {
	try {
		return plugin.mod.ubus_methods?.() ?? {};
	} catch (e) {
		log_exception(`plugin ${plugin.name} ubus_methods`, e);
		return {};
	}
}

/**
 * Adds the ubus methods of the plugins to a method table. A name that the
 * table already has is logged and the method of the plugin is left out.
 *
 * @param {array} plugins - Plugins from plugins_init()
 * @param {object} methods - Method table of bbf-device, changed in place
 * @returns {object} The method table
 */
export function plugins_methods(plugins, methods) {
	for (let plugin in plugins) {
		for (let name, method in plugin_methods_get(plugin)) {
			if (exists(methods, name)) {
				log_err('plugin %s: method %s exists already', plugin.name, name);
				continue;
			}
			methods[name] = method;
		}
	}

	return methods;
};

/**
 * Calls subscribe() of each plugin, after bbf-device is published.
 *
 * @param {array} plugins - Plugins from plugins_init()
 */
export function plugins_subscribe(plugins) {
	for (let plugin in plugins) {
		try {
			plugin.mod.subscribe?.();
		} catch (e) {
			log_exception(`plugin ${plugin.name} subscribe`, e);
		}
	}
};
