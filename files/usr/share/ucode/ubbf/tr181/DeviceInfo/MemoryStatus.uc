'use strict';

import * as ubus from 'ubus';

/**
 * Get handler for Device.DeviceInfo.MemoryStatus.
 *
 * @param {object} ctx - Context
 * @returns {object} Memory statistics from ubus system info
 */
function get(ctx) {
	let info = ubus?.call('system', 'info', {});

	let memory = info?.memory;
	let total = 0;
	let free = 0;
	let available = 0;
	if (memory) {
		total = int((memory.total ?? 0) / 1024);
		free = int((memory.free ?? 0) / 1024);
		available = int((memory.available ?? 0) / 1024);
	}

	let root = info?.root;
	let total_persistent = int(root?.total ?? 0);
	let free_persistent = int(root?.free ?? 0);

	return {
		Total: sprintf('%d', total),
		Free: sprintf('%d', free),
		TotalPersistent: sprintf('%d', total_persistent),
		FreePersistent: sprintf('%d', free_persistent),
		Available: sprintf('%d', available)
	};
}

export const model = {
	'Device.DeviceInfo.MemoryStatus': {
		schema: 'DeviceInfo.MemoryStatus',
		get: get
	}
};
