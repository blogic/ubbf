'use strict';

import * as fs from 'fs';
import * as ubus from 'ubus';
import * as uloop from 'uloop';
import { log_info, log_err } from 'ubbf.utils.logging';
import { popen_async } from 'ubbf.utils.process';
import * as ubbf from 'ubbf';
import {
	globals_read, containers_read, container_read,
	container_write, container_remove, instance_allocate
} from 'ubbf.container.uci';
import { monitor_start, monitor_stop } from 'ubbf.container.monitor';
import {
	manually_stopped_set, manually_stopped_clear,
	runtime_state_read, runtime_state_remove
} from 'ubbf.container.state';
import * as uxc_backend from 'ubbf.container.backend.uxc';
import * as lxc_backend from 'ubbf.container.backend.lxc';
import * as crun_backend from 'ubbf.container.backend.crun';
import {
	uuid_generate, is_apk_installed, du_state_change_emit
} from 'ubbf.utils.container';
import {
	apk_update, apk_install, apk_download_and_install, apk_install_local, apk_uninstall,
	uvol_up, container_name_from_url,
	bundle_download, bundle_validate, bundle_path_for, signature_verify, TMP_ARCHIVE
} from 'ubbf.utils.container_download';
import {
	config_apply, execenv_validate, signers_keyring_get, uid_range_allocate
} from 'ubbf.tr181.SoftwareModules.common';

let backend;

const backends = {
	uxc: uxc_backend,
	lxc: lxc_backend,
	crun: crun_backend
};

/**
 * Returns the backend module for a runtime name when its binary is present.
 *
 * @param {string} runtime - Backend identifier (uxc, lxc, crun)
 * @returns {object|null} Backend module or null when unavailable
 */
function backend_for_runtime(runtime) {
	let b = backends[runtime];
	if (b?.available())
		return b;
	return null;
}

/**
 * Picks the preferred backend, falling back to the first available one.
 *
 * @returns {object|null} Backend module or null if none are available
 */
function backend_select() {
	let globals = globals_read();
	let preferred = backend_for_runtime(globals.default_runtime);
	if (preferred)
		return preferred;

	for (let name in ['uxc', 'lxc', 'crun']) {
		let b = backend_for_runtime(name);
		if (b)
			return b;
	}

	return null;
}

/**
 * ubus handler: returns a summary entry for every configured container.
 *
 * @param {object} req - ubus request object
 */
function list_handler(req) {
	let containers = containers_read();
	let result = {};

	for (let name, cfg in containers) {
		let st = backend.state(name);
		let rs = runtime_state_read(name);

		result[name] = {
			name,
			instance: cfg.instance,
			runtime: cfg.runtime,
			uuid: cfg.uuid,
			vendor: cfg.vendor,
			version: cfg.version,
			url: cfg.url,
			exec_env_ref: cfg.exec_env_ref,
			autostart: cfg.autostart,
			privileged: cfg.privileged,
			installed: cfg.installed,
			last_update: cfg.last_update,
			status: st?.status ?? 'stopped',
			memory_kib: cfg.memory_kib,
			cpu_percent: cfg.cpu_percent,
			disk_space_kib: cfg.disk_space_kib,
			memory_in_use: (st?.status == 'running') ? backend.memory_usage(name) : -1,
			cpu_in_use: (st?.status == 'running') ? backend.cpu_usage(name) : -1,
			autorestart: cfg.autorestart,
			share_parent_network: cfg.share_parent_network,
			port_forward_count: length(cfg.port_forwards),
			mount_count: length(cfg.mounts),
			env_count: length(cfg.env_variables),
			appdata_count: length(cfg.application_data)
		};
	}

	req.reply({ containers: result });
}

/**
 * ubus handler: returns full configuration plus runtime stats for one container.
 *
 * @param {object} req - ubus request object (args.name required)
 */
function info_handler(req) {
	let name = req.args?.name;
	if (!name) {
		req.reply({ error: 'name required' }, 4);
		return;
	}

	let cfg = container_read(name);
	if (!cfg) {
		req.reply({ error: 'not found' }, 5);
		return;
	}

	let st = backend.state(name);
	let rs = runtime_state_read(name);
	let disk = backend.disk_usage(name);
	let ei = backend.exit_info(name);

	let is_running = st?.status == 'running';

	req.reply({
		name,
		instance: cfg.instance,
		runtime: cfg.runtime,
		uuid: cfg.uuid,
		vendor: cfg.vendor,
		version: cfg.version,
		url: cfg.url,
		exec_env_ref: cfg.exec_env_ref,
		autostart: cfg.autostart,
		privileged: cfg.privileged,
		installed: cfg.installed,
		last_update: cfg.last_update,
		status: st?.status ?? 'stopped',
		exit_code: ei.exit_code,
		bundle: cfg.bundle,
		memory_kib: cfg.memory_kib,
		cpu_percent: cfg.cpu_percent,
		disk_space_kib: cfg.disk_space_kib,
		memory_in_use: is_running ? backend.memory_usage(name) : -1,
		cpu_in_use: is_running ? backend.cpu_usage(name) : -1,
		disk_allocated: disk.allocated,
		disk_in_use: disk.in_use,
		uid_mapping: cfg.uid_mapping,
		autorestart: cfg.autorestart,
		restart_min_wait: cfg.restart_min_wait,
		restart_max_wait: cfg.restart_max_wait,
		restart_multiplier: cfg.restart_multiplier,
		restart_max_retries: cfg.restart_max_retries,
		restart_reset_period: cfg.restart_reset_period,
		retry_count: rs.retry_count ?? 0,
		last_restarted: rs.last_restarted,
		running_since: rs.running_since,
		share_parent_network: cfg.share_parent_network,
		port_forwards: cfg.port_forwards,
		mounts: cfg.mounts,
		env_variables: cfg.env_variables,
		application_data: cfg.application_data
	});
}

/**
 * ubus handler: starts a container and clears its manually-stopped flag.
 *
 * @param {object} req - ubus request object (args.name required)
 */
function start_handler(req) {
	let name = req.args?.name;
	if (!name) {
		req.reply({ error: 'name required' }, 4);
		return;
	}

	manually_stopped_clear(name);
	backend.start(name);
	log_info('started container %s', name);
	req.reply({});
}

/**
 * ubus handler: stops a container and sets its manually-stopped flag so the
 * monitor will not try to autorestart it.
 *
 * @param {object} req - ubus request object (args.name required)
 */
function stop_handler(req) {
	let name = req.args?.name;
	if (!name) {
		req.reply({ error: 'name required' }, 4);
		return;
	}

	manually_stopped_set(name);
	backend.stop(name);
	log_info('stopped container %s', name);
	req.reply({});
}

/**
 * ubus handler: restarts a container by stopping then starting it.
 *
 * @param {object} req - ubus request object (args.name required)
 */
function restart_handler(req) {
	let name = req.args?.name;
	if (!name) {
		req.reply({ error: 'name required' }, 4);
		return;
	}

	backend.stop(name);
	backend.start(name);
	log_info('restarted container %s', name);
	req.reply({});
}

/**
 * ubus handler: restarts the autorestart monitor so it picks up updated globals.
 *
 * @param {object} req - ubus request object
 */
function reload_handler(req) {
	monitor_stop();
	let globals = globals_read();
	monitor_start(backend, globals.monitor_interval * 1000);
	log_info('reloaded configuration');
	req.reply({});
}

/**
 * Polls the backend until the container reports a non-running state or the
 * deadline is reached, then invokes the callback unconditionally.
 *
 * @param {string} name - Container name
 * @param {number} max_wait - Maximum time to wait in milliseconds
 * @param {function} callback - Invoked once the container has stopped or the deadline expires
 */
function container_wait_stopped(name, max_wait, callback) {
	let elapsed = 0;
	let poll_interval = 500;

	function check() {
		let st = backend.state(name);
		if (!st?.status || st.status != 'running') {
			callback();
			return;
		}
		elapsed += poll_interval;
		if (elapsed >= max_wait) {
			log_err('container_wait_stopped: %s did not stop within %dms', name, max_wait);
			callback();
			return;
		}
		uloop.timer(poll_interval, check);
	}

	check();
}

/**
 * ubus handler: installs a container from an apk://, file:// or http(s):// URL,
 * verifies the bundle, registers it with the selected backend and persists its
 * configuration. Replies asynchronously via req.defer().
 *
 * @param {object} req - ubus request object (args.url required, plus optional bundle metadata)
 */
function install_handler(req) {
	let url = req.args?.url;
	if (!url) {
		req.reply({ error: 'URL required', error_code: 7004 });
		return;
	}

	let ee_result = execenv_validate(req.args?.exec_env_ref);
	if (!ee_result.valid) {
		req.reply({ error: ee_result.error, error_code: 7012 });
		return;
	}

	let is_apk = match(url, /^apk:\/\//);
	let is_file = match(url, /^file:\/\//);
	let is_http = match(url, /^https?:\/\//);

	if (!is_apk && !is_file && !is_http) {
		req.reply({ error: 'Unsupported URL scheme', error_code: 7004 });
		return;
	}

	req.defer();

	let install_fail = (err_msg) => {
		req.reply({ error: err_msg, error_code: 7012 });
	};

	function register_container(name, bundle_path) {
		let uuid = req.args?.uuid ?? uuid_generate(name, req.args?.vendor);
		let inst = instance_allocate();

		let cfg = {
			name,
			runtime: 'uxc',
			uuid,
			vendor: req.args?.vendor ?? '',
			version: req.args?.version ?? '',
			url,
			exec_env_ref: ee_result.ref,
			instance: inst,
			bundle: bundle_path,
			autostart: false,
			privileged: req.args?.privileged != false,
			installed: ubbf.iso8601_format(time()),
			last_update: ubbf.iso8601_format(time()),
			memory_kib: req.args?.memory_kib ?? -1,
			cpu_percent: req.args?.cpu_percent ?? -1,
			disk_space_kib: req.args?.disk_space_kib ?? -1,
			autorestart: false,
			restart_min_wait: 5,
			restart_max_wait: 300,
			restart_multiplier: 2000,
			restart_max_retries: 0,
			restart_reset_period: 0,
			share_parent_network: req.args?.share_parent_network ?? false,
			port_forwards: req.args?.port_forwards ?? [],
			mounts: req.args?.host_objects ?? [],
			env_variables: req.args?.env_variables ?? [],
			application_data: req.args?.application_data ?? [],
			uid_mapping: null
		};

		if (!cfg.privileged)
			cfg.uid_mapping = uid_range_allocate();

		container_write(name, cfg);
		backend.apply_config(name, cfg);
		config_apply();

		req.reply({
			uuid,
			instance: inst,
			deployment_unit_ref: sprintf('Device.SoftwareModules.DeploymentUnit.%d', inst),
			execution_unit_ref_list: sprintf('Device.SoftwareModules.ExecutionUnit.%d', inst)
		});
	}

	if (is_apk) {
		let package_name = replace(url, /^apk:\/\//, '');
		let name = container_name_from_url(url);

		apk_update((update_result) => {
			if (!update_result.success) {
				install_fail(update_result.error);
				return;
			}
			apk_install(package_name, (result) => {
				if (!result.success) {
					install_fail(result.error);
					return;
				}
				register_container(name, bundle_path_for(name));
			});
		});
		return;
	}

	if (is_file) {
		let path = replace(url, /^file:\/\//, '');

		if (match(path, /\.apk$/)) {
			let name = container_name_from_url(path);
			apk_install_local(path, (result) => {
				if (!result.success) {
					install_fail(result.error);
					return;
				}
				register_container(name, bundle_path_for(name));
			});
			return;
		}

		if (!fs.stat(sprintf('%s/config.json', path))) {
			install_fail(sprintf('Bundle not found or missing config.json: %s', path));
			return;
		}

		let name = fs.basename(path);
		register_container(name, path);
		return;
	}

	if (match(url, /\.apk(\?.*)?$/)) {
		let name = container_name_from_url(url);
		apk_download_and_install(url, {
			username: req.args?.username,
			password: req.args?.password
		}, (result) => {
			if (!result.success) {
				install_fail(result.error);
				return;
			}
			register_container(name, bundle_path_for(name));
		});
		return;
	}

	let url_parts = match(url, /\/([^\/]+?)(\.tar\.gz|\.tgz)?$/);
	let name = url_parts ? url_parts[1] : sprintf('du-%d', time());
	let bundle_path = bundle_path_for(name);

	bundle_download(url, bundle_path, {
		username: req.args?.username,
		password: req.args?.password,
		keep_archive: !!req.args?.signature
	}, (result) => {
		if (!result.success) {
			install_fail(result.error);
			return;
		}
		if (!bundle_validate(bundle_path)) {
			fs.unlink(TMP_ARCHIVE);
			install_fail('Downloaded bundle is invalid (missing config.json)');
			return;
		}

		let keyring = signers_keyring_get(ee_result.ref);
		let sig_url = req.args?.signature;

		if (keyring && !sig_url) {
			fs.unlink(TMP_ARCHIVE);
			req.reply({ error: 'ExecEnv requires signed bundles but no Signature URL provided', error_code: 7226 });
			return;
		}

		if (sig_url && keyring) {
			signature_verify(TMP_ARCHIVE, sig_url, keyring, (sig_result) => {
				fs.unlink(TMP_ARCHIVE);
				if (!sig_result.success) {
					req.reply({ error: sig_result.error, error_code: 7226 });
					return;
				}
				register_container(name, bundle_path);
			});
			return;
		}

		register_container(name, bundle_path);
	});
}

/**
 * ubus handler: replaces the bundle of an installed container from a new URL,
 * preserving its existing configuration. Restarts the container if it was
 * running before the update.
 *
 * @param {object} req - ubus request object (args.name and args.url required)
 */
function update_handler(req) {
	let name = req.args?.name;
	let url = req.args?.url;
	if (!name || !url) {
		req.reply({ error: 'name and url required', error_code: 7004 });
		return;
	}

	let cfg = container_read(name);
	if (!cfg) {
		req.reply({ error: 'Container not found', error_code: 7012 });
		return;
	}

	let st = backend.state(name);
	let was_running = st?.status == 'running';
	backend.stop(name);

	req.defer();

	let update_fail = (err_msg) => {
		req.reply({ error: err_msg, error_code: 7012 });
	};

	function finish_update() {
		cfg.version = req.args?.version ?? cfg.version;
		cfg.url = url;
		cfg.last_update = ubbf.iso8601_format(time());
		container_write(name, cfg);
		backend.apply_config(name, cfg);

		if (was_running)
			backend.start(name);

		config_apply();
		req.reply({ uuid: cfg.uuid, version: cfg.version });
	}

	let is_apk_url = match(url, /^apk:\/\//) || match(url, /\.apk(\?.*)?$/);
	let is_file = match(url, /^file:\/\//);
	let is_http = match(url, /^https?:\/\//);

	if (is_apk_url && is_apk_installed(name)) {
		let package_name = sprintf('container-%s', name);
		popen_async(sprintf('apk upgrade --no-interactive %s 2>&1', package_name), (result) => {
			if (result.error || result.exitcode != 0) {
				update_fail(result.error ?? result.data ?? 'apk upgrade failed');
				return;
			}
			uvol_up(name, (vol_result) => {
				if (!vol_result.success) {
					update_fail(vol_result.error);
					return;
				}
				finish_update();
			});
		});
		return;
	}

	if (is_file) {
		let path = replace(url, /^file:\/\//, '');
		if (match(path, /\.apk$/)) {
			apk_install_local(path, (result) => {
				if (!result.success) {
					update_fail(result.error);
					return;
				}
				uvol_up(name, (vol_result) => {
					if (!vol_result.success) {
						update_fail(vol_result.error);
						return;
					}
					finish_update();
				});
			});
			return;
		}
		if (!fs.stat(sprintf('%s/config.json', path))) {
			update_fail(sprintf('Bundle not found: %s', path));
			return;
		}
		cfg.bundle = path;
		finish_update();
		return;
	}

	if (is_http && match(url, /\.apk(\?.*)?$/)) {
		apk_download_and_install(url, {
			username: req.args?.username,
			password: req.args?.password
		}, (result) => {
			if (!result.success) {
				update_fail(result.error);
				return;
			}
			uvol_up(name, (vol_result) => {
				if (!vol_result.success) {
					update_fail(vol_result.error);
					return;
				}
				finish_update();
			});
		});
		return;
	}

	let bundle_path = cfg.bundle ?? bundle_path_for(name);
	bundle_download(url, bundle_path, {
		username: req.args?.username,
		password: req.args?.password,
		keep_archive: !!req.args?.signature
	}, (result) => {
		if (!result.success) {
			update_fail(result.error);
			return;
		}
		if (!bundle_validate(bundle_path)) {
			fs.unlink(TMP_ARCHIVE);
			update_fail('Downloaded bundle is invalid');
			return;
		}
		let keyring = signers_keyring_get(cfg.exec_env_ref);
		let sig_url = req.args?.signature;
		if (keyring && !sig_url) {
			fs.unlink(TMP_ARCHIVE);
			req.reply({ error: 'ExecEnv requires signed bundles', error_code: 7226 });
			return;
		}
		if (sig_url && keyring) {
			signature_verify(TMP_ARCHIVE, sig_url, keyring, (sig_result) => {
				fs.unlink(TMP_ARCHIVE);
				if (!sig_result.success) {
					req.reply({ error: sig_result.error, error_code: 7226 });
					return;
				}
				cfg.bundle = bundle_path;
				finish_update();
			});
			return;
		}
		cfg.bundle = bundle_path;
		finish_update();
	});
}

export function rmdir_recursive(path) {
	let entries = fs.lsdir(path);
	if (!entries)
		return;

	for (let entry in entries) {
		let full = path + '/' + entry;
		let st = fs.stat(full);

		if (!st)
			continue;

		if (st.type == 'directory')
			rmdir_recursive(full);
		else
			fs.unlink(full);
	}

	fs.rmdir(path);
};

/**
 * ubus handler: stops and removes a container, optionally retaining
 * application data marked Retain=forever, and unregisters it from the backend.
 *
 * @param {object} req - ubus request object (args.name required, args.retain_data optional)
 */
function uninstall_handler(req) {
	let name = req.args?.name;
	if (!name) {
		req.reply({ error: 'name required', error_code: 7004 });
		return;
	}

	let cfg = container_read(name);
	if (!cfg) {
		req.reply({ error: 'Container not found', error_code: 7012 });
		return;
	}

	backend.stop(name);

	req.defer();

	let retain_data = req.args?.retain_data;
	for (let ad in (cfg.application_data ?? [])) {
		if (retain_data && ad.Retain == 'forever')
			continue;
		let vol_path = sprintf('/opt/container-data/%s/%s', name, ad.Name);
		rmdir_recursive(vol_path);
	}

	let data_dir = sprintf('/opt/container-data/%s', name);
	let remaining = fs.lsdir(data_dir);
	if (!remaining || !length(remaining))
		fs.rmdir(data_dir);

	container_wait_stopped(name, 10000, () => {
		if (is_apk_installed(name)) {
			apk_uninstall(sprintf('container-%s', name), (result) => {
				if (!result.success)
					log_err('uninstall: apk del failed for %s: %s', name, result.error);
				backend.unregister(name);
				container_remove(name);
				runtime_state_remove(name);
				config_apply();
				req.reply({ uuid: cfg.uuid });
			});
			return;
		}

		backend.unregister(name);
		container_remove(name);
		runtime_state_remove(name);
		config_apply();
		req.reply({ uuid: cfg.uuid });
	});
}

/**
 * Starts the daemon: selects backend, publishes ubus, starts monitor.
 */
export function daemon_start() {
	backend = backend_select();
	if (!backend) {
		log_err('no container runtime available');
		return;
	}

	log_info('using runtime backend: %s', globals_read().default_runtime);

	ubus.publish('ubbf-container', {
		list: {
			call: list_handler,
			args: {}
		},
		info: {
			call: info_handler,
			args: { name: '' }
		},
		start: {
			call: start_handler,
			args: { name: '' }
		},
		stop: {
			call: stop_handler,
			args: { name: '' }
		},
		restart: {
			call: restart_handler,
			args: { name: '' }
		},
		reload: {
			call: reload_handler,
			args: {}
		},
		install: {
			call: install_handler,
			args: {
				url: '', uuid: '', vendor: '', version: '',
				exec_env_ref: '', username: '', password: '',
				privileged: true, signature: '',
				memory_kib: -1, cpu_percent: -1, disk_space_kib: -1,
				share_parent_network: false,
				host_objects: [], env_variables: [],
				application_data: [], port_forwards: []
			}
		},
		update: {
			call: update_handler,
			args: { name: '', url: '', version: '', username: '', password: '', signature: '' }
		},
		uninstall: {
			call: uninstall_handler,
			args: { name: '', retain_data: false }
		}
	});

	let globals = globals_read();
	monitor_start(backend, globals.monitor_interval * 1000);

	log_info('daemon started');
};
