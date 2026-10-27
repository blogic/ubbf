'use strict';

export let calls = [];

export function init() { push(calls, 'init'); };
export function subscribe() { push(calls, 'subscribe'); };
export function ubus_methods() {
	return {
		alpha_status: { call: () => ({ alpha: true }), args: {} },
		reboot: { call: () => ({}), args: {} }
	};
};
