// Host test of the inactive-host cleanup in utils/hosts.uc
// (CleanupHostsThreshold, RemoveInactiveHosts()). Run from the repository
// root with the native module built for the host. The test writes
// /tmp/ubbf/hosts-state.json, so run it with a private /tmp; tests/hosts/
// holds stand-ins for the iwinfo and udebug modules:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && ucode \
//     -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode/*.uc" \
//     -L "<host build>/*.so" tests/hosts.uc'
// The host build must not be below /tmp.
'use strict';

import * as fs from 'fs';
import { hosts_state_get, hosts_downstream_get, hosts_inactive_remove, hosts_numbered, host_by_instance } from 'ubbf.utils.hosts';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

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

let state = hosts_state_get();
state_fill(state);

let all = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: '-1' } } });
let present = length(all) - length(away_macs(all));
check('threshold -1 keeps every away host', length(away_macs(all)), 5);

let kept = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: sprintf('%d', present + 2) } } });
check('threshold keeps the two hosts that left last', away_macs(kept), [ '02:00:00:00:00:04', '02:00:00:00:00:05' ]);
check('trimmed hosts leave the state', sort(keys(state.entries)), [ '02:00:00:00:00:04', '02:00:00:00:00:05' ]);

state_fill(state);
let none = hosts_downstream_get({ Device: { Hosts: { CleanupHostsThreshold: '0' } } });
check('threshold 0 removes every away host', away_macs(none), []);

state_fill(state);
check('no threshold parameter keeps every away host', length(away_macs(hosts_downstream_get({}))), 5);

state_fill(state);
check('MinimumInactiveTime 250 removes hosts inactive longer', hosts_inactive_remove({}, 250), 3);
check('remaining after MinimumInactiveTime 250', sort(keys(state.entries)), [ '02:00:00:00:00:04', '02:00:00:00:00:05' ]);

state_fill(state);
check('MinimumInactiveTime 300 is exclusive', hosts_inactive_remove({}, 300), 2);

state_fill(state);
check('no MinimumInactiveTime removes all inactive hosts', hosts_inactive_remove({}, null), 5);
check('state file written', json(fs.readfile('/tmp/ubbf/hosts-state.json')), { entries: {} });

// A host keeps its instance number when another one leaves (TR-369 R-ARC.8)
state_fill(state);
let numbered = hosts_numbered({});
let away_numbers = {};
for (let n, h in numbered)
	if (substr(h.mac, 0, 3) == '02:')
		away_numbers[h.mac] = n;
delete state.entries['02:00:00:00:00:02'];
let renumbered = {};
for (let n, h in hosts_numbered({}))
	if (substr(h.mac, 0, 3) == '02:')
		renumbered[h.mac] = n;
delete away_numbers['02:00:00:00:00:02'];
check('hosts keep their numbers when one leaves', renumbered, away_numbers);
check('host by its number', host_by_instance({}, away_numbers['02:00:00:00:00:04'])?.mac, '02:00:00:00:00:04');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
