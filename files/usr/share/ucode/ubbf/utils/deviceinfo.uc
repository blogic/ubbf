'use strict';

import { readfile } from 'fs';

// json() throws on empty or malformed input, and this runs at module
// import so a throw would abort loading the whole VM; parse defensively.
function deviceinfo_load() {
	let raw = readfile('/etc/usp/deviceinfo.json');
	if (!raw)
		return {};
	try {
		let parsed = json(raw);
		return (type(parsed) == 'object') ? parsed : {};
	} catch (e) {
		return {};
	}
}

// Boot-time snapshot of /etc/usp/deviceinfo.json captured at module
// import; not refreshed until the ucode VM restarts. Missing or invalid
// JSON falls through to an empty object so callers always see a value.
const deviceinfo = deviceinfo_load();

/**
 * @returns {object} Cached device info (ManufacturerOUI, SerialNumber, etc.)
 */
export function deviceinfo_get() {
	return deviceinfo;
};
