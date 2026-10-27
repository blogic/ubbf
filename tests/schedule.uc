// Host test of schedule.c of ubbf.so: the time windows of schedule rows, their
// fw4 form, Status and TimeLeft, and the check of ScheduleRef. Run from the
// repository root:
//   ucode -L "$PWD/tests/hosts/*.uc" -L "$PWD/files/usr/share/ucode" \
//     -L "<host build>/*.so" tests/schedule.uc
'use strict';

import * as ubbf from 'ubbf';
import {
	schedule_intervals, intervals_union, intervals_complement, intervals_to_windows,
	intervals_active, schedule_state, refs_intervals, schedule_refs_check,
	start_time_valid, week_seconds
} from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

const H = 3600;
const DAY = 86400;

function windows(row) {
	return intervals_to_windows(schedule_intervals(row));
}

check('a plain window',
	windows({ Day: 'Monday,Wednesday', StartTime: '16:00', Duration: '3600' }),
	[ { start_time: '16:00:00', stop_time: '16:59:59', weekdays: [ 'Monday', 'Wednesday' ] } ]);

check('a window past midnight continues on the next day',
	windows({ Day: 'Friday', StartTime: '22:00', Duration: sprintf('%d', 4 * H) }),
	[
		{ start_time: '22:00:00', stop_time: '23:59:59', weekdays: [ 'Friday' ] },
		{ start_time: '00:00:00', stop_time: '01:59:59', weekdays: [ 'Saturday' ] }
	]);

check('Sunday night continues on Monday',
	windows({ Day: 'Sunday', StartTime: '23:00', Duration: sprintf('%d', 2 * H) }),
	[
		{ start_time: '00:00:00', stop_time: '00:59:59', weekdays: [ 'Monday' ] },
		{ start_time: '23:00:00', stop_time: '23:59:59', weekdays: [ 'Sunday' ] }
	]);

check('without Day the window repeats daily',
	windows({ StartTime: '08:30', Duration: '1800' }),
	[ { start_time: '08:30:00', stop_time: '08:59:59',
	    weekdays: [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' ] } ]);

check('without Duration the window lasts until midnight',
	windows({ Day: 'Monday', StartTime: '20:00', Duration: '0' }),
	[ { start_time: '20:00:00', stop_time: '23:59:59', weekdays: [ 'Monday' ] } ]);

check('InverseMode gives the rest of the week',
	windows({ Day: 'Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday',
		StartTime: '00:00', Duration: sprintf('%d', 22 * H), InverseMode: 'true' }),
	[ { start_time: '22:00:00', stop_time: '23:59:59',
	    weekdays: [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' ] } ]);

check('a full week', windows({ StartTime: '00:00', Duration: sprintf('%d', 8 * 7 * DAY) }),
	[ { start_time: '00:00:00', stop_time: '23:59:59',
	    weekdays: [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' ] } ]);

check('without StartTime the row cannot be used', schedule_intervals({ Duration: '7200' }), null);
check('a malformed StartTime', schedule_intervals({ StartTime: '24:00' }), null);
check('StartTime check', [ start_time_valid(''), start_time_valid('07:05'), start_time_valid('7:05') ],
	[ true, true, false ]);

check('union merges touching intervals', intervals_union([ [ 10, 20 ], [ 0, 10 ], [ 30, 40 ] ]),
	[ [ 0, 20 ], [ 30, 40 ] ]);
check('complement', intervals_complement([ [ 0, 20 ], [ 30, 40 ] ]), [ [ 20, 30 ], [ 40, 7 * DAY ] ]);

let row = { Enable: 'true', Day: 'Tuesday', StartTime: '16:00', Duration: '3600' };
let tue = DAY;
check('active inside the window', schedule_state(row, true, tue + 16 * H + 600),
	{ status: 'Active', time_left: 3000 });
check('inactive before the window', schedule_state(row, true, tue + 15 * H),
	{ status: 'Inactive', time_left: 3600 });
check('after the window, the next one is a week later', schedule_state(row, true, tue + 17 * H),
	{ status: 'Inactive', time_left: 7 * DAY - H });
check('a disabled row', schedule_state({ ...row, Enable: 'false' }, true, tue), { status: 'Inactive', time_left: 0 });
check('scheduling disabled', schedule_state(row, false, tue), { status: 'StackDisabled', time_left: 0 });
check('a daily allowance is an error', schedule_state({ Enable: 'true', Duration: '7200' }, true, tue),
	{ status: 'Error', time_left: 0 });

let wrap = { Enable: 'true', Day: 'Sunday', StartTime: '23:00', Duration: sprintf('%d', 2 * H) };
check('TimeLeft across the end of the week', schedule_state(wrap, true, 6 * DAY + 23 * H + 1800),
	{ status: 'Active', time_left: 5400 });

check('week seconds from localtime()', week_seconds({ wday: 0, hour: 1, min: 2, sec: 3 }), 6 * DAY + H + 123);

let config = { Device: { Schedules: { Enable: 'true', Schedule: {
	'1': { Enable: 'true', Day: 'Monday', StartTime: '10:00', Duration: '3600' },
	'2': { Enable: 'false', Day: 'Monday', StartTime: '12:00', Duration: '3600' },
	'3': { Enable: 'true', Day: 'Monday', StartTime: '11:00', Duration: '3600' },
	'4': { Enable: 'true', Duration: '3600' }
} } } };

check('refs give the union of the enabled rows',
	refs_intervals(config, 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.2.,Device.Schedules.Schedule.3'),
	[ [ 10 * H, 12 * H ] ]);
check('only disabled and unusable rows: not scheduled',
	refs_intervals(config, 'Device.Schedules.Schedule.2,Device.Schedules.Schedule.4'), null);
check('empty ScheduleRef: not scheduled', refs_intervals(config, ''), null);
check('scheduling disabled: not scheduled',
	refs_intervals({ Device: { Schedules: { ...config.Device.Schedules, Enable: 'false' } } },
		'Device.Schedules.Schedule.1'), null);
check('active check', [ intervals_active([ [ 10, 20 ] ], 10), intervals_active([ [ 10, 20 ] ], 20) ],
	[ true, false ]);

check('empty ScheduleRef is valid without the module', schedule_refs_check('', config, false), 0);
check('a reference needs the module', schedule_refs_check('Device.Schedules.Schedule.1', config, false),
	-USP_ERR_INVALID_VALUE);
check('a reference to a row', schedule_refs_check('Device.Schedules.Schedule.1,Device.Schedules.Schedule.3.', config, true), 0);
check('a reference to a missing row', schedule_refs_check('Device.Schedules.Schedule.9', config, true),
	-USP_ERR_INVALID_VALUE);
check('a reference to another table', schedule_refs_check('Device.Hosts.Host.1', config, true),
	-USP_ERR_INVALID_VALUE);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
