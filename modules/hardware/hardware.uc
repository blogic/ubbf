'use strict';

// Included with { hardware } as the scope, by handler.uc in the agent and by
// the ubbf-device plugin device/plugins/hardware.uc, so that both number the
// buttons and CPUs the same way. The device tree is read below /sys, where
// /proc/device-tree points, so that a host test needs only a tmpfs on /sys.

const fs = require('fs');

// Key codes of linux/input-event-codes.h to the BUTTON names that the
// OpenWrt driver gpio-button-hotplug sends (button_map[] in
// gpio-button-hotplug.c).
const BUTTON_NAMES = {
	'256': 'BTN_0', '257': 'BTN_1', '258': 'BTN_2', '259': 'BTN_3', '260': 'BTN_4',
	'261': 'BTN_5', '262': 'BTN_6', '263': 'BTN_7', '264': 'BTN_8', '265': 'BTN_9',
	'244': 'brightness_zero', '171': 'config', '133': 'copy', '161': 'eject',
	'138': 'help', '542': 'lights_toggle', '169': 'phone', '116': 'power',
	'356': 'reboot', '408': 'reset', '247': 'rfkill', '393': 'video',
	'114': 'volume_down', '115': 'volume_up', '246': 'wwan', '238': 'wlan',
	'529': 'wps', '360': 'vendor'
};

const KEYS_COMPATIBLE = [ 'gpio-keys', 'gpio-keys-polled' ];

const ROOTS = {
	dt: '/sys/firmware/devicetree/base',
	sysfs: '/sys'
};

/**
 * Reads a device tree cell as a big-endian 32 bit number.
 *
 * @param {string} path - Property file
 * @returns {number|null} Value, or null when the file is shorter
 */
function dt_cell(path) {
	let data = fs.readfile(path);
	if (data == null || length(data) < 4)
		return null;

	return (ord(data, 0) << 24) | (ord(data, 1) << 16) | (ord(data, 2) << 8) | ord(data, 3);
}

/**
 * Tells whether a device tree node is a gpio-keys node.
 *
 * @param {string} path - Node directory
 * @returns {boolean} True for gpio-keys and gpio-keys-polled
 */
function keys_node(path) {
	let compatible = split(fs.readfile(path + '/compatible') ?? '', '\0');
	return length(filter(compatible, (c) => index(KEYS_COMPATIBLE, c) >= 0)) > 0;
}

/**
 * Returns the buttons of the gpio-keys nodes of the device tree, in node
 * order. A key code that gpio-button-hotplug does not map gives a button
 * without name: the driver sends no event for it.
 *
 * @returns {array} Buttons as { node, key, code, name, device }
 */
hardware.buttons_list = function() {
	let dt = ROOTS.dt;
	let buttons = [];

	for (let node in sort(fs.lsdir(dt) ?? [])) {
		if (!keys_node(`${dt}/${node}`))
			continue;

		for (let key in sort(fs.lsdir(`${dt}/${node}`) ?? [])) {
			let code = dt_cell(`${dt}/${node}/${key}/linux,code`);
			if (code == null)
				continue;

			let device = `${ROOTS.sysfs}/devices/platform/${node}`;
			push(buttons, {
				node,
				key,
				code,
				name: BUTTON_NAMES[sprintf('%d', code)],
				device: fs.stat(device) ? device : null
			});
		}
	}

	return buttons;
};

/**
 * Returns the numbers of the CPUs that sysfs lists, in ascending order.
 *
 * @returns {array} CPU numbers
 */
hardware.cpus_list = function() {
	let dir = `${ROOTS.sysfs}/devices/system/cpu`;
	let cpus = [];

	for (let entry in fs.lsdir(dir) ?? []) {
		let m = match(entry, /^cpu([0-9]+)$/);
		if (m)
			push(cpus, +m[1]);
	}

	return sort(cpus, (a, b) => a - b);
};

/**
 * Returns the cpufreq directory of a CPU, or null without frequency
 * scaling.
 *
 * @param {number} cpu - CPU number
 * @returns {string|null} Directory
 */
hardware.cpufreq_dir = function(cpu) {
	let dir = `${ROOTS.sysfs}/devices/system/cpu/cpu${cpu}/cpufreq`;
	return fs.stat(dir + '/scaling_governor') ? dir : null;
};

/**
 * Reads a cpufreq attribute.
 *
 * @param {string} dir - cpufreq directory
 * @param {string} name - Attribute
 * @returns {string|null} Trimmed value, or null when absent
 */
hardware.cpufreq_read = function(dir, name) {
	let data = fs.readfile(`${dir}/${name}`);
	return data == null ? null : trim(data);
};
