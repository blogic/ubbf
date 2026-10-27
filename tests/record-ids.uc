// Host test of the instance numbers of rows that leave one by one: the
// AssociatedDevice rows of utils/wifi.uc (a station keeps its number, and
// the Hosts reference agrees with the table), and the ProcessFault,
// KernelFault and Reboot rows, which carry an id in their stores under
// /etc/ubbf (a Remove() or a rotation moves no other row).
'use strict';

import { describe, it, assert, beforeEach, setup } from 'utest';
import { state_clear } from 'test_env';
import { netifd_patch } from 'netifd_mock';
import * as fs from 'fs';
import { stations_numbered, station_number } from 'ubbf.utils.wifi';
import { model as process_model } from 'ubbf.tr181.DeviceInfo.ProcessFaults';
import { model as kernel_model } from 'ubbf.tr181.DeviceInfo.KernelFaults';
import { model as reboot_model, last_reboot_path } from 'ubbf.tr181.DeviceInfo.Reboots';
import * as process_faults from 'ubbf.device.process-faults';
import * as kernel_faults from 'ubbf.device.kernel-faults';
import * as reboots from 'ubbf.device.reboots';
import { instance_map_own } from 'ubbf';

function macs(rows) {
	let out = {};
	for (let n in sort(keys(rows), (a, b) => +a - +b))
		out[n] = rows[n].mac;
	return out;
}

function ids(rows) {
	return map(sort(keys(rows), (a, b) => +a - +b), (n) => [ +n, rows[n].Alias ]);
}

const process_get = process_model['Device.DeviceInfo.ProcessFaults.ProcessFault.{i}'].get;
const kernel_get = kernel_model['Device.DeviceInfo.KernelFaults.KernelFault.{i}'].get;
const reboot_get = reboot_model['Device.DeviceInfo.Reboots.Reboot.{i}'].get;

// This process numbers rows, as the agent does.
setup(() => instance_map_own(true));

describe('record instance numbers', () => {
	beforeEach(() => {
		state_clear();
		netifd_patch({});
	});

	it('numbers AssociatedDevice rows by station MAC', () => {
		assert.match({ '1': 'aa:aa:aa:aa:aa:01', '2': 'aa:aa:aa:aa:aa:02' },
			macs(stations_numbered(1, { 'aa:aa:aa:aa:aa:01': {}, 'aa:aa:aa:aa:aa:02': {} })), 'stations numbered by MAC');
		assert.match({ '2': 'aa:aa:aa:aa:aa:02', '3': 'aa:aa:aa:aa:aa:03' },
			macs(stations_numbered(1, { 'aa:aa:aa:aa:aa:02': {}, 'aa:aa:aa:aa:aa:03': {} })), 'a leaving station does not shift the other');
		assert.match(3, station_number(1, 'AA:AA:AA:AA:AA:03'), 'the Hosts reference takes the same number, in any case');
		assert.match(1, station_number(2, 'aa:aa:aa:aa:aa:03'), 'another access point has its own numbers');
	});

	it('keeps the ProcessFault numbers when one fault is removed', () => {
		const process_methods = process_faults.ubus_methods();

		fs.writefile('/etc/ubbf/process-faults.json', sprintf('%J', { meta: {}, faults: [
			{ process_name: 'a' }, { process_name: 'b' }, { process_name: 'c' }
		] }));
		assert.match([ [ 1, 'cpe-fault-1' ], [ 2, 'cpe-fault-2' ], [ 3, 'cpe-fault-3' ] ], ids(process_get({})),
			'faults without ids keep their positions');
		assert.match({ success: true }, process_methods.process_faults_remove.call({ args: { id: 2 } }), 'remove by id');
		assert.match([ [ 1, 'cpe-fault-1' ], [ 3, 'cpe-fault-3' ] ], ids(process_get({})), 'a removal moves no other fault');
		assert.match('c', process_get({ instance: 3 }).ProcessName, 'one fault by number');
		assert.match(null, process_get({ instance: 2 }), 'the removed number is gone');
		assert.match(true, process_methods.process_faults_remove.call({ args: { id: 2 } }).error != null, 'remove of an unknown id');
		assert.match(4, json(fs.readfile('/etc/ubbf/process-faults.json')).meta.next_id, 'the store keeps the next id');
	});

	// A rotation drops the oldest fault and gives the new one the next id.
	it('keeps the KernelFault numbers across a rotation and a removal', () => {
		fs.writefile('/etc/ubbf/kernel-faults.json', sprintf('%J', { meta: { max_entries: 2, next_id: 5 }, faults: [
			{ id: 3, reason: 'x' }, { id: 4, reason: 'y' }
		] }));
		fs.writefile('/tmp/ubbf/kernel-faults-boot.json', sprintf('%J', [ { reason: 'z' } ]));
		kernel_faults.record(false);
		assert.match([ [ 4, 'cpe-kfault-4' ], [ 5, 'cpe-kfault-5' ] ], ids(kernel_get({})), 'a rotation moves no other fault');
		assert.match({ success: true }, kernel_faults.ubus_methods().kernel_faults_remove.call({ args: { id: 4 } }),
			'remove of a kernel fault by id');
		assert.match([ [ 5, 'cpe-kfault-5' ] ], ids(kernel_get({})), 'the other kernel fault stays');
	});

	it('keeps the Reboot numbers across a removal and a new reboot', () => {
		fs.writefile('/etc/ubbf/reboots.json', sprintf('%J', [ { cause: 'LocalReboot' }, { cause: 'RemoteReboot' } ]));
		assert.match([ [ 1, 'cpe-reboot-1' ], [ 2, 'cpe-reboot-2' ] ], ids(reboot_get({})), 'reboots without ids keep their positions');
		reboots.ubus_methods().reboots_remove.call({ args: { id: 1 } });
		reboots.record({ cause: 'LocalFactoryReset' }, false);
		assert.match([ [ 2, 'cpe-reboot-2' ], [ 3, 'cpe-reboot-3' ] ], ids(reboot_get({})), 'a removal and a new reboot');
		assert.match('Device.DeviceInfo.Reboots.Reboot.3', last_reboot_path(), 'LastRebootRef names the newest reboot');
	});
});
