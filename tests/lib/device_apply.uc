// Runs the bbf-device apply of this tree for a host test.
'use strict';

import * as fs from 'fs';
import { shell_escape } from 'ubbf';

const REPO = fs.getcwd();
const TESTS = `${REPO}/tests`;

export const LIB_PATHS = `-L '${TESTS}/lib/*.uc' -L /usr/share/ucode -L '${getenv('UBBF_BUILD_DIR')}/*.so'`;

export function process_read(cmd) {
	let p = fs.popen(cmd, 'r');
	let out = p.read('all');
	return { out, rc: p.close() };
};

/**
 * The command that calls the apply method of bbf-device on a config, in a mount
 * namespace of its own: the device has umapd, and /usr/libexec/ubbf/apply is the
 * apply of this tree. The command prints the reply as JSON.
 *
 * @param {string} config_path - Config that the apply method reads
 * @param {string} [paths_first] - ucode -L options that the method and its dry-run search first
 * @returns {string} Shell command
 */
export function device_apply_cmd(config_path, paths_first) {
	let paths = `${paths_first ?? ''} -L '${TESTS}/datamodel/*.uc' ${LIB_PATHS}`;
	let shadow = `shadow() { host=$(mktemp -d); mount --bind "$1" "$host"; mount -t tmpfs none "$1"; ` +
		`for entry in "$host"/*; do ln -s "$entry" "$1"/; done; }; ` +
		`shadow /usr/sbin; touch /usr/sbin/umapd; shadow /usr/libexec; rm -f /usr/libexec/ubbf; mkdir /usr/libexec/ubbf; ` +
		`printf '#!/bin/sh\\nexec ucode ${replace(paths, /'/g, '"')} ${REPO}/files/usr/libexec/ubbf/apply "$@"\\n' > /usr/libexec/ubbf/apply; ` +
		`chmod +x /usr/libexec/ubbf/apply; ` +
		`exec ucode ${paths} ${TESTS}/secret-output/device-apply.uc ${config_path}`;
	return `unshare -m sh -ec ${shell_escape(shadow)}`;
};
