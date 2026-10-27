'use strict';

// The gate itself is ubbf.write_gate_create() in ubbf.so. This reply helper
// stays in ucode: it hands the gate a new closure over the request.

/**
 * Replies to a ubus request with the result of a write. When the write is
 * queued, the request is deferred and the reply goes out after the write.
 *
 * @param {object} req - The ubus request object
 * @param {function} write - Called with the `done` callback, returns the
 *                           result or null when the write is queued
 * @param {function} shape - Turns the result into the reply
 * @returns {object} The reply, or the deferred request
 */
export function write_reply(req, write, shape) {
	let result = write((queued) => req.reply(shape(queued)));
	if (result)
		return shape(result);

	req.defer();
	return req;
};
