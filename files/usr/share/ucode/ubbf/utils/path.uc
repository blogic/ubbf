'use strict';

import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Resolves a TR-181 interface path to a Linux device name.
 *
 * @param {object} root - Root data model object
 * @param {string} iface_path - TR-181 interface path
 * @returns {string|null} Linux device name or null if not found
 */
export function interface_resolve(root, iface_path) {
	if (!iface_path || iface_path == '')
		return null;

	let parts = ubbf.path_to_parts(iface_path);
	let config = ubbf.navigate_data(root, parts);
	let name = config?.Name;
	if (!name)
		return null;

	let status = netifd_status_get(name);

	return status?.l3_device ?? status?.device ?? null;
};
