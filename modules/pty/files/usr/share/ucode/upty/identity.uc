// Device identity reported to the server, for display only.
//
// Every field is best effort: on a device where a source file is missing the
// field is simply omitted rather than guessed at.

'use strict';

import * as fs from 'fs';

function file_line(path) {
	let data = fs.readfile(path);

	return data ? trim(data) : null;
}

function firmware_get() {
	let data = fs.readfile('/etc/openwrt_release');

	if (!data)
		return null;

	let m = match(data, /DISTRIB_DESCRIPTION='([^']*)'/);

	return m ? m[1] : null;
}

function wan_mac_get() {
	let data = fs.readfile('/etc/board.json');

	if (!data)
		return null;

	try {
		let device = json(data)?.network?.wan?.device;

		return device ? file_line(`/sys/class/net/${device}/address`) : null;
	} catch (e) {
		return null;
	}
}

/**
 * Collects the device description sent in the hello message.
 *
 * @returns {object} Only the fields that could be determined
 */
export function describe() {
	let fields = {
		model: file_line('/tmp/sysinfo/model'),
		board: file_line('/tmp/sysinfo/board_name'),
		hostname: file_line('/proc/sys/kernel/hostname'),
		firmware: firmware_get(),
		mac: wan_mac_get()
	};

	let device = {};

	for (let key, value in fields)
		if (value)
			device[key] = value;

	return device;
};
