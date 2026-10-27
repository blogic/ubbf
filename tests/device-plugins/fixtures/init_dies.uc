'use strict';

export function init() { die('init failed'); };
export function ubus_methods() { return { init_dies_status: { call: () => ({}), args: {} } }; };
