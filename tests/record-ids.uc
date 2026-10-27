// Host test of the instance numbers of rows that leave one by one: the
// AssociatedDevice rows of utils/wifi.uc (a station keeps its number, and
// the Hosts reference agrees with the table), and the ProcessFault,
// KernelFault and Reboot rows, which carry an id in their stores under
// /etc/ubbf (a Remove() or a rotation moves no other row). Run it in a
// private mount namespace; tests/ip/ holds a stand-in for ubus,
// tests/hosts/ ones for iwinfo and udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp && mount -t tmpfs none /etc/ubbf && \
//     ucode -L "$PWD/tests/ip/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/record-ids.uc'
'use strict';

import * as fs from 'fs';
import { stations_numbered, station_number } from 'ubbf.utils.wifi';
import { model as process_model } from 'ubbf.tr181.DeviceInfo.ProcessFaults';
import { model as kernel_model } from 'ubbf.tr181.DeviceInfo.KernelFaults';
import { model as reboot_model, last_reboot_path } from 'ubbf.tr181.DeviceInfo.Reboots';
import * as process_faults from 'ubbf.device.process-faults';
import * as kernel_faults from 'ubbf.device.kernel-faults';
import * as reboots from 'ubbf.device.reboots';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function macs(rows) {
	let out = {};
	for (let n in sort(keys(rows), (a, b) => +a - +b))
		out[n] = rows[n].mac;
	return out;
}

check('stations numbered by MAC', macs(stations_numbered(1, { 'aa:aa:aa:aa:aa:01': {}, 'aa:aa:aa:aa:aa:02': {} })),
	{ '1': 'aa:aa:aa:aa:aa:01', '2': 'aa:aa:aa:aa:aa:02' });
check('a leaving station does not shift the other', macs(stations_numbered(1, { 'aa:aa:aa:aa:aa:02': {}, 'aa:aa:aa:aa:aa:03': {} })),
	{ '2': 'aa:aa:aa:aa:aa:02', '3': 'aa:aa:aa:aa:aa:03' });
check('the Hosts reference takes the same number, in any case', station_number(1, 'AA:AA:AA:AA:AA:03'), 3);
check('another access point has its own numbers', station_number(2, 'aa:aa:aa:aa:aa:03'), 1);

function ids(rows) {
	return map(sort(keys(rows), (a, b) => +a - +b), (n) => [ +n, rows[n].Alias ]);
}

const process_get = process_model['Device.DeviceInfo.ProcessFaults.ProcessFault.{i}'].get;
const process_methods = process_faults.ubus_methods();

fs.writefile('/etc/ubbf/process-faults.json', sprintf('%J', { meta: {}, faults: [
	{ process_name: 'a' }, { process_name: 'b' }, { process_name: 'c' }
] }));
check('faults without ids keep their positions', ids(process_get({})),
	[ [ 1, 'cpe-fault-1' ], [ 2, 'cpe-fault-2' ], [ 3, 'cpe-fault-3' ] ]);
check('remove by id', process_methods.process_faults_remove.call({ args: { id: 2 } }), { success: true });
check('a removal moves no other fault', ids(process_get({})), [ [ 1, 'cpe-fault-1' ], [ 3, 'cpe-fault-3' ] ]);
check('one fault by number', process_get({ instance: 3 }).ProcessName, 'c');
check('the removed number is gone', process_get({ instance: 2 }), null);
check('remove of an unknown id', process_methods.process_faults_remove.call({ args: { id: 2 } }).error != null, true);
check('the store keeps the next id', json(fs.readfile('/etc/ubbf/process-faults.json')).meta.next_id, 4);

// A rotation drops the oldest fault and gives the new one the next id.
const kernel_get = kernel_model['Device.DeviceInfo.KernelFaults.KernelFault.{i}'].get;
fs.writefile('/etc/ubbf/kernel-faults.json', sprintf('%J', { meta: { max_entries: 2, next_id: 5 }, faults: [
	{ id: 3, reason: 'x' }, { id: 4, reason: 'y' }
] }));
fs.mkdir('/tmp/ubbf');
fs.writefile('/tmp/ubbf/kernel-faults-boot.json', sprintf('%J', [ { reason: 'z' } ]));
kernel_faults.record(false);
check('a rotation moves no other fault', ids(kernel_get({})), [ [ 4, 'cpe-kfault-4' ], [ 5, 'cpe-kfault-5' ] ]);
check('remove of a kernel fault by id', kernel_faults.ubus_methods().kernel_faults_remove.call({ args: { id: 4 } }), { success: true });
check('the other kernel fault stays', ids(kernel_get({})), [ [ 5, 'cpe-kfault-5' ] ]);

const reboot_get = reboot_model['Device.DeviceInfo.Reboots.Reboot.{i}'].get;
fs.writefile('/etc/ubbf/reboots.json', sprintf('%J', [ { cause: 'LocalReboot' }, { cause: 'RemoteReboot' } ]));
check('reboots without ids keep their positions', ids(reboot_get({})), [ [ 1, 'cpe-reboot-1' ], [ 2, 'cpe-reboot-2' ] ]);
reboots.ubus_methods().reboots_remove.call({ args: { id: 1 } });
reboots.record({ cause: 'LocalFactoryReset' }, false);
check('a removal and a new reboot', ids(reboot_get({})), [ [ 2, 'cpe-reboot-2' ], [ 3, 'cpe-reboot-3' ] ]);
check('LastRebootRef names the newest reboot', last_reboot_path(), 'Device.DeviceInfo.Reboots.Reboot.3');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
