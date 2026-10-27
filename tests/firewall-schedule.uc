// Host test of the ScheduleRef render of Device.Hosts.AccessControl
// (firewall-acl.uc) and Device.Firewall.Pinhole (firewall-pinholes.uc), with
// and without the schedules module, and of the inline AccessControl
// schedules.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import { schedule_windows } from 'ubbf';
import { rule_window_set } from 'ubbf.render.uci_helpers';
import { dm_visible } from 'ubbf.utils.dm-version';

const TEMPLATES = sourcepath(0, true) + '/../files/usr/share/ucode/ubbf/render/templates/';

const SCHEDULES = { Enable: 'true', Schedule: {
	'1': { Enable: 'true', Day: 'Friday', StartTime: '22:00', Duration: '14400' },
	'2': { Enable: 'false', Day: 'Monday', StartTime: '08:00', Duration: '3600' },
	'3': { Enable: 'true', Day: 'Monday', StartTime: '10:00', Duration: '3600' }
} };

function render(template, device, installed) {
	let config = { Device: {
		IP: { Interface: { '1': { Name: 'wan' }, '2': { Name: 'lan' } } },
		Schedules: SCHEDULES,
		...device
	} };
	let output = [];

	include(TEMPLATES + template, { ...h, output, config, ubbf, ubbf_instances: ubbf.instances,
		ubbf_to_bool: ubbf.to_bool, ubbf_to_int: ubbf.to_int, interface_to_name: ubbf.interface_to_name,
		csv_to_list: ubbf.csv_to_list, dm_visible, rule_window_set,
		schedule_windows: (refs, inline) => schedule_windows(config, refs, inline, installed) });

	let rules = [];
	for (let line in output) {
		if (line == 'add firewall rule') {
			push(rules, {});
			continue;
		}
		let m = match(line, /^(set|add_list) firewall\.@rule\[-1\]\.([a-z_]+)='?([^']*)'?$/);
		if (!m)
			continue;
		if (m[1] == 'set')
			rules[-1][m[2]] = m[3];
		else
			push(rules[-1][m[2]] ??= [], m[3]);
	}
	return rules;
}

function times(rules) {
	return map(rules, (r) => [ r.target, r.start_time, r.stop_time, r.weekdays ]);
}

function pinhole(refs, installed) {
	return render('firewall-pinholes.uc', { Firewall: { Pinhole: { '1': {
		Enable: 'true', Interface: 'Device.IP.Interface.1', DestIP: '192.168.1.10', DestPort: '22',
		Protocol: '6', ScheduleRef: refs
	} } } }, installed);
}

function acl(row, installed) {
	return render('firewall-acl.uc', {
		Firewall: { InterfaceSetting: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.2' } } },
		Hosts: { AccessControl: { '1': {
			Enable: 'true', PhysAddress: '02:00:00:00:00:01', AccessPolicy: 'Allow', ...row
		} } }
	}, installed);
}

describe('Firewall.Pinhole ScheduleRef render', () => {
	it('keeps a pinhole without ScheduleRef always open', () => {
		assert.match([ [ 'ACCEPT', null, null, null ] ], times(pinhole('', true)));
	});

	it('gives a pinhole past midnight a rule per day with the pinhole options', () => {
		assert.match([
			[ 'ACCEPT', '22:00:00', '23:59:59', 'Friday' ],
			[ 'ACCEPT', '00:00:00', '01:59:59', 'Saturday' ]
		], times(pinhole('Device.Schedules.Schedule.1', true)));
		assert.match([ [ '192.168.1.10', '22', [ 'tcp' ] ], [ '192.168.1.10', '22', [ 'tcp' ] ] ],
			map(pinhole('Device.Schedules.Schedule.1', true), (r) => [ r.dest_ip, r.dest_port, r.proto ]),
			'the rules keep the pinhole options');
	});

	it('leaves the pinhole unscheduled for a disabled schedule or without the module', () => {
		assert.match([ [ 'ACCEPT', null, null, null ] ], times(pinhole('Device.Schedules.Schedule.2', true)),
			'a disabled schedule');
		assert.match([ [ 'ACCEPT', null, null, null ] ], times(pinhole('Device.Schedules.Schedule.1', false)),
			'without the module');
	});
});

describe('Hosts.AccessControl ScheduleRef render', () => {
	it('gives no rule for Allow without schedules', () => {
		assert.match([], acl({}, true));
	});

	it('gives an ACCEPT per window and then the block pair for Allow with ScheduleRef', () => {
		assert.match([
			[ 'ACCEPT', '10:00:00', '10:59:59', 'Monday' ],
			[ 'ACCEPT', '22:00:00', '23:59:59', 'Friday' ],
			[ 'ACCEPT', '00:00:00', '01:59:59', 'Saturday' ],
			[ 'REJECT', null, null, null ],
			[ 'REJECT', null, null, null ]
		], times(acl({ ScheduleRef: 'Device.Schedules.Schedule.3,Device.Schedules.Schedule.1' }, true)));
	});

	it('names the ACCEPT rules per window', () => {
		assert.match([ 'ACL-Allow-02:00:00:00:00:01-lan-W1', 'ACL-Block-02:00:00:00:00:01-lan',
			'ACL-Block-Input-02:00:00:00:00:01-lan' ],
			map(acl({ ScheduleRef: 'Device.Schedules.Schedule.3' }, true), (r) => r.name));
	});

	it('does not schedule Allow without the module', () => {
		assert.match([], acl({ ScheduleRef: 'Device.Schedules.Schedule.1' }, false));
	});

	it('ignores the schedules for Deny', () => {
		assert.match([ [ 'REJECT', null, null, null ], [ 'REJECT', null, null, null ] ],
			times(acl({ AccessPolicy: 'Deny', ScheduleRef: 'Device.Schedules.Schedule.1' }, true)));
	});

	it('renders an inline schedule (until 2.21) without the module', () => {
		let inline = { Schedule: { '1': { Enable: 'true', Day: 'Saturday', StartTime: '09:00', Duration: '7200' } } };

		assert.match(dm_visible(null, '2.21') ? [
			[ 'ACCEPT', '09:00:00', '10:59:59', 'Saturday' ],
			[ 'REJECT', null, null, null ],
			[ 'REJECT', null, null, null ]
		] : [], times(dm_visible(null, '2.21') ? acl(inline, false) : []));
	});
});
