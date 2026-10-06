'use strict';

import * as fs from 'fs';
import * as ubbf from 'ubbf';

/**
 * Detects the cgroup base path for a container.
 * Works for UXC, LXC, and crun -- cgroup paths are runtime-agnostic.
 *
 * @param {string} name - Container name
 * @returns {object|null} { version: 1|2, path } or null
 */
export function path_detect(name) {
	if (fs.stat('/sys/fs/cgroup/cgroup.controllers')) {
		let paths = [
			sprintf('/sys/fs/cgroup/containers/%s/%s', name, name),
			sprintf('/sys/fs/cgroup/services/%s/%s', name, name),
			sprintf('/sys/fs/cgroup/system.slice/uxc-%s.scope', name),
			sprintf('/sys/fs/cgroup/uxc/%s', name),
			sprintf('/sys/fs/cgroup/lxc/%s', name),
			sprintf('/sys/fs/cgroup/crun/%s', name)
		];
		for (let p in paths) {
			if (fs.stat(p))
				return { version: 2, path: p };
		}
		return null;
	}

	let v1_paths = [
		sprintf('/sys/fs/cgroup/memory/uxc/%s', name),
		sprintf('/sys/fs/cgroup/memory/lxc/%s', name)
	];
	for (let p in v1_paths) {
		if (fs.stat(p))
			return { version: 1, path: p };
	}

	return null;
};

/**
 * @param {string} name - Container name
 * @returns {number} Memory usage in KiB, or -1
 */
export function memory_read(name) {
	let cg = path_detect(name);
	if (!cg)
		return -1;

	let file = (cg.version == 2)
		? sprintf('%s/memory.current', cg.path)
		: sprintf('%s/memory.usage_in_bytes', cg.path);

	let bytes = +ubbf.readfile_trim(file, '');
	if (bytes != bytes)
		return -1;

	return int(bytes / 1024);
};

/**
 * @param {string} name - Container name
 * @returns {number} CPU usage percentage, or -1
 */
export function cpu_read(name) {
	let cg = path_detect(name);
	if (!cg)
		return -1;

	if (cg.version == 2) {
		let content = fs.readfile(sprintf('%s/cpu.stat', cg.path));
		if (!content)
			return -1;
		let m = match(content, /usage_usec\s+(\d+)/);
		return m ? int(+m[1] / 10000) : -1;
	}

	let ns = +ubbf.readfile_trim(sprintf('%s/cpuacct.usage', cg.path), '');
	return (ns != ns) ? -1 : int(ns / 10000000);
};
