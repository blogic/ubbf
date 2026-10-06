'use strict';

import * as uloop from 'uloop';

let cache = {};
let cache_timer;

/**
 * Clears the function result cache and resets the timer.
 */
function cache_clear() {
	cache = {};
	cache_timer = null;
}

/**
 * Calls a function with caching. Results are cached for 2 seconds.
 *
 * @param {function} fn - Function to call
 * @param {...*} args - Arguments to pass to the function
 * @returns {*} Cached or fresh result from fn(...args)
 */
export function call(fn, ...args) {
	let key = "" + fn + args;

	if (key in cache)
		return cache[key];

	if (!cache_timer)
		cache_timer = uloop.timer(2000, cache_clear);

	let result = fn(...args);
	cache[key] = result;
	return result;
};
