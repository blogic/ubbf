// Host test of the write gate: write_gate_create() of ubbf.so queues the
// writes that arrive while a transaction holds the gate, and write_reply()
// of utils/write-gate.uc defers the ubus reply of a queued write.
'use strict';

import { describe, it, assert } from 'utest';
import { write_gate_create } from 'ubbf';
import { write_reply } from 'ubbf.utils.write-gate';

function fixture() {
	let t = { busy: false, scheduled: [], errors: [], log: [] };

	t.gate = write_gate_create(() => t.busy,
		(gate) => push(t.scheduled, () => gate.drain()),
		(what, e) => push(t.errors, what));

	t.job = (name) => () => {
		push(t.log, name);
		return { success: true, name };
	};

	t.run_scheduled = () => {
		while (length(t.scheduled))
			shift(t.scheduled)();
	};

	return t;
}

function fake_request() {
	return {
		deferred: false,
		replies: [],
		defer: function() { this.deferred = true; },
		reply: function(data) { push(this.replies, data); }
	};
}

describe('write gate', () => {
	it('runs a write at once on a free gate', () => {
		let t = fixture();
		let done = [];

		let result = t.gate.write(t.job('a'), (r) => push(done, r));

		assert.match({ success: true, name: 'a' }, result, 'free: result returned');
		assert.match([ 'a' ], t.log, 'free: job ran');
		assert.match([], done, 'free: done not called');
		assert.match(0, length(t.scheduled), 'free: nothing scheduled');
	});

	it('queues a write on a busy gate until the release', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		let result = t.gate.write(t.job('a'), (r) => push(done, r));

		assert.match(null, result, 'busy: queued');
		assert.match([], t.log, 'busy: job not run');
		assert.match(0, length(t.scheduled), 'busy: nothing scheduled while held');

		t.busy = false;
		t.gate.release();
		assert.match(1, length(t.scheduled), 'busy: drain scheduled on release');
		assert.match([], t.log, 'busy: job waits for the schedule');

		t.run_scheduled();
		assert.match([ 'a' ], t.log, 'busy: job ran after release');
		assert.match([ { success: true, name: 'a' } ], done, 'busy: done got the result');
	});

	it('runs the queue in arrival order', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		t.gate.write(t.job('a'), (r) => push(done, r.name));
		t.gate.write(t.job('b'), (r) => push(done, r.name));

		t.busy = false;
		t.gate.release();

		// A write that arrives before the drain must not overtake the queue.
		let result = t.gate.write(t.job('c'), (r) => push(done, r.name));
		assert.match(null, result, 'order: late write queued behind earlier ones');

		t.run_scheduled();
		assert.match([ 'a', 'b', 'c' ], t.log, 'order: jobs ran in arrival order');
		assert.match([ 'a', 'b', 'c' ], done, 'order: done in arrival order');
		assert.match('d', t.gate.write(t.job('d'), () => null)?.name, 'order: queue empty');
	});

	it('drains after each release', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		t.gate.write(t.job('a'), (r) => push(done, r.name));
		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		t.busy = true;
		t.gate.write(t.job('b'), (r) => push(done, r.name));
		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		assert.match([ 'a', 'b' ], done, 'release: both transactions drained');
	});

	it('stops the drain when a job takes the gate again', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		t.gate.write(() => {
			push(t.log, 'a');
			t.busy = true;
			return { success: true, name: 'a' };
		}, (r) => push(done, r.name));
		t.gate.write(t.job('b'), (r) => push(done, r.name));

		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		assert.match([ 'a' ], t.log, 'held: drain stopped after the job took the gate');
		assert.match([ 'a' ], done, 'held: second write still queued');

		t.busy = false;
		t.gate.release();
		t.run_scheduled();
		assert.match([ 'a', 'b' ], t.log, 'held: second write ran after the next release');
	});

	it('does not let a failing write block the others', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		t.gate.write(() => die('boom'), (r) => push(done, r));
		t.gate.write(t.job('b'), (r) => push(done, r));
		t.gate.write(t.job('c'), (r) => die('reply boom'));
		t.gate.write(t.job('d'), (r) => push(done, r));

		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		assert.match([ 'b', 'c', 'd' ], t.log, 'fail: later jobs ran');
		assert.match({ success: false, error: 'Write failed' }, done[0], 'fail: failed job reported as failure');
		assert.match([ 'b', 'd' ], [ done[1].name, done[2].name ], 'fail: other results delivered');
		assert.match([ 'queued write', 'queued write reply' ], t.errors, 'fail: both exceptions reported');
		assert.match('e', t.gate.write(t.job('e'), () => null)?.name, 'fail: queue empty');
	});

	it('runs a write inside a queued write at once', () => {
		let t = fixture();
		let inner;

		t.busy = true;
		t.gate.write(t.job('a'), () => null);
		t.gate.write(() => {
			inner = t.gate.write(t.job('inner'), () => null);
			return { success: true };
		}, () => null);
		t.gate.write(t.job('c'), () => null);

		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		assert.match({ success: true, name: 'inner' }, inner, 'nested: inner write ran inside its parent');
		assert.match([ 'a', 'inner', 'c' ], t.log, 'nested: order kept');
	});

	it('runs a write that a done callback queues', () => {
		let t = fixture();
		let done = [];

		t.busy = true;
		t.gate.write(t.job('a'), () => {
			t.busy = true;
			t.gate.write(t.job('b'), (r) => push(done, r.name));
			t.busy = false;
			t.gate.release();
		});

		t.busy = false;
		t.gate.release();
		t.run_scheduled();

		assert.match([ 'a', 'b' ], t.log, 'done-queued: write from a done callback ran');
		assert.match([ 'b' ], done, 'done-queued: its done ran');
	});

	it('schedules nothing for a release without a queue', () => {
		let t = fixture();

		t.gate.release();
		assert.match(0, length(t.scheduled), 'idle release: nothing scheduled');
	});

	it('write_reply returns the shaped reply on a free gate', () => {
		let t = fixture();
		let req = fake_request();

		let reply = write_reply(req, (done) => t.gate.write(t.job('a'), done),
			(r) => ({ shaped: r.name }));

		assert.match({ shaped: 'a' }, reply, 'reply free: shaped reply returned');
		assert.match(false, req.deferred, 'reply free: not deferred');
		assert.match([], req.replies, 'reply free: no late reply');
	});

	it('write_reply defers the request on a busy gate', () => {
		let t = fixture();
		let req = fake_request();

		t.busy = true;
		let reply = write_reply(req, (done) => t.gate.write(t.job('a'), done),
			(r) => ({ shaped: r.name }));

		assert.match(true, reply == req, 'reply busy: request returned');
		assert.match(true, req.deferred, 'reply busy: deferred');
		assert.match([], req.replies, 'reply busy: no reply yet');

		t.busy = false;
		t.gate.release();
		t.run_scheduled();
		assert.match([ { shaped: 'a' } ], req.replies, 'reply busy: shaped reply after the write');
	});
});
