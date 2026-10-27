// Stand-in for the ubus module of tests/ieee8021x-plugin.uc: keeps the
// wpa_supplicant and hostapd interfaces in global.WPAS.present and
// global.WPAS.hostapd, records each call in global.WPAS.calls, answers
// eapol_status from global.EAPOL and the netifd dump from global.IFACES,
// and keeps the listeners, and the subscribers with their objects in
// global.SUBSCRIBERS.
'use strict';

let last_error;

/**
 * Answers a call to the wpad daemon objects.
 *
 * @param {object} wpas - global.WPAS
 * @param {string} object - Object name
 * @param {string} method - Method name
 * @param {object} data - Arguments
 * @returns {*} The answer, or null
 */
function wpad_call(wpas, object, method, data) {
	let sets = { wpa_supplicant: wpas.present, hostapd: wpas.hostapd };

	if (sets[object] && method == 'config_add') {
		sets[object][data.iface] = true;
		return { pid: 1 };
	}
	if (sets[object] && method == 'config_remove') {
		delete sets[object][data.iface];
		return null;
	}

	let m = match(object, /^(wpa_supplicant|hostapd)\.(.+)$/);
	if (!m)
		return null;
	if (!sets[m[1]][m[2]]) {
		last_error = 'Not found';
		return null;
	}

	if (method == 'eapol_status')
		return global.EAPOL ?? { pae_state: 'CONNECTING' };
	if (method == 'control')
		return { result: 'OK\n' };
	if (method == 'get_status')
		return { driver: 'wired', status: 'ENABLED' };
	return null;
}

export function call(object, method, data) {
	let wpas = global.WPAS ??= {};
	wpas.present ??= {};
	wpas.hostapd ??= {};
	push(wpas.calls ??= [], [ object, method, data ]);
	last_error = null;

	if (object == 'network.interface' && method == 'dump')
		return { interface: global.IFACES ?? [] };

	return wpad_call(wpas, object, method, data);
};

export function error() {
	return last_error;
};

export function listener(pattern, cb) {
	(global.LISTENERS ??= {})[pattern] = cb;
	return {};
};

export function subscriber(cb, remove_cb, patterns) {
	let entry = { cb, objects: [ ...(patterns ?? []) ] };
	push(global.SUBSCRIBERS ??= [], entry);
	return { subscribe: (object) => push(entry.objects, object) };
};
