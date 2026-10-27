// Host test of the instance number pins in config.json (TR-369 R-ARC.8):
// the _instances section keeps the number of a runtime row that the
// configuration names across a reboot, config.json changes only when the
// configuration or its pins change, the live tree never holds the
// section, and a controller add does not take the number of a runtime
// row. A reboot needs a new process, so the test runs this file again in
// a plain ucode process per phase, with PHASE set, the ubus and uci
// stand-ins of tests/datamodel (utest mocks do not reach the process), those
// of tests/lib, and ubbf.datamodel in the scope: the datamodel loads config.json when it
// loads, which the utest worker must not do. Each phase prints its
// results, and the test asserts on them. Phase 2 runs after a reboot,
// which clears /tmp/ubbf.
'use strict';

import * as fs from 'fs';
import { describe, it, assert, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import { instance_numbers } from 'ubbf';

const TABLE = 'Device.Optical.Interface';
const MAPPINGS = 'Device.NAT.PortMapping';
const CODE = 'Device.DeviceInfo.ProvisioningCode';
const RESULT_TAG = 'instance-pins result: ';

function result(name, got, expected) {
	print(RESULT_TAG, sprintf('%J', { name, got, expected }), '\n');
}

function stored() {
	return json(fs.readfile('/etc/ubbf/config.json'));
}

function applies() {
	return length(filter(global.ubus_log ?? [], (e) => e[1] == 'bbf-device' && e[2] == 'apply'));
}

function phase_1(datamodel) {
	let dm = datamodel.dm;
	let code_set = (value) => datamodel.operations_apply([ { op: 'set', path: CODE, value } ], () => null)?.success;

	result('initial config has no pins', stored()._instances, null);
	result('two cages', instance_numbers(TABLE, [ 'sfp1', 'sfp2' ]), { sfp1: 1, sfp2: 2 });

	result('a reference to a runtime row is set', code_set(`${TABLE}.2`), true);
	result('config.json pins the named row', stored()._instances, { [TABLE]: { '2': 'sfp2' } });
	result('the live tree holds no pins', dm.config()._instances, null);

	let digest = dm.digest();
	let before = applies();
	result('the same value again', code_set(`${TABLE}.2`), true);
	result('no write without a change', [ dm.digest(), applies() ], [ digest, before ]);

	// A controller add to a table with a found row takes a number that the
	// found row does not hold, and the next found row follows the add.
	result('a found port mapping', instance_numbers(MAPPINGS, [ 'upnp1' ]), { upnp1: 1 });
	result('an add skips the number of the found row',
		datamodel.operations_apply([ { op: 'add', path: `${MAPPINGS}.` } ], () => null)?.results?.[0]?.instance, 2);
	result('a found row after the add', instance_numbers(MAPPINGS, [ 'upnp2' ]), { upnp2: 3 });
	result('a table the map does not number keeps the lowest free number',
		datamodel.operations_apply([ { op: 'add', path: 'Device.DHCPv4.Server.Pool.' } ], () => null)?.results?.[0]?.instance, 3);
}

function phase_2(datamodel) {
	let dm = datamodel.dm;
	let code_set = (value) => datamodel.operations_apply([ { op: 'set', path: CODE, value } ], () => null)?.success;

	result('a load of an unchanged config does not apply', applies(), 0);
	result('the pinned cage keeps its number after a reboot, a new one follows',
		instance_numbers(TABLE, [ 'sfpX', 'sfp2' ]), { sfpX: 3, sfp2: 2 });
	result('the live tree holds no pins', dm.config()._instances, null);

	result('the reference goes', code_set(''), true);
	result('the pin goes with it', stored()._instances, null);

	// UPnP mappings follow the stored port mapping that phase 1 added, and
	// a delete of one reaches upnpd with its mapping id.
	global.upnpd_mappings = [ { id: 7, external_port: 5100, internal_port: 5100, protocol: 'TCP' } ];
	let mappings = dm.get_subtree_with_state(MAPPINGS) ?? {};
	result('a UPnP mapping follows the stored row',
		map(filter(keys(mappings), (n) => mappings[n].Origin == 'UPnP'), (n) => +n), [ 3 ]);
	result('a delete of the UPnP row goes to upnpd', [ datamodel.object_delete(`${MAPPINGS}.3`),
		filter(global.ubus_log, (e) => e[1] == 'upnpd' && e[2] == 'delete_mapping')[0]?.[3] ], [ 0, { id: 7 } ]);
}

/**
 * Runs one phase in a new ucode process and returns its results.
 *
 * @param {string} phase - "1" or "2"
 * @returns {array} The { name, got, expected } results, in order
 */
function phase_run(phase) {
	let build_dir = getenv('UBBF_BUILD_DIR');
	let tests = `${fs.getcwd()}/tests`;
	let p = fs.popen(`PHASE=${phase} ucode -L '${tests}/datamodel/*.uc' -L '${tests}/lib/*.uc' ` +
		`-L /usr/share/ucode -L '${build_dir}/*.so' ` +
		`-e 'import * as datamodel from "ubbf.datamodel"; ` +
		`include("${tests}/instance-pins.uc", { datamodel });' 2>&1`, 'r');
	let output = p.read('all');
	let status = p.close();
	let results = [];

	for (let line in split(output, '\n'))
		if (index(line, RESULT_TAG) == 0)
			push(results, json(substr(line, length(RESULT_TAG))));

	assert.match(0, status, `phase ${phase} exits 0: ${output}`);
	return results;
}

function results_assert(phase, results, count) {
	assert.match(count, length(results), `phase ${phase} reports all its results`);
	for (let r in results)
		assert.match(r.expected, r.got, `phase ${phase}: ${r.name}`);
}

const PHASE = getenv('PHASE');

if (PHASE == '1')
	phase_1(datamodel);
else if (PHASE == '2')
	phase_2(datamodel);
else
	describe('instance number pins', () => {
		beforeEach(() => {
			state_clear();
			fs.writefile('/etc/ubbf/config.json', fs.readfile('/usr/share/ucode/ubbf/initial.json'));
		});

		it('keep the number of a named runtime row across a reboot', () => {
			results_assert(1, phase_run(1), 11);

			system([ 'rm', '-rf', '/tmp/ubbf' ]);
			fs.mkdir('/tmp/ubbf', 0755);

			results_assert(2, phase_run(2), 7);
		});
	});
