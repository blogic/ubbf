'use strict';

import * as uloop from 'uloop';

let cache = {};
let cache_fns = [];
let cache_timer;

/**
 * Clears the function result cache and resets the timer.
 */
function cache_clear() {
	cache = {};
	cache_fns = [];
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
	// A function converts to its signature only, "(x) => { ... }", so the
	// key uses its position in cache_fns, which compares references.
	let fn_idx = index(cache_fns, fn);
	if (fn_idx < 0) {
		push(cache_fns, fn);
		fn_idx = length(cache_fns) - 1;
	}

	let key = sprintf('%d%J', fn_idx, args);

	if (key in cache)
		return cache[key];

	if (!cache_timer)
		cache_timer = uloop.timer(2000, cache_clear);

	let result = fn(...args);
	cache[key] = result;
	return result;
};

/**
 * Drops the cached results of a function, for all arguments.
 *
 * A caller that changed the state behind fn calls this, so that the next
 * call() in the same 2 seconds reads the new state.
 *
 * @param {function} fn - Function whose results to drop
 */
export function invalidate(fn) {
	let fn_idx = index(cache_fns, fn);
	if (fn_idx < 0)
		return;

	let prefix = sprintf('%d[', fn_idx);
	for (let key in keys(cache))
		if (substr(key, 0, length(prefix)) == prefix)
			delete cache[key];
};
