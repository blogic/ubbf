'use strict';

const write_gate = {
	/**
	 * Runs a write now, or queues it while the gate is busy.
	 *
	 * A write also queues while earlier writes wait, so writes run in the
	 * order they arrive. A write made by a queued write that runs is part
	 * of it and runs at once.
	 *
	 * @param {function} job - Does the write, returns its result object
	 * @param {function} done - Called with the result of a queued write
	 * @returns {object|null} The result, or null when the write is queued
	 */
	write: function(job, done) {
		if (this.draining || (!this.busy() && !length(this.queue)))
			return job();

		push(this.queue, { job, done });
		this.release();
		return null;
	},

	/**
	 * Tells the gate that the writer which held it is done, so the queued
	 * writes run once the current event returns.
	 */
	release: function() {
		if (this.scheduled || this.busy() || !length(this.queue))
			return;

		let self = this;
		this.scheduled = true;
		this.schedule(() => self.drain());
	},

	/**
	 * Runs the queued writes in order until the queue is empty or a writer
	 * holds the gate again.
	 */
	drain: function() {
		this.scheduled = false;

		while (length(this.queue) && !this.busy()) {
			let entry = shift(this.queue);
			let result;

			this.draining = true;
			try {
				result = entry.job();
			} catch (e) {
				this.on_error('queued write', e);
				result = { success: false, error: 'Write failed' };
			}
			this.draining = false;

			try {
				entry.done(result);
			} catch (e) {
				this.on_error('queued write reply', e);
			}
		}
	}
};

/**
 * Creates a gate that serialises writes against a writer that holds the
 * config across several events.
 *
 * @param {function} busy - Returns true while that writer holds the config
 * @param {function} schedule - Runs a function after the current event
 * @param {function} on_error - Called with a label and the exception when a
 *                              queued write or its reply throws
 * @returns {object} The gate
 */
export function write_gate_create(busy, schedule, on_error) {
	return proto({
		busy,
		schedule,
		on_error,
		queue: []
	}, write_gate);
};

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
