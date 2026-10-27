// Host test of the instance number pins in config.json (TR-369 R-ARC.8):
// the _instances section keeps the number of a runtime row that the
// configuration names across a reboot, config.json changes only when the
// configuration or its pins change, the live tree never holds the
// section, and a controller add does not take the number of a runtime
// row. Run from the repository root with the native module built for
// the host; phase 2 runs after a reboot, which clears /tmp/ubbf:
//   tests/datamodel/run.sh <host build> tests/instance-pins.uc 1 reboot 2
'use strict';

import * as fs from 'fs';
import { dm, operations_apply, object_delete } from 'ubbf.datamodel';
import { instance_numbers } from 'ubbf';

const TABLE = 'Device.Optical.Interface';
const MAPPINGS = 'Device.NAT.PortMapping';
const CODE = 'Device.DeviceInfo.ProvisioningCode';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function stored() {
	return json(fs.readfile('/etc/ubbf/config.json'));
}

function code_set(value) {
	return operations_apply([ { op: 'set', path: CODE, value } ], () => null)?.success;
}

function applies() {
	return length(filter(global.ubus_log ?? [], (e) => e[1] == 'bbf-device' && e[2] == 'apply'));
}

if (getenv('PHASE') == '1') {
	check('initial config has no pins', stored()._instances, null);
	check('two cages', instance_numbers(TABLE, [ 'sfp1', 'sfp2' ]), { sfp1: 1, sfp2: 2 });

	check('a reference to a runtime row is set', code_set(`${TABLE}.2`), true);
	check('config.json pins the named row', stored()._instances, { [TABLE]: { '2': 'sfp2' } });
	check('the live tree holds no pins', dm.config()._instances, null);

	let digest = dm.digest();
	let before = applies();
	check('the same value again', code_set(`${TABLE}.2`), true);
	check('no write without a change', [ dm.digest(), applies() ], [ digest, before ]);

	// A controller add to a table with a found row takes a number that the
	// found row does not hold, and the next found row follows the add.
	check('a found port mapping', instance_numbers(MAPPINGS, [ 'upnp1' ]), { upnp1: 1 });
	check('an add skips the number of the found row',
		operations_apply([ { op: 'add', path: `${MAPPINGS}.` } ], () => null)?.results?.[0]?.instance, 2);
	check('a found row after the add', instance_numbers(MAPPINGS, [ 'upnp2' ]), { upnp2: 3 });
	check('a table the map does not number keeps the lowest free number',
		operations_apply([ { op: 'add', path: 'Device.DHCPv4.Server.Pool.' } ], () => null)?.results?.[0]?.instance, 3);
}

if (getenv('PHASE') == '2') {
	check('a load of an unchanged config does not apply', applies(), 0);
	check('the pinned cage keeps its number after a reboot, a new one follows',
		instance_numbers(TABLE, [ 'sfpX', 'sfp2' ]), { sfpX: 3, sfp2: 2 });
	check('the live tree holds no pins', dm.config()._instances, null);

	check('the reference goes', code_set(''), true);
	check('the pin goes with it', stored()._instances, null);

	// UPnP mappings follow the stored port mapping that phase 1 added, and
	// a delete of one reaches upnpd with its mapping id.
	global.upnpd_mappings = [ { id: 7, external_port: 5100, internal_port: 5100, protocol: 'TCP' } ];
	let mappings = dm.get_subtree_with_state(MAPPINGS) ?? {};
	check('a UPnP mapping follows the stored row',
		map(filter(keys(mappings), (n) => mappings[n].Origin == 'UPnP'), (n) => +n), [ 3 ]);
	check('a delete of the UPnP row goes to upnpd', [ object_delete(`${MAPPINGS}.3`),
		filter(global.ubus_log, (e) => e[1] == 'upnpd' && e[2] == 'delete_mapping')[0]?.[3] ], [ 0, { id: 7 } ]);
}

printf('phase %s passed: %d\nfailed: %d\n', getenv('PHASE'), pass, fail);
exit(fail ? 1 : 0);
