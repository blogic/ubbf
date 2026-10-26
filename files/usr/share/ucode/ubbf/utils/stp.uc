'use strict';

import * as ubbf from 'ubbf';
import { Bridge_STP } from 'ubbf.schemas.Bridging';

const STP_TIMER_UNITS = {
	HelloTime: 100,
	MaxAge: 100,
	ForwardingDelay: 1
};

/**
 * Converts one stored STP timer to whole seconds.
 *
 * A missing or empty timer takes the TR-181 default of Bridge_STP. A stored
 * value that is not an integer also takes the default and is invalid.
 *
 * @param {object|null} stp - Stored Device.Bridging.Bridge.{i}.STP object
 * @param {string} key - HelloTime, MaxAge or ForwardingDelay
 * @returns {object} { seconds, valid }
 */
function stp_timer_seconds(stp, key) {
	let stored = stp?.[key];
	let value = ubbf.to_int(stored);
	let valid = true;

	if (value == null) {
		valid = (stored == null || stored == '');
		value = ubbf.to_int(Bridge_STP.defaults[key]);
	}

	return { seconds: value / STP_TIMER_UNITS[key], valid };
}

/**
 * Gives the STP timers of a bridge in the whole seconds netifd and ustp use.
 *
 * The timers are invalid where a stored timer is not an integer, or where
 * they break 2 * (forward_delay - 1) >= max_age, the relation that ustp
 * MSTP_IN_set_cist_bridge_config() checks on the same seconds before it
 * applies any of them.
 *
 * @param {object|null} stp - Stored Device.Bridging.Bridge.{i}.STP object
 * @returns {object} { hello_time, max_age, forward_delay, valid }
 */
export function stp_timers_get(stp) {
	let hello = stp_timer_seconds(stp, 'HelloTime');
	let max_age = stp_timer_seconds(stp, 'MaxAge');
	let forward_delay = stp_timer_seconds(stp, 'ForwardingDelay');

	return {
		hello_time: hello.seconds,
		max_age: max_age.seconds,
		forward_delay: forward_delay.seconds,
		valid: hello.valid && max_age.valid && forward_delay.valid &&
		       2 * (forward_delay.seconds - 1) >= max_age.seconds
	};
};
