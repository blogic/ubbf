'use strict';

import * as fs from 'fs';
import { popen_async } from 'ubbf.utils.process';
import { log_info, log_err } from 'ubbf.utils.logging';
import { uxc_config_read } from 'ubbf.utils.container';

const BUNDLE_BASES = [
	'/usr/share/containers',
	'/tmp/run/uvol/.meta/oci'
];
const TMP_APK = '/tmp/ubbf-container.apk';
export const TMP_ARCHIVE = '/tmp/ubbf-bundle.tar.gz';

/**
 * Runs a shell command asynchronously and reports success or failure.
 * Always invokes the optional cleanup callback before delivering the
 * result so temporary files are removed regardless of outcome.
 *
 * @param {string} cmd - Shell command to execute
 * @param {string} label - Identifier used in log and error messages
 * @param {function} callback - Called with {success, error}
 * @param {function} [cleanup] - Optional cleanup invoked before callback
 */
function async_cmd_run(cmd, label, callback, cleanup) {
	popen_async(cmd, (result) => {
		if (cleanup)
			cleanup();

		if (result.error || result.exitcode != 0) {
			let err_msg = result.error ?? result.data ?? sprintf('%s failed (exit %d)', label, result.exitcode);
			log_err('%s: %s', label, err_msg);
			callback({ success: false, error: err_msg });
			return;
		}

		callback({ success: true });
	});
}

/**
 * Extracts the container name from an APK URL or package reference.
 *
 * @param {string} url - APK URL, package name, or apk:// reference
 * @returns {string} Container name (without 'container-' prefix)
 */
export function container_name_from_url(url) {
	let cleaned = replace(url, /^apk:\/\//, '');
	cleaned = replace(cleaned, /^.*\//, '');
	cleaned = replace(cleaned, /\.apk$/, '');
	cleaned = replace(cleaned, /-\d+[\d.]*$/, '');
	cleaned = replace(cleaned, /^container-/, '');
	return cleaned;
};

/**
 * Refreshes the APK package index from configured feeds.
 *
 * @param {function} callback - Called with {success, error}
 */
export function apk_update(callback) {
	log_info('apk_update');
	async_cmd_run('apk update 2>&1', 'apk_update', callback);
};

/**
 * Installs a container from pre-configured APK feeds.
 *
 * @param {string} package_name - APK package name (e.g. 'container-alpine')
 * @param {function} callback - Called with {success, error}
 */
export function apk_install(package_name, callback) {
	log_info('apk_install: %s', package_name);
	async_cmd_run(sprintf('apk add --no-interactive %s 2>&1', package_name), 'apk_install', callback);
};

/**
 * Downloads an APK file and installs it.
 *
 * @param {string} url - HTTP(S) URL to .apk file
 * @param {object} opts - Options (username, password)
 * @param {function} callback - Called with {success, error}
 */
export function apk_download_and_install(url, opts, callback) {
	opts ??= {};

	let fetch_parts = ['uclient-fetch', '-q'];

	if (opts.username)
		push(fetch_parts, sprintf('--user=%s', opts.username));
	if (opts.password)
		push(fetch_parts, sprintf('--password=%s', opts.password));

	push(fetch_parts, sprintf('-O "%s"', TMP_APK));
	push(fetch_parts, sprintf('"%s"', url));

	let steps = [
		join(' ', fetch_parts),
		sprintf('apk add --no-interactive --allow-untrusted "%s" 2>&1', TMP_APK)
	];

	let cmd = join(' && ', steps);

	log_info('apk_download_and_install: %s', url);
	async_cmd_run(cmd, 'apk_download_and_install', callback, () => fs.unlink(TMP_APK));
};

/**
 * Installs a local APK file.
 *
 * @param {string} path - Path to local .apk file
 * @param {function} callback - Called with {success, error}
 */
export function apk_install_local(path, callback) {
	log_info('apk_install_local: %s', path);
	async_cmd_run(sprintf('apk add --no-interactive --allow-untrusted "%s" 2>&1', path), 'apk_install_local', callback);
};

/**
 * Uninstalls an APK container package.
 *
 * @param {string} package_name - APK package name (e.g. 'container-alpine')
 * @param {function} callback - Called with {success, error}
 */
export function apk_uninstall(package_name, callback) {
	log_info('apk_uninstall: %s', package_name);
	async_cmd_run(sprintf('apk del --no-interactive %s 2>&1', package_name), 'apk_uninstall', callback);
};

/**
 * Activates uvol volumes for a container after APK install.
 * Reads the UXC config to find volume hashes and runs uvol up.
 *
 * @param {string} name - Container name
 * @param {function} callback - Called with {success, error}
 */
export function uvol_up(name, callback) {
	let cfg = uxc_config_read(name);
	if (!cfg?.volumes || !length(cfg.volumes)) {
		callback({ success: true });
		return;
	}

	let cmds = [];
	for (let hash in cfg.volumes)
		push(cmds, sprintf('uvol up "%s"', hash));

	let cmd = join(' && ', cmds);

	log_info('uvol_up: %s (%d volumes)', name, length(cfg.volumes));
	async_cmd_run(cmd, 'uvol_up', callback);
};

/**
 * Downloads and extracts an OCI bundle from an HTTP(S) URL.
 * Backward compatibility for non-APK tar.gz bundles.
 *
 * @param {string} url - HTTP(S) URL of the bundle archive
 * @param {string} dest_dir - Directory to extract the bundle into
 * @param {object} opts - Options (username, password)
 * @param {function} callback - Called with {success, error} on completion
 */
export function bundle_download(url, dest_dir, opts, callback) {
	opts ??= {};

	let curl_parts = ['curl', '--fail', '--silent', '--show-error'];

	if (opts.username)
		push(curl_parts, sprintf('-u "%s:%s"', opts.username, opts.password ?? ''));

	push(curl_parts, sprintf('-o "%s"', TMP_ARCHIVE));
	push(curl_parts, sprintf('"%s"', url));

	let steps = [
		sprintf('mkdir -p "%s"', dest_dir),
		join(' ', curl_parts),
		sprintf('tar -xzf "%s" -C "%s"', TMP_ARCHIVE, dest_dir)
	];

	if (!opts.keep_archive)
		push(steps, sprintf('rm -f "%s"', TMP_ARCHIVE));

	let cmd = join(' && ', steps);

	log_info('bundle_download: %s -> %s', url, dest_dir);

	popen_async(cmd, (result) => {
		if (result.error || result.exitcode != 0) {
			let err_msg = result.error ?? sprintf('download failed (exit %d)', result.exitcode);
			log_err('bundle_download: %s', err_msg);
			fs.unlink(TMP_ARCHIVE);
			callback({ success: false, error: err_msg });
			return;
		}

		callback({ success: true });
	});
};

/**
 * Validates that a directory contains a valid OCI bundle.
 * For APK-installed containers, only config.json is required (rootfs is in uvol).
 *
 * @param {string} bundle_path - Path to the bundle directory
 * @returns {boolean} True if bundle is valid
 */
export function bundle_validate(bundle_path) {
	return !!fs.stat(sprintf('%s/config.json', bundle_path));
};

/**
 * Returns the bundle path for a container name.
 * Checks uvol .meta path first (APK-installed), then /usr/share/containers.
 *
 * @param {string} name - Container name
 * @returns {string} Bundle path (existing or default)
 */
export function bundle_path_for(name) {
	for (let base in BUNDLE_BASES) {
		let path = sprintf('%s/%s', base, name);
		if (fs.stat(sprintf('%s/config.json', path)))
			return path;
	}

	return sprintf('%s/%s', BUNDLE_BASES[0], name);
};

/**
 * Verifies a GPG signature for a downloaded archive.
 * Backward compatibility for signed bundle downloads.
 *
 * @param {string} archive_path - Path to the archive file
 * @param {string} sig_url - URL of the detached signature
 * @param {string} keyring_path - Path to the GPG keyring
 * @param {function} callback - Called with {success, error} on completion
 */
export function signature_verify(archive_path, sig_url, keyring_path, callback) {
	let sig_path = archive_path + '.sig';

	let dl_cmd = sprintf('curl --fail --silent -o "%s" "%s"', sig_path, sig_url);
	let verify_cmd = sprintf('gpg --verify --keyring "%s" "%s" "%s" 2>&1',
		keyring_path, sig_path, archive_path);
	let cleanup_cmd = sprintf('rm -f "%s"', sig_path);

	let cmd = sprintf('%s && %s; rc=$?; %s; exit $rc', dl_cmd, verify_cmd, cleanup_cmd);

	log_info('signature_verify: %s', sig_url);

	popen_async(cmd, (result) => {
		if (result.error || result.exitcode != 0) {
			let err_msg = result.error ?? sprintf('signature verification failed (exit %d): %s',
				result.exitcode, result.data ?? '');
			log_err('signature_verify: %s', err_msg);
			callback({ success: false, error: err_msg });
			return;
		}

		callback({ success: true });
	});
};
