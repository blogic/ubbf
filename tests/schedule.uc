// Host test of schedule.c of ubbf.so: the time windows of schedule rows, their
// fw4 form, Status and TimeLeft, and the check of ScheduleRef.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';
import {
	schedule_intervals, intervals_union, intervals_complement, intervals_to_windows,
	intervals_active, schedule_state, refs_intervals, schedule_refs_check,
	start_time_valid, week_seconds
} from 'ubbf';

const H = 3600;
const DAY = 86400;
const WEEK = [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' ];

function windows(row) {
	return intervals_to_windows(schedule_intervals(row));
}

describe('schedule windows', () => {
	it('renders a plain window', () => {
		assert.match([ { start_time: '16:00:00', stop_time: '16:59:59', weekdays: [ 'Monday', 'Wednesday' ] } ],
			windows({ Day: 'Monday,Wednesday', StartTime: '16:00', Duration: '3600' }));
	});

	it('continues a window past midnight on the next day', () => {
		assert.match([
			{ start_time: '22:00:00', stop_time: '23:59:59', weekdays: [ 'Friday' ] },
			{ start_time: '00:00:00', stop_time: '01:59:59', weekdays: [ 'Saturday' ] }
		], windows({ Day: 'Friday', StartTime: '22:00', Duration: sprintf('%d', 4 * H) }));
		assert.match([
			{ start_time: '00:00:00', stop_time: '00:59:59', weekdays: [ 'Monday' ] },
			{ start_time: '23:00:00', stop_time: '23:59:59', weekdays: [ 'Sunday' ] }
		], windows({ Day: 'Sunday', StartTime: '23:00', Duration: sprintf('%d', 2 * H) }), 'Sunday night continues on Monday');
	});

	it('repeats the window daily without Day', () => {
		assert.match([ { start_time: '08:30:00', stop_time: '08:59:59', weekdays: WEEK } ],
			windows({ StartTime: '08:30', Duration: '1800' }));
	});

	it('lasts until midnight without Duration', () => {
		assert.match([ { start_time: '20:00:00', stop_time: '23:59:59', weekdays: [ 'Monday' ] } ],
			windows({ Day: 'Monday', StartTime: '20:00', Duration: '0' }));
	});

	it('gives the rest of the week with InverseMode', () => {
		assert.match([ { start_time: '22:00:00', stop_time: '23:59:59', weekdays: WEEK } ],
			windows({ Day: join(',', WEEK), StartTime: '00:00', Duration: sprintf('%d', 22 * H), InverseMode: 'true' }));
	});

	it('covers a full week', () => {
		assert.match([ { start_time: '00:00:00', stop_time: '23:59:59', weekdays: WEEK } ],
			windows({ StartTime: '00:00', Duration: sprintf('%d', 8 * 7 * DAY) }));
	});

	it('cannot use a row without a valid StartTime', () => {
		assert.match(null, schedule_intervals({ Duration: '7200' }), 'without StartTime');
		assert.match(null, schedule_intervals({ StartTime: '24:00' }), 'a malformed StartTime');
		assert.match([ true, true, false ], [ start_time_valid(''), start_time_valid('07:05'), start_time_valid('7:05') ]);
	});
});

describe('schedule intervals', () => {
	it('merges touching intervals in a union', () => {
		assert.match([ [ 0, 20 ], [ 30, 40 ] ], intervals_union([ [ 10, 20 ], [ 0, 10 ], [ 30, 40 ] ]));
	});

	it('gives the complement in the week', () => {
		assert.match([ [ 20, 30 ], [ 40, 7 * DAY ] ], intervals_complement([ [ 0, 20 ], [ 30, 40 ] ]));
	});

	it('is active from the start up to the end', () => {
		assert.match([ true, false ], [ intervals_active([ [ 10, 20 ] ], 10), intervals_active([ [ 10, 20 ] ], 20) ]);
	});

	it('counts week seconds from localtime()', () => {
		assert.match(6 * DAY + H + 123, week_seconds({ wday: 0, hour: 1, min: 2, sec: 3 }));
	});
});

describe('schedule Status and TimeLeft', () => {
	const row = { Enable: 'true', Day: 'Tuesday', StartTime: '16:00', Duration: '3600' };
	const tue = DAY;

	it('is Active inside the window and Inactive outside', () => {
		assert.match({ status: 'Active', time_left: 3000 }, schedule_state(row, true, tue + 16 * H + 600));
		assert.match({ status: 'Inactive', time_left: 3600 }, schedule_state(row, true, tue + 15 * H), 'before the window');
		assert.match({ status: 'Inactive', time_left: 7 * DAY - H }, schedule_state(row, true, tue + 17 * H),
			'after the window, the next one is a week later');
	});

	it('is Inactive for a disabled row and StackDisabled without scheduling', () => {
		assert.match({ status: 'Inactive', time_left: 0 }, schedule_state({ ...row, Enable: 'false' }, true, tue));
		assert.match({ status: 'StackDisabled', time_left: 0 }, schedule_state(row, false, tue));
	});

	it('is Error for a daily allowance', () => {
		assert.match({ status: 'Error', time_left: 0 }, schedule_state({ Enable: 'true', Duration: '7200' }, true, tue));
	});

	it('counts TimeLeft across the end of the week', () => {
		let wrap = { Enable: 'true', Day: 'Sunday', StartTime: '23:00', Duration: sprintf('%d', 2 * H) };
		assert.match({ status: 'Active', time_left: 5400 }, schedule_state(wrap, true, 6 * DAY + 23 * H + 1800));
	});
});

describe('ScheduleRef', () => {
	const config = { Device: { Schedules: { Enable: 'true', Schedule: {
		'1': { Enable: 'true', Day: 'Monday', StartTime: '10:00', Duration: '3600' },
		'2': { Enable: 'false', Day: 'Monday', StartTime: '12:00', Duration: '3600' },
		'3': { Enable: 'true', Day: 'Monday', StartTime: '11:00', Duration: '3600' },
		'4': { Enable: 'true', Duration: '3600' }
	} } } };

	it('gives the union of the enabled rows', () => {
		assert.match([ [ 10 * H, 12 * H ] ],
			refs_intervals(config, 'Device.Schedules.Schedule.1,Device.Schedules.Schedule.2.,Device.Schedules.Schedule.3'));
	});

	it('is not scheduled without a usable enabled row or with scheduling disabled', () => {
		assert.match(null, refs_intervals(config, 'Device.Schedules.Schedule.2,Device.Schedules.Schedule.4'),
			'only disabled and unusable rows');
		assert.match(null, refs_intervals(config, ''), 'empty ScheduleRef');
		assert.match(null, refs_intervals({ Device: { Schedules: { ...config.Device.Schedules, Enable: 'false' } } },
			'Device.Schedules.Schedule.1'), 'scheduling disabled');
	});

	it('accepts an empty value without the module and needs the module for a reference', () => {
		assert.match(0, schedule_refs_check('', config, false));
		assert.match(-USP_ERR_INVALID_VALUE, schedule_refs_check('Device.Schedules.Schedule.1', config, false));
	});

	it('accepts references to rows and refuses missing rows and other tables', () => {
		assert.match(0, schedule_refs_check('Device.Schedules.Schedule.1,Device.Schedules.Schedule.3.', config, true));
		assert.match(-USP_ERR_INVALID_VALUE, schedule_refs_check('Device.Schedules.Schedule.9', config, true),
			'a reference to a missing row');
		assert.match(-USP_ERR_INVALID_VALUE, schedule_refs_check('Device.Hosts.Host.1', config, true),
			'a reference to another table');
	});
});
