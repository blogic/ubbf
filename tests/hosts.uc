// Host test of the inactive-host cleanup in utils/hosts.uc
// (CleanupHostsThreshold, RemoveInactiveHosts()), the numbering of the
// hosts and the cache of hosts_build(). netifd answers no interface.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import * as fs from 'fs';
import { state_clear } from 'test_env';
import { hosts_build, hosts_state_get, hosts_downstream_get, hosts_inactive_remove, hosts_numbered, host_by_instance } from 'ubbf.utils.hosts';
import { instance_map_own } from 'ubbf';

// This process numbers rows, as the agent does.
instance_map_own(true);

function away_entry(now, left_ago) {
	return { active: false, last_change: 'x', changed: now - left_ago, seen: now - left_ago, host: { hostname: 'h' } };
}

function state_fill(state) {
	let now = state.now;
	state.entries = {
		'02:00:00:00:00:01': away_entry(now, 500),
		'02:00:00:00:00:02': away_entry(now, 400),
		'02:00:00:00:00:03': away_entry(now, 300),
		'02:00:00:00:00:04': away_entry(now, 200),
		'02:00:00:00:00:05': { active: true, last_change: 'x', changed: now - 9000, seen: now - 100, host: { hostname: 'h' } }
	};
}

function away_macs(hosts) {
	return sort(map(filter(hosts, (h) => substr(h.mac, 0, 3) == '02:'), (h) => h.mac));
}

function away_numbers(numbered) {
	let out = {};
	for (let n, h in numbered)
		if (substr(h.mac, 0, 3) == '02:')
			out[h.mac] = n;
	return out;
}

beforeEach(() => {
	state_clear();
	mock.global.patch('ubus', { data: {} });
});

describe('Hosts CleanupHostsThreshold', () => {
	it('keeps the away hosts that left last up to the threshold', () => {
		let state = hosts_state_get();
		state_fill(state);

		let all = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: '-1' } } });
		let present = length(all) - length(away_macs(all));
		assert.match(5, length(away_macs(all)), 'threshold -1 keeps every away host');

		let kept = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: sprintf('%d', present + 2) } } });
		assert.match([ '02:00:00:00:00:04', '02:00:00:00:00:05' ], away_macs(kept));
		assert.match([ '02:00:00:00:00:04', '02:00:00:00:00:05' ], sort(keys(state.entries)), 'trimmed hosts leave the state');

		state_fill(state);
		let none = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: '0' } } });
		assert.match([], away_macs(none), 'threshold 0 removes every away host');

		state_fill(state);
		assert.match(5, length(away_macs(hosts_downstream_get({}))), 'no threshold parameter keeps every away host');
	});
});

describe('Hosts RemoveInactiveHosts()', () => {
	it('removes the hosts inactive longer than MinimumInactiveTime', () => {
		let state = hosts_state_get();
		state_fill(state);
		assert.match(3, hosts_inactive_remove({}, 250));
		assert.match([ '02:00:00:00:00:04', '02:00:00:00:00:05' ], sort(keys(state.entries)));
	});

	it('does not remove a host inactive for exactly MinimumInactiveTime', () => {
		state_fill(hosts_state_get());
		assert.match(2, hosts_inactive_remove({}, 300));
	});

	it('removes all inactive hosts without MinimumInactiveTime and writes the state', () => {
		state_fill(hosts_state_get());
		assert.match(5, hosts_inactive_remove({}, null));
		assert.match({ entries: {} }, json(fs.readfile('/tmp/ubbf/hosts-state.json')));
	});
});

describe('Hosts numbering', () => {
	// TR-369 R-ARC.8
	it('keeps the numbers of the other hosts when one leaves', () => {
		let state = hosts_state_get();
		state_fill(state);
		let before = away_numbers(hosts_numbered({}));

		delete state.entries['02:00:00:00:00:02'];
		let after = away_numbers(hosts_numbered({}));
		delete before['02:00:00:00:00:02'];

		assert.match(before, after);
		assert.match('02:00:00:00:00:04', host_by_instance({}, before['02:00:00:00:00:04'])?.mac);
	});
});

describe('Hosts inventory', () => {
	it('caches the scan of the system, not the root of the first caller', () => {
		let root_a = { Device: {} }, root_b = { Device: {} };
		let built_a = hosts_build(root_a);
		assert.match(true, hosts_build(root_b).config === root_b);
		assert.match(true, hosts_build(root_a).config === root_a);
		assert.match(true, hosts_build(root_a) === hosts_build(root_a));
		assert.match(true, hosts_build(root_b).hosts === built_a.hosts);
	});
});
