// Host test of the write gate. Run from the repository root; the search path
// has to be absolute:
//   ucode -L "$PWD/files/usr/share/ucode" tests/write-gate.uc
'use strict';

import { write_gate_create, write_reply } from 'ubbf.utils.write-gate';

let pass_count = 0;
let fail_count = 0;

function assert_eq(name, got, expected) {
	let got_json = sprintf('%J', got);
	let exp_json = sprintf('%J', expected);

	if (got_json == exp_json) {
		pass_count++;
		return;
	}

	fail_count++;
	printf('FAIL: %s\n  expected: %s\n  got:      %s\n', name, exp_json, got_json);
}

function fixture() {
	let t = { busy: false, scheduled: [], errors: [], log: [] };

	t.gate = write_gate_create(() => t.busy,
		(fn) => push(t.scheduled, fn),
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

function test_free_gate_runs_at_once() {
	let t = fixture();
	let done = [];

	let result = t.gate.write(t.job('a'), (r) => push(done, r));

	assert_eq('free: result returned', result, { success: true, name: 'a' });
	assert_eq('free: job ran', t.log, [ 'a' ]);
	assert_eq('free: done not called', done, []);
	assert_eq('free: nothing scheduled', length(t.scheduled), 0);
}

function test_busy_gate_queues_until_release() {
	let t = fixture();
	let done = [];

	t.busy = true;
	let result = t.gate.write(t.job('a'), (r) => push(done, r));

	assert_eq('busy: queued', result, null);
	assert_eq('busy: job not run', t.log, []);
	assert_eq('busy: nothing scheduled while held', length(t.scheduled), 0);

	t.busy = false;
	t.gate.release();
	assert_eq('busy: drain scheduled on release', length(t.scheduled), 1);
	assert_eq('busy: job waits for the schedule', t.log, []);

	t.run_scheduled();
	assert_eq('busy: job ran after release', t.log, [ 'a' ]);
	assert_eq('busy: done got the result', done, [ { success: true, name: 'a' } ]);
}

function test_queue_runs_in_order() {
	let t = fixture();
	let done = [];

	t.busy = true;
	t.gate.write(t.job('a'), (r) => push(done, r.name));
	t.gate.write(t.job('b'), (r) => push(done, r.name));

	t.busy = false;
	t.gate.release();

	// A write that arrives before the drain must not overtake the queue.
	let result = t.gate.write(t.job('c'), (r) => push(done, r.name));
	assert_eq('order: late write queued behind earlier ones', result, null);

	t.run_scheduled();
	assert_eq('order: jobs ran in arrival order', t.log, [ 'a', 'b', 'c' ]);
	assert_eq('order: done in arrival order', done, [ 'a', 'b', 'c' ]);
	assert_eq('order: queue empty', length(t.gate.queue), 0);
}

function test_release_after_abort_and_commit() {
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

	assert_eq('release: both transactions drained', done, [ 'a', 'b' ]);
}

function test_drain_stops_when_held_again() {
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

	assert_eq('held: drain stopped after the job took the gate', t.log, [ 'a' ]);
	assert_eq('held: second write still queued', length(t.gate.queue), 1);

	t.busy = false;
	t.gate.release();
	t.run_scheduled();
	assert_eq('held: second write ran after the next release', t.log, [ 'a', 'b' ]);
}

function test_failing_write_does_not_block_others() {
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

	assert_eq('fail: later jobs ran', t.log, [ 'b', 'c', 'd' ]);
	assert_eq('fail: failed job reported as failure', done[0],
		{ success: false, error: 'Write failed' });
	assert_eq('fail: other results delivered', [ done[1].name, done[2].name ], [ 'b', 'd' ]);
	assert_eq('fail: both exceptions reported', t.errors,
		[ 'queued write', 'queued write reply' ]);
	assert_eq('fail: queue empty', length(t.gate.queue), 0);
}

function test_write_inside_queued_write_runs_at_once() {
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

	assert_eq('nested: inner write ran inside its parent',
		inner, { success: true, name: 'inner' });
	assert_eq('nested: order kept', t.log, [ 'a', 'inner', 'c' ]);
}

function test_write_queued_by_a_done_callback_runs() {
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

	assert_eq('done-queued: write from a done callback ran', t.log, [ 'a', 'b' ]);
	assert_eq('done-queued: its done ran', done, [ 'b' ]);
}

function test_release_without_queue_schedules_nothing() {
	let t = fixture();

	t.gate.release();
	assert_eq('idle release: nothing scheduled', length(t.scheduled), 0);
}

function fake_request() {
	return {
		deferred: false,
		replies: [],
		defer: function() { this.deferred = true; },
		reply: function(data) { push(this.replies, data); }
	};
}

function test_write_reply_free_gate() {
	let t = fixture();
	let req = fake_request();

	let reply = write_reply(req, (done) => t.gate.write(t.job('a'), done),
		(r) => ({ shaped: r.name }));

	assert_eq('reply free: shaped reply returned', reply, { shaped: 'a' });
	assert_eq('reply free: not deferred', req.deferred, false);
	assert_eq('reply free: no late reply', req.replies, []);
}

function test_write_reply_busy_gate() {
	let t = fixture();
	let req = fake_request();

	t.busy = true;
	let reply = write_reply(req, (done) => t.gate.write(t.job('a'), done),
		(r) => ({ shaped: r.name }));

	assert_eq('reply busy: request returned', reply == req, true);
	assert_eq('reply busy: deferred', req.deferred, true);
	assert_eq('reply busy: no reply yet', req.replies, []);

	t.busy = false;
	t.gate.release();
	t.run_scheduled();
	assert_eq('reply busy: shaped reply after the write', req.replies, [ { shaped: 'a' } ]);
}

test_free_gate_runs_at_once();
test_busy_gate_queues_until_release();
test_queue_runs_in_order();
test_release_after_abort_and_commit();
test_drain_stops_when_held_again();
test_failing_write_does_not_block_others();
test_write_inside_queued_write_runs_at_once();
test_write_queued_by_a_done_callback_runs();
test_release_without_queue_schedules_nothing();
test_write_reply_free_gate();
test_write_reply_busy_gate();

printf('%d passed, %d failed\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
