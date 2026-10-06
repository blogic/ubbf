// USB device authorization for Device.USB.USBHosts.AllowAllDevices and
// AllowedDevice.{i}. The kernel holds a new device unconfigured while the
// authorized_default of its root hub is 0; writing 1 to the authorized
// file of the device lets it configure, 0 takes it away again.
'use strict';

import * as fs from 'fs';

const ROOT_HUB = regexp('^usb[0-9]+$');
const DEVICE = regexp('^[0-9]+-[0-9.]+$');

/**
 * Reads the policy from the UCI package ubbf_usb.
 *
 * @param {object} cursor - uci cursor
 * @returns {object} { allow_all, rules }; allow_all is true without a
 *   global section, as the kernel default
 */
export function policy_load(cursor) {
	let policy = { allow_all: true, rules: [] };

	cursor?.foreach('ubbf_usb', null, (s) => {
		if (s['.type'] == 'usb' && s['.name'] == 'global')
			policy.allow_all = (s.allow_all != '0');
		else if (s['.type'] == 'allow')
			push(policy.rules, {
				vendor: s.vendor ?? '',
				product: s.product ?? '',
				class: s.class ?? '',
				subclass: s.subclass ?? '',
				protocol: s.protocol ?? '',
				interfaces: (type(s.interface) == 'array') ? s.interface : (s.interface ? [ s.interface ] : [])
			});
	});

	return policy;
};

/**
 * Lists the interfaces of a device as class:subclass:protocol, taken from
 * the raw descriptors, which an unauthorized device has too.
 *
 * @param {string} raw - Content of the descriptors file
 * @returns {array} Lower-case two-digit hex triples, one per interface
 *   descriptor (alternate settings included)
 */
export function descriptors_interfaces(raw) {
	let list = [];
	let len = length(raw ?? '');

	for (let off = 0; off + 1 < len; ) {
		let size = ord(raw, off);
		if (!size)
			break;

		// bDescriptorType 4 is an interface descriptor (USB 2.0 table 9-12)
		if (ord(raw, off + 1) == 4 && size >= 9 && off + 8 < len)
			push(list, sprintf('%02x:%02x:%02x', ord(raw, off + 5), ord(raw, off + 6), ord(raw, off + 7)));

		off += size;
	}

	return list;
};

/**
 * Reads the identity of a device from its sysfs directory.
 *
 * @param {string} dir - /sys/bus/usb/devices/<name>
 * @returns {object|null} { vendor, product, class, subclass, protocol,
 *   interfaces } as lower-case hex
 */
export function device_identity(dir) {
	let read = (name) => lc(trim(fs.readfile(`${dir}/${name}`) ?? ''));
	let vendor = read('idVendor');
	if (vendor == '')
		return null;

	return {
		vendor,
		product: read('idProduct'),
		class: read('bDeviceClass'),
		subclass: read('bDeviceSubClass'),
		protocol: read('bDeviceProtocol'),
		interfaces: descriptors_interfaces(fs.readfile(`${dir}/descriptors`))
	};
};

/**
 * Matches one criterion. An empty pattern does not filter; a pattern with
 * `*` matches as a wildcard on the zero-padded value; any other pattern
 * matches by hex number, so `12` and `0012` are the same Vendor ID.
 *
 * @param {string} pattern - Criterion from the rule
 * @param {string} value - Lower-case hex value of the device
 * @returns {boolean} True when the value matches
 */
export function field_match(pattern, value) {
	pattern = lc(pattern ?? '');
	if (pattern == '')
		return true;

	if (index(pattern, '*') >= 0)
		return wildcard(value, pattern);

	return match(pattern, /^[0-9a-f]+$/) != null && hex(pattern) == hex(value);
};

/**
 * Matches one interface triple against one Interfaces item.
 *
 * @param {string} item - 'Class:SubClass:Protocol' pattern
 * @param {string} iface - Interface triple of the device
 * @returns {boolean} True when all three fields match
 */
function interface_match(item, iface) {
	let p = split(item, ':');
	let v = split(iface, ':');
	if (length(p) != 3)
		return false;

	return field_match(p[0], v[0]) && field_match(p[1], v[1]) && field_match(p[2], v[2]);
}

/**
 * Matches a device against one rule. With Interfaces set, every interface
 * of the device must match an item.
 *
 * @param {object} rule - Rule of policy_load()
 * @param {object} id - Identity of device_identity()
 * @returns {boolean} True when the rule allows the device
 */
export function rule_match(rule, id) {
	for (let f in [ 'vendor', 'product', 'class', 'subclass', 'protocol' ])
		if (!field_match(rule[f], id[f]))
			return false;

	if (!length(rule.interfaces))
		return true;

	for (let iface in id.interfaces)
		if (!length(filter(rule.interfaces, (item) => interface_match(item, iface))))
			return false;

	return true;
};

/**
 * Reports whether the policy allows a device.
 *
 * @param {object} policy - Policy of policy_load()
 * @param {object} id - Identity of device_identity()
 * @returns {boolean} True when the device may configure
 */
export function device_allowed(policy, id) {
	if (policy.allow_all)
		return true;

	return length(filter(policy.rules, (r) => rule_match(r, id))) > 0;
};

/**
 * Applies the policy to one device directory.
 *
 * @param {object} policy - Policy of policy_load()
 * @param {string} dir - Device directory in sysfs
 */
export function device_apply(policy, dir) {
	let id = device_identity(dir);
	if (!id)
		return;

	let want = device_allowed(policy, id) ? '1' : '0';
	if (trim(fs.readfile(`${dir}/authorized`) ?? '') != want)
		fs.writefile(`${dir}/authorized`, want);
};

/**
 * Applies the policy to every root hub and device below a sysfs root.
 *
 * @param {object} policy - Policy of policy_load()
 * @param {string} root - Directory of the USB devices, /sys/bus/usb/devices
 */
export function policy_apply(policy, root) {
	let names = fs.lsdir(root) ?? [];

	for (let name in names)
		if (match(name, ROOT_HUB))
			fs.writefile(`${root}/${name}/authorized_default`, policy.allow_all ? '1' : '0');

	for (let name in names)
		if (match(name, DEVICE))
			device_apply(policy, `${root}/${name}`);
};
