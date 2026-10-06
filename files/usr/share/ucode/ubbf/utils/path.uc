'use strict';

import * as ubbf from 'ubbf';
import { netifd_status_get } from 'ubbf.utils.netifd';

/**
 * Resolves a netifd logical interface name to its Linux device name.
 *
 * @param {string} name - netifd interface name, for example "lan"
 * @returns {string|null} Linux device name or null if the interface is unknown
 */
export function device_from_name(name) {
	let status = netifd_status_get(name);

	return status?.l3_device ?? status?.device ?? null;
};

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

	return device_from_name(name);
};

/**
 * Returns the Device.Ethernet.Interface row of a netdev, the reverse of
 * interface_resolve() for a layer 1 interface.
 *
 * The rows are read directly: ubbf.instances() would add `.instance` and
 * `.path` keys to the tree it walks, and those leak into later responses.
 *
 * @param {object} root - Root data model object
 * @param {string} netdev - Linux device name, for example "lan1"
 * @returns {string} Row path, or '' when no row has that Name
 */
export function ethernet_interface_path(root, netdev) {
	if (!netdev)
		return '';

	for (let key, iface in root?.Device?.Ethernet?.Interface ?? {}) {
		if (ubbf.is_instance_key(key) && type(iface) == 'object' && iface.Name == netdev)
			return sprintf('Device.Ethernet.Interface.%s', key);
	}

	return '';
};
