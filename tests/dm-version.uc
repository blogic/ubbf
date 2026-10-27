// Host test of the TR-181 version gate: the tag helpers of
// utils/dm-version.uc, and the DeviceInfo members per version as the core
// schema table of the host build in UBBF_BUILD_DIR serves them.
'use strict';

import { describe, it, skip, setup, assert } from 'utest';
import { tag_minor, tag_visible, DM_VERSIONS } from 'ubbf.utils.dm-version';

const build_dir = getenv('UBBF_BUILD_DIR');

// The tables of the build tree are optional: without UBBF_BUILD_DIR their
// tests are reported as skipped.
const table_it = build_dir ? it : skip;

// Each supported version against the DeviceInfo PoC tags.
const CASES = [
	[ 'untagged', null, null, [ true, true, true ] ],
	[ 'since 2.20', '2.20', null, [ false, true, true ] ],
	[ 'since 2.21', '2.21', null, [ false, false, true ] ],
	[ 'until 2.21', null, '2.21', [ true, true, false ] ],
	[ 'until 2.20', null, '2.20', [ true, false, false ] ],
	[ 'since 2.20 until 2.21', '2.20', '2.21', [ false, true, false ] ],
];

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

const COMMANDS = [
	[ 'DHCPv4.Client', 'Release()', [ false, true, true ] ],
	[ 'DHCPv4.Client', 'Renew()', [ true, true, true ] ],
	[ 'DHCPv6.Client', 'Release()', [ false, true, true ] ],
	[ 'Device.Device', 'Shutdown()', [ false, false, true ] ],
];

function members_at(ubbf, minor, id) {
	ubbf.schema_version_set(minor);

	let s = ubbf.schema_get(id);

	return { schema: sort(keys(s?.schema ?? {})), defaults: sort(keys(s?.defaults ?? {})) };
}

function has(list, name) {
	return index(list, name) >= 0;
}

let ubbf;
let core_loaded;

// A table loads once per process, so the load happens before the tests.
setup(() => {
	if (!build_dir)
		return;

	ubbf = require('ubbf');
	core_loaded = ubbf.schema_tables_load(build_dir + '/schema-core.so');
});

describe('dm-version tags', () => {
	it('reads the minor of a 2.x tag', () => {
		assert.match(20, tag_minor('2.20'));
		assert.match(9, tag_minor('2.9'));
		assert.match(null, tag_minor('2.20.1'), 'tag_minor with patch');
		assert.match(null, tag_minor('3.1'), 'tag_minor other major');
		assert.match(null, tag_minor(2.2), 'tag_minor number');
		assert.match(null, tag_minor(null));
	});

	it('shows a tagged member in the versions of its since and until', () => {
		for (let c in CASES)
			assert.match(c[3], map([ 19, 20, 21 ], (minor) => tag_visible(minor, c[1], c[2])), `tag_visible ${c[0]}`);
	});

	it('ignores a malformed since or until', () => {
		assert.match(true, tag_visible(19, '2.21.0', null));
		assert.match(true, tag_visible(21, null, 'x'));
	});

	it('lists the supported versions', () => {
		assert.match([ '2.19.1', '2.20.0', '2.20.1', '2.21.0' ], DM_VERSIONS);
	});
});

describe('dm-version schema tables', () => {
	table_it('opens the core table', () => {
		assert.match([ 'core' ], core_loaded);
	});

	table_it('serves the members and defaults per version', () => {
		for (let m in MEMBERS) {
			let rows = map([ 19, 20, 21 ], (minor) => members_at(ubbf, minor, m[0]));

			assert.match(m[2], map(rows, (r) => has(r.schema, m[1])), `${m[0]}.${m[1]} member`);
			assert.match(m[2], map(rows, (r) => has(r.defaults, m[1])), `${m[0]}.${m[1]} default`);
		}
	});

	table_it('serves the commands per version', () => {
		for (let c in COMMANDS) {
			let rows = map([ 19, 20, 21 ], (minor) => members_at(ubbf, minor, c[0]));

			assert.match(c[2], map(rows, (r) => has(r.schema, c[1])), `${c[0]}.${c[1]} member`);
		}
	});
});
