// Stand-in for the ubus module of tests/hardware-plugin.uc: records each
// call in global.UBUS_CALLS and answers nothing.
'use strict';

export function call(...args) {
	push(global.UBUS_CALLS ??= [], args);
	return null;
};

export function listener() {
	return null;
};

export function subscriber() {
	return null;
};

export function error() {
	return null;
};
