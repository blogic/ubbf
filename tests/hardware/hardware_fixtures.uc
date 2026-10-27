// Fake device tree and sysfs for tests/hardware.uc and
// tests/hardware-plugin.uc, written below a tmpfs on /sys: a gpio-keys node
// with reset, wps and a key code gpio-button-hotplug does not map, and
// three CPUs, of which cpu2 has no cpufreq.
'use strict';

import * as fs from 'fs';

function mkdir_p(path) {
	let cur = '';
	for (let part in split(ltrim(path, '/'), '/')) {
		cur += '/' + part;
		fs.mkdir(cur);
	}
}

function cell(value) {
	return chr((value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255);
}

function cpufreq(cpu) {
	let dir = `/sys/devices/system/cpu/cpu${cpu}/cpufreq`;
	mkdir_p(dir);
	let files = {
		scaling_governor: 'schedutil\n',
		scaling_available_governors: 'ondemand userspace performance schedutil\n',
		scaling_available_frequencies: '437500 875000 1312500 1750000\n',
		scaling_cur_freq: '875000\n',
		scaling_min_freq: '437500\n',
		scaling_max_freq: '1750000\n',
		cpuinfo_min_freq: '437500\n',
		cpuinfo_max_freq: '1750000\n'
	};
	for (let name, value in files)
		fs.writefile(`${dir}/${name}`, value);
}

export function build() {
	let dt = '/sys/firmware/devicetree/base';
	mkdir_p(`${dt}/gpio-keys`);
	fs.writefile(`${dt}/gpio-keys/compatible`, 'gpio-keys\0');
	for (let key, code in { 'key-reset': 0x198, 'key-wps': 0x211, 'key-mystery': 0x999 }) {
		mkdir_p(`${dt}/gpio-keys/${key}`);
		fs.writefile(`${dt}/gpio-keys/${key}/linux,code`, cell(code));
	}
	mkdir_p(`${dt}/leds`);
	fs.writefile(`${dt}/leds/compatible`, 'gpio-leds\0');
	mkdir_p('/sys/devices/platform/gpio-keys');

	cpufreq(0);
	cpufreq(1);
	mkdir_p('/sys/devices/system/cpu/cpu2');
};
