'use strict';

export let services = {};

/**
 * Records the desired enabled state of a service.
 *
 * Apply turns true into enable+start and false into disable+stop. A
 * single system-wide reload_config after the UCI commit picks up
 * config changes for already-running services that registered a procd
 * reload trigger, so callers do not need to request restart or reload.
 *
 * @param {string} name - Service name
 * @param {*} enable - Truthy to ensure running, falsy to stop
 */
export function set_enabled(name, enable) {
	services[name] = !!enable;
};

/**
 * Resets the services state map.
 */
export function init() {
	services = {};
};
