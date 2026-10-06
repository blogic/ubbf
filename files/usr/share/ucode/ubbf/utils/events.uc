'use strict';

import * as ubus from 'ubus';

/**
 * Forwards a USP event to the bbf-dm data model without waiting for a
 * reply. Uses `return: 'ignore'` so the caller's uloop never blocks on
 * bbf-dm; this is required to avoid deadlock when the calling process
 * also serves ubus requests that bbf-dm might be blocked on during a
 * trans_commit -> bbf-device.apply chain.
 *
 * @param {string} path - TR-181 event path (e.g. "Device.X.Y!")
 * @param {object} args - Event arguments payload
 */
export function dm_event_send(path, args) {
	ubus.call({
		object: 'bbf-dm',
		method: 'event',
		data: { path, args },
		return: 'ignore'
	});
};
