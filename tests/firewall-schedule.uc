// Host test of the ScheduleRef render of Device.Hosts.AccessControl
// (firewall-acl.uc) and Device.Firewall.Pinhole (firewall-pinholes.uc), with
// and without the schedules module, and of the inline AccessControl
// schedules. Run from the repository root with the native module built for
// the host:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/firewall-schedule.uc
'use strict';

import * as ubbf from 'ubbf';
import * as h from 'ubbf.render.uci_helpers';
import { schedule_windows } from 'ubbf';
import { rule_window_set } from 'ubbf.render.uci_helpers';
import { dm_visible } from 'ubbf.utils.dm-version';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

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

check('a pinhole without ScheduleRef is always open', times(pinhole('', true)),
	[ [ 'ACCEPT', null, null, null ] ]);
check('a pinhole past midnight gets a rule per day',
	times(pinhole('Device.Schedules.Schedule.1', true)), [
		[ 'ACCEPT', '22:00:00', '23:59:59', 'Friday' ],
		[ 'ACCEPT', '00:00:00', '01:59:59', 'Saturday' ]
	]);
check('the rules keep the pinhole options',
	map(pinhole('Device.Schedules.Schedule.1', true), (r) => [ r.dest_ip, r.dest_port, r.proto ]),
	[ [ '192.168.1.10', '22', [ 'tcp' ] ], [ '192.168.1.10', '22', [ 'tcp' ] ] ]);
check('a disabled schedule leaves the pinhole unscheduled',
	times(pinhole('Device.Schedules.Schedule.2', true)), [ [ 'ACCEPT', null, null, null ] ]);
check('without the module ScheduleRef does nothing',
	times(pinhole('Device.Schedules.Schedule.1', false)), [ [ 'ACCEPT', null, null, null ] ]);

function acl(row, installed) {
	return render('firewall-acl.uc', {
		Firewall: { InterfaceSetting: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.2' } } },
		Hosts: { AccessControl: { '1': {
			Enable: 'true', PhysAddress: '02:00:00:00:00:01', AccessPolicy: 'Allow', ...row
		} } }
	}, installed);
}

check('Allow without schedules gives no rule', acl({}, true), []);
check('Allow with ScheduleRef: an ACCEPT per window, then the block pair',
	times(acl({ ScheduleRef: 'Device.Schedules.Schedule.3,Device.Schedules.Schedule.1' }, true)), [
		[ 'ACCEPT', '10:00:00', '10:59:59', 'Monday' ],
		[ 'ACCEPT', '22:00:00', '23:59:59', 'Friday' ],
		[ 'ACCEPT', '00:00:00', '01:59:59', 'Saturday' ],
		[ 'REJECT', null, null, null ],
		[ 'REJECT', null, null, null ]
	]);
check('the ACCEPT rules are named per window',
	map(acl({ ScheduleRef: 'Device.Schedules.Schedule.3' }, true), (r) => r.name),
	[ 'ACL-Allow-02:00:00:00:00:01-lan-W1', 'ACL-Block-02:00:00:00:00:01-lan',
	  'ACL-Block-Input-02:00:00:00:00:01-lan' ]);
check('Allow without the module is not scheduled',
	acl({ ScheduleRef: 'Device.Schedules.Schedule.1' }, false), []);
check('Deny ignores the schedules',
	times(acl({ AccessPolicy: 'Deny', ScheduleRef: 'Device.Schedules.Schedule.1' }, true)),
	[ [ 'REJECT', null, null, null ], [ 'REJECT', null, null, null ] ]);

let inline = { Schedule: { '1': { Enable: 'true', Day: 'Saturday', StartTime: '09:00', Duration: '7200' } } };
check('an inline schedule (until 2.21), without the module',
	times(dm_visible(null, '2.21') ? acl(inline, false) : []),
	dm_visible(null, '2.21') ? [
		[ 'ACCEPT', '09:00:00', '10:59:59', 'Saturday' ],
		[ 'REJECT', null, null, null ],
		[ 'REJECT', null, null, null ]
	] : []);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
