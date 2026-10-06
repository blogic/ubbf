// Host test of the TR-181 version gate. Run from the repository root; the
// search path has to be absolute:
//   ucode -L "$PWD/files/usr/share/ucode" tests/dm-version.uc
'use strict';

import { tag_minor, tag_visible, DM_VERSIONS } from 'ubbf.utils.dm-version';

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

assert_eq('tag_minor 2.20', tag_minor('2.20'), 20);
assert_eq('tag_minor 2.9', tag_minor('2.9'), 9);
assert_eq('tag_minor with patch', tag_minor('2.20.1'), null);
assert_eq('tag_minor other major', tag_minor('3.1'), null);
assert_eq('tag_minor number', tag_minor(2.2), null);
assert_eq('tag_minor null', tag_minor(null), null);

// Each supported version against the DeviceInfo PoC tags.
const CASES = [
	[ 'untagged', null, null, [ true, true, true ] ],
	[ 'since 2.20', '2.20', null, [ false, true, true ] ],
	[ 'since 2.21', '2.21', null, [ false, false, true ] ],
	[ 'until 2.21', null, '2.21', [ true, true, false ] ],
	[ 'until 2.20', null, '2.20', [ true, false, false ] ],
	[ 'since 2.20 until 2.21', '2.20', '2.21', [ false, true, false ] ],
];

for (let c in CASES) {
	let got = map([ 19, 20, 21 ], (minor) => tag_visible(minor, c[1], c[2]));
	assert_eq(`tag_visible ${c[0]}`, got, c[3]);
}

assert_eq('malformed since is ignored', tag_visible(19, '2.21.0', null), true);
assert_eq('malformed until is ignored', tag_visible(21, null, 'x'), true);

assert_eq('supported versions', DM_VERSIONS, [ '2.19.1', '2.20.0', '2.20.1', '2.21.0' ]);

// The DeviceInfo members per version, as the core table of a build tree
// serves them. Set UBBF_BUILD_DIR to the CMake build directory of
// src/ucode-mod-ubbf and add it to the search path:
//   UBBF_BUILD_DIR=$B ucode -L "$PWD/files/usr/share/ucode" -L "$B/*.so" tests/dm-version.uc
function members_at(ubbf, minor, id) {
	ubbf.schema_version_set(minor);

	let s = ubbf.schema_get(id);

	return { schema: sort(keys(s?.schema ?? {})), defaults: sort(keys(s?.defaults ?? {})) };
}

function has(list, name) {
	return index(list, name) >= 0;
}

function table_checks(build_dir) {
	let ubbf = require('ubbf');

	assert_eq('core table opens', ubbf.schema_tables_load(build_dir + '/schema-core.so'), [ 'core' ]);

	const MEMBERS = [
		[ 'DeviceInfo.DeviceInfo', 'ProcessorNumberOfEntries', [ true, true, false ] ],
		[ 'DeviceInfo.Reboots', 'CurrentBootCycle', [ false, true, true ] ],
		[ 'DeviceInfo.MemoryStatus', 'Available', [ false, false, true ] ],
		[ 'DeviceInfo.MemoryStatus', 'Total', [ true, true, true ] ],
		[ 'Hosts.Hosts', 'CleanupHostsThreshold', [ false, true, true ] ],
		[ 'IP.Interface', 'Description', [ false, false, true ] ],
		[ 'DHCPv4.Pool_Option', 'Force', [ false, false, true ] ],
		[ 'DHCPv4.Pool_StaticAddress', 'Status', [ false, false, true ] ],
		[ 'DHCPv6.Pool_Option', 'Force', [ false, false, true ] ],
		[ 'Bridging.Bridge_Port', 'STPPointToPointMode', [ false, false, true ] ],
		[ 'Bridging.Bridge_Port', 'STPAdminEdgePort', [ false, false, true ] ],
		[ 'Bridging.Bridge_Port', 'IGMP', [ false, false, true ] ],
		[ 'Bridging.Bridge_Port', 'MLD', [ false, false, true ] ],
		[ 'Routing.Router', 'ID', [ false, true, true ] ],
		[ 'Routing.Router_IPv6Forwarding', 'SourceIPPrefix', [ false, true, true ] ],
	];

	for (let m in MEMBERS) {
		let rows = map([ 19, 20, 21 ], (minor) => members_at(ubbf, minor, m[0]));

		assert_eq(`${m[0]}.${m[1]} member`, map(rows, (r) => has(r.schema, m[1])), m[2]);
		assert_eq(`${m[0]}.${m[1]} default`, map(rows, (r) => has(r.defaults, m[1])), m[2]);
	}

	const COMMANDS = [
		[ 'DHCPv4.Client', 'Release()', [ false, true, true ] ],
		[ 'DHCPv4.Client', 'Renew()', [ true, true, true ] ],
		[ 'DHCPv6.Client', 'Release()', [ false, true, true ] ],
		[ 'Device.Device', 'Shutdown()', [ false, false, true ] ],
	];

	for (let c in COMMANDS) {
		let rows = map([ 19, 20, 21 ], (minor) => members_at(ubbf, minor, c[0]));

		assert_eq(`${c[0]}.${c[1]} member`, map(rows, (r) => has(r.schema, c[1])), c[2]);
	}
}

let build_dir = getenv('UBBF_BUILD_DIR');

if (build_dir)
	table_checks(build_dir);
else
	printf('UBBF_BUILD_DIR not set: schema table checks skipped\n');

printf('\n  passed: %d\n  failed: %d\n', pass_count, fail_count);
exit(fail_count ? 1 : 0);
