'use strict';

import * as ubbf from 'ubbf';
import { ssid_ifname_get } from 'ubbf.utils.wifi';

/**
 * Resolves a TR-181 LowerLayers reference object to its backing Linux
 * netdev name. WiFi.SSID instances are mapped via ssid_ifname_get since
 * their kernel ifname is not stored on the data-model object; everything
 * else exposes its ifname through the Name property.
 *
 * @param {object} obj - Resolved data-model object for the reference
 * @param {string} ref - Original TR-181 path, used for SSID matching
 * @returns {string|null} Linux netdev name, or null when unresolvable
 */
function lower_netdev_resolve(obj, ref) {
	let ssid_inst = ubbf.tr181_ref_parse(ref, 'Device.WiFi.SSID');
	if (ssid_inst != null)
		return ssid_ifname_get(ssid_inst);

	return obj?.Name;
}

/**
 * Tri-state operational check on a TR-181 LowerLayers reference.
 *
 * Returns true/false from the object's own Status field where it is
 * authoritative, otherwise falls back to reading the kernel operstate
 * via the resolved netdev. Returning null means indeterminate, so
 * callers can distinguish "definitely down" from "unknown" when
 * aggregating multiple lower layers.
 *
 * @param {object} obj - Resolved data-model object for the reference
 * @param {string} ref - Original TR-181 path, passed to lower_netdev_resolve
 * @returns {boolean|null} true if up, false if down, null if indeterminate
 */
function lower_is_up(obj, ref) {
	if (!obj)
		return null;

	let st = obj.Status;
	if (st == 'Up' || st == 'Enabled')
		return true;
	if (st == 'Down' || st == 'Disabled' || st == 'LowerLayerDown'
	    || st == 'NotPresent' || st == 'Error' || st == 'Dormant')
		return false;

	let ifname = lower_netdev_resolve(obj, ref);
	if (!ifname)
		return null;

	let op = ubbf.readfile_trim(`/sys/class/net/${ifname}/operstate`, 'unknown');
	if (op == 'up')
		return true;
	if (op == 'down' || op == 'lowerlayerdown' || op == 'notpresent')
		return false;

	return null;
}

/**
 * Derives a TR-181 Status value using the 7-value ifOperStatus-style enum.
 *
 * Used by Device.Ethernet.Interface, Device.Ethernet.Link,
 * Device.Ethernet.VLANTermination and Device.Bridging.Bridge.Port. Honours the
 * admin Enable flag and, when LowerLayers is supplied, reports LowerLayerDown
 * if the resolved lower netdev is not up.
 *
 * @param {string|boolean} enable - Admin state (TR-181 "true"/"false" or bool)
 * @param {string} ifname - Linux netdev name
 * @param {string} [lower_layers] - TR-181 LowerLayers reference
 * @param {object} [root] - Root data model, required to resolve lower_layers
 * @returns {string} One of: Up, Down, Unknown, Dormant, NotPresent, LowerLayerDown, Error
 */
export function ifop_status_derive(enable, ifname, lower_layers, root) {
	if (!ubbf.to_bool(enable))
		return 'Down';

	if (lower_layers && root) {
		let any_resolved;
		let any_indeterminate;
		for (let ref in ubbf.csv_to_list(lower_layers)) {
			let obj = ubbf.navigate_data(root, ubbf.path_to_parts(ref));
			if (!obj)
				continue;
			any_resolved = true;
			let state = lower_is_up(obj, ref);
			if (state == true)
				return 'Up';
			if (state == null)
				any_indeterminate = true;
		}
		if (any_resolved)
			return any_indeterminate ? 'Unknown' : 'LowerLayerDown';
	}

	if (!ifname)
		return 'Down';

	let op = ubbf.readfile_trim(`/sys/class/net/${ifname}/operstate`, 'unknown');
	return ubbf.operstate_to_status(op);
};

/**
 * Derives a TR-181 Status value using the 3-value Bridge enum.
 *
 * Used by Device.Bridging.Bridge.{i}.
 *
 * @param {string|boolean} enable - Admin state
 * @param {string} ifname - Bridge netdev name
 * @returns {string} One of: Disabled, Enabled, Error
 */
export function bridge_status_derive(enable, ifname) {
	if (!ubbf.to_bool(enable))
		return 'Disabled';
	if (!ifname)
		return 'Error';

	let op = ubbf.readfile_trim(`/sys/class/net/${ifname}/operstate`, 'unknown');
	if (op == 'up')
		return 'Enabled';
	if (op == 'down')
		return 'Disabled';
	return 'Error';
};
