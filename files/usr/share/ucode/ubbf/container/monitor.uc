'use strict';

import * as uloop from 'uloop';
import { log_info, log_err } from 'ubbf.utils.logging';
import { containers_read } from 'ubbf.container.uci';
import {
	restart_timer_get, restart_timer_set, restart_timer_clear,
	is_manually_stopped,
	runtime_state_read, runtime_state_write
} from 'ubbf.container.state';

let backend;
let monitor_timer;

/**
 * Calculates restart delay with exponential backoff.
 *
 * @param {object} cfg - Container UCI config with autorestart fields
 * @param {number} retry_count - Current retry count
 * @returns {number} Delay in milliseconds
 */
function restart_delay_calculate(cfg, retry_count) {
	let base = (cfg.restart_min_wait ?? 5) * 1000;
	let multiplier = (cfg.restart_multiplier ?? 2000) / 1000;
	let max_wait = (cfg.restart_max_wait ?? 300) * 1000;

	let delay = base * (multiplier ** retry_count);
	if (delay > max_wait)
		delay = max_wait;

	return int(delay);
}

/**
 * Performs one autorestart attempt: clears the pending timer, re-reads the
 * container config to pick up live changes, enforces the retry-count cap, then
 * starts the container and updates its persisted runtime state.
 *
 * @param {string} name - Container name
 */
function restart_attempt(name) {
	restart_timer_clear(name);

	let containers = containers_read();
	let cfg = containers[name];
	if (!cfg?.autorestart)
		return;

	let rs = runtime_state_read(name);

	if (cfg.restart_max_retries > 0 && rs.retry_count >= cfg.restart_max_retries) {
		log_info('autorestart: %s reached max retry count %d', name, cfg.restart_max_retries);
		return;
	}

	log_info('autorestart: restarting %s (attempt %d)', name, rs.retry_count + 1);
	backend.start(name);

	rs.retry_count = (rs.retry_count ?? 0) + 1;
	rs.last_restarted = time();
	rs.running_since = time();
	runtime_state_write(name, rs);
}

/**
 * Periodic monitor tick: for each autorestart-enabled container, resets the
 * retry counter after a stable run window, or schedules an exponential-backoff
 * restart attempt when the container is down and not manually stopped.
 */
function poll() {
	let containers = containers_read();

	for (let name, cfg in containers) {
		if (!cfg.autorestart)
			continue;

		if (is_manually_stopped(name))
			continue;

		if (restart_timer_get(name))
			continue;

		let st = backend.state(name);
		let is_running = st?.status == 'running';

		if (is_running) {
			let rs = runtime_state_read(name);
			if (cfg.restart_reset_period > 0 && rs.running_since) {
				let elapsed = time() - rs.running_since;
				if (elapsed >= cfg.restart_reset_period && rs.retry_count > 0) {
					rs.retry_count = 0;
					runtime_state_write(name, rs);
				}
			}
			continue;
		}

		let rs = runtime_state_read(name);
		let delay = restart_delay_calculate(cfg, rs.retry_count);
		log_info('autorestart: scheduling restart of %s in %dms', name, delay);

		restart_timer_set(name, uloop.timer(delay, () => {
			restart_attempt(name);
		}));
	}
}

/**
 * Starts the auto-restart monitor.
 *
 * @param {object} rt_backend - Runtime backend module (must have state/start)
 * @param {number} interval_ms - Poll interval in milliseconds
 */
export function monitor_start(rt_backend, interval_ms) {
	backend = rt_backend;
	monitor_timer = uloop.interval(interval_ms, poll);
	log_info('monitor: started with %dms interval', interval_ms);
};

/**
 * Stops the auto-restart monitor.
 */
export function monitor_stop() {
	if (monitor_timer) {
		monitor_timer.cancel();
		monitor_timer = null;
	}
};
